/// Deterministic presentation policy. Notification read state stays in Firestore.
enum BannerType { story, activity, like, comment, follow, mention, visit }

BannerType? bannerTypeForActivity(Object? type) => switch (type) {
  'like' => BannerType.like,
  'comment' || 'reply' => BannerType.comment,
  'follow' => BannerType.follow,
  'mention' || 'duet' => BannerType.mention,
  'story_new' => BannerType.story,
  _ => null,
};

/// Cache and pending writes cannot consume the later server-confirmed event.
class BannerSnapshotCursor {
  BannerSnapshotCursor(this.startedAt);
  final DateTime startedAt;
  final Map<String, DateTime> _versions = {};
  bool accept(
    String id,
    DateTime at, {
    required bool fromCache,
    required bool pendingWrites,
    required bool firstServerSnapshot,
  }) {
    if (fromCache || pendingWrites || _versions[id] == at) return false;
    _versions[id] = at;
    if (_versions.length > 3000) _versions.remove(_versions.keys.first);
    return !firstServerSnapshot || !at.isBefore(startedAt);
  }
}

/// Both relationship lists contribute to the live set of mutual friends.
class BannerPresenceState {
  final Set<String> followers = {};
  final Set<String> following = {};
  final Map<String, bool> online = {};
  List<String> get friends =>
      following.intersection(followers).toList()..sort();
  bool observe(
    String actor, {
    required bool isOnline,
    required DateTime sessionStartedAt,
    DateTime? lastSeen,
  }) {
    final previous = online[actor];
    online[actor] = isOnline;
    if (!isOnline) return false;
    return previous == false ||
        (previous == null &&
            lastSeen != null &&
            !lastSeen.isBefore(sessionStartedAt));
  }
}

