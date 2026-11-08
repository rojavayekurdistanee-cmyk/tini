import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'box_provider.dart';
import 'box_model.dart';
import 'app_colors.dart';
import 'package:intl/intl.dart';
import 'post_view_screen.dart';
import 'box_timer_widget.dart';
import 'box_win_celebration_overlay.dart';
import 'audience_access.dart';
import 'audience_gate.dart';

class MysterySeaGrid extends StatefulWidget {
  final Function(bool) onModalOpen;
  const MysterySeaGrid({super.key, required this.onModalOpen});

  @override
  State<MysterySeaGrid> createState() => _MysterySeaGridState();
}

class _MysterySeaGridState extends State<MysterySeaGrid> {
  BoxRarity? _selectedFilter;

  IconData _getRarityIcon(BoxRarity rarity) {
    switch (rarity) {
      case BoxRarity.bronze:
        return Icons.workspace_premium;
      case BoxRarity.silver:
        return Icons.military_tech;
      case BoxRarity.gold:
        return Icons.emoji_events;
      case BoxRarity.diamond:
        return Icons.diamond;
    }
  }

  String _getRarityName(BoxRarity rarity) {
    switch (rarity) {
      case BoxRarity.bronze:
        return 'برونزي';
      case BoxRarity.silver:
        return 'فضي';
      case BoxRarity.gold:
        return 'ذهبي';
      case BoxRarity.diamond:
        return 'ماسي';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BoxProvider>(
      builder: (context, boxProvider, child) {
        final filteredBoxes = _selectedFilter == null
       ? boxProvider.boxes
            : boxProvider.boxes.where((b) => b.rarity == _selectedFilter).toList();

        return Column(
          children: [
            _buildHeader(boxProvider),
            _buildFilterBar(),
            const SizedBox(height: 2), // كان 4
            Expanded(
              child: boxProvider.isLoading
             ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : filteredBoxes.isEmpty
                 ? _buildEmptyState()
                      : GridView.builder(
                          padding: const EdgeInsets.all(6), // كان 8
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 6, // كان 8
                            mainAxisSpacing: 6, // كان 8
                            childAspectRatio: 0.85,
                          ),
                          itemCount: filteredBoxes.length,
                          itemBuilder: (context, index) {
                            final box = filteredBoxes[index];
                            return AudiencePostGate(
                              post: box.toPostModel(),
                              postId: box.id,
                              child: _buildBoxCard(context, box, boxProvider),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BoxProvider boxProvider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6), // كان 12,10,12,10
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.surface],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2, color: AppColors.primary, size: 18), // كان 22
              const SizedBox(width: 4), // كان 6
              const Text(
                'بحر الصناديق',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold), // كان 17
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), // كان 10,4
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12), // كان 16
              border: Border.all(color: AppColors.primary, width: 1), // قللت السماكة
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on, color: AppColors.highlight, size: 14), // كان 16
                const SizedBox(width: 2), // كان 3
                Text(
                  NumberFormat('#,###').format(boxProvider.userPoints),
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11), // كان 13
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 32, // كان 40
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6), // كان 8
        children: [
          _buildFilterChip('الكل', null),
          _buildFilterChip('برونزي', BoxRarity.bronze),
          _buildFilterChip('فضي', BoxRarity.silver),
          _buildFilterChip('ذهبي', BoxRarity.gold),
          _buildFilterChip('ماسي', BoxRarity.diamond),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, BoxRarity? rarity) {
    final isSelected = _selectedFilter == rarity;
    return Padding(
      padding: const EdgeInsets.only(right: 4), // كان 6
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = selected? rarity : null;
          });
        },
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary.withValues(alpha: 0.3),
        labelStyle: TextStyle(
          color: isSelected? AppColors.primary : AppColors.greyText,
          fontWeight: isSelected? FontWeight.bold : FontWeight.normal,
          fontSize: 10, // كان 12
        ),
        side: BorderSide(color: isSelected? AppColors.primary : AppColors.iconInactive, width: 0.8), // أرفع
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), // كان 8,4
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact, // يضغط أكثر
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: AppColors.iconInactive), // كان 70
          const SizedBox(height: 10),
          Text(
            'لا توجد صناديق متاحة',
            style: TextStyle(color: AppColors.greyText, fontSize: 14), // كان 15
          ),
        ],
      ),
    );
  }

  Widget _buildBoxCard(BuildContext context, BoxModel box, BoxProvider provider) {
    final colors = _getRarityColors(box.rarity);
    final isAvailable = box.status == BoxStatus.available;
    final isOnHold = box.status == BoxStatus.onHold;
    final isSold = box.status == BoxStatus.sold;
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMine = isSold && box.ownedByUid == currentUser?.uid;
    final isDiamond = box.rarity == BoxRarity.diamond;

    Widget card = GestureDetector(
      onTap: () async {
        FocusScope.of(context).unfocus();
        await Future.delayed(Duration.zero);
        _showBoxDetails(context, box, provider);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSold? [AppColors.surface, AppColors.background] : [colors[0], colors[1]],
          ),
          borderRadius: BorderRadius.circular(10), // كان 12
          border: Border.all(
            color: isAvailable? colors[0].withValues(alpha: 0.8) : AppColors.iconInactive,
            width: 1.5, // كان 2
          ),
          boxShadow: isAvailable
         ? [
                  BoxShadow(
                    color: colors[0].withValues(alpha: isDiamond? 0.6 : 0.4),
                    blurRadius: isDiamond? 14 : 8, // قللت
                    spreadRadius: isDiamond? 2 : 1, // قللت
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getRarityIcon(box.rarity),
                    size: 28, // كان 32
                    color: AppColors.textPrimary.withValues(alpha: isSold? 0.3 : 1),
                  ),
                  const SizedBox(height: 4), // كان 6
                  Text(
                    _getRarityName(box.rarity),
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: isSold? 0.5 : 1),
                      fontSize: 10, // كان 11
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2), // كان 3
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.monetization_on, color: AppColors.highlight, size: 11), // كان 12
                      const SizedBox(width: 2),
                      Text(
                        '${box.price}',
                        style: TextStyle(
                          color: AppColors.textPrimary.withValues(alpha: isSold? 0.5 : 1),
                          fontSize: 11, // كان 12
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isOnHold)
              Positioned(
                top: 4, // كان 6
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), // كان 5,2
                  decoration: BoxDecoration(
                    color: AppColors.highlight,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'محجوز',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 7, fontWeight: FontWeight.bold), // كان 8
                  ),
                ),
              ),
            if (isSold)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10), // كان 12
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isMine? Icons.play_circle_fill : Icons.check_circle,
                          color: AppColors.primary,
                          size: 30, // كان 34
                        ),
                        if (isMine)...[
                          const SizedBox(height: 2),
                          const Text(
                            'افتح',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10, // كان 11
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            if (box.boxOpenedAt!= null)
              Positioned(
                top: 4, // كان 6
                left: 0,
                right: 0,
                child: Center(
                  child: BoxCountdownTimer(boxOpenedAt: box.boxOpenedAt),
                ),
              ),
          ],
        ),
      ),
    );

    if (isDiamond && isAvailable) {
      return _DiamondShimmer(child: card);
    }
    return card;
  }

  void _showBoxDetails(BuildContext context, BoxModel box, BoxProvider provider) {
    final currentUser = FirebaseAuth.instance.currentUser;
    widget.onModalOpen(true);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetContext) {
        bool isLoading = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return AudiencePostGate(
              post: box.toPostModel(),
              postId: box.id,
              child: Container(
              padding: const EdgeInsets.all(18), // كان 20
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.iconInactive,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14), // كان 16
                  Icon(_getRarityIcon(box.rarity), size: 46, color: _getRarityColors(box.rarity)[0]), // كان 50
                  const SizedBox(height: 10), // كان 12
                  Text(
                    'صندوق ${_getRarityName(box.rarity)}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.bold), // كان 20
                  ),
                  const SizedBox(height: 5), // كان 6
                  if (box.boxTitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        box.boxTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4), // كان 15
                      ),
                    ),
                  const SizedBox(height: 8), // كان 10
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.monetization_on, color: AppColors.highlight, size: 17), // كان 18
                      const SizedBox(width: 4),
                      Text(
                        '${box.price} نقطة',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16), // كان 17
                      ),
                    ],
                  ),
                  const SizedBox(height: 18), // كان 20
                  if (box.status == BoxStatus.available)
                    ElevatedButton(
                      onPressed: isLoading
                     ? null
                          : () async {
                              setSheetState(() => isLoading = true);
                              if (!await AudienceAccess.instance.verifyPost(box.id)) {
                                if (context.mounted) setSheetState(() => isLoading = false);
                                return;
                              }
                              final success = await provider.reserveBox(box.id);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم حجز الصندوق! لديك 10 دقائق للتأكيد'),
                                    backgroundColor: AppColors.primary,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(provider.errorMsg),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(double.infinity, 46), // كان 48
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: isLoading
                     ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                          : const Text('احجز الآن', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), // كان 15
                    ),
                  if (box.status == BoxStatus.onHold && box.ownedByUid == currentUser?.uid)
                    Column(
                      children: [
                        ElevatedButton(
                          onPressed: isLoading
                         ? null
                              : () async {
                                  setSheetState(() => isLoading = true);
                                  if (!await AudienceAccess.instance.verifyPost(box.id)) {
                                    if (context.mounted) setSheetState(() => isLoading = false);
                                    return;
                                  }
                                  final postDoc = await provider.confirmPurchase(box.id);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  if (postDoc!= null) {
                                    BoxWinCelebrationOverlay.show(context, box.rarity);
                                    await Future.delayed(const Duration(milliseconds: 500));
                                    if (!context.mounted) return;
                                    if (!await AudienceAccess.instance.verifyPost(postDoc.id)) return;
                                    if (!context.mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PostViewScreen(
                                          posts: [postDoc],
                                          initialIndex: 0,
                                        ),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(provider.errorMsg),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.textPrimary,
                            minimumSize: const Size(double.infinity, 46), // كان 48
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: isLoading
                         ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                              : const Text('تأكيد الشراء', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), // كان 15
                        ),
                        const SizedBox(height: 8), // كان 10
                        TextButton(
                          onPressed: isLoading
                         ? null
                              : () async {
                                  setSheetState(() => isLoading = true);
                                  await provider.cancelReservation(box.id);
                                  if (context.mounted) Navigator.pop(context);
                                },
                          child: const Text('إلغاء الحجز', style: TextStyle(color: AppColors.error, fontSize: 13)),
                        ),
                      ],
                    ),
                  if (box.status == BoxStatus.sold && box.ownedByUid == currentUser?.uid)
                    ElevatedButton(
                      onPressed: isLoading
                     ? null
                          : () async {
                              setSheetState(() => isLoading = true);
                              if (!await AudienceAccess.instance.verifyPost(box.id)) {
                                if (context.mounted) setSheetState(() => isLoading = false);
                                return;
                              }
                              final postDoc = await provider.confirmPurchase(box.id);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              if (postDoc!= null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PostViewScreen(
                                      posts: [postDoc],
                                      initialIndex: 0,
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(provider.errorMsg.isEmpty? 'فشل فتح الصندوق' : provider.errorMsg),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(double.infinity, 46), // كان 48
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: isLoading
                     ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                          : const Text('فتح الفيديو', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), // كان 15
                    ),
                  if (box.status == BoxStatus.sold && box.ownedByUid!= currentUser?.uid)
                    Container(
                      padding: const EdgeInsets.all(12), // كان 14
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Text(
                        'تم بيع هذا الصندوق',
                        style: TextStyle(color: AppColors.greyText, fontSize: 14), // كان 15
                      ),
                    ),
                  if (box.status == BoxStatus.onHold && box.ownedByUid!= currentUser?.uid)
                    Container(
                      padding: const EdgeInsets.all(12), // كان 14
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        'محجوز من ${box.ownedByName?? "مستخدم آخر"}',
                        style: const TextStyle(color: AppColors.greyText, fontSize: 14), // كان 15
                      ),
                    ),
                  const SizedBox(height: 14), // كان 16
                ],
              ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => widget.onModalOpen(false));
  }

  List<Color> _getRarityColors(BoxRarity rarity) {
    switch (rarity) {
      case BoxRarity.bronze:
        return [const Color(0xFFCD7F32), const Color(0xFF8B4513)];
      case BoxRarity.silver:
        return [const Color(0xFFE8E8E8), const Color(0xFFA8A8A8)];
      case BoxRarity.gold:
        return [const Color(0xFFFFD700), const Color(0xFFFF8C00)];
      case BoxRarity.diamond:
        return [const Color(0xFF00D9FF), const Color(0xFF0077FF)];
    }
  }
}

class _DiamondShimmer extends StatefulWidget {
  final Widget child;
  const _DiamondShimmer({required this.child});

  @override
  State<_DiamondShimmer> createState() => _DiamondShimmerState();
}

class _DiamondShimmerState extends State<_DiamondShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 + _controller.value * 3, -0.3),
              end: Alignment(1.0 + _controller.value * 3, 0.3),
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.4),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}
