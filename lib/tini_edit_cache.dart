import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class TiniEditCancelled implements Exception {}

/// A producer transfers ownership only for a newly-created temporary artifact.
class TiniEditArtifact {
  final String path;
  final Map<String, dynamic> metadata;
  final bool temporary;
  const TiniEditArtifact(
    this.path, {
    this.metadata = const {},
    this.temporary = false,
  });
}

typedef TiniEditProducer =
    Future<TiniEditArtifact> Function(
      List<TiniEditArtifact> inputs,
      bool Function() cancelled,
    );

/// Immutable dependency graph. Keys describe actual content and parameters;
/// clip IDs, object identity and UI history do not affect render identity.
class TiniEditNode {
  final String key, extension, stage;
  final String? retainGroup;
  final List<TiniEditNode> parents;
  final TiniEditProducer? producer;
  final TiniEditArtifact? source;
  TiniEditNode.source(String path, String fingerprint)
    : key = TiniEditCache.digest({'source': fingerprint}),
      extension = '',
      stage = 'source',
      retainGroup = null,
      parents = const [],
      producer = null,
      source = TiniEditArtifact(path);
  TiniEditNode({
    required this.stage,
    required Object? parameters,
    required List<TiniEditNode> inputs,
    required TiniEditProducer render,
    this.extension = 'mp4',
    this.retainGroup,
    String? cacheKey,
  }) : key = cacheKey ?? TiniEditCache.digest({
         'schema': 1,
         'stage': stage,
         'container': extension,
         'parameters': parameters,
         'inputs': inputs.map((n) => n.key).toList(),
       }),
       parents = List.unmodifiable(inputs),
       producer = render,
       source = null;

  /// Read-only stand-in for a fully committed checkpoint. Missing or pruned
  /// results throw and the caller rebuilds through the original effect graph.
  /// Never use it as an editable source or accept an arbitrary user key.
  TiniEditNode.cached(String cachedKey, {this.retainGroup})
      : key = cachedKey,
        extension = 'mp4',
        stage = 'editor.cached.result.v1',
        parents = const [],
        producer = ((_, __) async => throw StateError('Cached edit was evicted')),
        source = null;
}

class _Flight {
  final callers = <bool Function()?>[];
  late Future<TiniEditArtifact> future;
  bool get cancelled =>
      callers.isNotEmpty && callers.every((c) => c?.call() == true);
}

/// Persistent, content-addressed intermediate cache. Public results are owned
/// copies: existing editor cleanup can never delete a shared cache entry.
/// Evaluating a cached leaf does not visit or reconstruct its ancestors.
class TiniEditCache {
  static final shared = TiniEditCache();
  final Future<Directory> Function() _directory;
  final int maxBytes;
  final Duration maxAge;
  final _flights = <String, _Flight>{};
  final _pins = <String, int>{};
  // Retain a bounded history of completed face-processing checkpoints so
  // undo/redo can recover earlier results without rerunning the same work.
  final _retained = <String, List<String>>{};
  final _retainedSizes = <String, int>{};
  final _retainedOrder = <String>[];
  final _deletions = <String, Future<void>>{};
  final _fingerprints = <String, String>{};
  // Serialize commits to each project ledger. A process restart cannot
  // recreate previous edit snapshots from an in-memory list alone.
  final _editorHistoryWrites = <String, Future<void>>{};
  Future<Directory>? _root;
  Future<void>? _pruning;
  Future<void> _maintenance = Future.value();
  int hits = 0, misses = 0;
  final stageHits = <String, int>{};
  final stageBuilds = <String, int>{};
  Future<void> get idle => _maintenance;

