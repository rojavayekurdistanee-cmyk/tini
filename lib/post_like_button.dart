import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'post_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'biji.dart';

/*
  [Tini - PostLikeButton - Direct Sync Edition V3.0]
  التعديل:
    - إصلاح didUpdateWidget لتحديث الحالة (isLiked/likesCount) فور وصول بيانات جديدة من السيرفر.
    - ضمان استجابة القلب للون الأحمر فوراً حتى في تبويب المشاركة.
    - الحفاظ على قاعدة "الإضافة فقط" واستقرار الأداء.
*/

class PostLikeButton extends StatefulWidget {
  final String postId;
  final int likesCount;
  final String currentUserId;
  final String? postOwnerId; 

  const PostLikeButton({
    super.key,
    required this.postId,
    required this.likesCount,
    required this.currentUserId,
    this.postOwnerId, 
  });

  @override
  State<PostLikeButton> createState() => _PostLikeButtonState();
}

class _PostLikeButtonState extends State<PostLikeButton> with SingleTickerProviderStateMixin {
  late bool isLiked;
  late int localLikesCount;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _initLocalState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      lowerBound: 0.8,
      upperBound: 1.2,
    );
    _controller.value = 1.0;
  }

  void _initLocalState() {
    isLiked = false;
    localLikesCount = widget.likesCount;
  }

  @override
  void didUpdateWidget(covariant PostLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.likesCount != widget.likesCount || 
        oldWidget.postId != widget.postId) {
      setState(() {
        localLikesCount = widget.likesCount;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() async {
  final bool wasLiked = isLiked;
      if (!wasLiked) {
      Biji.show(context);
    }
  final docId = '${widget.postId}_${widget.currentUserId}_like';
  final docRef = FirebaseFirestore.instance.collection('activities').doc(docId);
  
  if (mounted) {
    setState(() {
      if (isLiked) {
        isLiked = false;
        localLikesCount--;
      } else {
        isLiked = true;
        localLikesCount++;
        _controller.forward().then((_) => _controller.reverse());
      }
    });
  }

  context.read<PostProvider>().toggleLike(widget.postId, widget.postOwnerId ?? "");

  try {
    if (wasLiked) {
      await docRef.delete();
    } else {
      if (widget.postOwnerId != null && widget.postOwnerId != widget.currentUserId) {
        // جيب اسم يلي عمل لايك
        String userName = 'مستخدم';
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.currentUserId).get();
          if (userDoc.exists) {
            final data = userDoc.data() as Map<String, dynamic>;
            userName = data['fullName'] ?? data['username'] ?? 'مستخدم';
          }
        } catch (_) {}

        await docRef.set({
          'toUid': widget.postOwnerId,
          'fromUid': widget.currentUserId,
          'type': 'like',
          'text': '$userName أعجب بمنشورك',
          'postId': widget.postId,
          'timestamp': FieldValue.serverTimestamp(),
          'seen': false,
        }, SetOptions(merge: true));
      }
    }
  } catch (e) {
    debugPrint("Activity error: $e");
  }
}

  @override
  Widget build(BuildContext context) {
    if (widget.currentUserId.isEmpty || widget.postId.isEmpty) {
      return RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: null,
              child: Icon(
                Icons.favorite_border,
                size: 38,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$localLikesCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'Tajawal',
              ),
            ),
          ],
        ),
      );
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .collection('likedPosts')
          .doc(widget.postId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          isLiked = true;
        } else if (snapshot.hasData && !snapshot.data!.exists) {
          // اذا السيرفر قال مش موجود، نترك الحالة المحلية للتحديث التفاؤلي
        }
        // نعتمد على الـ Stream كمصدر أساسي للحقيقة
        final bool serverIsLiked = snapshot.data?.exists ?? false;
        if (snapshot.connectionState == ConnectionState.active && snapshot.hasData) {
          isLiked = serverIsLiked;
        }
        return RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleTap,
                child: ScaleTransition(
                  scale: _controller,
                  child: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 38,
                    // [Titi Identity]: اللون الأحمر المعتمد للحذف والنبض (Error Red)
                    color: isLiked ? const Color(0xFFE53935) : Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$localLikesCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Tajawal',
                  shadows: [
                    Shadow(
                      blurRadius: 4,
                      color: Colors.black45,
                      offset: Offset(0, 2),
                    )
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}