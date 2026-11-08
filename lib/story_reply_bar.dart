import 'package:flutter/material.dart';

class StoryReplyBar extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onLike;
  final bool isLiked;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> quickEmojis;
  final Function(String) onQuickEmoji;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  const StoryReplyBar({
    super.key,
    required this.onShare,
    required this.onLike,
    required this.isLiked,
    required this.controller,
    required this.focusNode,
    required this.quickEmojis,
    required this.onQuickEmoji,
    required this.onSend,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: Colors.black.withValues(alpha:0.85),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
               onTap: onShare,
               behavior: HitTestBehavior.opaque,
               child: const Padding(
                 padding: EdgeInsets.all(4.0),
                 child: Icon(Icons.send, size: 26, color: Colors.white),
               ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: onLike,
                child: Icon(isLiked? Icons.favorite : Icons.favorite_border, color: isLiked? Colors.red : Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44, maxHeight: 110),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626), // ✅ يملي كامل
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (!focusNode.hasFocus && controller.text.isEmpty)
                      ...quickEmojis.map((e) => GestureDetector(
                          onTap: () => onQuickEmoji(e),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(e, style: const TextStyle(fontSize: 24)),
                          ),
                        )),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode, // ✅ NEW
                          onChanged: (_) => onChanged(),
                          style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
                          textAlignVertical: TextAlignVertical.center,
                          textAlign: TextAlign.right,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          maxLines: 5,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: 'إرسال رسالة',
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          onSubmitted: (_) => onSend(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.text.trim().isNotEmpty) const SizedBox(width: 8),
              if (controller.text.trim().isNotEmpty)
                GestureDetector(
                  onTap: onSend,
                  child: const Icon(Icons.send, size: 26, color: Color(0xFF00A3FF)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}