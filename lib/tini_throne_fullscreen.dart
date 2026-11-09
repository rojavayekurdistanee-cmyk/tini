import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_colors.dart';
import 'auth_provider.dart' as custom;
import 'crown_provider.dart';
import 'king_fire_ring.dart';
import 'profile_screen.dart';

/// واجهة عرش كاملة المساحة. تستخدم CrownProvider الحالي دون تعديل آلية المزايدة.
/// تبقى ThroneSection الأصلية دون تغيير لتجنب التأثير على أي استخدام آخر لها.
class TiniThroneFullScreen extends StatefulWidget {
  final bool hideBidField;

  const TiniThroneFullScreen({super.key, this.hideBidField = false});

  @override
  State<TiniThroneFullScreen> createState() => _TiniThroneFullScreenState();
}

class _TiniThroneFullScreenState extends State<TiniThroneFullScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController bidController = TextEditingController();
  final FocusNode bidFocusNode = FocusNode();
  late final AnimationController _crownRotationController;
  Timer? _timer;
  int _currentStyleIndex = 0;
  String? _followingViewerUid;
  String? _followingKingUid;
  Stream<DocumentSnapshot>? _followingStream;

  Stream<DocumentSnapshot> _followingFor(String viewerUid, String kingUid) {
    if (_followingStream == null ||
        _followingViewerUid != viewerUid ||
        _followingKingUid != kingUid) {
      _followingViewerUid = viewerUid;
      _followingKingUid = kingUid;
      _followingStream = FirebaseFirestore.instance
          .collection('users')
          .doc(viewerUid)
          .collection('following')
          .doc(kingUid)
          .snapshots();
    }
    return _followingStream!;
  }

  @override
  void initState() {
    super.initState();
    _currentStyleIndex = DateTime.now().minute % 3;
    _crownRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    // تحديث العد التنازلي وتبديل أنماط شارة الملك، دون أي كتابة إلى Firebase.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() => _currentStyleIndex = DateTime.now().minute % 3);
      }
    });
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
      builder: (context, crown, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final wide = width >= 600;
            final short = constraints.maxHeight < 570;
            final side = wide ? 24.0 : 12.0;
            final top = short ? 8.0 : 16.0;
            final bottom = math.max(
              24.0,
              MediaQuery.viewInsetsOf(context).bottom + 20.0,
            );

            return SingleChildScrollView(
              key: const PageStorageKey<String>('tini_throne_full_screen_scroll'),
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(side, top, side, bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0.0,
                        constraints.maxHeight - top - bottom,
                      ),
                    ),
                    // نتجنب IntrinsicHeight لأن داخل حقل المزايدة LayoutBuilder.
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildRoyalHeader(),
                        SizedBox(height: short ? 10 : 18),
                        _buildKingCard(crown, wide: wide),
                        SizedBox(height: short ? 10 : 16),
                        if (!widget.hideBidField) ...[
                          _buildBidSection(crown),
                          SizedBox(height: short ? 10 : 16),
                        ],
                        if (crown.currentKingName != null &&
                            crown.currentKingName!.isNotEmpty) ...[
                          _buildRotatingKingBadge(crown),
                          SizedBox(height: short ? 10 : 16),
                        ],
                        _buildUserInfo(crown),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRoyalHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _crownRotationController,
          builder: (context, _) {
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(_crownRotationController.value * 2 * math.pi),
              child: const Text('👑', style: TextStyle(fontSize: 28)),
            );
          },
        ),
        const SizedBox(width: 10),
        const Flexible(
          child: Text(
            'Tini Throne',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKingCard(CrownProvider crown, {required bool wide}) {
    final content = <Widget>[
      _buildKingAvatar(crown, wide: wide),
      SizedBox(width: wide ? 32 : 0, height: wide ? 0 : 12),
      if (wide)
        Expanded(child: _buildKingDetails(crown, wide: wide))
      else
        _buildKingDetails(crown, wide: wide),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 26 : 14,
        vertical: wide ? 26 : 18,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 18,
          ),
        ],
      ),
      child: wide
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: content,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: content,
            ),
    );
  }

  Widget _buildKingAvatar(CrownProvider crown, {required bool wide}) {
    final kingUid = crown.currentKingUid;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwnKing = kingUid != null && kingUid == myUid;
    final avatarRadius = wide ? 73.0 : 60.0;
    final ringSize = avatarRadius * 2.6;
    final hasKing = kingUid != null && kingUid.isNotEmpty;

    return KingFireRing(
      size: ringSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: hasKing
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: kingUid),
                      ),
                    )
                : null,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundColor: AppColors.surface,
                backgroundImage: crown.currentKingAvatar != null &&
                        crown.currentKingAvatar!.isNotEmpty
                    ? CachedNetworkImageProvider(crown.currentKingAvatar!)
                    : null,
                child: crown.currentKingAvatar == null ||
                        crown.currentKingAvatar!.isEmpty
                    ? const Icon(
                        Icons.person,
                        size: 36,
                        color: AppColors.iconInactive,
                      )
                    : null,
              ),
            ),
          ),
          // زر المتابعة نفسه؛ لا نغيّر آلية المتابعة الموجودة في AuthProvider.
          if (kingUid != null && kingUid.isNotEmpty && !isOwnKing && myUid != null)
            Positioned(
              bottom: 0,
              right: 0,
              child: Consumer<custom.AuthProvider>(
                builder: (context, auth, _) {
                  return StreamBuilder<DocumentSnapshot>(
                    stream: _followingFor(myUid, kingUid),
                    builder: (context, snapshot) {
                      final isFollowing =
                          snapshot.hasData && snapshot.data!.exists;
                      return Material(
                        color: isFollowing
                            ? AppColors.surface
                            : AppColors.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () async => auth.toggleFollow(kingUid),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              isFollowing ? Icons.check : Icons.add,
                              color: isFollowing
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              size: 22,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKingDetails(CrownProvider crown, {required bool wide}) {
    final alignment = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text(
          crown.currentKingName ?? 'لا يوجد ملك حالياً',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: wide ? 24 : 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.17),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.65),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 19),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${NumberFormat('#,###').format(crown.currentBid)} نقطة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCountdown(crown),
      ],
    );
  }

  Widget _buildCountdown(CrownProvider crown) {
    final isLocked = crown.isThroneLocked && crown.lockEndTime != null;
    final deadline = isLocked ? crown.lockEndTime : crown.auctionEndsAt;
    if (deadline == null) {
      return const Text(
        'صارع الملك: زايد واستلم العرش',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.greyText, fontSize: 13),
      );
    }

    final remaining = deadline.toDate().difference(DateTime.now());
    if (remaining.isNegative) {
      return Text(
        isLocked ? 'جاري التصفير...' : 'انتهى المزاد',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.error, fontSize: 13),
      );
    }
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final time = isLocked
        ? '${days}ي ${hours}س ${minutes}د'
        : '${remaining.inHours}س ${minutes}د';
    return Text(
      'ينتهي خلال: $time',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildBidSection(CrownProvider crown) {
    if (crown.isThroneLocked) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, color: AppColors.error, size: 19),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'العرش مغلق لمدة 7 أيام',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (crown.isKing) return const SizedBox.shrink();

    final field = TextField(
      controller: bidController,
      focusNode: bidFocusNode,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'أدخل مزايدتك (${crown.currentBid + 100}+)',
        hintStyle: const TextStyle(color: AppColors.greyText, fontSize: 14),
        filled: true,
        fillColor: AppColors.background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );

    final bidButton = ElevatedButton(
      onPressed: crown.isLoading ? null : () => _placeBid(crown),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        minimumSize: const Size(120, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: crown.isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: AppColors.textPrimary,
                strokeWidth: 2,
              ),
            )
          : const Text(
              'زايد',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
    );

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 330) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field,
                const SizedBox(height: 10),
                bidButton,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: 10),
              bidButton,
            ],
          );
        },
      ),
    );
  }

  Future<void> _placeBid(CrownProvider crown) async {
    final bid = int.tryParse(bidController.text.trim());
    if (bid == null || bid <= crown.currentBid) {
      _showMessage('المزايدة يجب أن تكون أعلى', isError: true);
      return;
    }
    if (bid > CrownProvider.maxBid) {
      _showMessage('السقف الأعلى 10,000 نقطة', isError: true);
      return;
    }
    final success = await crown.placeBid(bid);
    if (!mounted) return;
    if (success) {
      bidController.clear();
      bidFocusNode.unfocus();
      _showMessage(
        bid >= CrownProvider.maxBid
            ? 'مبروك! استلمت العرش لمدة 7 أيام 👑'
            : 'تم وضع المزايدة! 👑',
      );
    } else {
      _showMessage('لم تكتمل المزايدة. تحقق من الرصيد وحالة العرش.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
      ),
    );
  }

  Widget _buildRotatingKingBadge(CrownProvider crown) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: _buildBadgeStyle(crown),
    );
  }

  Widget _buildBadgeStyle(CrownProvider crown) {
    final text = crown.isKing
        ? 'أنت الملك الحالي 👑'
        : 'الملك الحالي ${crown.currentKingName} 👑';
    switch (_currentStyleIndex) {
      case 0:
        return _buildBadgeFrame(
          key: const ValueKey(0),
          text: text,
          icon: Icons.auto_awesome,
          borderColor: const Color(0xFFFFD700),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFFFFD700), Color(0xFF1A1A1A)],
            stops: [0, 0.5, 1],
          ),
          textColor: Colors.white,
        );
      case 1:
        return _buildBadgeFrame(
          key: const ValueKey(1),
          text: text,
          icon: Icons.diamond,
          borderColor: const Color(0xFFFFD700),
          gradient: const LinearGradient(
            colors: [Color(0xFF2C2C2C), Color(0xFF2C2C2C)],
          ),
          textColor: const Color(0xFFFFD700),
        );
      default:
        return _buildBadgeFrame(
          key: const ValueKey(2),
          text: text,
          icon: Icons.workspace_premium,
          borderColor: const Color(0xFFFFD700),
          gradient: const LinearGradient(
            colors: [Color(0xFF8B0000), Color(0xFF5C0000)],
          ),
          textColor: const Color(0xFFFFD700),
        );
    }
  }

  Widget _buildBadgeFrame({
    required Key key,
    required String text,
    required IconData icon,
    required Color borderColor,
    required Gradient gradient,
    required Color textColor,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.2),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: textColor, size: 18),
        ],
      ),
    );
  }

  Widget _buildUserInfo(CrownProvider crown) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.iconInactive.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildInfoItem(
              'نقاطك',
              NumberFormat('#,###').format(crown.myPoints),
            ),
          ),
          Container(height: 40, width: 1, color: AppColors.iconInactive),
          Expanded(child: _buildInfoItem('رقم التاج', crown.myCrownNumber)),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.greyText, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