  /// Retain recently completed retouch stages, not entire edit histories.
  /// The GPU export retains up to four valid results; the software stages
  /// retain up to two each. Earlier results share half the cache budget.
  /// This keeps undo/redo responsive without pinning unlimited video files.
  /// A changed *upstream* pixel graph still needs correct reprocessing.
  Future<void> _retain(TiniEditNode node, String path) async {
    final group = node.retainGroup ?? switch (node.stage) {
      'skin.v1' => 'editor.retouch.skin',
      'teeth.v1' => 'editor.retouch.teeth',
      _ => null,
    };
    if (group == null) return;
    final budget = maxBytes ~/ 2;
    if (budget <= 0) return;
    int bytes;
    try {
      bytes = await File(path).length();
    } on FileSystemException {
      return;
    }
    // Very large lossless intermediate files remain under the normal cache
    // eviction policy. Never make the protected history consume all space.
    if (bytes <= 0 || (bytes > budget && group != 'editor.gpu.checkpoint')) return;

    final keys = _retained.putIfAbsent(group, () => <String>[]);
    if (keys.remove(node.key)) {
      _retainedOrder.remove(node.key);
    } else {
      _pin(node.key);
    }
    keys.add(node.key);
    _retainedSizes[node.key] = bytes;
    _retainedOrder.add(node.key);

    final limit = group == 'editor.gpu.checkpoint'
        ? 4
        : group.startsWith('editor.incremental.')
            ? 12
            : 2;
    while (keys.length > limit) {
      _unretainKey(keys.first);
    }
    var protectedBytes = _retainedSizes.values.fold<int>(0, (a, b) => a + b);
    while (protectedBytes > budget && _retainedOrder.isNotEmpty) {
      // Preserve the latest GPU result as before; release older history first.
      final gpu = _retained['editor.gpu.checkpoint'];
      final newestGpu = gpu == null || gpu.isEmpty ? null : gpu.last;
      final oldest = _retainedOrder.firstWhere(
        (key) => key != newestGpu,
        orElse: () => '',
      );
      if (oldest.isEmpty) break;
      protectedBytes -= _retainedSizes[oldest] ?? 0;
      _unretainKey(oldest);
    }
  }

  void _unretainKey(String key) {
    for (final group in _retained.values) {
      group.remove(key);
    }
    _retainedOrder.remove(key);
    if (_retainedSizes.remove(key) != null) _unpin(key);
  }

  void releaseRetention(String group) {
    final keys = _retained.remove(group);
    if (keys != null) {
      for (final key in keys) {
        _retainedOrder.remove(key);
        if (_retainedSizes.remove(key) != null) _unpin(key);
      }
    }
    _queuePrune();
  }

  // Many consecutive render stages request the same disk cleanup. Delay a
  // scan briefly to coalesce a burst, and do one more pass only when an entry
  // was committed while the preceding scan was already running.
  bool _pruneQueued = false;
  bool _pruneAgain = false;

  void _queuePrune() {
    if (_pruneQueued) {
      _pruneAgain = true;
      return;
    }
    _pruneQueued = true;
    _maintenance = _maintenance.then((_) async {
      try {
        do {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          _pruneAgain = false;
          await prune();
        } while (_pruneAgain);
      } finally {
        _pruneQueued = false;
      }
    }).catchError((Object _) {
      // A transient disk error must not prevent future cleanup requests.
      _pruneQueued = false;
    });
  }

