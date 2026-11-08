import 'package:flutter/material.dart';

class EmojiPicker extends StatelessWidget {
  final List<String> emojis;
  final Function(String) onPick;
  final VoidCallback onClose;

  const EmojiPicker({
    super.key,
    required this.emojis,
    required this.onPick,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha:0.7),
          child: Center(
            child: Wrap(
              spacing: 28, runSpacing: 28, alignment: WrapAlignment.center,
              children: emojis.map((e) => GestureDetector(
                onTap: () => onPick(e),
                child: Text(e, style: const TextStyle(fontSize: 38)),
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }
}