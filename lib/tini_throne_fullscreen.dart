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
import 'throne_badges.dart';
import 'throne_social.dart';
import 'throne_earned_badge.dart';
import 'throne_countdown.dart';

/// واجهة العرش؛ كل المزايدات والانتقالات المالية معتمدة من السيرفر.
/// تحافظ على الهوية البصرية والمتابعة والبروفايل ومكافآت العرش.
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
              key: const PageStorageKey<String>(
                'tini_throne_full_screen_scroll',
              ),
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
                        SizedBox(height: short ? 10 : 16),
                        const ThroneSocial(),
                        const _ThroneRewardsSection(),
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
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: content)
          : Column(mainAxisSize: MainAxisSize.min, children: content),
    );
  }

  Widget _buildKingAvatar(CrownProvider crown, {required bool wide}) {
    final kingUid = crown.displayUid;
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
                backgroundImage:
                    crown.displayAvatar != null &&
                        crown.displayAvatar!.isNotEmpty
                    ? CachedNetworkImageProvider(crown.displayAvatar!)
                    : null,
                child:
                    crown.displayAvatar == null || crown.displayAvatar!.isEmpty
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
          if (kingUid != null &&
              kingUid.isNotEmpty &&
              !isOwnKing &&
              myUid != null)
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
    final alignment = wide
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text(
          crown.displayName ?? 'لا يوجد ملك حالياً',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: wide ? 24 : 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (crown.isThroneLocked && crown.currentKingUid != null)
          EarnedThroneBadge(uid: crown.currentKingUid!),
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

  Widget _buildCountdown(CrownProvider crown) => ThroneCountdown(
    deadline: (crown.isThroneLocked ? crown.lockEndTime : crown.auctionEndsAt)
        ?.toDate(),
    reign: crown.isThroneLocked,
    now: () => crown.serverNow,
  );

  Widget _buildBidSection(CrownProvider crown) {
    if (crown.needsPendingBidCheck) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            crown.hasPendingBid
                ? 'تحقق من نتيجة المزايدة السابقة قبل تقديم مزايدة جديدة'
                : crown.isRestoringPendingBid
                    ? 'جاري استعادة الطلب السابق'
                    : 'تعذر التحقق من الطلب المحفوظ؛ أعد المحاولة',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          TextButton.icon(
            onPressed: crown.isLoading || crown.isRestoringPendingBid
                ? null
                : () async {
                    final success = await crown.retryPendingBid();
                    if (!context.mounted) return;
                    if (success) bidController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(success
                          ? 'تم تأكيد نتيجة المزايدة السابقة'
                          : crown.lastError ?? 'لم تتأكد النتيجة بعد؛ أعد المحاولة'),
                    ));
                  },
            icon: crown.isLoading || crown.isRestoringPendingBid
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('التحقق من نتيجة المزايدة'),
          ),
        ],
      );
    }
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
                'المزايدات مغلقة خلال فترة الحكم',
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
        hintText: 'أدخل مزايدتك (${crown.currentBid + 1}+)',
        hintStyle: const TextStyle(color: AppColors.greyText, fontSize: 14),
        filled: true,
        fillColor: AppColors.background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );

    final bidButton = ElevatedButton(
      onPressed: crown.isLoading || !crown.canBid
          ? null
          : () => _placeBid(crown),
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
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 330) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [field, const SizedBox(height: 10), bidButton],
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
    if (bid == null) {
      _showMessage('أدخل رقماً صحيحاً للمزايدة', isError: true);
      return;
    }
    if (bid <= crown.currentBid) {
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
      _showMessage(
        crown.lastError ?? 'لم تكتمل المزايدة. تحقق من الرصيد وحالة العرش.',
        isError: true,
      );
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
        border: Border.all(
          color: AppColors.iconInactive.withValues(alpha: 0.18),
        ),
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

/// قسم توضيحي لمكافآت العرش؛ للعرض فقط ولا يمنح شارات أو يكتب إلى Firestore.
/// يُغلق افتراضياً لتبقى شاشة العرش مركّزة على الملك والمزايدات.
class _ThroneRewardsSection extends StatelessWidget {
  const _ThroneRewardsSection();

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: AppColors.primary.withValues(alpha: 0.25));
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: border,
    );

    return ExpansionTile(
      key: const PageStorageKey<String>('tini_throne_rewards_expansion'),
      initiallyExpanded: false,
      maintainState: false, // يوقف حركة الشارة عندما تُغلق المكافآت.
      backgroundColor: AppColors.surface,
      collapsedBackgroundColor: AppColors.surface,
      shape: shape,
      collapsedShape: shape,
      iconColor: const Color(0xFFFFD36B),
      collapsedIconColor: AppColors.greyText,
      textColor: AppColors.textPrimary,
      collapsedTextColor: AppColors.textPrimary,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      leading: const Icon(
        Icons.workspace_premium_outlined,
        color: Color(0xFFFFD36B),
        size: 24,
      ),
      title: const Text(
        'مكافآت العرش',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: const Text(
        'اضغط لاستكشاف شارات الملك الحالي والملك السابق',
        style: TextStyle(color: AppColors.greyText, fontSize: 12),
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final availableWidth = constraints.maxWidth;
            final twoColumns = availableWidth >= 300;
            final tileWidth = twoColumns
                ? (availableWidth - gap) / 2
                : availableWidth;
            final badgeSize = math.min(112.0, math.max(48.0, tileWidth - 22));

            return Wrap(
              alignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: gap,
              children: [
                _ThroneRewardCard(
                  width: tileWidth,
                  badgeSize: badgeSize,
                  kind: ThroneBadgeKind.currentKing,
                  title: 'الملك الحالي',
                  description: 'احصل على هذه الشارة أثناء حكمك للعرش',
                ),
                _ThroneRewardCard(
                  width: tileWidth,
                  badgeSize: badgeSize,
                  kind: ThroneBadgeKind.formerKing,
                  title: 'الملك السابق',
                  description: 'احتفظ بهذه الشارة للأبد بعد انتهاء حكمك',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// تعرض الشارة نفسها من throne_badges.dart دون أي تعديل على صورها أو حركتها.
class _ThroneRewardCard extends StatelessWidget {
  final double width;
  final double badgeSize;
  final ThroneBadgeKind kind;
  final String title;
  final String description;

  const _ThroneRewardCard({
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
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}