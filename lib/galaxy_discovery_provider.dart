import 'dart:async';
import 'dart:ui' show Offset;
import 'galaxy_star.dart';
import 'package:flutter/foundation.dart';
import 'audience_policy.dart';
import 'galaxy_discovery_selector.dart';
import 'galaxy_discovery_service.dart';
import 'galaxy_user_star.dart';

class GalaxyDiscoveryProvider extends ChangeNotifier {
  final GalaxyDiscoveryBackend backend;
  final DateTime Function() now;
  final List<StreamSubscription<dynamic>> _sessionSubs = [];
  StreamSubscription<String?>? _identity;
  StreamSubscription<GalaxyRecords>? _profilesSub;
  String? _uid;
  int _generation = 0, _ticket = 0, _refresh = 0, _profileVersion = 0;
  bool _disposed = false, _active = false;
  bool _viewerReady = false, _blocksReady = false, _reverseReady = false;
  bool _profilesReady = false;
  Map<String, dynamic> _viewer = {};
  Set<String> _blocks = {}, _reverse = {};
  Map<String, Map<String, dynamic>> _profiles = {};
  List<GalaxyUserStar> _placed = [];
  DateTime? _loadedAt;
  bool loading = false;
  String? error;

  GalaxyDiscoveryProvider(this.backend, {DateTime Function()? now})
    : now = now ?? DateTime.now {
    _setIdentity(backend.currentUid);
    _identity = backend.identityChanges.listen(
      _setIdentity,
      onError: (_) {
        _setIdentity(null);
      },
    );
  }

  bool get _gatesReady => _viewerReady && _blocksReady && _reverseReady;
  List<GalaxyUserStar> get stars =>
      !_gatesReady || !_profilesReady || _uid != backend.currentUid
      ? const []
      : List.unmodifiable(
          _placed
              .where((star) => _allowed(star.uid))
              .map(
                (star) => GalaxyUserStar.fromProfile(
                  star.uid,
                  _profiles[star.uid]!,
                  star.position,
                ),
              ),
        );

  /// The owner's private document is already observed for audience checks.
  /// Self visibility is independent of eligibility, blocks and discovery slots.
  GalaxyUserStar? get ownStar {
    final uid = _uid;
    if (_disposed ||
        !_viewerReady ||
        uid == null ||
        uid != backend.currentUid) {
      return null;
    }
    return GalaxyUserStar.fromProfile(
      uid,
      _viewer,
      GalaxyStar.worldSize.center(Offset.zero),
    );
  }

  bool _allowed(String id, {Map<String, dynamic>? profile}) {
    final data = profile ?? _profiles[id];
    final blockedArrays = [
      if (_viewer['blockedUsers'] is List) ...(_viewer['blockedUsers'] as List),
      if (_viewer['blocked'] is List) ...(_viewer['blocked'] as List),
    ];
    return _gatesReady &&
        id != _uid &&
        !_blocks.contains(id) &&
        !_reverse.contains(id) &&
        !blockedArrays.contains(id) &&
        data != null &&
        data['galaxyEligible'] == true &&
        data['isPrivate'] != true &&
        (AudiencePolicy.viewerIsAdult(_viewer, now: now()) ||
            !AudiencePolicy.isAccountRestricted(data));
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation, [int? ticket]) =>
      !_disposed &&
      generation == _generation &&
      _uid == backend.currentUid &&
      (ticket == null || ticket == _ticket);

