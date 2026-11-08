import 'package:flutter/material.dart';

class EmojiBurstOverlay extends StatelessWidget {
  final List<Widget> flyingEmojis;
  const EmojiBurstOverlay({super.key, required this.flyingEmojis});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: flyingEmojis,
    );
  }
}