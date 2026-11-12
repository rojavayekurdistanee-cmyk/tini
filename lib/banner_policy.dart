/// Deterministic presentation policy. Notification read state stays in Firestore.
enum BannerType { story, activity, like, comment, follow, mention, visit }

class BannerEvent {
  final String id;
  final BannerType type;
  final Map<String, dynamic> data;
  final DateTime at;
  BannerEvent(this.id, this.type, this.data, this.at);
  String get actor => data['uid'] as String? ?? '';
  String get groupKey => switch (type) {
    BannerType.like ||
    BannerType.comment ||
    BannerType.mention => '${type.name}:${data['postId']}',
    BannerType.story => 'story:$actor',
    _ => type.name,
  };
}

class BannerItem {
  final String id;
  final BannerType type;
  final Map<String, dynamic> data;
  final Map<String, String> actors;
  final Map<String, Map<String, dynamic>> events;
  Set<String> get eventIds => events.keys.toSet();
  final DateTime createdAt;
  final DateTime latestEventAt;
  BannerItem._(
    this.id,
    this.type,
    this.data,
    this.actors,
    this.events,
    this.createdAt,
    this.latestEventAt,
  );
  factory BannerItem.fromEvent(BannerEvent e, DateTime now) => BannerItem._(
    '${e.groupKey}:${now.microsecondsSinceEpoch}',
    e.type,
    Map.of(e.data),
    {e.actor: e.data['name'] as String? ?? 'مستخدم'},
    {e.id: Map.of(e.data)},
    now,
    e.at,
  );
  BannerItem add(BannerEvent e) => BannerItem._(
    id,
    type,
    Map.of(e.data),
    {...actors, e.actor: e.data['name'] as String? ?? 'مستخدم'},
    {...events, e.id: Map.of(e.data)},
    createdAt,
    e.at.isAfter(latestEventAt) ? e.at : latestEventAt,
  );
  String get groupKey => BannerEvent('', type, data, createdAt).groupKey;
  String get names {
    final values = actors.values.toList();
    if (values.length == 1) return values.first;
    final first = '${values[0]} و${values[1]}';
    return values.length > 2 ? '$first و${values.length - 2} آخرون' : first;
  }

  String get text {
    final plural = actors.length > 1;
    return switch (type) {
      BannerType.like => '$names ${plural ? 'أعجبوا' : 'أعجب'} بمنشورك',
      BannerType.comment =>
        '$names ${plural ? 'أضافوا تعليقات أو ردودًا' : (data['activityType'] == 'reply' ? 'ردّ على تعليقك' : 'علّق على منشورك')}',
      BannerType.follow => '$names ${plural ? 'بدأوا' : 'بدأ'} بمتابعتك',
      BannerType.mention => '$names ${plural ? 'ذكروك' : 'ذكرك'} في منشور',
      BannerType.visit => '$names ${plural ? 'زاروا' : 'زار'} ملفك الشخصي',
      BannerType.story =>
        '$names نشر قصة${eventIds.length > 1 ? ' جديدة (${eventIds.length})' : ''}',
      BannerType.activity => '$names ${plural ? 'نشطون' : 'نشط'} الآن',
    };
  }
}

class BannerPolicy {
  static const collect = Duration(seconds: 5);
  static const visible = Duration(seconds: 5);
  static const interval = Duration(seconds: 30);
  static const window = Duration(minutes: 5);
  static const cooldown = Duration(minutes: 10);
  static const expiry = Duration(minutes: 2);
  final Map<String, DateTime> history = {};
  final Map<String, BannerItem> pending = {};
  final List<DateTime> starts = [];
  BannerItem? current;
  DateTime? startedAt;
  bool foreground = true;