class BannerEvent {
  final String id;
  final BannerType type;
  final Map<String, dynamic> data;
  final DateTime at;
  BannerEvent(this.id, this.type, this.data, this.at);
  String get actor => data['uid'] as String? ?? '';
  String get groupKey => switch (type) {
    BannerType.like || BannerType.comment => '${type.name}:${data['postId']}',
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
  BannerItem forDisplay(DateTime queuedAt) =>
      BannerItem._(id, type, data, actors, events, queuedAt, latestEventAt);

  BannerItem? withoutEvent(String eventId) {
    final remaining = Map<String, Map<String, dynamic>>.of(events)
      ..remove(eventId);
    if (remaining.isEmpty) return null;
    final people = <String, String>{};
    for (final value in remaining.values) {
      people[value['uid'] as String] = value['name'] as String? ?? 'مستخدم';
    }
    return BannerItem._(
      id,
      type,
      remaining.values.last,
      people,
      remaining,
      createdAt,
      latestEventAt,
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> presentation(Map<String, dynamic> value) => {
      for (final key in [
        'uid',
        'name',
        'img',
        'postId',
        'commentId',
        'replyToCommentId',
        'activityType',
      ])
        if (value[key] is String) key: value[key],
    };
    return {
      'id': id,
      'type': type.name,
      'data': presentation(data),
      'events': events.map((key, value) => MapEntry(key, presentation(value))),
      'createdAt': createdAt.millisecondsSinceEpoch,
      'latestAt': latestEventAt.millisecondsSinceEpoch,
    };
  }

  static BannerItem fromJson(Map<String, dynamic> json) {
    final type = BannerType.values.byName(json['type'] as String);
    final events = (json['events'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
    );
    if (events.isEmpty) throw const FormatException('Empty banner group');
    final people = <String, String>{};
    for (final data in events.values) {
      final uid = data['uid'] as String;
      if (uid.isEmpty) throw const FormatException('Missing actor');
      people[uid] = data['name'] as String? ?? 'مستخدم';
    }
    return BannerItem._(
      json['id'] as String,
      type,
      Map<String, dynamic>.from(json['data'] as Map),
      people,
      events,
      DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      DateTime.fromMillisecondsSinceEpoch(json['latestAt'] as int),
    );
  }

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
        '$names ${plural ? 'علّقوا على فيديوك' : (data['activityType'] == 'reply' ? 'ردّ على تعليقك' : 'علّق على فيديوك')}',
      BannerType.follow => '$names ${plural ? 'بدأوا' : 'بدأ'} بمتابعتك',
      BannerType.mention => 'تم ذكرك بواسطة $names',
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
  final Map<String, BannerItem> groups = {};
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
  String _onlineDay(String actor, DateTime now) =>
      'online_day:$actor:${now.toIso8601String().split('T').first}';

  void seed(BannerEvent event, DateTime now) {
    if (event.actor.isEmpty ||
        now.difference(event.at) > const Duration(days: 2) ||
        event.at.isAfter(now.add(const Duration(seconds: 30)))) {
      return;
    }
    final consumed = history['consumed:${event.groupKey}'];
    if (consumed != null && !event.at.isAfter(consumed)) return;
    final existing = groups[event.groupKey];
    if (existing?.eventIds.contains(event.id) ?? false) return;
    history['event:${event.id}'] = now;
    groups[event.groupKey] =
        existing?.add(event) ?? BannerItem.fromEvent(event, now);
    prune(now);
  }

  bool add(BannerEvent event, DateTime now) {
    prune(now);
    if (event.actor.isEmpty ||
        event.at.isAfter(now.add(const Duration(seconds: 30))) ||
        now.difference(event.at) > expiry ||
        _recent('event:${event.id}', now, const Duration(days: 2))) {
      return false;
    }
    history['event:${event.id}'] = now;
    if (event.type == BannerType.activity &&
        _recent(_onlineDay(event.actor, now), now, const Duration(days: 2))) {
      return false;
    }
    final previous = groups[event.groupKey];
    final newPerson =
        previous == null || !previous.actors.containsKey(event.actor);
    final group = previous?.add(event) ?? BannerItem.fromEvent(event, now);
    groups[event.groupKey] = group;
    // Aggregation continues after a banner disappears. Presentation limits never
    // throw away new names; they only prevent another interruption.
    if (!foreground) return false;
    if (event.type == BannerType.visit &&
        _recent('visitor:${event.actor}', now, const Duration(hours: 24))) {
      return false;
    }
    if (current?.groupKey == event.groupKey) {
      current = group.forDisplay(current!.createdAt);
      return true;
    }
    if (pending.containsKey(event.groupKey)) {
      pending[event.groupKey] = group.forDisplay(
        pending[event.groupKey]!.createdAt,
      );
      return true;
    }
    if (_recent('dismissed:${event.groupKey}', now, cooldown) ||
        (!newPerson && history.containsKey('group:${event.groupKey}'))) {
      return false;
    }
    if (event.type == BannerType.activity &&
        _recent('activity', now, const Duration(minutes: 30))) {
      return false;
    }
    pending[event.groupKey] = group.forDisplay(now);
    if (pending.length > 30) pending.remove(pending.keys.first);
    return true;
  }

  void consumeGroup(String key, {DateTime? at}) {
    history['consumed:$key'] = at ?? DateTime.now();
    _discardGroup(key);
  }

  void _discardGroup(String key) {
    groups.remove(key);
    pending.remove(key);
    history.remove('group:$key');
    history.remove('dismissed:$key');
    if (current?.groupKey == key) current = null;
  }

  void removeEvent(String id) {
    for (final entry in groups.entries.toList()) {
      if (!entry.value.events.containsKey(id)) continue;
      final updated = entry.value.withoutEvent(id);
      if (updated == null) {
        _discardGroup(entry.key);
        continue;
      }
      groups[entry.key] = updated;
      if (pending.containsKey(entry.key)) {
        pending[entry.key] = updated.forDisplay(pending[entry.key]!.createdAt);
      }
      if (current?.groupKey == entry.key) {
        current = updated.forDisplay(current!.createdAt);
      }
    }
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
      if (eligible != null && !eligible(current!)) {
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
      if (item.type == BannerType.activity) {
        history['activity'] = now;
        for (final actor in item.actors.keys) {
          history[_onlineDay(actor, now)] = now;
        }
      }
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
    groups.removeWhere(
      (_, item) => now.difference(item.latestEventAt) > const Duration(days: 2),
    );
    while (groups.length > 30) {
      groups.remove(groups.keys.first);
    }

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
    groups.clear();
    history.clear();
    starts.clear();
    current = null;
    startedAt = null;
  }
}