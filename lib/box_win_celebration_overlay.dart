import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'box_model.dart';
import 'app_colors.dart';

class BoxWinCelebrationOverlay extends StatefulWidget {
  final BoxRarity rarity;
  final VoidCallback onDismiss;

  const BoxWinCelebrationOverlay({
    super.key,
    required this.rarity,
    required this.onDismiss,
  });

  /// لتشغيل الاحتفال بسهولة:
  /// BoxWinCelebrationOverlay.show(context, box.rarity);
  static void show(BuildContext context, BoxRarity rarity) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => BoxWinCelebrationOverlay(
        rarity: rarity,
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }

  @override
  State<BoxWinCelebrationOverlay> createState() => _BoxWinCelebrationOverlayState();
}

class _BoxWinCelebrationOverlayState extends State<BoxWinCelebrationOverlay>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fireworksController;
  late Animation<double> _scaleAnimation;

  String _getRarityName(BoxRarity rarity) {
    switch (rarity) {
      case BoxRarity.bronze:
        return 'برونزية';
      case BoxRarity.silver:
        return 'فضية';
      case BoxRarity.gold:
        return 'ذهبية';
      case BoxRarity.diamond:
        return 'ماسية';
    }
  }

  Color _getRarityColor(BoxRarity rarity) {
    switch (rarity) {
      case BoxRarity.bronze:
        return const Color(0xFFCD7F32);
      case BoxRarity.silver:
        return const Color(0xFFC0C0C0);
      case BoxRarity.gold:
        return const Color(0xFFFFD700);
      case BoxRarity.diamond:
        return const Color(0xFF00D9FF);
    }
  }

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fireworksController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    _scaleController.forward();
    _fireworksController.forward();
    
    // هزاز احتفالي فقط
    HapticFeedback.heavyImpact();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fireworksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      child: Stack(
        children: [
          // الألعاب النارية
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _fireworksController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _FireworksPainter(
                    progress: _fireworksController.value,
                    color: _getRarityColor(widget.rarity),
                  ),
                );
              },
            ),
          ),
          // النص بالنص
          Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _getRarityColor(widget.rarity).withValues(alpha: 0.3),
                      AppColors.surface.withValues(alpha: 0.95),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _getRarityColor(widget.rarity),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getRarityColor(widget.rarity).withValues(alpha: 0.6),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.celebration,
                      color: AppColors.highlight,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '🎉 مبروك!',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ربحت شارة ${_getRarityName(widget.rarity)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _getRarityColor(widget.rarity),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '+ تعليق ملون لمدة 7 أيام',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FireworksPainter extends CustomPainter {
  final double progress;
  final Color color;
  final math.Random _random = math.Random(42);

  _FireworksPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 15; i++) {
      final centerX = size.width * (0.2 + _random.nextDouble() * 0.6);
      final centerY = size.height * (0.2 + _random.nextDouble() * 0.6);
      final particleCount = 20;
      final radius = progress * 100;

      for (int j = 0; j < particleCount; j++) {
        final angle = (j / particleCount) * 2 * math.pi;
        final x = centerX + math.cos(angle) * radius * (0.5 + _random.nextDouble() * 0.5);
        final y = centerY + math.sin(angle) * radius * (0.5 + _random.nextDouble() * 0.5);
        final opacity = (1 - progress) * 0.8;

        paint.color = color.withValues(alpha: opacity);
        canvas.drawCircle(Offset(x, y), 3, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter oldDelegate) => oldDelegate.progress != progress;
}