import 'package:flutter/material.dart';
import 'sticker_layer.dart';

class StickerWidget extends StatelessWidget {
  final StickerLayer sticker;
  final Size screenSize;
  final Function(StickerLayer) onUpdate;
  final Function(String) onDelete;
  final Function(String) onTap;

  const StickerWidget({
    super.key,
    required this.sticker,
    required this.screenSize,
    required this.onUpdate,
    required this.onDelete,
    required this.onTap,
  });

  static const Color _titiTeal = Colors.teal;
  static const double _hitAreaPadding = 30.0;
  static const double _stickerBaseSize = 120.0;

  @override
  Widget build(BuildContext context) {
    final left = sticker.x * screenSize.width;
    final top = sticker.y * screenSize.height;
    final touchAreaSize = _stickerBaseSize * sticker.scale + _hitAreaPadding * 2;

    return Positioned(
      left: left,
      top: top,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => onTap(sticker.id),
          onDoubleTap: () {
            onUpdate(sticker.copyWith(scale: 1.0, rotation: 0.0));
          },
          child: SizedBox(
            width: touchAreaSize,
            height: touchAreaSize,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: sticker.rotation,
                  child: Container(
                    decoration: BoxDecoration(
                      border: sticker.isSelected
                          ? Border.all(color: _titiTeal, width: 1.5)
                          : null,
                    ),
                    child: sticker.isEmoji
                        ? Text(
                            sticker.path,
                            style: TextStyle(fontSize: 80 * sticker.scale),
                          )
                        : Image.network(
                            sticker.path,
                            width: _stickerBaseSize * sticker.scale,
                            height: _stickerBaseSize * sticker.scale,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Image.asset(
                              sticker.path,
                              width: _stickerBaseSize * sticker.scale,
                              height: _stickerBaseSize * sticker.scale,
                              fit: BoxFit.contain,
                            ),
                          ),
                  ),
                ),
                if (sticker.isSelected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onDelete(sticker.id),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}