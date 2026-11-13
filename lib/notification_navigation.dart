import 'package:flutter/material.dart';

/// Cold notifications need a real Home route underneath their destination so
/// both system back and the destination's own back button can pop normally.
class NotificationNavigation {
  static Future<T?> pushCold<T>({
    required NavigatorState navigator,
    required Route<T> destination,
    required WidgetBuilder homeBuilder,
  }) {
    navigator.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: homeBuilder),
      (_) => false,
    );
    // Push synchronously: Home is already covered when its widgets first build.
    return navigator.push<T>(destination);
  }
}
