import 'user_documents.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'auth_provider.dart' as custom;
import 'story_ring.dart';
import 'badge_colors.dart'; // أضفت هذا السطر
import 'moderation_service.dart';
import 'block_service.dart';
import 'mention_privacy_service.dart';
import 'throne_earned_badge.dart';

/// Uses the space supplied by the parent, which already accounts for the keyboard.
class ResponsiveCommentsLayout extends StatelessWidget {
  final Widget comments;
  final Widget Function(BuildContext, double) composerBuilder;

  const ResponsiveCommentsLayout({
    super.key,
    required this.comments,
    required this.composerBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height * 0.85;
        final lineHeight = MediaQuery.textScalerOf(context).scale(16) * 1.5;
        final headerHeight = math.min(
          lineHeight + 30,
          math.max(0.0, height - 69),
        );
        final dividerHeight = math.min(
          1.0,
          math.max(0.0, height - headerHeight),
        );
        final composerHeight = math.min(
          math.max(0.0, height - headerHeight - dividerHeight),
          math.max(68.0, height * 0.55),
        );
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Color(0xFF0F1720),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: headerHeight,
                child: const SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(15),
                    child: Text(
                      'التعليقات',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: dividerHeight,
                child: const Divider(color: Colors.white12, height: 1),
              ),
              Expanded(child: comments),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: composerHeight),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SafeArea(
                    top: false,
                    child: composerBuilder(context, composerHeight),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Long drafts scroll inside the input instead of expanding beyond the sheet.
class ResponsiveCommentField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final double maxHeight;
  final ValueChanged<String> onChanged;

  const ResponsiveCommentField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.maxHeight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        minLines: 1,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
          hintText: 'أضف تعليقاً لـ Tini...',
          hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class PostCommentsSheet extends StatefulWidget {
  final String? postId;
  final String? postOwnerId;
  final String? highlightCommentId;
  // [Tini - Owner Reactions Overlay] - تمييز تركوازي مؤقت، دون تغيير سلوك إشعارات التعليقات.
  final bool highlightTemporarily;
  const PostCommentsSheet({Key? key, this.postId, this.postOwnerId, this.highlightCommentId, this.highlightTemporarily = false}) : super(key: key);
  @override
  _PostCommentsSheetState createState() => _PostCommentsSheetState();
}

// [Tini - Comment Reactions] - حالة مؤقتة لعرض نتيجة الضغط فوراً قبل تأكيد Firestore.
class _OptimisticCommentReaction {
  final bool liked;
  final bool disliked;
  final int likes;
  final int dislikes;

  const _OptimisticCommentReaction({
    required this.liked,
    required this.disliked,
    required this.likes,
    required this.dislikes,
  });
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // [Tini - Comment Reactions] - تحديث متفائل للون والعداد، مع إبقاء Firestore مصدراً للحقيقة.
  final Map<String, _OptimisticCommentReaction> _optimisticCommentReactions = {};
  final Set<String> _savingCommentReactions = {};
  final Map<String, bool> _serverLikedReactions = {};
  final Map<String, bool> _serverDislikedReactions = {};
  final Map<String, int> _serverCommentLikes = {};
  final Map<String, int> _serverCommentDislikes = {};
  final Map<String, Timer> _reactionReconcileTimers = {};

  String? _replyingToId;
  String? _replyingToName;
  String? _editingCommentId;
  // [Tini - Full Name Mention]: ربط الاسم الظاهر بمعرّف الحساب الحقيقي.
  final Map<String, String> _linkedCommentMentions = {};
  List<Map<String, dynamic>> _mentionSuggestions = [];
  Timer? _mentionSearchTimer;
  int _mentionSearchVersion = 0;
  int _mentionStart = -1;
  bool _isSending = false;
  bool _canLoadStream = false;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  // تثبيت موضع التعليق المحدد داخل القائمة حتى لو كان بعيداً عن أول الشاشة.
  final GlobalKey _highlightSliverKey = GlobalKey();
  Timer? _highlightTimer;
  bool _highlightVisible = true;
  bool _didScrollToHighlighted = false;

  // Cache للشارات عشان الأداء
  final Map<String, Map<String, dynamic>> _userBadgesCache = {};

  // [Tini - Comment Privacy Logic - NEW]
  String _commentPrivacy = 'comment_everyone';
  bool _privacyLoaded = false;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('ar', timeago.ArMessages());
    _loadCommentPrivacy(); // [NEW]
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _canLoadStream = true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _commentController.dispose();
    _commentFocusNode.dispose();
    _mentionSearchTimer?.cancel();
    _highlightTimer?.cancel();
    for (final timer in _reactionReconcileTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  // [Tini - Owner Reactions Overlay] - لا يبدأ زمن التمييز إلا بعد العثور على التعليق وعرضه.
  void _revealHighlightedComment() {
    if (!mounted || _didScrollToHighlighted || widget.highlightCommentId == null) return;
    final targetContext = _itemKeys[widget.highlightCommentId]?.currentContext;
    if (targetContext == null) return;
    _didScrollToHighlighted = true;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      alignment: 0.2,
    );
    if (widget.highlightTemporarily) {
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _highlightVisible = false);
      });
    }
  }

