import 'banner_transition.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'banner_manager.dart';
import 'auth_provider.dart' as custom;
import 'audience_access.dart';
import 'story_ring.dart';
import 'post_view_screen.dart';
import 'profile_screen.dart';
import 'visits_screen.dart';
import 'follow_list_screen.dart';
import 'story.dart';
import 'titi_single_engine.dart';
import 'app_navigator.dart';

class GlobalBannerOverlay extends StatefulWidget {
  const GlobalBannerOverlay({super.key, required this.child});
  final Widget child;
  @override
  State<GlobalBannerOverlay> createState() => _GlobalBannerOverlayState();
}

class _GlobalBannerOverlayState extends State<GlobalBannerOverlay>
    with WidgetsBindingObserver {
  final manager = BannerManager.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    manager.setForeground(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    manager.canPresent = _canPresent;
    manager.readyToPresent = _readyToPresent;
  }

  bool _canPresent(BannerItem item) {
    if (!mounted || FirebaseAuth.instance.currentUser == null) {
      return false;
    }
    final auth = context.read<custom.AuthProvider>();
    if (item.actors.keys.any(
      (uid) =>
          auth.blockedUsersSet.contains(uid) || auth.blockedBySet.contains(uid),
    )) {
      return false;
    }
    final postId = item.data['postId']?.toString();
    if (postId != null && postId.isNotEmpty && manager.isViewingPost(postId)) {
      return false;
    }
    return true;
  }

  bool _readyToPresent(BannerItem item) =>
      mounted &&
      !manager.isOpening &&
      item.actors.keys.every(
        (uid) => AudienceAccess.instance.canViewProfile(uid),
      );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      manager.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    manager.canPresent = null;
    manager.readyToPresent = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: media.padding.top + kToolbarHeight + 8,
          left: 16,
          right: 16,
          child: ValueListenableBuilder<BannerItem?>(
            valueListenable: manager.currentBanner,
            builder: (context, item, _) => BannerTransition(
              child: item == null
                  ? null
                  : _BannerCard(key: ValueKey(item.id), item: item),
            ),
          ),
        ),
      ],
    );
  }
}

class _BannerCard extends StatefulWidget {
  final BannerItem item;
  const _BannerCard({super.key, required this.item});
  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stories;
  bool _tapping = false;
  String get _actor => widget.item.data['uid']?.toString() ?? '';
  void _watchStories() {
    _stories = _actor.isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection('stories')
              .doc(_actor)
              .collection('items')
              .where('expiresAt', isGreaterThan: Timestamp.now())
              .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _watchStories();
  }

  @override
  void didUpdateWidget(covariant _BannerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.data['uid'] != _actor) _watchStories();
  }

  Future<void> _open() async {
    final manager = BannerManager.instance;
    if (_tapping || !manager.beginOpen()) return;
    _tapping = true;
    final item = widget.item;
    final viewer = FirebaseAuth.instance.currentUser?.uid;
    manager.dismiss(manual: false);
    try {
      final nav = navigatorKey.currentState;
      if (nav == null || viewer == null) return;
      final auth = context.read<custom.AuthProvider>();
      if (auth.blockedUsersSet.contains(_actor) ||
          auth.blockedBySet.contains(_actor)) {
        return;
      }
      Widget destination;
      final postId = item.data['postId']?.toString() ?? '';
      if ({
        BannerType.like,
        BannerType.comment,
        BannerType.mention,
      }.contains(item.type)) {
        if (postId.isEmpty ||
            !await AudienceAccess.instance.verifyPost(postId)) {
          return;
        }
        final doc = await FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .get();
        if (!doc.exists ||
            doc.data()?['isDeleted'] == true ||
            doc.data()?['isHidden'] == true) {
          return;
        }
        final owner = doc.data()?['uid']?.toString() ?? '';
        if (auth.blockedUsersSet.contains(owner) ||
            auth.blockedBySet.contains(owner)) {
          return;
        }
        destination = PostViewScreen(
          posts: [doc],
          initialIndex: 0,
          openComments: item.type == BannerType.comment,
          highlightCommentId: item.data['commentId']?.toString(),
        );
      } else if (item.type == BannerType.visit) {
        destination = const VisitsScreen();
      } else if (item.type == BannerType.follow && item.actors.length > 1) {
        destination = FollowListScreen(
          userId: viewer,
          userName: 'المتابعون',
          initialTab: 1,
        );
      } else {
        if (!AudienceAccess.instance.canViewProfile(_actor)) return;
        destination = item.type == BannerType.story
            ? Story(userId: _actor)
            : ProfileScreen(userId: _actor);
      }
      if (FirebaseAuth.instance.currentUser?.uid != viewer ||
          !nav.mounted ||
          auth.blockedUsersSet.contains(_actor) ||
          auth.blockedBySet.contains(_actor)) {
        return;
      }
      try {
        unawaited(
          TitiSingleEngine().player.pause().catchError((Object error) {
            debugPrint('Banner pause skipped: $error');
          }),
        );
      } catch (_) {}
      unawaited(nav.push(MaterialPageRoute(builder: (_) => destination)));
    } catch (error) {
      debugPrint('Banner navigation skipped: $error');
    } finally {
      manager.endOpen();
      _tapping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final icon = switch (item.type) {
      BannerType.like => Icons.favorite,
      BannerType.comment => Icons.chat_bubble,
      BannerType.follow => Icons.person_add,
      BannerType.mention => Icons.alternate_email,
      BannerType.visit => Icons.visibility,
      BannerType.story => Icons.auto_stories,
      BannerType.activity => Icons.circle,
    };
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -100) {
            BannerManager.instance.dismiss();
          }
        },
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0).abs() > 100) {
            BannerManager.instance.dismiss();
          }
        },
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xF200695C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF26A69A), width: .8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _stories,
                builder: (context, snapshot) {
                  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  final active =
                      snapshot.data?.docs.where((doc) {
                        final at = doc.data()['expiresAt'];
                        return at is Timestamp &&
                            at.toDate().isAfter(DateTime.now());
                      }).toList() ??
                      [];
                  final unseen =
                      uid.isNotEmpty &&
                      active.any(
                        (doc) => !(doc.data()['viewedBy'] as List? ?? [])
                            .contains(uid),
                      );
                  return StoryRing(
                    imageUrl: item.data['img']?.toString() ?? '',
                    size: 44,
                    hasStories: active.isNotEmpty,
                    hasUnviewed: unseen,
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.text,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, color: Colors.white, size: 20),
              IconButton(
                tooltip: 'إغلاق',
                visualDensity: VisualDensity.compact,
                onPressed: () => BannerManager.instance.dismiss(),
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
