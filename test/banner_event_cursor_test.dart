import 'package:flutter_test/flutter_test.dart';
import 'package:titi_star/banner_event_cursor.dart';

void main() {
  final opened = DateTime(2026, 11, 12, 12);
  test(
    'first server response includes follow arriving during session startup',
    () {
      final cursor = BannerEventCursor(opened);
      expect(
        cursor.accept(
          'old',
          opened.subtract(const Duration(minutes: 1)),
          fromCache: false,
          pendingWrites: false,
          firstServerSnapshot: true,
        ),
        isFalse,
      );
      expect(
        cursor.accept(
          'new-follow',
          opened.add(const Duration(seconds: 1)),
          fromCache: false,
          pendingWrites: false,
          firstServerSnapshot: true,
        ),
        isTrue,
      );
    },
  );
  test('cache and pending writes cannot consume a later confirmed event', () {
    final cursor = BannerEventCursor(opened);
    final at = opened.add(const Duration(seconds: 1));
    expect(
      cursor.accept(
        'follow',
        at,
        fromCache: true,
        pendingWrites: false,
        firstServerSnapshot: true,
      ),
      isFalse,
    );
    expect(
      cursor.accept(
        'follow',
        at,
        fromCache: false,
        pendingWrites: true,
        firstServerSnapshot: true,
      ),
      isFalse,
    );
    expect(
      cursor.accept(
        'follow',
        at,
        fromCache: false,
        pendingWrites: false,
        firstServerSnapshot: true,
      ),
      isTrue,
    );
    expect(
      cursor.accept(
        'follow',
        at,
        fromCache: false,
        pendingWrites: false,
        firstServerSnapshot: false,
      ),
      isFalse,
    );
  });
  test('new visit version reuses document id and is still accepted', () {
    final cursor = BannerEventCursor(opened);
    expect(
      cursor.accept(
        'visitor',
        opened.subtract(const Duration(days: 1)),
        fromCache: false,
        pendingWrites: false,
        firstServerSnapshot: true,
      ),
      isFalse,
    );
    expect(
      cursor.accept(
        'visitor',
        opened.add(const Duration(seconds: 1)),
        fromCache: false,
        pendingWrites: false,
        firstServerSnapshot: false,
      ),
      isTrue,
    );
  });
}
