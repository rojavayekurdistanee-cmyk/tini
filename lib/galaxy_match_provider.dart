import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'galaxy_match_models.dart';
import 'galaxy_match_service.dart';

class GalaxyMatchProvider extends ChangeNotifier {
  final GalaxyMatchBackend backend;
  StreamSubscription<String?>? _identity;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _uid;
  int _session = 0;
  bool _disposed = false;
  bool busy = false, ready = false, hasMore = false;
  String? error;
  GalaxyMatchPreferences? _preferences;
  List<GalaxyMatchPreview> _results = [];
  final Map<String, GalaxyMatchInvite> _items = {};
  Set<String> _blocked = {}, _blockedBy = {};
  Set<String> _liveIds = {};
  bool _blocksReady = false, _reverseReady = false;

  GalaxyMatchProvider(this.backend) {
    _setUser(backend.currentUid);
    _identity = backend.identityChanges.listen(
      _setUser,
      onError: (_) => _setUser(null),
    );
  }
  bool get signedIn => !_disposed && _uid != null && _uid == backend.currentUid;
  String? get userId => signedIn ? _uid : null;
  GalaxyMatchPreferences? get preferences => signedIn ? _preferences : null;
  List<GalaxyMatchPreview> get results => !signedIn
      ? const []
      : List.unmodifiable(
          _results.where((r) => r.expiresAt.isAfter(DateTime.now())),
        );
  List<GalaxyMatchInvite> get items {
    if (!signedIn) return const [];
    final list = _items.values
        .where(
          (i) =>
              i.peerUid == null ||
              (_blocksReady &&
                  _reverseReady &&
                  !_blocked.contains(i.peerUid) &&
                  !_blockedBy.contains(i.peerUid)),
        )
        .toList();
    list.sort(_compare);
    return List.unmodifiable(list);
  }

  static int _compare(GalaxyMatchInvite a, GalaxyMatchInvite b) {
    final order = b.updatedAt.compareTo(a.updatedAt);
    return order == 0 ? b.id.compareTo(a.id) : order;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int session) =>
      !_disposed && session == _session && _uid == backend.currentUid;
  void _setUser(String? uid) {
    if (_disposed || (_uid == uid && _subscriptions.isNotEmpty)) return;
    _session++;
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
    _uid = uid;
    _preferences = null;
    _results = [];
    _items.clear();
    _liveIds = {};
    _blocked = {};
    _blockedBy = {};
    _blocksReady = _reverseReady = false;
    busy = false;
    ready = false;
    error = null;
    hasMore = false;
    if (uid != null) {
      final session = _session;
      void failed(Object e) {
        if (_valid(session)) {
          error = 'تعذّر تحميل البيانات. تحقق من الاتصال وأعد فتح القسم.';
          _emit();
        }
      }

      _subscriptions.add(
        backend.preferences(uid).listen((p) {
          if (_valid(session)) {
            if (_preferences?.offer != p?.offer ||
                _preferences?.need != p?.need ||
                p?.enabled != true) {
              _results = [];
            }
            _preferences = p;
            ready = true;
            _emit();
          }
        }, onError: failed),
      );
      _subscriptions.add(
        backend.inbox(uid).listen((list) {
          if (_valid(session)) {
            // Replace only the prior live page, preserving paginated records.
            for (final id in _liveIds) {
              _items.remove(id);
            }
            _liveIds = list.map((item) => item.id).toSet();
            for (final item in list) {
              _items[item.id] = item;
            }
            hasMore = list.length == 100;
            _emit();
          }
        }, onError: failed),
      );
      for (final reverse in [false, true]) {
        _subscriptions.add(
          backend
              .blocks(uid, reverse: reverse)
              .listen(
                (ids) {
                  if (_valid(session)) {
                    if (reverse) {
                      _blockedBy = ids;
                      _reverseReady = true;
                    } else {
                      _blocked = ids;
                      _blocksReady = true;
                    }
                    _emit();
                  }
                },
                onError: (Object e) {
                  if (_valid(session)) {
                    if (reverse) {
                      _reverseReady = false;
                    } else {
                      _blocksReady = false;
                    }
                    failed(e);
                  }
                },
              ),
        );
      }
    }
    _emit();
  }

  Future<bool> _run(Future<void> Function(int) task) async {
    if (!signedIn || busy) return false;
    final session = _session;
    busy = true;
    error = null;
    _emit();
    try {
      await task(session);
      return _valid(session);
    } on FirebaseFunctionsException catch (e) {
      if (_valid(session)) error = e.message ?? 'تعذّر تنفيذ العملية.';
      return false;
    } catch (_) {
      if (_valid(session)) error = 'تعذّر تنفيذ العملية. أعد المحاولة.';
      return false;
    } finally {
      if (_valid(session)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> save(String offer, String need, bool enabled) =>
      _run((session) async {
        await backend.call('saveGalaxyMatchPreferences', {
          'offer': offer,
          'need': need,
          'enabled': enabled,
        });
        if (_valid(session)) {
          _preferences = GalaxyMatchPreferences(
            offer: offer,
            need: need,
            enabled: enabled,
          );
          _results = [];
        }
      });
  Future<bool> discover() => _run((session) async {
    final data = await backend.call('discoverGalaxyMatches', {});
    if (_valid(session)) {
      _results = (data['results'] as List? ?? [])
          .map(
            (r) =>
                GalaxyMatchPreview.fromMap(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    }
  });
  Future<bool> request(String token) => _run((session) async {
    await backend.call('requestGalaxyMatch', {'token': token});
    if (_valid(session)) _results.removeWhere((r) => r.token == token);
  });
  Future<bool> respond(String id, bool accept) => _run((_) async {
    await backend.call('respondGalaxyMatch', {'id': id, 'accept': accept});
  });
  Future<bool> manage(String id, String action) => _run((_) async {
    await backend.call('manageGalaxyMatch', {'id': id, 'action': action});
  });
  Future<bool> loadMore() => _run((session) async {
    final current = _items.values.toList()..sort(_compare);
    if (current.isEmpty || !hasMore) return;
    final list = await backend.older(_uid!, current.last);
    if (_valid(session)) {
      for (final i in list) {
        _items[i.id] = i;
      }
      hasMore = list.length == 100;
    }
  });
  @override
  void dispose() {
    _disposed = true;
    _session++;
    unawaited(_identity?.cancel());
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}