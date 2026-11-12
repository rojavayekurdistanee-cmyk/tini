import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:titi_star/banner_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manager = BannerManager.instance;
  setUp(() async {
    await manager.bindUser(null);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await manager.bindUser(null);
  });

  test(
    'account switch persists presentation history without leaking pending items',
    () async {
      await manager.bindUser('account-a');
      final now = DateTime.now();
      manager.submit(
        BannerEvent('follow1', BannerType.follow, {
          'uid': 'actor',
          'name': 'أحمد',
        }, now),
      );
      expect(manager.policy.pending.length, 1);
      await manager.bindUser('account-b');
      expect(manager.policy.pending, isEmpty);
      expect(manager.policy.history, isEmpty);
      await manager.bindUser('account-a');
      expect(manager.policy.history.containsKey('event:follow1'), isTrue);
      manager.submit(
        BannerEvent('follow1', BannerType.follow, {
          'uid': 'actor',
          'name': 'أحمد',
        }, now),
      );
      expect(manager.policy.pending, isEmpty);
    },
  );
  test(
    'overlapping identity binds leave only the latest identity active',
    () async {
      final a = manager.bindUser('a');
      final b = manager.bindUser('b');
      await Future.wait([a, b]);
      manager.submit(
        BannerEvent('event-b', BannerType.follow, {
          'uid': 'actor',
          'name': 'أحمد',
        }, DateTime.now()),
      );
      await manager.bindUser('a');
      expect(manager.policy.history.containsKey('event:event-b'), isFalse);
      await manager.bindUser('b');
      expect(manager.policy.history.containsKey('event:event-b'), isTrue);
    },
  );
  test(
    'settings are respected on arrival and checked live before presentation',
    () async {
      SharedPreferences.setMockInitialValues({'notify_like_banner': false});
      await manager.bindUser('a');
      expect(manager.enabled(BannerType.like), isFalse);
      manager.submit(
        BannerEvent('like1', BannerType.like, {
          'uid': 'actor',
          'name': 'أحمد',
          'postId': 'post',
        }, DateTime.now()),
      );
      expect(manager.policy.pending, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notify_like_banner', true);
      expect(manager.enabled(BannerType.like), isTrue);
    },
  );
  test(
    'foreground social FCM uses canonical handler; messages keep existing delivery',
    () async {
      await manager.bindUser('a');
      var calls = 0;
      manager.foregroundActivity = (data) async {
        calls++;
        return data['activityId'] == 'known';
      };
      expect(
        await manager.handleForegroundActivity({'type': 'message'}),
        isFalse,
      );
      expect(
        await manager.handleForegroundActivity({
          'type': 'follow',
          'activityId': 'known',
        }),
        isTrue,
      );
      expect(
        await manager.handleForegroundActivity({
          'type': 'follow',
          'activityId': 'unknown',
        }),
        isFalse,
      );
      expect(calls, 2);
      await manager.bindUser('b');
      expect(
        await manager.handleForegroundActivity({
          'type': 'follow',
          'activityId': 'known',
        }),
        isFalse,
      );
    },
  );
  test(
    'leaving foreground clears pending presentation without touching notifications',
    () async {
      await manager.bindUser('a');
      manager.submit(
        BannerEvent('a', BannerType.follow, {
          'uid': 'actor',
          'name': 'أحمد',
        }, DateTime.now()),
      );
      manager.setForeground(false);
      expect(manager.policy.pending, isEmpty);
      expect(manager.currentBanner.value, isNull);
      expect(manager.policy.history.containsKey('event:a'), isTrue);
      manager.setForeground(true);
    },
  );
  test(
    'migration imports old activity IDs without permanently blocking old visitors',
    () async {
      final day = DateTime.now().toIso8601String().split('T').first;
      SharedPreferences.setMockInitialValues({
        'shown_follow_banners': ['already-presented'],
        'shown_visit_banners': ['visitor'],
        'activity_shown_a_friend_$day': true,
      });
      await manager.bindUser('a');
      expect(
        manager.policy.history.containsKey('event:activity:already-presented'),
        isTrue,
      );
      expect(
        manager.policy.history.containsKey('event:online:friend:$day'),
        isTrue,
      );
      expect(manager.policy.history.containsKey('visitor:visitor'), isFalse);
    },
  );
  test(
    'Firestore and FCM deliveries with one canonical ID produce one event',
    () async {
      await manager.bindUser('a');
      final event = BannerEvent('activity:one', BannerType.follow, {
        'uid': 'actor',
        'name': 'أحمد',
      }, DateTime.now());
      manager.foregroundActivity = (_) async {
        manager.submit(event);
        return true;
      };
      manager.submit(event);
      await manager.handleForegroundActivity({
        'type': 'follow',
        'activityId': 'one',
      });
      expect(manager.policy.pending.length, 1);
      expect(manager.policy.pending.values.single.eventIds.length, 1);
    },
  );
}