  TiniEditCache({
    Future<Directory> Function()? directory,
    this.maxBytes = 1024 * 1024 * 1024,
    this.maxAge = const Duration(days: 7),
  }) : _directory =
           directory ??
           (() async => Directory(
             '${(await getTemporaryDirectory()).path}/tini_edit_graph_v1',
           ));

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _canonical(value[k])};
    }
    if (value is Iterable) return value.map(_canonical).toList();
    if (value is double && !value.isFinite) {
      throw ArgumentError('Non-finite render parameter');
    }
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    throw ArgumentError('Unsupported render parameter: ${value.runtimeType}');
  }

  static String digest(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

  Future<Directory> _open() async {
    final dir = await (_root ??= _directory());
    // Android can remove its cache directory while the process is alive.
    await dir.create(recursive: true);
    return dir;
  }

  /// Contents, not a transient filename, identify sources and media assets.
  /// changed/modified/size memoization also detects overwritten same-size files.
  Future<String> fingerprint(String path) async {
    final uri = Uri.tryParse(path);
    final local = uri?.scheme == 'file' ? uri!.toFilePath() : path;
    if (uri != null && uri.hasScheme && uri.scheme != 'file') {
      // A mutable remote URL has no immutable local identity: do not reuse its
      // processing until the existing media loader has produced a local file.
      return digest({
        'remote': path,
        'request': DateTime.now().microsecondsSinceEpoch,
      });
    }
    final type = await FileSystemEntity.type(local);
    if (type == FileSystemEntityType.directory) {
      final files = await Directory(local)
          .list(recursive: true, followLinks: false)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      return digest([
        for (final f in files)
          [f.path.substring(local.length), await fingerprint(f.path)],
      ]);
    }
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Render source is missing', local);
    }
    final file = File(local);
    final stat = await file.stat();
    final stamp =
        '$local|${stat.size}|${stat.modified.microsecondsSinceEpoch}|${stat.changed.microsecondsSinceEpoch}';
    final known = _fingerprints[stamp];
    if (known != null) return known;
    final hash = (await sha256.bind(file.openRead()).first).toString();
    if (_fingerprints.length > 512) _fingerprints.clear();
    _fingerprints[stamp] = hash;
    return hash;
  }

  Future<TiniEditNode> source(String path) async {
    final uri = Uri.tryParse(path);
    final local = uri?.scheme == 'file' ? uri!.toFilePath() : path;
    return TiniEditNode.source(local, await fingerprint(local));
  }

  void _pin(String key) => _pins[key] = (_pins[key] ?? 0) + 1;
  void _unpin(String key) {
    final n = (_pins[key] ?? 1) - 1;
    if (n == 0) {
      _pins.remove(key);
    } else {
      _pins[key] = n;
    }
  }

  Future<TiniEditArtifact?> _read(TiniEditNode node, Directory root) async {
    try {
      final dir = Directory('${root.path}/${node.key}');
      final metaFile = File('${dir.path}/entry.json');
      final data =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final file = File('${dir.path}/artifact.${node.extension}');
      final stat = await file.stat();
      if (data['key'] != node.key ||
          stat.size <= 0 ||
          data['size'] != stat.size ||
          data['modified'] != stat.modified.microsecondsSinceEpoch) {
        return null;
      }
      await metaFile.setLastModified(DateTime.now());
      return TiniEditArtifact(
        file.path,
        metadata: Map<String, dynamic>.from(data['metadata'] as Map? ?? {}),
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<TiniEditArtifact> _resolve(
    TiniEditNode node,
    bool Function()? cancelled,
  ) async {
    if (cancelled?.call() == true) throw TiniEditCancelled();
    if (node.source != null) return node.source!;
    final eviction = _deletions[node.key];
    if (eviction != null) {
      try {
        await eviction;
      } on FileSystemException {
        /* Revalidate below. */
      }
    }
    if (cancelled?.call() == true) throw TiniEditCancelled();
    _pin(node.key);
    try {
      var flight = _flights[node.key];
      if (flight == null) {
        flight = _Flight();
        _flights[node.key] = flight;
        flight.callers.add(cancelled);
        final task = flight;
        task.future = _materialize(node, () => task.cancelled);
        // Always install an error handler, including when the only waiter cancels.
        task.future.then(
          (_) {
            if (identical(_flights[node.key], task)) _flights.remove(node.key);
          },
          onError: (Object _, StackTrace _) {
            if (identical(_flights[node.key], task)) _flights.remove(node.key);
          },
        );
      } else {
        flight.callers.add(cancelled);
      }
      final result = await flight.future;
      if (cancelled?.call() == true) throw TiniEditCancelled();
      return result;
    } catch (_) {
      _unpin(node.key);
      rethrow;
    }
  }

  Future<TiniEditArtifact> _materialize(
    TiniEditNode node,
    bool Function() cancelled,
  ) async {
    final root = await _open();
    final saved = await _read(node, root);
    if (saved != null) {
      // Completed artifacts remain valid for undo/redo even if a caller was superseded.
      await _retain(node, saved.path);
      hits++;
      stageHits.update(node.stage, (n) => n + 1, ifAbsent: () => 1);
      return saved;
    }
    misses++;
    final inputs = <TiniEditArtifact>[];
    Directory? work;
    TiniEditArtifact? produced;
    try {
      for (final parent in node.parents) {
        inputs.add(await _resolve(parent, cancelled));
      }
      if (cancelled()) throw TiniEditCancelled();
      produced = await node.producer!(inputs, cancelled);
      // A fully completed immutable result is useful even if its UI request
      // was replaced meanwhile. _resolve still rejects the obsolete caller.
      // Cooperative producers throw before returning an incomplete artifact.
      final inputFile = File(produced.path);
      if (!await inputFile.exists() || await inputFile.length() == 0) {
        throw StateError('Empty artifact for ${node.key}');
      }
      work = await root.createTemp('.pending_');
      final destination = '${work.path}/artifact.${node.extension}';
      File artifact;
      if (produced.temporary && !inputs.any((i) => i.path == produced!.path)) {
        try {
          artifact = await inputFile.rename(destination);
        } on FileSystemException {
          artifact = await inputFile.copy(destination);
        }
      } else {
        artifact = await inputFile.copy(destination);
      }
      final stat = await artifact.stat();
      await File('${work.path}/entry.json').writeAsString(
        jsonEncode({
          'key': node.key,
          'size': stat.size,
          'modified': stat.modified.microsecondsSinceEpoch,
          'metadata': produced.metadata,
        }),
        flush: true,
      );
      final target = Directory('${root.path}/${node.key}');
      if (await target.exists()) await target.delete(recursive: true);
      await work.rename(target.path);
      work = null;
      // Keep a fully committed checkpoint under the bounded retention policy.
      await _retain(node, '${target.path}/artifact.${node.extension}');
      stageBuilds.update(node.stage, (n) => n + 1, ifAbsent: () => 1);
      return TiniEditArtifact(
        '${target.path}/artifact.${node.extension}',
        metadata: produced.metadata,
      );
    } finally {
      for (var i = 0; i < inputs.length; i++) {
        if (node.parents[i].source == null) _unpin(node.parents[i].key);
      }
      _queuePrune();
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
      if (produced?.temporary == true &&
          !inputs.any((i) => i.path == produced!.path)) {
        try {
          await File(produced!.path).delete();
        } on FileSystemException {
          /* Already released by its engine. */
        }
      }
      if (produced?.temporary == true &&
          !inputs.any((i) => i.path == produced!.path)) {
        final parent = File(produced!.path).parent;
        if (parent.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('tini_')) {
          try {
            await parent.delete();
          } on FileSystemException {
            /* Not an empty owned folder. */
          }
        }
      }
    }
  }

  /// Verify a committed cache leaf without rendering or copying its ancestors.
  /// Stale history entries are ignored rather than forcing an expensive export.
  Future<bool> containsCached(TiniEditNode node) async {
    if (node.source != null) return false;
    final eviction = _deletions[node.key];
    if (eviction != null) {
      try {
        await eviction;
      } on FileSystemException {
        // The validation below will decide whether the entry survived.
      }
    }
    return await _read(node, await _open()) != null;
  }

  static bool _isCacheIdentity(String value) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

  /// An index only: video bytes always remain in the existing content-addressed
  /// cache. Missing, pruned or corrupt results are not recreated from the index.
  /// The manifest is local to the device; no editor history is sent to a server.
  Future<List<Map<String, dynamic>>> editorHistory(String project) async {
    if (!_isCacheIdentity(project)) return const [];
    final pending = _editorHistoryWrites[project];
    if (pending != null) await pending;
    final file = File('${(await _open()).path}/editor_history_$project.json');
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['schema'] != 1 || raw['project'] != project ||
          raw['entries'] is! List) return const [];
      final result = <Map<String, dynamic>>[];
      for (final item in raw['entries'] as List) {
        if (item is! Map ||
            item['signature'] is! String ||
            !_isCacheIdentity(item['signature'] as String) ||
            item['clips'] is! List) continue;
        final entry = Map<String, dynamic>.from(item);
        final previous = entry['previous'];
        if (previous != null &&
            (previous is! String || !_isCacheIdentity(previous) ||
                previous == entry['signature'])) {
          entry.remove('previous');
        }
        result.add(entry);
      }
      return result;
    } on FileSystemException {
      return const [];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  /// Persist the last completed projects in commit order. Atomic replacement
  /// prevents an interrupted write from turning a valid result into a false hit.
  Future<void> rememberEditorHistory(
    String project,
    String signature,
    List<Map<String, Object?>> clips, {
    String? previousSignature,
  }) async {
    if (!_isCacheIdentity(project) || !_isCacheIdentity(signature) ||
        (previousSignature != null &&
            !_isCacheIdentity(previousSignature))) {
      throw ArgumentError('Invalid edit history identifier');
    }
    final previous = _editorHistoryWrites[project] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) async {
      final directory = await _open();
      final file = File('${directory.path}/editor_history_$project.json');
      List<dynamic> records = [];
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map && decoded['schema'] == 1 &&
            decoded['project'] == project && decoded['entries'] is List) {
          records = List<dynamic>.of(decoded['entries'] as List);
        }
      } on FileSystemException {
        // The first completed export creates the index.
      } on FormatException {
        // A truncated index can be rebuilt from valid completed renders.
      } on TypeError {
        // Do not trust a malformed index.
      }
      // Preserve the previous editor parent on a repeated publication of an
      // already-known state. Completion order is not user edit order, because
      // warmup and publishing can finish in either order.
      String? recordedParent;
      for (final item in records) {
        if (item is Map && item['signature'] == signature &&
            item['previous'] is String &&
            _isCacheIdentity(item['previous'] as String)) {
          recordedParent = item['previous'] as String;
        }
      }
      records.removeWhere((entry) =>
          entry is! Map || entry['signature'] == signature);
      final parent = previousSignature != signature
          ? (previousSignature ?? recordedParent)
          : recordedParent;
      records.add({
        'signature': signature,
        'clips': clips,
        if (parent != null && parent != signature) 'previous': parent,
      });
      if (records.length > 12) records = records.sublist(records.length - 12);
      final json = jsonEncode({
        'schema': 1,
        'project': project,
        'entries': records,
      });
      // Mask strokes can be large. Rendering is still cached even when the
      // index would be larger than the bounded history budget.
      if (json.length > 256 * 1024) return;
      final pending = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.pending');
      try {
        await pending.writeAsString(json, flush: true);
        await pending.rename(file.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
    });
    _editorHistoryWrites[project] = next;
    try {
      await next;
    } finally {
      if (identical(_editorHistoryWrites[project], next)) {
        _editorHistoryWrites.remove(project);
      }
    }
  }

  /// Returns an independent owned file. The graph's protected entries remain
  /// reusable after controllers, undo snapshots or publish cleanup delete it.
  Future<TiniEditArtifact> run(
    TiniEditNode node, {
    bool Function()? cancelled,
  }) async {
    final saved = await _resolve(node, cancelled);
    try {
      if (cancelled?.call() == true) throw TiniEditCancelled();
      if (node.source != null) return saved;
      final root = await _open();
      final leases = await Directory(
        '${root.path}/leases',
      ).create(recursive: true);
      final folder = await leases.createTemp('result_');
      try {
        final copy = await File(
          saved.path,
        ).copy('${folder.path}/result.${node.extension}');
        // Keep the immutable cache hit, but do not hand an obsolete edit
        // a large owned copy once the user has moved to a newer operation.
        if (cancelled?.call() == true) throw TiniEditCancelled();
        return TiniEditArtifact(
          copy.path,
          metadata: saved.metadata,
          temporary: true,
        );
      } catch (_) {
        await folder.delete(recursive: true);
        rethrow;
      }
    } finally {
      if (node.source == null) _unpin(node.key);
      _queuePrune();
    }
  }

  /// Only cache-owned, unpinned results are evicted. Undo/redo do not purge data.
  Future<void> prune({int? targetBytes}) async {
    while (_pruning != null) {
      await _pruning;
    }
    final done = Completer<void>();
    _pruning = done.future;
    try {
      await _pruneEntries(targetBytes);
    } finally {
      _pruning = null;
      done.complete();
    }
  }

  Future<void> _pruneEntries(int? targetBytes) async {
    final root = await _open();
    final entries =
        <({Directory dir, int bytes, DateTime accessed, String key})>[];
    var total = 0;
    await for (final item in root.list()) {
      if (item is! Directory) continue;
      final key = item.path.split(Platform.pathSeparator).last;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) continue;
      try {
        final meta = File('${item.path}/entry.json');
        final stat = await meta.stat();
        final data = jsonDecode(await meta.readAsString()) as Map;
        final size = (data['size'] as num).toInt();
        total += size;
        entries.add((
          dir: item,
          bytes: size,
          accessed: stat.modified,
          key: key,
        ));
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    entries.sort((a, b) => a.accessed.compareTo(b.accessed));
    for (final e in entries) {
      if (_pins.containsKey(e.key)) continue;
      if (total <= (targetBytes ?? maxBytes) &&
          DateTime.now().difference(e.accessed) <= maxAge) {
        continue;
      }
      try {
        final deletion = e.dir.delete(recursive: true).then<void>((_) {});
        _deletions[e.key] = deletion;
        try {
          await deletion;
          total -= e.bytes;
        } finally {
          _deletions.remove(e.key);
        }
      } on FileSystemException {
        /* Another cleanup won. */
      }
    }
  }
}
