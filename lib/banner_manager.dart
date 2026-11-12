import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'banner_policy.dart';
export 'banner_policy.dart';

class BannerManager {
  BannerManager._();
  static final instance = BannerManager._();
  final currentBanner = ValueNotifier<BannerItem?>(null);
  final policy = BannerPolicy();
  String? _uid;
  int _generation = 0;
  SharedPreferences? _prefs;
  Timer? _timer;
  Timer? _persistTimer;
  Future<void> _writes = Future.value();
  bool Function(BannerItem)? canPresent;
  final Map<Object, String? Function()> _visiblePosts = {};
  void watchVisiblePost(Object owner, String? Function() selected) =>
      _visiblePosts[owner] = selected;
  void unwatchVisiblePost(Object owner) => _visiblePosts.remove(owner);
  bool isViewingPost(String id) =>
      _visiblePosts.values.any((selected) => selected() == id);
  bool _opening = false;
  Future<bool> Function(Map<String, dynamic>)? foregroundActivity;
  Future<bool> handleForegroundActivity(Map<String, dynamic> data) async {
    if (_uid == null ||
        _prefs == null ||
        !const {
          'like',
          'comment',
          'reply',
          'follow',
          'mention',
        }.contains(data['type'])) {
      return false;
    }
    return await foregroundActivity?.call(data) ?? false;
  }

  bool get isOpening => _opening;
  bool beginOpen() {
    if (_opening) return false;
    _opening = true;
    return true;
  }

  void endOpen() => _opening = false;

  Future<void> bindUser(String? uid) async {
    final generation = ++_generation;
    _saveNow();
    clearAllQueues();
    policy.reset();
    _uid = uid;
    _prefs = null;
    foregroundActivity = null;
    if (uid == null) {
      await _writes;
      return;
    }
    await _writes;
    final prefs = await SharedPreferences.getInstance();
    if (_uid != uid || generation != _generation) return;
    _prefs = prefs;
    try {
      final saved =
          jsonDecode(prefs.getString('banner_v2:$uid') ?? '{}')
              as Map<String, dynamic>;
      for (final entry in saved.entries) {
        if (entry.value is int) {
          policy.history[entry.key] = DateTime.fromMillisecondsSinceEpoch(
            entry.value as int,
          );
        }
      }
    } catch (_) {
      /* Corrupt local presentation state never affects notifications. */
    }
    if (!prefs.containsKey('banner_v2:$uid')) {
      final now = DateTime.now();
      // Old activity IDs are globally unique even though the old keys weren't
      // account-scoped. Import only a bounded tail; visits use new timestamps.
      for (final key in [
        'shown_like_banners',
        'shown_comment_banners',
        'shown_follow_banners',
        'shown_mention_banners',
        'shown_banners',
      ]) {
        final ids = prefs.getStringList(key) ?? const <String>[];
        for (final id in ids.skip(ids.length > 300 ? ids.length - 300 : 0)) {
          policy.history['event:activity:$id'] = now;
        }
      }
      final prefix = 'activity_shown_${uid}_';
      for (final key in prefs.getKeys().where(
        (key) => key.startsWith(prefix),
      )) {
        final suffix = key.substring(prefix.length);
        if (suffix.length <= 11 || prefs.getBool(key) != true) continue;
        final actor = suffix.substring(0, suffix.length - 11);
        final day = suffix.substring(suffix.length - 10);
        if (day == now.toIso8601String().split('T').first) {
          policy.history['event:online:$actor:$day'] = now;
        }
      }
    }
    policy.restore(DateTime.now());
    _save();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  bool enabled(BannerType type) {
    final key = switch (type) {
      BannerType.like => 'notify_like_banner',
      BannerType.comment => 'notify_comment_banner',
      BannerType.follow => 'notify_new_followers_banner',
      BannerType.mention => 'notify_mentions_banner',
      BannerType.visit => 'notify_profile_visits_banner',
      BannerType.activity => 'notify_activity_banner',
      BannerType.story => null,
    };
    return key == null || (_prefs?.getBool(key) ?? true);
  }

  bool _eligible(BannerItem item) =>
      enabled(item.type) && (canPresent?.call(item) ?? true);
  void _tick() {
    final previous = policy.current;
    policy.tick(DateTime.now(), eligible: _eligible);
    if (!identical(previous, policy.current)) {
      currentBanner.value = policy.current;
      _save();
    }
  }

  void submit(BannerEvent event) {
    if (_uid == null || _prefs == null || !enabled(event.type)) return;
    if (policy.add(event, DateTime.now())) currentBanner.value = policy.current;
    _save();
  }

  void dismiss({bool manual = true}) {
    policy.dismiss(DateTime.now(), manual: manual);
    currentBanner.value = null;
    _save();
  }

  void setForeground(bool value) {
    policy.foreground = value;
    if (!value) {
      policy.pending.clear();
      dismiss(manual: false);
    }
  }

  void _save() {
    _persistTimer ??= Timer(const Duration(milliseconds: 200), _saveNow);
  }

  void _saveNow() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final uid = _uid;
    final prefs = _prefs;
    if (uid == null || prefs == null) return;
    final value = jsonEncode(
      policy.history.map((key, at) => MapEntry(key, at.millisecondsSinceEpoch)),
    );
    _writes = _writes
        .then((_) async {
          await prefs.setString('banner_v2:$uid', value);
        })
        .catchError((Object _) {});
  }

  void clearAllQueues() {
    _timer?.cancel();
    _timer = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    policy.pending.clear();
    policy.current = null;
    currentBanner.value = null;
    _opening = false;
  }

  void dispose() => clearAllQueues();
}