  bool _recent(String key, DateTime now, Duration age) =>
      history[key] != null && now.difference(history[key]!) < age;
  int _priority(BannerItem item) => switch (item.type) {
    BannerType.mention => 0,
    BannerType.comment =>
      item.events.values.any((data) => data['activityType'] == 'reply') ? 0 : 1,
    BannerType.follow => 2,
    BannerType.like => 3,
    BannerType.story => 4,
    BannerType.visit => 5,
    BannerType.activity => 6,
  };
  bool add(BannerEvent event, DateTime now) {
    prune(now);
    if (event.actor.isEmpty ||
        event.at.isAfter(now.add(const Duration(seconds: 30))) ||
        now.difference(event.at) > expiry ||
        _recent('event:${event.id}', now, const Duration(days: 2))) {
      return false;
    }
    history['event:${event.id}'] = now;
    if (!foreground) return false;
    if (event.type == BannerType.visit) {
      final key = 'visitor:${event.actor}';
      if (_recent(key, now, const Duration(hours: 24))) return false;
    }
    if (current?.groupKey == event.groupKey) {
      current = current!.add(event);
      return true;
    }
    if (_recent('group:${event.groupKey}', now, cooldown)) return false;
    if (event.type == BannerType.activity &&
        _recent('activity', now, const Duration(minutes: 30))) {
      return false;
    }
    pending[event.groupKey] =
        pending[event.groupKey]?.add(event) ?? BannerItem.fromEvent(event, now);
    if (pending.length > 30) pending.remove(pending.keys.first);
    return true;
  }

  void dismiss(DateTime now, {bool manual = false}) {
    if (current != null) {
      history['group:${current!.groupKey}'] = now;
      if (manual) history['dismissed:${current!.groupKey}'] = now;
    }
    current = null;
  }

  void tick(
    DateTime now, {
    bool Function(BannerItem)? eligible,
    bool Function(BannerItem)? readyToPresent,
  }) {
    prune(now);
    if (!foreground) {
      dismiss(now);
      return;
    }
    if (current != null) {
      if ((eligible != null && !eligible(current!)) ||
          (readyToPresent != null && !readyToPresent(current!))) {
        dismiss(now);
      } else if (startedAt != null && now.difference(startedAt!) >= visible) {
        dismiss(now);
      } else {
        return;
      }
    }
    starts.removeWhere((at) => now.difference(at) >= window);
    if ((startedAt != null && now.difference(startedAt!) < interval) ||
        starts.length >= 3) {
      return;
    }
    final ready =
        pending.values
            .where((b) => now.difference(b.createdAt) >= collect)
            .toList()
          ..sort((a, b) {
            final p = _priority(a).compareTo(_priority(b));
            return p != 0 ? p : a.createdAt.compareTo(b.createdAt);
          });
    for (final item in ready) {
      if (eligible != null && !eligible(item)) {
        pending.remove(item.groupKey);
        continue;
      }
      // Readiness (e.g. a profile gate still loading) is temporary. Do not
      // consume the group or its presentation cooldown before it can render.
      if (readyToPresent != null && !readyToPresent(item)) continue;
      pending.remove(item.groupKey);
      if (item.type == BannerType.activity &&
          _recent('activity', now, const Duration(minutes: 30))) {
        continue;
      }
      current = item;
      startedAt = now;
      starts.add(now);
      history['start:${now.microsecondsSinceEpoch}'] = now;
      history['group:${item.groupKey}'] = now;
      if (item.type == BannerType.visit) {
        for (final actor in item.actors.keys) {
          history['visitor:$actor'] = now;
        }
      }
      if (item.type == BannerType.activity) history['activity'] = now;
      break;
    }
  }

  void restore(DateTime now) {
    prune(now);
    starts.clear();
    starts.addAll(
      history.entries
          .where(
            (e) =>
                e.key.startsWith('start:') && now.difference(e.value) < window,
          )
          .map((e) => e.value),
    );
    if (starts.isNotEmpty) {
      starts.sort();
      startedAt = starts.last;
    }
  }

  void prune(DateTime now) {
    pending.removeWhere(
      (_, b) =>
          now.difference(b.createdAt) > expiry ||
          now.difference(b.latestEventAt) > expiry,
    );
    history.removeWhere(
      (_, at) => now.difference(at) > const Duration(days: 2),
    );
    while (history.length > 2000) {
      final oldestEvent = history.keys.firstWhere(
        (key) => key.startsWith('event:'),
        orElse: () => history.keys.first,
      );
      history.remove(oldestEvent);
    }
  }

  void reset() {
    pending.clear();
    history.clear();
    starts.clear();
    current = null;
    startedAt = null;
  }
}
