import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math' as math;
import 'crown_provider.dart';
import 'app_colors.dart';
import 'profile_screen.dart';
import 'auth_provider.dart' as custom;
import 'king_fire_ring.dart';
import 'throne_countdown.dart';
import 'throne_earned_badge.dart';

class ThroneSection extends StatefulWidget {
  final bool hideBidField;
  const ThroneSection({super.key, this.hideBidField = false});

  @override
  State<ThroneSection> createState() => _ThroneSectionState();
}

class _ThroneSectionState extends State<ThroneSection> with TickerProviderStateMixin {
  Timer? _timer;
  int _currentStyleIndex = 0;
  late AnimationController _crownRotationController;
  final TextEditingController bidController = TextEditingController();
  final FocusNode bidFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _syncStyleWithServerTime();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentStyleIndex = (_currentStyleIndex + 1) % 3;
        });
      }
    });
    
    _crownRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  void _syncStyleWithServerTime() {
    final now = DateTime.now();
    _currentStyleIndex = now.minute % 3;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _crownRotationController.dispose();
    bidController.dispose();
    bidFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CrownProvider>(
      builder: (context, crown, child) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 1, 12, 1), // شلت كل المارجن تقريبا
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 3), // شلت كل البادنج تقريبا
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.3),
                  AppColors.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(14), // كان 20
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1), // كان 1.5
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 10, // كان 20
                  spreadRadius: 0, // كان 2
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const SizedBox(height: 0), // شلت كل المسافات
                _buildKingDisplay(crown),
                const SizedBox(height: 0),
                _buildBidSection(context, crown),
                const SizedBox(height: 0),
                _buildUserInfo(crown),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _crownRotationController,
          builder: (context, child) {
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(_crownRotationController.value * 2 * math.pi),
              child: const Text(
                '👑',
                style: TextStyle(fontSize: 16), // كان 20
              ),
            );
          },
        ),
        const SizedBox(width: 3), // كان 4
        const Text(
          'Tini Throne',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14, // كان 16
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildKingDisplay(CrownProvider crown) {
    const double avatarRadius = 48; // كان 28 - هذا أهم شي
    const double ringSize = avatarRadius * 2.6; // كان 2.8
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final kingUid = crown.displayUid;
    final isOwnKing = currentUserId == kingUid && kingUid != null;

    // الأفتار مع الزر - مفصول عن الحلقة
    Widget avatarWithButton = Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () {
            if (kingUid != null && kingUid.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(userId: kingUid),
                ),
              );
            }
          },
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 1), // كان 2
            ),
            child: CircleAvatar(
              radius: avatarRadius - 1, // كان -2
              backgroundColor: AppColors.surface,
              backgroundImage: crown.displayAvatar != null && crown.displayAvatar!.isNotEmpty
                  ? CachedNetworkImageProvider(crown.displayAvatar!)
                  : null,
              child: crown.displayAvatar == null || crown.displayAvatar!.isEmpty
                  ? const Icon(Icons.person, size: 22, color: AppColors.iconInactive) // كان 28
                  : null,
            ),
          ),
        ),
        // زر الزائد لازق على الأفتار
        if (kingUid != null && kingUid.isNotEmpty && !isOwnKing && currentUserId != null)
          Positioned(
            bottom: 2,
            right: 2,
            child: Consumer<custom.AuthProvider>(
              builder: (context, auth, child) {
                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUserId)
                      .collection('following')
                      .doc(kingUid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final bool isFollowing = snapshot.hasData && snapshot.data!.exists;
                    return GestureDetector(
                      onTap: () async {
                        await auth.toggleFollow(kingUid);
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isFollowing ? AppColors.surface : AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surface, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha:0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          isFollowing ? Icons.check : Icons.add,
                          color: isFollowing ? AppColors.primary : AppColors.textPrimary,
                          size: 14,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // الحلقة الخارجية + الأفتار مع الزر
        KingFireRing(
          size: ringSize,
          child: avatarWithButton,
        ),
        const SizedBox(height: 0), // كان 2
        Text(
          crown.displayName ?? 'لا يوجد ملك حالياً',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12, // كان 14
            fontWeight: FontWeight.bold,
          ),
        ),
        if (crown.isThroneLocked && crown.currentKingUid != null)
          EarnedThroneBadge(uid: crown.currentKingUid!),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1), // كان 10, 3
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16), // كان 20
            border: Border.all(color: AppColors.primary, width: 0.5), // كان 1
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 12), // كان 14
              const SizedBox(width: 2), // كان 3
              Text(
                '${NumberFormat('#,###').format(crown.currentBid)} نقطة',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 10, // كان 12
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        _buildCountdown(crown),
      ],
    );
  }

  Widget _buildCountdown(CrownProvider crown) => ThroneCountdown(
    deadline: (crown.isThroneLocked ? crown.lockEndTime : crown.auctionEndsAt)?.toDate(),
    reign: crown.isThroneLocked, now: () => crown.serverNow,
  );

  Widget _buildBidSection(BuildContext context, CrownProvider crown) {
    if (widget.hideBidField) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!crown.isKing && !crown.isThroneLocked)
          SizedBox(
            height: 28, // ارتفاع ثابت صغير للصف كامل
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: bidController,
                    focusNode: bidFocusNode,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 11), // كان 12
                    decoration: InputDecoration(
                      hintText: 'أدخل مزايدتك (${crown.currentBid + 1}+)',
                      hintStyle: TextStyle(color: AppColors.greyText, fontSize: 9), // كان 10
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), // كان 12
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), // كان 8, 6
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4), // كان 5
                ElevatedButton(
                  onPressed: crown.isLoading || !crown.canBid ? null : () async {
                    final bid = int.tryParse(bidController.text);
                    if (bid == null || bid <= crown.currentBid) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المزايدة يجب أن تكون أعلى'), backgroundColor: AppColors.error));
                      return;
                    }
                    if (bid > CrownProvider.maxBid) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('السقف الأعلى 10,000 نقطة'), backgroundColor: AppColors.error));
                      return;
                    }
                    final success = await crown.placeBid(bid);
                    if (!context.mounted) return;
                    if (success) {
                      bidController.clear();
                      if (bid >= CrownProvider.maxBid) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مبروك! استلمت العرش لمدة 7 أيام 👑'), backgroundColor: AppColors.primary));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم وضع المزايدة! 👑'), backgroundColor: AppColors.primary));
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(crown.lastError ?? 'تعذر تأكيد المزايدة'), backgroundColor: AppColors.error));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, 
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), // كان 14, 6
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), // كان 12
                    minimumSize: const Size(0, 28), // كان 32
                  ),
                  child: crown.isLoading ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2)) : const Text('زايد', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11)), // كان 12
                ),
              ],
            ),
          ),
        if (crown.isThroneLocked)
          Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error, width: 1),
            ),
            child: const Text(
              'المزايدات مغلقة خلال فترة الحكم',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        if (crown.currentKingName != null && crown.currentKingName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1), // كان 2
            child: _buildRotatingKingBadge(crown),
          ),
      ],
    );
  }

  Widget _buildRotatingKingBadge(CrownProvider crown) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      child: _getCurrentBadgeStyle(crown),
    );
  }

  Widget _getCurrentBadgeStyle(CrownProvider crown) {
    switch (_currentStyleIndex) {
      case 0:
        return _buildRoyalSashBadge(crown: crown, key: const ValueKey(0));
      case 1:
        return _buildGoldenPulseBadge(crown: crown, key: const ValueKey(1));
      case 2:
        return _buildRoyalSealBadge(crown: crown, key: const ValueKey(2));
      default:
        return _buildRoyalSashBadge(crown: crown, key: const ValueKey(0));
    }
  }

  String _getBadgeText(CrownProvider crown) {
    if (crown.isKing) {
      return 'أنت الملك الحالي 👑';
    } else {
      return 'الملك الحالي ${crown.currentKingName} 👑';
    }
  }

  Widget _buildRoyalSashBadge({required CrownProvider crown, Key? key}) {
    return Container(
      key: key,
      height: 28, // كان 36 - هذا مهم
      padding: const EdgeInsets.symmetric(horizontal: 8), // كان 10
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFFFFD700), Color(0xFF1A1A1A)],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(10), // كان 12
        border: Border.all(color: const Color(0xFFFFD700), width: 1), // كان 2
        boxShadow: [
          BoxShadow(color: Colors.amber.withValues(alpha:0.7), blurRadius: 8, spreadRadius: 0), // كان 12, 1
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⚜', style: TextStyle(fontSize: 11)), // كان 14
          const SizedBox(width: 2), // كان 4
          Flexible(
            child: Text(
              _getBadgeText(crown),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 10, // كان 12
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2), // كان 4
          const Text('⚜', style: TextStyle(fontSize: 11)), // كان 14
        ],
      ),
    );
  }

  Widget _buildGoldenPulseBadge({required CrownProvider crown, Key? key}) {
    return Container(
      key: key,
      height: 28, // كان 36
      padding: const EdgeInsets.symmetric(horizontal: 6), // كان 8
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12), // كان 16
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5), // كان 2.5
        boxShadow: [
          BoxShadow(color: const Color(0xFFFFD700).withValues(alpha:0.5), blurRadius: 10, spreadRadius: 0), // كان 16
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.diamond, color: Color(0xFFFFD700), size: 14), // كان 18
          const SizedBox(width: 2), // كان 4
          Flexible(
            child: Text(
              _getBadgeText(crown),
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontSize: 11, // كان 13
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2), // كان 4
          const Icon(Icons.diamond, color: Color(0xFFFFD700), size: 14), // كان 18
        ],
      ),
    );
  }

  Widget _buildRoyalSealBadge({required CrownProvider crown, Key? key}) {
    return Container(
      key: key,
      height: 28, // كان 36
      padding: const EdgeInsets.symmetric(horizontal: 8), // كان 12
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B0000), Color(0xFF5C0000)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(10), // كان 12
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha:0.6), blurRadius: 6, offset: const Offset(0, 1)), // كان 10, 3
          BoxShadow(color: const Color(0xFFFFD700).withValues(alpha:0.4), blurRadius: 8, spreadRadius: 0), // كان 14, 1
        ],
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5), // كان 2.5
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 16), // كان 20
          const SizedBox(width: 2), // كان 4
          Flexible(
            child: Text(
              _getBadgeText(crown),
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.w900,
                fontSize: 9, // كان 11
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfo(CrownProvider crown) {
    return Container(
      padding: const EdgeInsets.all(3), // كان 6
      decoration: BoxDecoration(color: AppColors.background.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)), // كان 12
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoItem('نقاطك', '${NumberFormat('#,###').format(crown.myPoints)}'),
          Container(width: 1, height: 16, color: AppColors.iconInactive), // كان 20
          _buildInfoItem('رقم التاج', crown.myCrownNumber),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: AppColors.greyText, fontSize: 7)), // كان 8
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold)), // كان 12
      ],
    );
  }
}