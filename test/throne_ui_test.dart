import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:titi_star/throne_badges.dart';
import 'package:titi_star/throne_celebration.dart';
import 'package:titi_star/throne_countdown.dart';
import 'package:titi_star/throne_earned_badge.dart';

void main() {
  test(
    'badge eligibility changes at exact expiry, preserves former title and supports return',
    () {
      final now = DateTime.utc(2026, 11, 10);
      expect(earnedThroneKind(now: now, formerKing: false), isNull);
      expect(
        earnedThroneKind(
          now: now,
          formerKing: false,
          currentUntil: now.add(const Duration(seconds: 1)),
        ),
        ThroneBadgeKind.currentKing,
      );
      expect(
        earnedThroneKind(now: now, formerKing: false, currentUntil: now),
        ThroneBadgeKind.formerKing,
      );
      expect(
        earnedThroneKind(now: now, formerKing: true),
        ThroneBadgeKind.formerKing,
      );
      expect(
        earnedThroneKind(
          now: now,
          formerKing: true,
          currentUntil: now.add(const Duration(days: 7)),
        ),
        ThroneBadgeKind.currentKing,
      );
    },
  );

  testWidgets(
    'countdown updates each second, distinguishes reign and waits for server at zero',
    (tester) async {
      var now = DateTime.utc(2026, 11, 10);
      final deadline = now.add(const Duration(seconds: 2));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThroneCountdown(
              deadline: deadline,
              reign: false,
              now: () => now,
            ),
          ),
        ),
      );
      expect(find.text('المزاد: 0ي 0س 0د 2ث'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('المزاد: 0ي 0س 0د 1ث'), findsOneWidget);
      now = deadline;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('انتهى المزاد؛ بانتظار تأكيد السيرفر'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThroneCountdown(
              deadline: deadline,
              reign: true,
              now: () => now,
            ),
          ),
        ),
      );
      expect(find.text('انتهى الحكم؛ بانتظار تأكيد السيرفر'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('countdown recomputes from deadline after app resume', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 10);
    final deadline = now.add(const Duration(days: 7));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThroneCountdown(
            deadline: deadline,
            reign: true,
            now: () => now,
          ),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(days: 7));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('انتهى الحكم؛ بانتظار تأكيد السيرفر'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('coronation banner respects reduced motion and long names', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(
            body: SizedBox(
              width: 240,
              child: ThroneCelebration(name: 'ملك تيني باسم طويل جداً جداً'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('الملك الجديد'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [240.0, 320.0, 600.0, 1024.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'original badges render at width $width and text scale $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: const Scaffold(
                  body: SingleChildScrollView(child: ThroneBadgesPreview()),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(ThroneBadgeImage), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
