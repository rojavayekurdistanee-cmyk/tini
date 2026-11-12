import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:titi_star/banner_transition.dart';

void main() {
  Widget host(Widget? child, {bool reduced = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: BannerTransition(child: child)),
    ),
  );
  Widget card(String label) => SizedBox(
    key: const ValueKey('same-group'),
    height: 80,
    child: Text(label),
  );

  testWidgets(
    'dismissal retains outgoing card until exit completes and blocks taps',
    (tester) async {
      await tester.pumpWidget(host(null));
      await tester.pumpWidget(host(card('أحمد بدأ بمتابعتك')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(null));
      expect(find.text('أحمد بدأ بمتابعتك'), findsOneWidget);
      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: find.byType(BannerTransition),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('أحمد بدأ بمتابعتك'), findsNothing);
    },
  );
  testWidgets(
    'new names in same group update in place without another entrance',
    (tester) async {
      await tester.pumpWidget(host(card('أحمد')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(card('أحمد وجميل')));
      expect(find.text('أحمد'), findsNothing);
      expect(find.text('أحمد وجميل'), findsOneWidget);
      final transition = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(BannerTransition),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(transition.opacity.value, 1);
    },
  );
  testWidgets('reduced motion removes card without waiting for animation', (
    tester,
  ) async {
    await tester.pumpWidget(host(card('أحمد'), reduced: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(null, reduced: true));
    await tester.pump();
    expect(find.text('أحمد'), findsNothing);
  });
}
