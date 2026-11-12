import 'package:flutter_test/flutter_test.dart';
import 'package:titi_star/banner_policy.dart';

void main() {
  final origin = DateTime(2026, 11, 12, 12);
  BannerEvent event(
    String id, {
    BannerType type = BannerType.follow,
    String actor = 'ahmad',
    String post = 'post1',
    DateTime? at,
    String? subtype,
  }) => BannerEvent(id, type, {
    'uid': actor,
    'name': actor,
    'postId': post,
    'activityType': subtype,
  }, at ?? origin);

  test(
    'collects for five seconds; five followers produce one stable group',
    () {
      final p = BannerPolicy();
      for (var i = 0; i < 5; i++) {
        p.add(event('$i', actor: 'user$i'), origin);
      }
      p.tick(origin.add(const Duration(seconds: 4)));
      expect(p.current, isNull);
      p.tick(origin.add(const Duration(seconds: 5)));
      expect(p.current!.actors.length, 5);
      expect(p.current!.text, 'user0 وuser1 و3 آخرون بدأوا بمتابعتك');
      final id = p.current!.id;
      p.add(
        event('6', actor: 'user6', at: origin.add(const Duration(seconds: 6))),
        origin.add(const Duration(seconds: 6)),
      );
      expect(p.current!.id, id);
      p.tick(origin.add(const Duration(seconds: 10)));
      expect(p.current, isNull); // Updates never prolong display.
    },
  );
  test(
    'multiple comments from one actor count one person and retain latest target',
    () {
      final p = BannerPolicy();
      p.add(event('a', type: BannerType.comment, subtype: 'comment'), origin);
      p.add(
        BannerEvent('b', BannerType.comment, {
          'uid': 'ahmad',
          'name': 'ahmad',
          'postId': 'post1',
          'commentId': 'reply2',
          'activityType': 'reply',
        }, origin),
        origin,
      );
      p.tick(origin.add(const Duration(seconds: 5)));
      expect(p.current!.actors.length, 1);
      expect(p.current!.eventIds.length, 2);
      expect(p.current!.data['commentId'], 'reply2');
      expect(p.current!.text, contains('ردّ'));
    },
  );
  test('post groups remain separate and mention outranks likes', () {
    final p = BannerPolicy();
    p.add(event('a', type: BannerType.like), origin);
    p.add(event('b', type: BannerType.like, post: 'post2'), origin);
    p.add(event('c', type: BannerType.mention), origin);
    expect(p.pending.length, 3);
    p.tick(origin.add(const Duration(seconds: 5)));
    expect(p.current!.type, BannerType.mention);
  });
  test('replayed identity is ignored before and after persistent restore', () {
    final p = BannerPolicy();
    p.add(event('a'), origin);
    expect(p.add(event('a'), origin), isFalse);
    final restored = BannerPolicy()
      ..history.addAll(p.history)
      ..restore(origin);
    expect(restored.add(event('a'), origin), isFalse);
  });
  test('dismissed groups do not reopen for new actors during cooldown', () {
    final p = BannerPolicy();
    p.add(event('a'), origin);
    p.tick(origin.add(const Duration(seconds: 5)));
    p.dismiss(origin.add(const Duration(seconds: 6)), manual: true);
    final next = origin.add(const Duration(minutes: 1));
    expect(p.add(event('b', actor: 'jamil', at: next), next), isFalse);
    final restored = BannerPolicy()
      ..history.addAll(p.history)
      ..restore(next);
    expect(restored.add(event('c', at: next), next), isFalse);
    expect(
      restored.history.keys.any((key) => key.startsWith('dismissed:')),
      isTrue,
    );
  });
  test(
    'same visitor can notify again after 24 hours, with a new visit version',
    () {
      final p = BannerPolicy();
      p.add(event('visit:1', type: BannerType.visit), origin);
      p.tick(origin.add(const Duration(seconds: 5)));
      final later = origin.add(const Duration(hours: 1));
      expect(
        p.add(event('visit:2', type: BannerType.visit, at: later), later),
        isFalse,
      );
      final tomorrow = origin.add(const Duration(hours: 24, seconds: 5));
      expect(
        p.add(event('visit:3', type: BannerType.visit, at: tomorrow), tomorrow),
        isTrue,
      );
    },
  );
  test(
    'at most three starts in five minutes, with a 30 second start interval',
    () {
      final p = BannerPolicy();
      for (var i = 0; i < 4; i++) {
        final at = origin.add(Duration(seconds: i * 30));
        p.add(event('$i', type: BannerType.like, post: '$i', at: at), at);
        p.tick(at.add(const Duration(seconds: 5)));
        if (i < 3) {
          expect(p.current, isNotNull);
        } else {
          expect(p.current, isNull);
        }
        p.tick(at.add(const Duration(seconds: 10)));
      }
      expect(p.starts.length, 3);
      final restored = BannerPolicy()
        ..history.addAll(p.history)
        ..restore(origin.add(const Duration(seconds: 100)));
      expect(restored.starts.length, 3);
    },
  );
  test('fixed collection window cannot be postponed by a busy stream', () {
    final p = BannerPolicy();
    p.add(event('a'), origin);
    final four = origin.add(const Duration(seconds: 4));
    p.add(event('b', actor: 'jamil', at: four), four);
    p.tick(origin.add(const Duration(seconds: 5)));
    expect(p.current!.actors.length, 2);
  });
  test(
    'old waiting groups expire; old and future events never enter queue',
    () {
      final p = BannerPolicy();
      expect(
        p.add(
          event('old', at: origin.subtract(const Duration(minutes: 3))),
          origin,
        ),
        isFalse,
      );
      expect(
        p.add(
          event('future', at: origin.add(const Duration(minutes: 3))),
          origin,
        ),
        isFalse,
      );
      p.add(event('a'), origin);
      p.tick(origin.add(const Duration(minutes: 3)));
      expect(p.current, isNull);
      expect(p.pending, isEmpty);
    },
  );
  test('disabled or currently visible content is silently excluded', () {
    final p = BannerPolicy();
    p.add(event('a', type: BannerType.like), origin);
    p.tick(origin.add(const Duration(seconds: 5)), eligible: (_) => false);
    expect(p.current, isNull);
    expect(p.pending, isEmpty);
  });
  test(
    'online groups obey global 30 minute limit across different friends',
    () {
      final p = BannerPolicy();
      p.add(event('online:a:today', type: BannerType.activity), origin);
      p.tick(origin.add(const Duration(seconds: 5)));
      p.tick(origin.add(const Duration(seconds: 10)));
      final later = origin.add(const Duration(minutes: 11));
      expect(
        p.add(
          event(
            'online:b:today',
            type: BannerType.activity,
            actor: 'b',
            at: later,
          ),
          later,
        ),
        isFalse,
      );
    },
  );
  test('background delivery does not become a delayed foreground banner', () {
    final p = BannerPolicy()..foreground = false;
    expect(p.add(event('a'), origin), isFalse);
    p.foreground = true;
    p.tick(origin.add(const Duration(seconds: 5)));
    expect(p.current, isNull);
    expect(p.add(event('a'), origin), isFalse);
  });
  test('reset isolates accounts and prunes local history', () {
    final p = BannerPolicy();
    p.add(event('a'), origin);
    p.reset();
    expect(p.history, isEmpty);
    expect(p.pending, isEmpty);
    expect(p.add(event('a'), origin), isTrue);
    p.prune(origin.add(const Duration(days: 3)));
    expect(p.history, isEmpty);
  });
  test(
    'event cannot age past the freshness limit while waiting to display',
    () {
      final p = BannerPolicy();
      p.add(
        event('nearly-old', at: origin.subtract(const Duration(seconds: 119))),
        origin,
      );
      p.tick(origin.add(const Duration(seconds: 5)));
      expect(p.current, isNull);
      expect(p.pending, isEmpty);
    },
  );
  for (final type in [
    BannerType.follow,
    BannerType.visit,
    BannerType.like,
    BannerType.comment,
    BannerType.mention,
    BannerType.story,
    BannerType.activity,
  ]) {
    test(
      'loading presentation gate defers ${type.name} without consuming group',
      () {
        final p = BannerPolicy();
        p.add(event('new', type: type), origin);
        p.tick(
          origin.add(const Duration(seconds: 5)),
          readyToPresent: (_) => false,
        );
        expect(p.current, isNull);
        expect(p.pending.length, 1);
        expect(p.starts, isEmpty);
        expect(p.history.keys.any((key) => key.startsWith('group:')), isFalse);
        p.tick(
          origin.add(const Duration(seconds: 8)),
          readyToPresent: (_) => true,
        );
        expect(p.current?.type, type);
        expect(p.pending, isEmpty);
      },
    );
  }
}
