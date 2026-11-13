import 'package:flutter_test/flutter_test.dart';
import 'package:titi_star/notification_payload.dart';

void main() {
  test('all interaction aliases retain external pushes and matching switches', () {
    for (final type in NotificationPayload.externalTypes) {
      expect(NotificationPayload.preferenceKey(type), isNotNull, reason: type);
    }
    expect(NotificationPayload.preferenceKey('chat'), isNull);
    expect(NotificationPayload.preferenceKey('favorite'), 'interactions_saves');
    expect(NotificationPayload.preferenceKey('share'), 'interactions_reposts');
  });

  test('empty or whitespace content never creates a Tini-only notification', () {
    expect(NotificationPayload.mayPresent({}, 'owner', ''), isFalse);
    expect(NotificationPayload.mayPresent({}, 'owner', ' \n '), isFalse);
    expect(NotificationPayload.text(['', '  ', 'تعليق جديد']), 'تعليق جديد');
  });

  test('recipient-bound pushes cannot leak across account changes or logout', () {
    final data = {'toUid': 'owner'};
    expect(NotificationPayload.mayPresent(data, 'owner', 'نص'), isTrue);
    expect(NotificationPayload.mayPresent(data, 'another-user', 'نص'), isFalse);
    expect(NotificationPayload.mayPresent(data, null, 'نص'), isFalse);
    expect(NotificationPayload.mayPresent({}, 'owner', 'legacy payload'), isTrue);
  });

  test('identity distinguishes independent activities and preserves redeliveries', () {
    expect(NotificationPayload.eventKey({'eventId': 'event', 'activityId': 'activity'}), 'event');
    expect(NotificationPayload.eventKey({'activityId': 'activity'}), 'activity');
    expect(NotificationPayload.eventKey({'messageId': 'chat-message'}), 'chat-message');
    expect(NotificationPayload.eventKey({}), '');
    final ids = {for (var i = 0; i < 2000; i++) NotificationPayload.notificationId('owner:event-$i')};
    expect(ids.length, 2000);
    expect(NotificationPayload.notificationId('owner:إشعار'), NotificationPayload.notificationId('owner:إشعار'));
    expect(ids.every((id) => id >= 0 && id <= 0x7fffffff), isTrue);
  });
}
