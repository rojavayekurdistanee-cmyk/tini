import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// نوع الشارة المعروضة. منح الشارات وحفظ استحقاقها يتم خارج هذا الملف.
enum ThroneBadgeKind { currentKing, formerKing }

/// يعرض صورة شارة العرش الأصلية من assets دون تعديل الصورة أو بيانات المستخدم.
/// يمكن إعادة استخدامه لاحقاً بجانب اسم المستخدم أو في صفحة الإنجازات.
class ThroneBadgeImage extends StatefulWidget {
  final ThroneBadgeKind kind;
  final double size;
  final bool animate;

  const ThroneBadgeImage({
    super.key,
    required this.kind,
    this.size = 104,
    this.animate = true,
  });

  @override
  State<ThroneBadgeImage> createState() => _ThroneBadgeImageState();
}

class _ThroneBadgeImageState extends State<ThroneBadgeImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _syncAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // احترام إعدادات إمكانية الوصول وإيقاف المؤثرات عند طلب تقليل الحركة.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
      _syncAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant ThroneBadgeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind || oldWidget.animate != widget.animate) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.kind == ThroneBadgeKind.currentKing &&
        widget.animate &&
        !_reduceMotion) {
      if (!_glowController.isAnimating) {
        _glowController.repeat();
      }
    } else {
      _glowController.stop();
      _glowController.value = 0;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = widget.kind == ThroneBadgeKind.currentKing;
    final asset = isCurrent
        ? 'assets/badges/tini_current_king_badge_final.png'
        : 'assets/badges/tini_former_king_badge_final.png';
    final image = RepaintBoundary(
      child: Image.asset(
        asset,
        width: widget.size,
        height: widget.size,
        cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context))
            .round(),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => SizedBox.square(
          dimension: widget.size,
          child: const Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 30,
              color: AppColors.greyText,
            ),
          ),
        ),
      ),
    );

    // الملك السابق ثابت. احترم إعداد النظام لتقليل الحركات.
    if (!isCurrent || !widget.animate || MediaQuery.disableAnimationsOf(context)) {
      return SizedBox.square(dimension: widget.size, child: image);
    }

    // الملك الحالي فقط: لمعة تمر على الذهب، ونبض طفيف.
    // جميع الحركات دورية رياضياً، فلا تحدث قفزة عند انتهاء الدورة.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _glowController,
        child: image,
        builder: (context, child) {
          final progress = _glowController.value;
          final phase = progress * 2 * math.pi;
          final glowProgress = (1 - math.cos(phase)) * 0.5;
          final scale = 1.015 - 0.015 * math.cos(phase); // 1.00 → 1.03 → 1.00

          // اللمعة تتحرك مرة كل أربع ثوان، وتختفي خارج حدود الشارة.
          // srcATop يحافظ على شفافية الـ PNG ولا يرسم مستطيلاً فوقها.
          final sweepActive = progress > 0.08 && progress < 0.60;
          final sweep = (progress - 0.08) / 0.52;
          final Widget badge = sweepActive
              ? ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment(-3.1 + 5.6 * sweep, -0.25),
                    end: Alignment(-2.4 + 5.6 * sweep, 0.25),
                    colors: const [
                      Color(0x00FFF7CB),
                      Color(0x12FFE7A3),
                      Color(0xFFFFFBE2),
                      Color(0x12FFE7A3),
                      Color(0x00FFF7CB),
                    ],
                    stops: [0.0, 0.30, 0.50, 0.70, 1.0],
                  ).createShader(bounds),
                  child: child!,
                )
              : child!;

          return SizedBox.square(
            dimension: widget.size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // الاحتفاظ بالهالة الذهبية الخفيفة الموجودة في النسخة السابقة.
                Container(
                  width: widget.size * 0.62,
                  height: widget.size * 0.62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD36B)
                            .withValues(alpha: 0.08 + 0.13 * glowProgress),
                        blurRadius: 8 + 11 * glowProgress,
                        spreadRadius: 1 + 2 * glowProgress,
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: scale,
                  child: SizedBox.square(
                    dimension: widget.size,
                    child: badge,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// معاينة بصرية فقط. لا تمنح أي شارة، ولا تكتب إلى Firestore.
class ThroneBadgesPreview extends StatelessWidget {
  const ThroneBadgesPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.workspace_premium_outlined,
                  color: Color(0xFFFFD36B), size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'معاينة شارات العرش',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'عرض تجريبي للتصميم فقط؛ لم يتم ربط الشارات بالتتويج بعد.',
            style: TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final availableWidth = constraints.maxWidth;
              final twoColumns = availableWidth >= 286;
              final tileWidth = twoColumns
                  ? (availableWidth - gap) / 2
                  : availableWidth;
              final badgeSize = math.min(112.0, tileWidth - 22);

              return Wrap(
                alignment: WrapAlignment.center,
                spacing: gap,
                runSpacing: gap,
                children: [
                  _BadgePreviewTile(
                    width: tileWidth,
                    badgeSize: badgeSize,
                    kind: ThroneBadgeKind.currentKing,
                    title: 'الملك الحالي',
                    description: 'أثناء فترة الحكم',
                  ),
                  _BadgePreviewTile(
                    width: tileWidth,
                    badgeSize: badgeSize,
                    kind: ThroneBadgeKind.formerKing,
                    title: 'الملك السابق',
                    description: 'ذكرى ملكية دائمة',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BadgePreviewTile extends StatelessWidget {
  final double width;
  final double badgeSize;
  final ThroneBadgeKind kind;
  final String title;
  final String description;

  const _BadgePreviewTile({
    required this.width,
    required this.badgeSize,
    required this.kind,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = kind == ThroneBadgeKind.currentKing;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isCurrent ? const Color(0xFFFFD36B) : const Color(0xFFA98569))
              .withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThroneBadgeImage(kind: kind, size: badgeSize),
          const SizedBox(height: 7),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.greyText, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
