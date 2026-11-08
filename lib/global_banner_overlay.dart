import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'banner_manager.dart';
import 'story_ring.dart';
import 'post_view_screen.dart';
import 'profile_screen.dart';
import 'visits_screen.dart';
import 'story.dart';
import 'titi_single_engine.dart';
import 'app_navigator.dart';

class GlobalBannerOverlay extends StatelessWidget {
  const GlobalBannerOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      Positioned(
        top: 60,
        left: 35,
        right: 35,
        child: ValueListenableBuilder<BannerItem?>(
          valueListenable: BannerManager.instance.currentBanner,
          builder: (context, item, _) {
            if (item == null) return const SizedBox.shrink();
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (c, a) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                child: c,
              ),
              child: Material(
                key: ValueKey(item.id),
                type: MaterialType.transparency,
                child: _BannerCard(item: item),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _BannerCard extends StatelessWidget {
  final BannerItem item;
  const _BannerCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    late IconData icon; late Color color; late String text;
    switch(item.type){
      case BannerType.like: icon=Icons.favorite; color=const Color(0xFFE91E63); text="${item.data['name']} أعجب بمنشورك"; break;
      case BannerType.comment: icon=Icons.chat_bubble; color=const Color(0xFF26A69A); text="${item.data['name']} علّق على منشورك"; break;
      case BannerType.follow: icon=Icons.person_add; color=const Color(0xFF7C4DFF); text="${item.data['name']} بدأ بمتابعتك"; break;
      case BannerType.mention: icon=Icons.alternate_email; color=const Color(0xFFFF9800); text="${item.data['name']} ذكرك في منشور"; break;
      case BannerType.visit: icon=Icons.visibility; color=const Color(0xFF03A9F4); text="${item.data['name']} زار ملفك الشخصي"; break;
      case BannerType.story: icon=Icons.auto_stories; color=const Color(0xFF4CAF50); text="${item.data['name']} نشر قصة"; break;
      case BannerType.activity: icon=Icons.circle; color=Colors.green; text="${item.data['name']} نشط الآن"; break;
    }

    return GestureDetector(
      onTap: () async {
        try { TitiSingleEngine().player.pause(); } catch(_){}
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        final postId = item.data['postId'];
        if ([BannerType.like,BannerType.comment,BannerType.mention].contains(item.type) && postId!=null){
          final doc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
          if(!doc.exists) return;
          nav.push(MaterialPageRoute(builder: (_)=> PostViewScreen(posts:[doc], initialIndex:0, openComments: item.type==BannerType.comment, highlightCommentId: item.data['commentId'])));
        } else if(item.type==BannerType.visit){
          nav.push(MaterialPageRoute(builder: (_)=> const VisitsScreen()));
        } else if(item.type==BannerType.story){
          nav.push(MaterialPageRoute(builder: (_)=> Story(userId: item.data['uid'])));
        } else {
          nav.push(MaterialPageRoute(builder: (_)=> ProfileScreen(userId: item.data['uid'])));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xF200695C), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF26A69A), width: 0.8), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0,4))]),
        child: Row(children: [
          // [Tini - Banner Story Ring]: لون الدائرة يعتمد على القصص الفعالة وغير المشاهدة.
          StreamBuilder<QuerySnapshot>(
            stream: (item.data['uid']??'').toString().isNotEmpty
                ? FirebaseFirestore.instance.collection('stories').doc(item.data['uid'].toString()).collection('items').where('expiresAt', isGreaterThan: Timestamp.now()).snapshots()
                : null,
            builder: (context, snapshot) {
              final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
              final hasUnviewed = currentUid.isNotEmpty && (snapshot.data?.docs.any((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final expiresAt = data['expiresAt'];
                if (expiresAt is! Timestamp || !expiresAt.toDate().isAfter(DateTime.now())) return false;
                final viewedBy = List<String>.from(data['viewedBy']?? []);
                return !viewedBy.contains(currentUid);
              })?? false);
              // تبقى الدائرة رمادية دون قصة، أو عندما تكون كل القصص مقروءة.
              return StoryRing(imageUrl: item.data['img']??"", size: 60, hasStories: true, hasUnviewed: hasUnviewed);
            },
          ),
          const SizedBox(width:10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15, decoration: TextDecoration.none), maxLines:2, overflow: TextOverflow.ellipsis)),
          Container(width:28,height:28,decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size:16)),
        ]),
      ),
    );
  }
}