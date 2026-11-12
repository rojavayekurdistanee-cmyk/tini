import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:titi_star/banner_transition.dart';
import 'package:titi_star/banner_policy.dart';

void main() {
  // Reproduce the production position: this widget is a sibling of Navigator,
  // in MaterialApp.builder, rather than inside Navigator's Overlay.
  Widget host({required VoidCallback dismiss, VoidCallback? tap}) =>
      MaterialApp(
        builder: (context, child) => Stack(
          children: [
            child!,
            Positioned(
              top: 80,
              left: 20,
              right: 20,
              child: BannerTransition(
                child: BannerDismissGesture(
                  onDismiss: dismiss,
                  onTap: tap,
                  child: const Material(
                    child: SizedBox(
                      height: 100,
                      child: Center(child: Text('أحمد وجميل بدأوا بمتابعتك')),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        home: const Scaffold(),
      );

  testWidgets('renders outside Navigator Overlay with no Tooltip assertion', (
    tester,
  ) async {
    await tester.pumpWidget(host(dismiss: () {}));
    await tester.pumpAndSettle();
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('slow upward swipe dismisses exactly once', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(host(dismiss: () => dismissals++));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BannerDismissGesture)),
    );
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    expect(dismissals, 1);
  });
  testWidgets('upward flick dismisses', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(host(dismiss: () => dismissals++));
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(BannerDismissGesture),
      const Offset(0, -50),
      800,
    );
    expect(dismissals, 1);
  });
  testWidgets('downward and horizontal drags do not dismiss', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(host(dismiss: () => dismissals++));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(BannerDismissGesture), const Offset(0, 80));
    await tester.drag(find.byType(BannerDismissGesture), const Offset(100, 0));
    expect(dismissals, 0);
  });
  testWidgets('tap retains the existing content navigation callback', (
    tester,
  ) async {
    var taps = 0;
    var dismissals = 0;
    await tester.pumpWidget(
      host(dismiss: () => dismissals++, tap: () => taps++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BannerDismissGesture));
    expect(taps, 1);
    expect(dismissals, 0);
  });
  test(
    'first-version policy still closes automatically five seconds after display',
    () {
      final start = DateTime(2026, 11, 12, 12);
      final policy = BannerPolicy();
      policy.add(
        BannerEvent('new', BannerType.follow, {
          'uid': 'actor',
          'name': 'أحمد',
        }, start),
        start,
      );
      policy.tick(start.add(const Duration(seconds: 5)));
      expect(policy.current, isNotNull);
      policy.tick(start.add(const Duration(seconds: 9)));
      expect(policy.current, isNotNull);
      policy.tick(start.add(const Duration(seconds: 10)));
      expect(policy.current, isNull);
    },
  );
}
