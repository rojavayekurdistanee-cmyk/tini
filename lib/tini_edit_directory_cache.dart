import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'tini_edit_cache.dart';

class TiniEditDirectoryResult {
  final String path;
  final Map<String, dynamic> metadata;
  final Future<void> Function()? release;
  const TiniEditDirectoryResult(this.path, this.metadata, {this.release});
}

/// File-backed analysis results (segmentation masks, poses) are independent of
/// visual effects. Store the immutable directory as an uncompressed archive;
/// callers receive their own extraction and can keep existing cleanup rules.
class TiniEditDirectoryCache {
  static Future<void> _validate(TiniEditDirectoryResult result) async {
    final count = result.metadata['count'] ?? result.metadata['frames'];
    if (count is! int || count < 1) return;
    final masks = result.metadata.containsKey('count');
    final prefix = masks ? 'mask' : 'frame';
    for (var i = 0; i < count; i++) {
      final file = File(
        '${result.path}/${prefix}_${i.toString().padLeft(6, '0')}.png',
      );
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('Incomplete $prefix analysis');
      }
    }
    final poses = File('${result.path}/poses.json');
    if (await poses.exists()) {
      final data = jsonDecode(await poses.readAsString());
      if (data is! List || data.length != count) {
        throw StateError('Incomplete pose analysis');
      }
    }
  }

  static Future<TiniEditDirectoryResult> obtain({
    required String stage,
    required Object parameters,
    required List<String> sources,
    required Future<TiniEditDirectoryResult> Function(
      List<TiniEditArtifact>,
      bool Function(),
    )
    build,
    bool persistentExtraction = false,
    bool Function()? cancelled,
  }) async {
    final cache = TiniEditCache.shared;
    final inputs = <TiniEditNode>[
      for (final source in sources) await cache.source(source),
    ];
    final node = TiniEditNode(
      stage: stage,
      parameters: parameters,
      inputs: inputs,
      extension: 'zip',
      render: (i, stop) async {
        if (stop()) throw TiniEditCancelled();
        final result = await build(i, stop);
        final temp = await getTemporaryDirectory();
        await temp.create(recursive: true);
        final folder = await temp.createTemp('tini_analysis_pack_');
        final path = '${folder.path}/analysis.zip';
        try {
          await _validate(result);
          await ZipFileEncoder().zipDirectory(
            Directory(result.path),
            filename: path,
            level: ZipFileEncoder.store,
            followLinks: false,
          );
          return TiniEditArtifact(
            path,
            metadata: result.metadata,
            temporary: true,
          );
        } catch (_) {
          if (await folder.exists()) await folder.delete(recursive: true);
          rethrow;
        } finally {
          try {
            await Directory(result.path).delete(recursive: true);
          } catch (_) {}
          await result.release?.call();
        }
      },
    );
    final saved = await cache.run(node, cancelled: cancelled);
    final root = persistentExtraction
        ? await getApplicationSupportDirectory()
        : await getTemporaryDirectory();
    await root.create(recursive: true);
    final output = await root.createTemp('tini_analysis_');
    try {
      await extractFileToDisk(saved.path, output.path);
      return TiniEditDirectoryResult(output.path, saved.metadata);
    } catch (_) {
      if (await output.exists()) await output.delete(recursive: true);
      rethrow;
    } finally {
      try {
        await File(saved.path).delete();
      } catch (_) {}
    }
  }
}
