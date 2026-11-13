import 'dart:convert';

/// Shared presentation rules for foreground and background activity pushes.
class NotificationPayload {
  static const externalTypes = {
    'like', 'comment', 'follow', 'new_follower', 'new_followers',
    'share', 'repost', 'reposts', 'save', 'bookmark', 'favorite', 'saves',
  };

  static String text(Iterable<Object?> values) {
    for (final value in values) {
      final result = value?.toString().trim() ?? '';
      if (result.isNotEmpty) return result;
    }
    return '';
  }

  static String? preferenceKey(String type) => switch (type) {
    'like' => 'interactions_likes',
    'comment' => 'interactions_comments',
    'follow' || 'new_follower' || 'new_followers' => 'interactions_new_followers',
    'share' || 'repost' || 'reposts' => 'interactions_reposts',
    'save' || 'bookmark' || 'favorite' || 'saves' => 'interactions_saves',
    _ => null,
  };

  static bool mayPresent(Map<String, dynamic> data, String? viewer, String body) {
    if (body.trim().isEmpty) return false;
    final recipient = text([data['toUid']]);
    return recipient.isEmpty || (viewer != null && recipient == viewer);
  }

  // eventId distinguishes a newly created activity from redelivery of that event.
  static String eventKey(Map<String, dynamic> data) =>
      text([data['eventId'], data['activityId'], data['messageId']]);

  // A reproducible positive Android ID; timestamps in milliseconds collide at 1000.
  static int notificationId(String key) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(key)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}