  // [NEW] دالة جديدة - أضفها بعد dispose مباشرة
  Future<void> _loadCommentPrivacy() async {
    try {
      final doc = await _firestore.collection('posts').doc(widget.postId).get();
      if (doc.exists && mounted) {
        setState(() {
          _commentPrivacy = doc.data()?['commentPrivacy'] ?? 'comment_everyone';
          _privacyLoaded = true;
        });
      } else {
        if (mounted) setState(() => _privacyLoaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _privacyLoaded = true);
    }
  }

  bool _canCurrentUserComment() {
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    if (_commentPrivacy == 'comment_nobody') return false;
    if (_commentPrivacy == 'comment_friends') {
      final isOwner = auth.uid == widget.postOwnerId;
      if (isOwner) return true;
      return auth.isFriendSync(widget.postOwnerId ?? '');
    }
    return true;
  }

    ImageProvider _getAvatar(String path) {
    if (path.isEmpty) return const AssetImage('assets/images/default_avatar.png');
    if (path.startsWith('/') || path.contains('cache') || path.contains('data') || path.startsWith('file://')) {
      final cleanPath = path.replaceFirst('file://', '');
      return FileImage(File(cleanPath));
    }
    return CachedNetworkImageProvider(path, cacheKey: path);
  }

  // جلب شارة المستخدم
  Future<Map<String, dynamic>> _getUserBadge(String uid) async {
    if (_userBadgesCache.containsKey(uid)) return _userBadgesCache[uid]!;

    try {
      final doc = await UserDocuments.readable(_firestore, uid).get();
      if (!doc.exists) return {};

      final data = doc.data()!;
      final badge = data['badge'] as String?;
      final badgeEndsAt = data['badgeEndsAt'] as Timestamp?;

      // شيك إذا الشارة انتهت
      if (badgeEndsAt!= null && badgeEndsAt.toDate().isBefore(DateTime.now())) {
        return {};
      }

      final result = {'badge': badge, 'badgeEndsAt': badgeEndsAt};
      _userBadgesCache[uid] = result;
      return result;
    } catch (e) {
      return {};
    }
  }

  // ويدجت الشارة
  Widget _buildUserBadge(String? badgeType) {
    if (badgeType == null) return const SizedBox.shrink();

    IconData icon;
    Color color;

    switch (badgeType) {
      case 'bronze':
        icon = Icons.workspace_premium;
        color = const Color(0xFFCD7F32);
        break;
      case 'silver':
        icon = Icons.military_tech;
        color = const Color(0xFFE8E8E8);
        break;
      case 'gold':
        icon = Icons.emoji_events;
        color = const Color(0xFFFFD700);
        break;
      case 'diamond':
        icon = Icons.diamond;
        color = const Color(0xFF00D9FF);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(icon, size: 14, color: color),
    );
  }

  // [Tini - Full Name Mention]: الاقتراحات تعمل مع الاسم الظاهر، دون تغيير شاشة الكتابة الأصلية.
  void _onCommentTextChanged(String value) {
    _mentionSearchTimer?.cancel();
    final version = ++_mentionSearchVersion;
    final caret = _commentController.selection.baseOffset;
    if (caret < 0 || caret > value.length) {
      setState(() { _mentionSuggestions = []; _mentionStart = -1; });
      return;
    }
    final beforeCaret = value.substring(0, caret);
    final mention = RegExp(r'(^|[\s(])@([\p{L}\p{N}_. ]{0,48})$', unicode: true)
        .firstMatch(beforeCaret);
    if (mention == null || mention.group(2)!.trim().isEmpty) {
      if (_mentionSuggestions.isNotEmpty || _mentionStart != -1) {
        setState(() { _mentionSuggestions = []; _mentionStart = -1; });
      }
      return;
    }
    final query = mention.group(2)!.trim();
    final start = mention.start + mention.group(1)!.length;
    _mentionSearchTimer = Timer(const Duration(milliseconds: 280), () async {
      try {
        final users = await MentionPrivacyService.searchMentionableUsers(query);
        if (!mounted || version != _mentionSearchVersion) return;
        setState(() {
          _mentionStart = start;
          _mentionSuggestions = BlockService.filterBlockedMaps(
              users, Provider.of<custom.AuthProvider>(context, listen: false).blockedUsersSet)
              .take(6).toList();
        });
      } catch (_) {
        if (mounted && version == _mentionSearchVersion) {
          setState(() { _mentionSuggestions = []; _mentionStart = -1; });
        }
      }
    });
  }

  void _insertSuggestedMention(Map<String, dynamic> user) {
    final uid = (user['uid'] ?? '').toString();
    final fullName = (user['fullName'] ?? '').toString().trim();
    final username = (user['username'] ?? '').toString().trim();
    final name = fullName.isNotEmpty ? fullName : username;
    final selection = _commentController.selection;
    if (uid.isEmpty || name.isEmpty || _mentionStart < 0 || selection.baseOffset < 0) return;
    final text = _commentController.text;
    final from = _mentionStart;
    final to = selection.baseOffset;
    if (from > to || to > text.length || text[from] != '@') return;
    final insertion = '@$name ';
    final updated = text.replaceRange(from, to, insertion);
    _linkedCommentMentions[name.toLowerCase()] = uid;
    _commentController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: from + insertion.length),
    );
    _mentionSearchTimer?.cancel();
    ++_mentionSearchVersion;
    setState(() { _mentionSuggestions = []; _mentionStart = -1; });
    _commentFocusNode.requestFocus();
  }

  void _clearMentionSuggestions() {
    _mentionSearchTimer?.cancel();
    ++_mentionSearchVersion;
    _mentionSuggestions = [];
    _mentionStart = -1;
  }

  // [Tini - Mention Color]: تخزين مواضع الذكر الذي اجتاز فحص الخصوصية فقط.
  Future<List<Map<String, int>>> _confirmedMentionRanges(
      String text, Map<String, String> verifiedMentions) async {
    if (verifiedMentions.isEmpty) return [];
    final labels = <String>{...verifiedMentions.keys};
    final verifiedUids = verifiedMentions.values.toSet();
    for (final entry in _linkedCommentMentions.entries) {
      if (verifiedUids.contains(entry.value)) labels.add(entry.key);
    }
    for (final uid in verifiedUids) {
      try {
        final doc = await UserDocuments.readable(_firestore, uid).get();
        final fullName = (doc.data()?['fullName'] ?? '').toString().trim();
        if (fullName.isNotEmpty) labels.add(fullName);
      } catch (_) { /* لا يؤثر تعذّر جلب الاسم على إرسال التعليق. */ }
    }
    final names = labels.where((name) => name.trim().isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty) return [];
    final pattern = RegExp(
      '@(?:${names.map(RegExp.escape).join('|')})(?![\\p{L}\\p{N}_])',
      caseSensitive: false, unicode: true,
    );
    final precedingCharacter = RegExp(r'[\p{L}\p{N}_@]', unicode: true);
    final ranges = <Map<String, int>>[];
    for (final match in pattern.allMatches(text)) {
      if (match.start > 0 &&
          precedingCharacter.hasMatch(text.substring(match.start - 1, match.start))) {
        continue;
      }
      ranges.add({'start': match.start, 'end': match.end});
    }
    return ranges;
  }

  // [Tini - Mention Color]: النص يبقى بلونه الأصلي؛ الذكر المؤكد فقط بلون Tini.
  List<TextSpan> _commentMentionSpans(String text, dynamic savedRanges) {
    if (savedRanges is! List || savedRanges.isEmpty) return [TextSpan(text: text)];
    final ranges = savedRanges.whereType<Map>().toList()
      ..sort((a, b) => ((a['start'] as int?) ?? 0).compareTo((b['start'] as int?) ?? 0));
    final spans = <TextSpan>[];
    var last = 0;
    for (final range in ranges) {
      final start = range['start'];
      final end = range['end'];
      if (start is! int || end is! int || start < last || end <= start ||
          end > text.length || !text.startsWith('@', start)) continue;
      if (start > last) spans.add(TextSpan(text: text.substring(last, start)));
      spans.add(TextSpan(text: text.substring(start, end),
          style: const TextStyle(color: Colors.teal)));
      last = end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  Future<void> _logActivity(String toUid, String type, String text, String uniqueId, {String? commentId, String? replyToCommentId}) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid?? "";
    if (currentUid.isEmpty || currentUid == toUid) return;
    try {
      final userDoc = await UserDocuments.readable(_firestore, currentUid).get();
      final userName = userDoc.data()?['fullName']?? userDoc.data()?['username']?? 'مستخدم';
      final docId = '${widget.postId}_${uniqueId}_${toUid}_$type';
      await _firestore.collection('activities').doc(docId).set({
        'toUid': toUid,
        'fromUid': currentUid,
        'type': type,
        'text': '$userName $text',
        'postId': widget.postId,
        'commentId': commentId,
        'replyToCommentId': replyToCommentId,
        'timestamp': FieldValue.serverTimestamp(),
        'seen': false,
      }, SetOptions(merge: true));
    } catch (e) {}
  }

  void _sendComment() async {
    // [Tini Safety - NEW]
    if (!_canCurrentUserComment()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_commentPrivacy == 'comment_nobody' ? "التعليقات معطلة" : "التعليقات للأصدقاء فقط"),
          backgroundColor: Colors.teal,
        ),
      );
      return;
    }

    final String commentText = _commentController.text.trim();
    if (commentText.isEmpty || _isSending) return;

    // [Tini - Mention Privacy]: ينطبق على التعليقات وعلى تعديلها أيضاً.
    late final Map<String, String> validCommentMentions;
    try {
      validCommentMentions = await MentionPrivacyService.validateMentions(
        text: commentText, linkedUserIds: _linkedCommentMentions);
    } on MentionNotAllowedException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()), backgroundColor: const Color(0xFFE53935)));
      return;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذّر التحقق من خصوصية الذكر. حاول مجدداً.'),
        backgroundColor: Color(0xFFE53935)));
      return;
    }

    // [Titi Moderation - NEW] فحص التعليق قبل النشر
    bool commentOk = await ModerationService.checkText(commentText);
    if (!commentOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("التعليق يحتوي محتوى غير مسموح"), backgroundColor: Color(0xFFE53935)),
      );
      return;
    }

    setState(() { _isSending = true; });

    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    String targetPostId = widget.postId?? 'default_post';

    try {
      // [Tini - Mention Color]: تجهيز مواضع الذكر المؤكَّد دون تغيير نص التعليق.
      final mentionRanges = await _confirmedMentionRanges(commentText, validCommentMentions);
      // جيب شارة المستخدم الحالي
      final userDoc = await UserDocuments.readable(_firestore, auth.uid).get();
      final userBadge = userDoc.data()?['badge'];
      final userBadgeEndsAt = userDoc.data()?['badgeEndsAt'];

      if (_editingCommentId!= null) {
        await _firestore.collection('posts').doc(targetPostId).collection('comments').doc(_editingCommentId).update({
          'text': commentText,
          'mentionRanges': mentionRanges,
          'isEdited': true,
          'lastEditTimestamp': FieldValue.serverTimestamp(),
          'badge': userBadge,
          'badgeEndsAt': userBadgeEndsAt,
        });

        _commentController.clear();
        _linkedCommentMentions.clear();
        _clearMentionSuggestions();
        setState(() {
          _editingCommentId = null;
          _isSending = false;
        });
        if (_commentFocusNode.hasFocus) _commentFocusNode.unfocus();

      } else {
        String? parentId = _replyingToId;

        WriteBatch batch = _firestore.batch();
        DocumentReference commentRef = _firestore.collection('posts').doc(targetPostId).collection('comments').doc();
        DocumentReference postRef = _firestore.collection('posts').doc(targetPostId);

        batch.set(commentRef, {
          'uid': auth.uid,
          'userName': auth.fullName,
          'userImage': auth.profileImg,
          'text': commentText,
          'mentionRanges': mentionRanges,
          'timestamp': FieldValue.serverTimestamp(),
          'likes': 0,
          'dislikes': 0,
          'parentId': parentId,
          'badge': userBadge,
          'badgeEndsAt': userBadgeEndsAt,
        });

        batch.update(postRef, {
          'comments': FieldValue.increment(1),
        });

        await batch.commit();
        // [Titi Hashtag Interest - COMMENT +2]
final postSnap = await _firestore.collection('posts').doc(targetPostId).get();
final List<String> postHashtags = List<String>.from((postSnap.data()?['hashtags'] ?? []));
for (String tag in postHashtags) {
  String cleanTag = tag.toLowerCase().trim();
  if (cleanTag.isEmpty) continue;
  await _firestore.collection('users').doc(auth.uid).collection('hashtagInterests').doc(cleanTag).set({
    'name': cleanTag,
    'count': FieldValue.increment(2),
    'lastLiked': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

        final commentId = commentRef.id;
        // [Tini - Mention Privacy]: نشاط الذكر للأسماء الصحيحة والمسموح بها فقط.
        for (final mentionedUid in validCommentMentions.values.toSet()) {
          if (mentionedUid == auth.uid) continue;
          try {
            if (await MentionPrivacyService.canMentionUser(
                targetUid: mentionedUid, senderUid: auth.uid)) {
              await _logActivity(mentionedUid, 'mention',
                  'ذكرك في تعليق', commentId, commentId: commentId);
            }
          } catch (_) { /* لا ينشأ إشعار ذكر عند فشل فحص الخصوصية. */ }
        }
        if (widget.postOwnerId!= null && widget.postOwnerId!.isNotEmpty && widget.postOwnerId!= auth.uid) {
          await _logActivity(widget.postOwnerId!, 'comment', 'علّق على منشورك', commentId, commentId: commentId);
        }

        if (parentId!= null) {
          final parentDoc = await _firestore.collection('posts').doc(targetPostId).collection('comments').doc(parentId).get();
          final parentOwnerId = parentDoc.data()?['uid'];
          if (parentOwnerId!= null && parentOwnerId!= auth.uid) {
            await _logActivity(parentOwnerId, 'reply', 'رد على تعليقك', commentId, commentId: commentId, replyToCommentId: parentId);
          }
        }

        _commentController.clear();
        _linkedCommentMentions.clear();
        _clearMentionSuggestions();
        if (_commentFocusNode.hasFocus) _commentFocusNode.unfocus();

        setState(() {
          _replyingToId = null;
          _replyingToName = null;
          _isSending = false;
        });
      }
    } catch (e) {
      debugPrint("Titi Error: فشل الإرسال الفعلي - $e");
      setState(() { _isSending = false; });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("حدث خطأ أثناء الإرسال، حاول مجدداً"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCommentOptions(String commentId, String commentUid, String text, String userName) {
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    bool isMyComment = commentUid == auth.uid;
    bool isPostOwner = widget.postOwnerId == auth.uid;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A222C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Iconsax.copy, color: Colors.white),
                title: const Text("نسخ التعليق", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                },
              ),
              if (isMyComment)
                ListTile(
                  leading: const Icon(Iconsax.edit, color: Colors.teal),
                  title: const Text("تعديل تعليقي", style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _editingCommentId = commentId;
                      _linkedCommentMentions.clear();
                      _clearMentionSuggestions();
                      _commentController.text = text;
                    });
                    _commentFocusNode.requestFocus();
                  },
                ),
              if (isMyComment || isPostOwner)
                ListTile(
                  leading: const Icon(Iconsax.trash, color: Color(0xFFE53935)),
                  title: Text(isPostOwner &&!isMyComment? "حذف تعليق المستخدم" : "حذف تعليقي", style: const TextStyle(color: Color(0xFFE53935))),
                  onTap: () async {
                    Navigator.pop(context);
                    WriteBatch batch = _firestore.batch();
                    DocumentReference commentRef = _firestore.collection('posts').doc(widget.postId?? 'default_post').collection('comments').doc(commentId);
                    DocumentReference postRef = _firestore.collection('posts').doc(widget.postId?? 'default_post');

                    batch.delete(commentRef);
                    batch.update(postRef, {
                      'comments': FieldValue.increment(-1),
                    });

                    await batch.commit();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _replyToUser(String userName, String commentId, String commentUid) async {
    // الرد نفسه مسموح، حتى لو كان صاحب التعليق لا يسمح بالذكر.
    // فقط إضافة @الاسم مرتبطة بإذن الذكر، وبـ UID وليس fullName.
    setState(() {
      _replyingToId = commentId;
      _replyingToName = userName;
      _editingCommentId = null;
      _linkedCommentMentions.clear();
      _clearMentionSuggestions();
      _commentController.clear();
    });
    _commentFocusNode.requestFocus();

    bool mayMention = false;
    try {
      mayMention = await MentionPrivacyService.canMentionUser(targetUid: commentUid);
    } catch (_) { /* تعذّر التحقق: لا نضيف منشن، لكن الرد يبقى متاحاً. */ }
    if (!mounted || _replyingToId != commentId || _editingCommentId != null) return;
    if (!mayMention || userName.trim().isEmpty) return;

    // احتفظ بأي كلام بدأ المستخدم بكتابته أثناء انتظار التحقق.
    final previousText = _commentController.text;
    final mention = '@$userName ';
    _linkedCommentMentions[userName.toLowerCase().trim()] = commentUid;
    _clearMentionSuggestions();
    _commentController.value = TextEditingValue(
      text: '$mention$previousText',
      selection: TextSelection.collapsed(offset: mention.length + previousText.length),
    );
    _commentFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCommentsLayout(
      composerBuilder: (context, maxHeight) => _buildInputArea(maxHeight),
      comments: !_canLoadStream
        ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : StreamBuilder<QuerySnapshot>(
                    stream: _firestore
               .collection('posts')
               .doc(widget.postId?? 'default_post')
               .collection('comments')
               .orderBy('timestamp', descending: true)
               .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: Colors.teal));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text("لا توجد تعليقات بعد، كن أول من يعلق!", style: TextStyle(color: Colors.grey)));
                      }

                      final allDocs = snapshot.data!.docs;
                      final mainComments = allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return data['parentId'] == null;
                      }).toList();

                      if (mainComments.isEmpty) {
                        return const Center(child: Text("لا توجد تعليقات بعد، كن أول من يعلق!", style: TextStyle(color: Colors.grey)));
                      }

                      if (widget.highlightCommentId != null && !_didScrollToHighlighted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => _revealHighlightedComment());
                      }

                      // التعليق قد يكون رداً؛ نثبت القائمة عند التعليق الأب ونفتح الردود تلقائياً.
                      var highlightedMainIndex = -1;
                      if (widget.highlightCommentId != null) {
                        for (final doc in allDocs) {
                          if (doc.id != widget.highlightCommentId) continue;
                          final targetData = doc.data() as Map<String, dynamic>;
                          final parentId = targetData['parentId']?.toString();
                          final mainId = parentId != null && parentId.isNotEmpty ? parentId : doc.id;
                          highlightedMainIndex = mainComments.indexWhere((main) => main.id == mainId);
                          break;
                        }
                      }

                      Widget buildMainComment(int index) {
                        final doc = mainComments[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final timeStr = data['timestamp'] != null
                            ? timeago.format((data['timestamp'] as Timestamp).toDate(), locale: 'ar')
                            : "الآن";
                        final itemKey = _itemKeys.putIfAbsent(doc.id, () => GlobalKey());
                        final isHighlighted = widget.highlightCommentId == doc.id && _highlightVisible;
                        return KeyedSubtree(
                          key: itemKey,
                          child: _buildCommentItem(
                            doc.id,
                            data['userName'] ?? 'مستخدم',
                            data['text'] ?? '',
                            data['userImage'] ?? '',
                            data['likes'] ?? 0,
                            data['dislikes'] ?? 0,
                            data['uid'] ?? '',
                            timeStr,
                            isReply: false,
                            isHighlighted: isHighlighted,
                            badge: data['badge'],
                            badgeEndsAt: data['badgeEndsAt'],
                            mentionRanges: data['mentionRanges'],
                          ),
                        );
                      }

                      // CustomScrollView.center يبدأ من التعليق المستهدف مباشرة،
                      // ويُبقي باقي التعليقات قابلة للتمرير صعوداً ونزولاً مع البناء الكسول.
                      if (widget.highlightTemporarily && highlightedMainIndex > 0) {
                        return CustomScrollView(
                          controller: _scrollController,
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          center: _highlightSliverKey,
                          anchor: 0.2,
                          slivers: [
                            SliverList.builder(
                              itemCount: highlightedMainIndex,
                              itemBuilder: (context, index) =>
                                  buildMainComment(highlightedMainIndex - 1 - index),
                            ),
                            SliverList.builder(
                              key: _highlightSliverKey,
                              itemCount: mainComments.length - highlightedMainIndex,
                              itemBuilder: (context, index) =>
                                  buildMainComment(highlightedMainIndex + index),
                            ),
                          ],
                        );
                      }
                      return ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: mainComments.length,
                        itemBuilder: (context, index) => buildMainComment(index),
                      );
                    },
                  ),
    );
  }

  Widget _buildCommentItem(String commentId, String name, String text, String userImg, dynamic likes, dynamic dislikes, String commentUid, String timeStr, {bool isReply = false, bool isHighlighted = false, String? badge, Timestamp? badgeEndsAt, dynamic mentionRanges}) {
    final auth = Provider.of<custom.AuthProvider>(context);
    bool isActuallyMe = commentUid == auth.uid;
    // عدادات السيرفر تبقى محفوظة حتى نزيل العرض المتفائل بعد وصول تحديث Firestore.
    final serverLikes = _commentReactionCount(likes);
    final serverDislikes = _commentReactionCount(dislikes);
    _serverCommentLikes[commentId] = serverLikes;
    _serverCommentDislikes[commentId] = serverDislikes;

    String finalName = isActuallyMe? auth.fullName : name;
    String finalImg = isActuallyMe? auth.profileImg : userImg;

    return Container(
      color: isHighlighted? const Color(0xFF009688).withValues(alpha: 0.22) : Colors.transparent,
      child: Column(
        children: [
          GestureDetector(
            onLongPress: () => _showCommentOptions(commentId, commentUid, text, finalName),
            child: Padding(
              padding: EdgeInsets.only(left: isReply? 40 : 12, right: 12, top: 8, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('stories').doc(commentUid).collection('items').where('expiresAt', isGreaterThan: Timestamp.now()).snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs?? [];
                      final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
                      final hasStories = docs.isNotEmpty;
                      final hasUnviewed = docs.any((d) {
                        final viewedBy = List<String>.from(d['viewedBy']?? []);
                        return!viewedBy.contains(currentUid);
                      });
                      final bool hasImage = finalImg.isNotEmpty;
                      final String initial = finalName.isNotEmpty? finalName[0].toUpperCase() : '?';
                      final double avatarSize = isReply? 28 : 36;

                      if (hasStories) {
                        return StoryRing(
                          imageUrl: finalImg,
                          size: avatarSize,
                          hasStories: true,
                          hasUnviewed: hasUnviewed,
                          heroTag: 'comment-$commentId',
                        );
                      } else if (hasImage) {
                        return CircleAvatar(
                          radius: isReply? 14 : 18,
                          backgroundColor: const Color(0xFF1A222C),
                          backgroundImage: _getAvatar(finalImg),
                        );
                      } else {
                        return CircleAvatar(
                          radius: isReply? 14 : 18,
                          backgroundColor: const Color(0xFF1A222C),
                          child: Text(initial, style: TextStyle(color: Colors.white, fontSize: isReply? 12 : 14, fontWeight: FontWeight.bold)),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // عرض الشارة جنب الاسم
                            Flexible(child: FutureBuilder<Map<String, dynamic>>(
                              future: _getUserBadge(commentUid),
                              builder: (context, snapshot) {
                                final badge = snapshot.data?['badge'];
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildUserBadge(badge),
                                    Flexible(child: Text(finalName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.bold))),
                                    EarnedThroneBadge(uid: commentUid),
                                  ],
                                );
                              },
                            )),
                            const SizedBox(width: 8),
                            Text(timeStr, style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(children: _commentMentionSpans(text, mentionRanges)),
                          style: TextStyle(
                            color: getBadgeCommentColorFromTimestamp(badge, badgeEndsAt),
                            fontSize: 14,
                            fontWeight: badge!= null? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            StreamBuilder<DocumentSnapshot>(
                              stream: _firestore.collection('posts').doc(widget.postId?? 'default_post').collection('comments').doc(commentId).collection('likedBy').doc(auth.uid).snapshots(),
                              builder: (context, likeSnap) {
                                if (likeSnap.hasData) {
                                  _serverLikedReactions[commentId] = likeSnap.data!.exists;
                                }
                                final preview = _optimisticCommentReactions[commentId];
                                final isLiked = preview?.liked ?? (_serverLikedReactions[commentId] ?? false);
                                return _InteractionButton(
                                  icon: Iconsax.heart5,
                                  activeColor: Colors.teal,
                                  count: (preview?.likes ?? serverLikes).toString(),
                                  size: isReply? 14 : 18,
                                  isSelected: isLiked,
                                  onTap: () => _toggleCommentReaction(commentId, 'likes', serverLikes, serverDislikes),
                                );
                              },
                            ),
                            const SizedBox(width: 15),
                            StreamBuilder<DocumentSnapshot>(
                              stream: _firestore.collection('posts').doc(widget.postId?? 'default_post').collection('comments').doc(commentId).collection('dislikedBy').doc(auth.uid).snapshots(),
                              builder: (context, dislikeSnap) {
                                if (dislikeSnap.hasData) {
                                  _serverDislikedReactions[commentId] = dislikeSnap.data!.exists;
                                }
                                final preview = _optimisticCommentReactions[commentId];
                                final isDisliked = preview?.disliked ?? (_serverDislikedReactions[commentId] ?? false);
                                return _InteractionButton(
                                  icon: Iconsax.dislike5,
                                  activeColor: const Color(0xFFFF3B30),
                                  count: (preview?.dislikes ?? serverDislikes).toString(),
                                  size: isReply? 14 : 18,
                                  isSelected: isDisliked,
                                  onTap: () => _toggleCommentReaction(commentId, 'dislikes', serverLikes, serverDislikes),
                                );
                              },
                            ),
                            const SizedBox(width: 20),
                            GestureDetector(
                              onTap: () => _replyToUser(finalName, commentId, commentUid),
                              child: const Text("رد", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildRepliesList(commentId),
        ],
      ),
    );
  }

  int _commentReactionCount(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // [Tini - Comment Reactions] - لا نحذف الحالة السريعة قبل وصول اللون والعدد النهائيين من Firestore.
  void _reconcileCommentReaction(String commentId, _OptimisticCommentReaction preview) {
    _reactionReconcileTimers.remove(commentId)?.cancel();
    _reactionReconcileTimers[commentId] = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted || !identical(_optimisticCommentReactions[commentId], preview)) {
        timer.cancel();
        _reactionReconcileTimers.remove(commentId);
        return;
      }
      if (_savingCommentReactions.contains(commentId)) return;
      final isSynced = _serverLikedReactions[commentId] == preview.liked &&
          _serverDislikedReactions[commentId] == preview.disliked &&
          _serverCommentLikes[commentId] == preview.likes &&
          _serverCommentDislikes[commentId] == preview.dislikes;
      // مهلة احتياطية إذا تغيّر العدد بفعل مستخدم آخر أثناء الحفظ.
      if (isSynced || timer.tick >= 40) {
        timer.cancel();
        _reactionReconcileTimers.remove(commentId);
        setState(() => _optimisticCommentReactions.remove(commentId));
      }
    });
  }

  Future<void> _toggleCommentReaction(String commentId, String type, int likes, int dislikes) async {
    // نقفل هذا التعليق فقط أثناء الكتابة، حتى لا تتكرر المعاملة بسبب النقر السريع.
    if (_savingCommentReactions.contains(commentId)) return;
    final myId = Provider.of<custom.AuthProvider>(context, listen: false).uid;
    if (myId.isEmpty) return;
    final previous = _optimisticCommentReactions[commentId];
    final wasLiked = previous?.liked ?? (_serverLikedReactions[commentId] ?? false);
    final wasDisliked = previous?.disliked ?? (_serverDislikedReactions[commentId] ?? false);
    final shownLikes = previous?.likes ?? likes;
    final shownDislikes = previous?.dislikes ?? dislikes;

    final nextLiked = type == 'likes' && !wasLiked;
    final nextDisliked = type == 'dislikes' && !wasDisliked;
    final preview = _OptimisticCommentReaction(
      liked: nextLiked,
      disliked: nextDisliked,
      likes: (shownLikes + (nextLiked ? 1 : 0) - (wasLiked ? 1 : 0)).clamp(0, 1 << 31).toInt(),
      dislikes: (shownDislikes + (nextDisliked ? 1 : 0) - (wasDisliked ? 1 : 0)).clamp(0, 1 << 31).toInt(),
    );
    _reactionReconcileTimers.remove(commentId)?.cancel();
    _savingCommentReactions.add(commentId);
    // اللون والعدد يتغيران فور الضغط، بدون انتظار الشبكة.
    setState(() => _optimisticCommentReactions[commentId] = preview);

    final String targetPostId = widget.postId?? 'default_post';
    DocumentReference commentRef = _firestore.collection('posts').doc(targetPostId).collection('comments').doc(commentId);
    DocumentReference likedRef = commentRef.collection('likedBy').doc(myId);
    DocumentReference dislikedRef = commentRef.collection('dislikedBy').doc(myId);

    String? commentOwnerId;
    bool shouldNotify = false;
    try {
      final didUpdate = await _firestore.runTransaction<bool>((transaction) async {
        // قد يعيد Firestore المحاولة، لذلك نعيد تهيئة قرار الإشعار في كل محاولة.
        commentOwnerId = null;
        shouldNotify = false;
        DocumentSnapshot commentSnap = await transaction.get(commentRef);
        if (!commentSnap.exists) return false;

        Map<String, dynamic> data = commentSnap.data() as Map<String, dynamic>;
        DocumentSnapshot likedSnap = await transaction.get(likedRef);
        DocumentSnapshot dislikedSnap = await transaction.get(dislikedRef);

        bool isLiked = likedSnap.exists;
        bool isDisliked = dislikedSnap.exists;
        bool wasLiked = isLiked;

        if (type == 'likes') {
          if (isLiked) {
            transaction.delete(likedRef);
            transaction.update(commentRef, {'likes': FieldValue.increment(-1)});
          } else {
            transaction.set(likedRef, {'timestamp': FieldValue.serverTimestamp()});
            transaction.update(commentRef, {'likes': FieldValue.increment(1)});
            if (isDisliked) {
              transaction.delete(dislikedRef);
              transaction.update(commentRef, {'dislikes': FieldValue.increment(-1)});
            }
            if (!wasLiked) {
              commentOwnerId = data['uid'];
              shouldNotify = commentOwnerId!= myId;
            }
          }
        } else {
          if (isDisliked) {
            transaction.delete(dislikedRef);
            transaction.update(commentRef, {'dislikes': FieldValue.increment(-1)});
          } else {
            transaction.set(dislikedRef, {'timestamp': FieldValue.serverTimestamp()});
            transaction.update(commentRef, {'dislikes': FieldValue.increment(1)});
            if (isLiked) {
              transaction.delete(likedRef);
              transaction.update(commentRef, {'likes': FieldValue.increment(-1)});
            }
          }
        }
        return true;
      });
      if (!didUpdate) throw StateError('Comment no longer exists');
      _savingCommentReactions.remove(commentId);
      if (mounted) _reconcileCommentReaction(commentId, preview);

      // يبقى إشعار إعجاب التعليق بعد نجاح الحفظ فقط، مثل السلوك الأصلي.
      if (shouldNotify && commentOwnerId!= null) {
        await _logActivity(commentOwnerId!, 'comment_like', 'أعجب بتعليقك', commentId, commentId: commentId);
      }
    } catch (error) {
      _savingCommentReactions.remove(commentId);
      _reactionReconcileTimers.remove(commentId)?.cancel();
      if (mounted) {
        setState(() => _optimisticCommentReactions.remove(commentId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر حفظ التفاعل، حاول مجدداً'), backgroundColor: Color(0xFFE53935)),
        );
      }
      debugPrint('[Tini Comment Reactions] Save failed: $error');
    }
  }

    Widget _buildRepliesList(String parentId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('posts').doc(widget.postId?? 'default_post').collection('comments').orderBy('timestamp', descending: false).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final replies = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['parentId'] == parentId;
        }).toList();

        if (replies.isEmpty) return const SizedBox.shrink();

        final bool containsHighlighted = replies.any((d) => d.id == widget.highlightCommentId);

        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: containsHighlighted,
            title: Padding(padding: const EdgeInsets.only(left: 40), child: Text("عرض ${replies.length} ردود", style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
            iconColor: Colors.grey, collapsedIconColor: Colors.grey,
            children: replies.map((doc) {
              var data = doc.data() as Map<String, dynamic>;
              String timeStr = data['timestamp']!= null? timeago.format((data['timestamp'] as Timestamp).toDate(), locale: 'ar') : "الآن";
              final itemKey = _itemKeys.putIfAbsent(doc.id, () => GlobalKey());
              final isHighlighted = widget.highlightCommentId == doc.id && _highlightVisible;
              if (isHighlighted && !_didScrollToHighlighted) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _revealHighlightedComment());
              }
              return KeyedSubtree(
                key: itemKey,
                child: _buildCommentItem(
                  doc.id,
                  data['userName']?? 'مستخدم',
                  data['text']?? '',
                  data['userImage']?? '',
                  data['likes']?? 0,
                  data['dislikes']?? 0,
                  data['uid']?? '',
                  timeStr,
                  isReply: true,
                  isHighlighted: isHighlighted,
                  badge: data['badge'],
                  badgeEndsAt: data['badgeEndsAt'],
                  mentionRanges: data['mentionRanges'],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildInputArea(double maxHeight) {
    final auth = Provider.of<custom.AuthProvider>(context);
    
    // [NEW] اذا التعليقات مغلقة اعرض رسالة بدل حقل الكتابة
    if (_privacyLoaded && !_canCurrentUserComment()) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: const BoxDecoration(color: Color(0xFF1A222C), border: Border(top: BorderSide(color: Colors.white12))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_commentPrivacy == 'comment_nobody' ? Icons.block : Icons.people_outline, color: Colors.white38, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
              _commentPrivacy == 'comment_nobody' ? "التعليقات معطلة من صاحب المنشور" : "التعليقات للأصدقاء فقط - يجب أن تتابعوا بعضكم",
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            )),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_mentionSuggestions.isNotEmpty)
          Container(
            constraints: BoxConstraints(maxHeight: math.min(190, maxHeight * 0.35)),
            color: const Color(0xFF1A222C),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _mentionSuggestions.length,
              itemBuilder: (context, index) {
                final user = _mentionSuggestions[index];
                final fullName = (user['fullName'] ?? '').toString();
                final username = (user['username'] ?? '').toString();
                return ListTile(
                  dense: true,
                  title: Text(fullName.isNotEmpty ? fullName : username,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('@$username',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () => _insertSuggestedMention(user),
                );
              },
            ),
          ),
        if (_replyingToName!= null || _editingCommentId!= null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            color: Colors.black26,
            child: Row(
              children: [
                Expanded(child: Text(_editingCommentId!= null? "تعديل تعليقك..." : "الرد على $_replyingToName", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12))),
                GestureDetector(
                  onTap: () => setState(() { _replyingToId = null; _replyingToName = null; _editingCommentId = null; _linkedCommentMentions.clear(); _clearMentionSuggestions(); _commentController.clear(); }),
                  child: const Icon(Icons.close, color: Colors.grey, size: 16),
                )
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(color: Color(0xFF1A222C), border: Border(top: BorderSide(color: Colors.white12))),
          child: Row(
            children: [
              CircleAvatar(radius: 18, backgroundColor: Colors.grey, backgroundImage: _getAvatar(auth.profileImg)),
              const SizedBox(width: 10),
              Expanded(
                child: ResponsiveCommentField(
                  controller: _commentController,
                  focusNode: _commentFocusNode,
                  maxHeight: math.max(48, maxHeight - 20),
                  onChanged: _onCommentTextChanged,
                ),
              ),
              _isSending
       ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Iconsax.send_1, color: Colors.teal),
                    onPressed: _sendComment,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InteractionButton extends StatefulWidget {
  final IconData icon; final Color activeColor; final String count; final double? size;
  final bool isSelected; final VoidCallback onTap;
  const _InteractionButton({required this.icon, required this.activeColor, required this.count, this.size = 18, required this.isSelected, required this.onTap});
  @override __InteractionButtonState createState() => __InteractionButtonState();
}

class __InteractionButtonState extends State<_InteractionButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller; late Animation<double> _scaleAnimation;
  @override void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(_controller);
  }

  void _handlePress() {
    widget.onTap();
    if (!widget.isSelected) { _controller.forward().then((_) => _controller.reverse()); }
  }

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handlePress,
      child: Row(children: [
        ScaleTransition(scale: _scaleAnimation, child: Icon(widget.icon, color: widget.isSelected? widget.activeColor : Colors.grey, size: widget.size)),
        const SizedBox(width: 4),
        Text(widget.count, style: const TextStyle(color: Colors.grey, fontSize: 11))
      ]),
    );
  }
  @override void dispose() { _controller.dispose(); super.dispose(); }
}