  void _setIdentity(String? uid) {
    if (_disposed || (_uid == uid && _sessionSubs.isNotEmpty)) return;
    _generation++;
    _ticket++;
    for (final sub in _sessionSubs) {
      unawaited(sub.cancel());
    }
    _sessionSubs.clear();
    unawaited(_profilesSub?.cancel());
    _profilesSub = null;
    _uid = uid;
    _viewer = {};
    _blocks = {};
    _reverse = {};
    _profiles = {};
    _placed = [];
    _loadedAt = null;
    _refresh = 0;
    loading = false;
    error = null;
    _viewerReady = _blocksReady = _reverseReady = _profilesReady = false;
    if (uid != null) {
      final generation = _generation;
      void changed() {
        if (!_current(generation)) return;
        if (!_gatesReady) {
          error = 'بانتظار الاتصال للتحقق من الحساب والخصوصية…';
        } else if (error?.startsWith('بانتظار الاتصال') == true) {
          error = null;
        }
        _emit();
        if (_active && _gatesReady && _loadedAt == null && !loading) {
          unawaited(load());
        }
      }

      _sessionSubs.add(
        backend
            .watchViewer(uid)
            .listen(
              (event) {
                if (!_current(generation)) return;
                _viewer = event.records[uid] ?? {};
                _viewerReady = event.verified && event.records.containsKey(uid);
                changed();
              },
              onError: (_) {
                if (_current(generation)) {
                  _viewerReady = false;
                  error = 'تعذّر التحقق من الحساب. أعد المحاولة.';
                  _emit();
                }
              },
            ),
      );
      for (final reverse in [false, true]) {
        _sessionSubs.add(
          backend
              .watchBlocks(uid, reverse: reverse)
              .listen(
                (event) {
                  if (!_current(generation)) return;
                  if (reverse) {
                    _reverse = event.records.keys.toSet();
                    _reverseReady = event.verified;
                  } else {
                    _blocks = event.records.keys.toSet();
                    _blocksReady = event.verified;
                  }
                  changed();
                },
                onError: (_) {
                  if (!_current(generation)) return;
                  if (reverse) {
                    _reverseReady = false;
                  } else {
                    _blocksReady = false;
                  }
                  error = 'تعذّر التحقق من الخصوصية. أعد المحاولة.';
                  _emit();
                },
              ),
        );
      }
    }
    _emit();
  }

  void setActive(bool active) {
    _active = active;
    if (active &&
        _gatesReady &&
        (_loadedAt == null ||
            now().difference(_loadedAt!) >= const Duration(minutes: 15))) {
      scheduleMicrotask(() {
        if (!_disposed && _active) unawaited(load());
      });
    }
  }

  Future<void> refresh() async {
    if (!_gatesReady) {
      final uid = _uid;
      _setIdentity(null);
      _setIdentity(uid);
      return;
    }
    _refresh++;
    await load();
  }

  Future<void> load() async {
    if (_disposed || loading || !_gatesReady || _uid == null) return;
    final generation = _generation, ticket = ++_ticket;
    final uid = _uid!;
    loading = true;
    error = null;
    _emit();
    final cycle = GalaxyDiscoverySelector.cycle(now());
    final shared = <String>[], personal = <String>[];
    final candidates = <String, Map<String, dynamic>>{};
    // Evaluate the newest viewer/block state on every page, not a stale copy.
    bool allowed(String id) => _allowed(id, profile: candidates[id]);

    List<String> select() => GalaxyDiscoverySelector.select(
      shared: shared,
      personal: personal,
      allowed: allowed,
    );
    try {
      for (final common in [true, false]) {
        final seed = common ? 'shared:$cycle' : '$uid:$cycle:$_refresh';
        await for (final page in backend.pages(
          GalaxyDiscoverySelector.pivot(seed),
        )) {
          if (!_current(generation, ticket)) return;
          candidates.addAll(page);
          (common ? shared : personal).addAll(page.keys);
          if (common
              ? shared.where(allowed).length >= 6
              : select().length >= 30) {
            break;
          }
        }
      }
      if (!_current(generation, ticket)) return;
      final ids = select();
      await _profilesSub?.cancel();
      if (!_current(generation, ticket)) return;
      _profiles = {for (final id in ids) id: candidates[id]!};
      _placed = GalaxyDiscoverySelector.place(
        ids,
        _profiles,
        '$uid:$cycle:$_refresh',
      );
      _profilesReady = true;
      _loadedAt = now();
      final profileVersion = ++_profileVersion;
      if (ids.isNotEmpty) {
        _profilesSub = backend
            .watchProfiles(ids)
            .listen(
              (event) {
                if (!_current(generation) ||
                    profileVersion != _profileVersion) {
                  return;
                }
                _profiles = event.records;
                _profilesReady = event.verified;
                if (!event.verified) {
                  error = 'بانتظار الاتصال لتحديث النجوم…';
                } else if (error?.startsWith('بانتظار الاتصال') == true) {
                  error = null;
                }
                _emit();
              },
              onError: (_) {
                if (!_current(generation) ||
                    profileVersion != _profileVersion) {
                  return;
                }
                _profilesReady = false;
                error = 'تعذّر تحديث النجوم. تحقق من الاتصال وأعد المحاولة.';
                _emit();
              },
            );
      }
    } catch (_) {
      if (_current(generation, ticket)) {
        error = 'تعذّر تحميل النجوم. تحقق من الاتصال وأعد المحاولة.';
        // Keep verified existing stars; never substitute fake accounts.
      }
    } finally {
      if (_current(generation, ticket)) {
        loading = false;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _ticket++;
    unawaited(_identity?.cancel());
    unawaited(_profilesSub?.cancel());
    for (final sub in _sessionSubs) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}