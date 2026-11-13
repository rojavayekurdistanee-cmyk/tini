import 'dart:convert';

/// Original documents stay intact: grouping only changes how the feed is shown.
class ActivityEntry {
  final String id;
  final Map<String, dynamic> data;
  final DateTime? timestamp;

  const ActivityEntry({required this.id, required this.data, this.timestamp});

  String get actorUid => (data['fromUid'] ?? '').toString().trim();
  String get type => (data['type'] ?? '').toString();
  String get postId => (data['postId'] ?? '').toString().trim();
}

class ActivityGroup {
  final String key;
  final List<ActivityEntry> entries;

  ActivityGroup(this.key, List<ActivityEntry> entries)
    : entries = List.unmodifiable(entries);

  ActivityEntry get latest => entries.first;
  Set<String> get ids => entries.map((entry) => entry.id).toSet();
  List<String> get actorUids => entries
      .map((entry) => entry.actorUid)
      .where((uid) => uid.isNotEmpty)
      .toSet()
      .toList(growable: false);
  bool get hasMultipleActors => actorUids.length > 1;

  String title(List<String> names) {
    final displayed = names.take(2).join(' و');
    final others = actorUids.length - 2;
    return others > 0 ? '$displayed و$others آخرون' : displayed;
  }

  /// A single person's original text (including comment/reply text) is retained.
  String get text {
    if (!hasMultipleActors) return (latest.data['text'] ?? '').toString();
    switch (latest.type) {
      case 'like':
        return 'أعجبوا بالفيديو الخاص بك';
      case 'favorite':
        return 'أضافوا الفيديو الخاص بك إلى المحفوظات';
      case 'share':
        return 'شاركوا الفيديو الخاص بك';
      case 'download':
        return 'نزّلوا الفيديو الخاص بك';
      case 'comment':
        return 'علّقوا على الفيديو الخاص بك';
      case 'reply':
        return 'ردّوا على تعليقك';
      case 'comment_like':
        return 'أعجبوا بتعليقك';
      case 'mention':
      case 'duet':
        return 'تم ذكرك في هذا الفيديو';
      case 'follow':
        return 'بدأوا بمتابعتك';
      case 'view':
        return 'زاروا ملفك الشخصي';
      default:
        return (latest.data['text'] ?? '').toString();
    }
  }
}

/// Each local calendar day forms a separate batch. Unknown or incomplete events
/// stay separate; replies and comment likes also require the same target comment.
List<ActivityGroup> groupActivities(Iterable<ActivityEntry> activities) {
  final sorted = activities.toList()
    ..sort((a, b) {
      final time = (b.timestamp?.microsecondsSinceEpoch ?? 0).compareTo(
        a.timestamp?.microsecondsSinceEpoch ?? 0,
      );
      return time != 0 ? time : a.id.compareTo(b.id);
    });
  final groups = <String, List<ActivityEntry>>{};
  final seenIds = <String>{};
  for (final entry in sorted) {
    if (!seenIds.add(entry.id)) continue;
    final key = _groupKey(entry);
    groups.putIfAbsent(key, () => []).add(entry);
  }
  return groups.entries
      .map((entry) => ActivityGroup(entry.key, entry.value))
      .toList(growable: false);
}

String _groupKey(ActivityEntry entry) {
  final type = entry.type == 'duet' ? 'mention' : entry.type;
  const videoTypes = {
    'like',
    'favorite',
    'share',
    'download',
    'comment',
    'reply',
    'comment_like',
    'mention',
  };
  const profileTypes = {'follow', 'view'};
  final at = entry.timestamp?.toLocal();
  if (at == null ||
      entry.actorUid.isEmpty ||
      (!videoTypes.contains(type) && !profileTypes.contains(type)) ||
      (videoTypes.contains(type) && entry.postId.isEmpty)) {
    return jsonEncode(['single', entry.id]);
  }
  String commentId = '';
  if (type == 'reply' || type == 'comment_like') {
    commentId =
        (type == 'reply'
                ? entry.data['replyToCommentId']
                : entry.data['commentId'])
            ?.toString()
            .trim() ??
        '';
    if (commentId.isEmpty) return jsonEncode(['single', entry.id]);
  }
  return jsonEncode([
    'group',
    entry.data['toUid'],
    type,
    videoTypes.contains(type) ? entry.postId : '',
    commentId,
    at.year,
    at.month,
    at.day,
  ]);
}
