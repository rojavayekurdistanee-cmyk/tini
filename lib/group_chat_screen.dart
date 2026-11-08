import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'group_chat_provider.dart';
import 'chat_album_widgets.dart';
import 'group_message_model.dart';
import 'group_info_screen.dart';
import 'group_theme_sheet.dart';
import 'r2_service.dart';
import 'tini_chat_attachments.dart';
import 'tini_chat_message_pager.dart';
import 'tini_chat_video_thumbnail.dart';
import 'media_picker_screen.dart';
import 'video_processor.dart';
import 'voice_message_bubble.dart';
import 'titi_input_bar.dart';
import 'chat_camera_screen.dart';
import 'multi_media_preview_screen.dart';
import 'preview_media_item.dart';
import 'video_note_bubble.dart';
import 'view_once_icon.dart';
import 'view_once_viewer_screen.dart';

const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kFieldFill = Color(0xFF1C1C1E);
const Color kTitiTeal = Colors.teal;
const Color kErrorRed = Color(0xFFE53935);
const Color kHighlight = Color(0xFFFF3B30);

// شرح الوسائط في الدردشة الجماعية: سطر واحد افتراضياً، دون توسيع الفقاعة.
class _GroupCompactMediaCaption extends StatefulWidget {
  final String caption;
  const _GroupCompactMediaCaption({super.key, required this.caption});

  @override
  State<_GroupCompactMediaCaption> createState() => _GroupCompactMediaCaptionState();
}

class _GroupCompactMediaCaptionState extends State<_GroupCompactMediaCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final caption = widget.caption.trim();
    if (caption.isEmpty) return const SizedBox.shrink();
    final isLong = caption.length > 25 || caption.contains('\n');
    const style = TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 14);
    if (_expanded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(caption, style: style, textAlign: TextAlign.right, textDirection: TextDirection.rtl),
          GestureDetector(
            onTap: () => setState(() => _expanded = false),
            child: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('أقل', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.max,
      textDirection: TextDirection.rtl,
      children: [
        Expanded(child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: style, textAlign: TextAlign.right, textDirection: TextDirection.rtl)),
        if (isLong) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _expanded = true),
            child: const Text('المزيد', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }
}

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  const GroupChatScreen({super.key, required this.groupId});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _PendingUpload {
  final String id;
  final String localPath;
  final String type;
  final String? fileName;
  bool failed;
  _PendingUpload({required this.id, required this.localPath, required this.type, this.fileName, this.failed = false});
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  TiniChatMessagePager? _messagePager;
  // ارتفاع شريط الكتابة (بما فيه لوحة الإيموجي) لحجز مساحة الرسائل فوقه.
  final GlobalKey _composerKey = GlobalKey();
  double _composerHeight = 85;

  void _updateComposerHeight() {
    if (!mounted) return;
    final render = _composerKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final height = render.size.height;
    if ((height - _composerHeight).abs() > 0.5) {
      setState(() => _composerHeight = height);
    }
  }

  GroupMessageModel? _replyTo;
  String _cameraGroupName = '';
  String? _cachedThemeId;
  String? _cachedFontId;
  final List<_PendingUpload> _pendingUploads = [];
  final ValueNotifier<int> _pendingUploadsRevision = ValueNotifier<int>(0);
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _groupStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _themeStream;
  // الرسائل التي عالجنا وصولها أثناء فتح المجموعة، لتجنب إعادة طلب القراءة.
  final Set<String> _handledOpenChatReads = <String>{};

  bool _pickingGroupDocument = false;
  final Set<String> _uploadingGroupDocuments = <String>{};

// --- بداية الإصلاح للتعليق ---
  final Map<String, List<String>> _memberPhotosCache = {};
  final Map<String, Future<List<String>>> _memberPhotosFutureCache = {};
  final Map<String, String> _userPhotoCache = {};
  final Map<String, Future<String>> _userPhotoFutureCache = {};

  Future<String> _getUserPhotoCached(String uid) {
    if (_userPhotoCache.containsKey(uid)) {
      return Future.value(_userPhotoCache[uid]!);
    }
    if (_userPhotoFutureCache.containsKey(uid)) {
      return _userPhotoFutureCache[uid]!;
    }
    final future = FirebaseFirestore.instance.collection('users').doc(uid).get().then((snap) {
      String photo = '';
      if (snap.exists) {
        final data = snap.data();
        photo = (data?['profileImg'] ?? data?['photoUrl'] ?? '') as String;
      }
      _userPhotoCache[uid] = photo;
      _userPhotoFutureCache.remove(uid);
      return photo;
    }).catchError((_) {
      _userPhotoFutureCache.remove(uid);
      return '';
    });
    _userPhotoFutureCache[uid] = future;
    return future;
  }

  Future<List<String>> _getMemberPhotosCached(List<String> memberIds) {
    if (memberIds.isEmpty) return Future.value([]);
    final ids = memberIds.length > 10? memberIds.sublist(memberIds.length - 10) : memberIds;
    // نفس الـ key يعني نفس الأعضاء، لا تعيد الطلب
    final key = ids.join(',');
    if (_memberPhotosCache.containsKey(key)) {
      return Future.value(_memberPhotosCache[key]!);
    }
    if (_memberPhotosFutureCache.containsKey(key)) {
      return _memberPhotosFutureCache[key]!;
    }
    final future = _getMemberPhotos(memberIds).then((photos) {
      _memberPhotosCache[key] = photos;
      _memberPhotosFutureCache.remove(key);
      return photos;
    }).catchError((_) {
      _memberPhotosFutureCache.remove(key);
      return <String>[];
    });
    _memberPhotosFutureCache[key] = future;
    return future;
  }
  // --- نهاية الإصلاح ---


  // Limit original media before native decoding/compression to avoid OOM.
  static const int _maxChatImageBytes = 25 * 1024 * 1024;
  static const int _maxChatVideoBytes = 250 * 1024 * 1024;

  Future<void> _validateChatMediaSize(File file, bool isVideo) async {
    final bytes = await file.length();
    final maxBytes = isVideo ? _maxChatVideoBytes : _maxChatImageBytes;
    if (bytes <= 0 || bytes > maxBytes) {
      throw StateError(isVideo
          ? 'حجم الفيديو غير صالح أو يتجاوز 250 MB.'
          : 'حجم الصورة غير صالح أو يتجاوز 25 MB.');
    }
  }

  void _notifyMediaUploadError(Object error) {
    if (!mounted) return;
    final message = error.toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message.contains('250 MB') || message.contains('25 MB')
          ? message.replaceFirst('Bad state: ', '')
          : 'تعذر إرسال الوسائط. حاول مجددًا.'),
      backgroundColor: const Color(0xFFE53935),
    ));
  }

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _groupStream = FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).snapshots();
    _themeStream = FirebaseFirestore.instance.collection('users').doc(uid)
        .collection('groupThemes').doc(widget.groupId).snapshots();
    _messagePager = TiniChatMessagePager(
      query: FirebaseFirestore.instance
          .collection('group_chats')
          .doc(widget.groupId)
          .collection('messages')
          .orderBy('timestamp', descending: true),
    )..start();
    _scrollController.addListener(_loadOlderOnScroll);
    context.read<GroupChatProvider>().markAsDelivered(widget.groupId, uid);
    context.read<GroupChatProvider>().markAsRead(widget.groupId, uid);
    _loadCachedTheme();
  }

  void _loadOlderOnScroll() {
    final pager = _messagePager;
    if (pager == null || !_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 300) {
      pager.loadOlder();
    }
  }

  Future<void> _loadCachedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cachedThemeId = prefs.getString('theme_${widget.groupId}');
      _cachedFontId = prefs.getString('font_${widget.groupId}');
    });
  }

  Future<void> _cacheTheme(String? themeId, String? fontId) async {
    final prefs = await SharedPreferences.getInstance();
    if (themeId!= null && themeId.isNotEmpty) {
      await prefs.setString('theme_${widget.groupId}', themeId);
    } else {
      await prefs.remove('theme_${widget.groupId}');
    }
    if (fontId!= null && fontId.isNotEmpty) {
      await prefs.setString('font_${widget.groupId}', fontId);
    } else {
      await prefs.remove('font_${widget.groupId}');
    }
    if (!mounted) return;
    setState(() {
      if (themeId!= null) _cachedThemeId = themeId;
      if (fontId!= null) _cachedFontId = fontId;
    });
  }

    void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendGroupMediaMessages(List<String> paths, {String caption = '', bool isVideoForce = false, bool isVideoNote = false, bool viewOnce = false}) async {
    final provider = Provider.of<GroupChatProvider>(context, listen: false);
    for (int i = 0; i < paths.length; i++) {
      final path = paths[i];
      final file = File(path);
      if (!await file.exists()) continue;
      final isVideo = isVideoForce || path.toLowerCase().endsWith('.mp4') ||
          path.toLowerCase().endsWith('.mov') ||
          path.toLowerCase().endsWith('.avi');
      final type = isVideoNote ? 'video_note' : (isVideo? 'video' : 'image');
      final pendingId = '${DateTime.now().millisecondsSinceEpoch}_$i';
      if (!mounted) return;
      _pendingUploads.insert(0, _PendingUpload(id: pendingId, localPath: path, type: type));
      _pendingUploadsRevision.value++;
      try {
        final bool isGif = !isVideo && path.toLowerCase().endsWith('.gif');
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$i${isVideo? '.mp4' : (isGif ? '.gif' : '.jpg')}';
        final objectName = 'group_media/${widget.groupId}/$fileName';
        await _validateChatMediaSize(file, isVideo);
        File fileToUpload = file;
        if (isVideo) {
          fileToUpload = await VideoProcessor.compressChatVideo(path);
        }
        final url = await R2Service().uploadFile(fileToUpload, objectName);
        if (isVideoNote) {
          await provider.sendVideoNote(groupId: widget.groupId, mediaUrl: url);
        } else if (isVideo) {
          await provider.sendVideo(groupId: widget.groupId, mediaUrl: url, caption: caption, viewOnce: viewOnce);
        } else {
          await provider.sendImage(groupId: widget.groupId, mediaUrl: url, caption: caption, viewOnce: viewOnce);
        }
        _scrollToBottom();
      } catch (e) {
        debugPrint('Upload error: $e');
        _notifyMediaUploadError(e);
      } finally {
        if (mounted) {
          _pendingUploads.removeWhere((p) => p.id == pendingId);
          _pendingUploadsRevision.value++;
        }
      }
    }
  }

  // عرض المستند أثناء رفعه، ومنع رفع النسخة نفسها مرتين في الوقت ذاته.
  Future<void> _uploadGroupDocument(_PendingUpload pending) async {
    if (_uploadingGroupDocuments.contains(pending.id)) return;
    _uploadingGroupDocuments.add(pending.id);
    if (mounted) setState(() => pending.failed = false);
    try {
      final file = File(pending.localPath);
      final size = await file.length();
      if (size > TiniChatAttachments.maxDocumentBytes) {
        throw StateError('حجم المستند يتجاوز الحد المسموح (50 ميغابايت). يرجى اختيار ملف أصغر.');
      }
      if (size <= 0) throw StateError('المستند فارغ');
      final name = pending.fileName ?? pending.localPath.split(Platform.pathSeparator).last;
      final objectName = 'group_media/${widget.groupId}/doc_${DateTime.now().microsecondsSinceEpoch}_$name';
      final url = await R2Service().uploadDocument(file, objectName);
      if (!mounted) return;
      await context.read<GroupChatProvider>().sendMessage(
        groupId: widget.groupId, text: name, type: 'document', mediaUrl: url,
      );
      if (mounted) {
        setState(() => _pendingUploads.removeWhere((p) => p.id == pending.id));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => pending.failed = true);
        final message = e.toString();
        final display = message.contains('50 ميغابايت')
            ? 'حجم المستند يتجاوز الحد المسموح (50 MB). اختر ملفاً أصغر.'
            : 'تعذر إرسال المستند. يمكنك إعادة المحاولة.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(display)));
      }
    } finally {
      _uploadingGroupDocuments.remove(pending.id);
    }
  }

  // إرسال مجموعة وسائط في مستند رسالة واحد بعد اكتمال رفع جميع العناصر.
  Future<void> _sendGroupMediaAlbum(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    if (items.length == 1 || items.any((e) => e['viewOnce'] == true)) {
      for (final item in items) {
        if (item['path'] == null) continue;
        await _sendGroupMediaMessages([item['path'].toString()],
          caption: (item['caption'] ?? '').toString(),
          isVideoForce: item['isVideo'] == true, viewOnce: item['viewOnce'] == true);
      }
      return;
    }
    final provider = context.read<GroupChatProvider>();
    final uploaded = <Map<String, dynamic>>[];
    final pendingId = 'album_${DateTime.now().microsecondsSinceEpoch}';
    final firstPath = items.first['path'].toString();
    final firstPathLower = firstPath.toLowerCase();
    final firstIsVideo = items.first['isVideo'] == true ||
        firstPathLower.endsWith('.mp4') ||
        firstPathLower.endsWith('.mov') ||
        firstPathLower.endsWith('.avi');
    if (mounted) setState(() => _pendingUploads.insert(0,
      _PendingUpload(id: pendingId, localPath: firstPath, type: firstIsVideo ? 'video' : 'image')));
    try {
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final path = item['path']?.toString() ?? '';
        final file = File(path);
        if (!await file.exists()) throw StateError('الملف غير موجود: $path');
        final lower = path.toLowerCase();
        final isVideo = item['isVideo'] == true || lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi');
        await _validateChatMediaSize(file, isVideo);
        final ext = isVideo ? '.mp4' : (lower.endsWith('.png') ? '.png' : lower.endsWith('.webp') ? '.webp' : lower.endsWith('.gif') ? '.gif' : '.jpg');
        final objectName = 'group_media/${widget.groupId}/album_${DateTime.now().microsecondsSinceEpoch}_$i$ext';
        final upload = isVideo ? await VideoProcessor.compressChatVideo(path) : file;
        final url = await R2Service().uploadFile(upload, objectName);
        uploaded.add({'url': url, 'isVideo': isVideo});
      }
      await provider.sendAlbum(groupId: widget.groupId, mediaItems: uploaded,
        caption: items.map((e) => (e['caption'] ?? '').toString()).where((s) => s.isNotEmpty).join(' '));
      _scrollToBottom();
    } catch (e) {
      debugPrint('Group album upload error: $e');
      if (e.toString().contains('250 MB') || e.toString().contains('25 MB')) {
        _notifyMediaUploadError(e);
      } else if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('تعذر إرسال مجموعة الوسائط. حاول مجددًا.'),
          action: SnackBarAction(label: 'إعادة المحاولة', onPressed: () { _sendGroupMediaAlbum(items); })));
    } finally {
      if (mounted) setState(() => _pendingUploads.removeWhere((p) => p.id == pendingId));
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_loadOlderOnScroll);
    _messagePager?.dispose();
    _pendingUploadsRevision.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildAvatar(String? groupImage, List<String> memberPhotos, {required double radius}) {
    final hasGroupImage = groupImage!= null && groupImage.trim().isNotEmpty;
    if (hasGroupImage) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(groupImage),
        backgroundColor: kFieldFill,
      );
    }
    if (memberPhotos.length >= 2) {
      return SizedBox(
        width: radius * 2.9,
        height: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: 0,
              child: CircleAvatar(
                radius: radius,
                backgroundImage: NetworkImage(memberPhotos[0]),
                backgroundColor: kFieldFill,
              ),
            ),
            Positioned(
              right: radius * 0.9,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kBg, width: 2),
                ),
                child: CircleAvatar(
                  radius: radius,
                  backgroundImage: NetworkImage(memberPhotos[1]),
                  backgroundColor: kFieldFill,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (memberPhotos.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(memberPhotos[0]),
        backgroundColor: kFieldFill,
      );
    }
    return CircleAvatar(radius: radius, backgroundColor: kFieldFill);
  }

  Future<List<String>> _getMemberPhotos(List<String> memberIds) async {
    if (memberIds.isEmpty) return [];
    final ids = memberIds.length > 10? memberIds.sublist(memberIds.length - 10) : memberIds;
    if (ids.isEmpty) return [];
    final snap = await FirebaseFirestore.instance
      .collection('users')
      .where(FieldPath.documentId, whereIn: ids)
      .get();
    List<String> photos = snap.docs.map((d) {
      final data = d.data();
      return (data['profileImg']?? '') as String;
    }).where((u) => u.trim().isNotEmpty).toList();
    if (photos.length > 2) photos = photos.sublist(photos.length - 2);
    return photos;
  }

  String _formatRestrictTime(Timestamp until) {
    final diff = until.toDate().difference(DateTime.now());
    if (diff.inMinutes < 60) return '${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return '${diff.inHours} ساعة';
    if (diff.inDays < 7) return '${diff.inDays} يوم';
    return '${(diff.inDays / 7).ceil()} أسبوع';
  }

  ChatTheme _getCurrentTheme(String? themeId) {
    return kThemes.firstWhere((t) => t.id == themeId, orElse: () => kThemes[3]);
  }

  ChatFont _getCurrentFont(String? fontId) {
    return kFonts.firstWhere((f) => f.id == fontId, orElse: () => kFonts[0]);
  }

  void _openMediaViewer(String url, String type) {
    if (type == 'image') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewerScreen(imageUrl: url)));
    } else if (type == 'video') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoViewerScreen(videoUrl: url)));
    }
  }

  // ===== [عرض مرة واحدة] =====
  Widget _buildViewOnceContent(GroupMessageModel m, bool isMe) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool opened = isMe ? m.viewedBy.isNotEmpty : m.viewedBy.contains(uid);
    final bool gone = m.mediaUrl == null || m.mediaUrl!.isEmpty;
    final bool consumed = opened || gone;
    final String label = consumed ? 'تم فتحها' : (m.type == 'video' ? 'مقطع فيديو' : 'صورة');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ViewOnceIcon(size: 24, color: consumed ? Colors.white54 : Colors.white),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: consumed ? Colors.white70 : Colors.white,
              fontFamily: 'Tajawal',
              fontSize: 15,
              fontStyle: consumed ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  bool _openingViewOnce = false;

  void _viewOnceSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal'))));
  }

  Future<void> _openViewOnce(GroupMessageModel m, bool isMe) async {
    if (_openingViewOnce) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final url = m.mediaUrl;
    if (isMe) {
      _viewOnceSnack('لا يمكنك فتح رسالة العرض مرة واحدة التي أرسلتها');
      return;
    }
    if (url == null || url.isEmpty || m.viewedBy.contains(uid)) {
      _viewOnceSnack('تم فتح هذه الرسالة مسبقاً');
      return;
    }
    _openingViewOnce = true;
    try {
      final agreed = await showViewOnceIntro(context);
      if (!agreed || !mounted) return;
      final provider = Provider.of<GroupChatProvider>(context, listen: false);
      final ok = await provider.claimViewOnce(groupId: widget.groupId, messageId: m.id);
      if (!ok) {
        _viewOnceSnack('تعذر فتح الرسالة');
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ViewOnceViewerScreen(url: url, isVideo: m.type == 'video', senderName: m.senderName)),
      );
      await provider.cleanupViewOnce(groupId: widget.groupId, messageId: m.id);
    } finally {
      _openingViewOnce = false;
    }
  }

  Widget _buildMessageContent(GroupMessageModel m, bool isMe, Color bubbleColor) {
    final hasCaption = m.text.trim().isNotEmpty;
    if (m.viewOnce && (m.type == 'image' || m.type == 'video')) {
      return _buildViewOnceContent(m, isMe);
    }
    if (m.type == 'location' || m.type == 'document') {
      return TiniChatAttachments.message(type: m.type, text: m.text, mediaUrl: m.mediaUrl);
    }
    if (m.type == 'album' && m.mediaItems.isNotEmpty) {
      return SizedBox(
        width: 230,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          ChatAlbumGrid(items: m.mediaItems),
          if (hasCaption) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _GroupCompactMediaCaption(key: ValueKey('group_caption_${m.id}'), caption: m.text),
          ),
        ]),
      );
    }
    if (m.mediaUrl != null && m.type == 'image') {
      return SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(m.mediaUrl!, width: 200, height: 200, fit: BoxFit.cover),
            ),
            if (hasCaption) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _GroupCompactMediaCaption(key: ValueKey('group_caption_${m.id}'), caption: m.text),
            ),
          ],
        ),
      );
    } else if (m.mediaUrl != null && m.type == 'video') {
      return SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 200, height: 200, child: VideoThumbnail(videoUrl: m.mediaUrl!))),
                  Container(decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), padding: const EdgeInsets.all(8), child: const Icon(Icons.play_arrow, color: Colors.white, size: 32)),
                ],
              ),
            ),
            if (hasCaption) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _GroupCompactMediaCaption(key: ValueKey('group_caption_${m.id}'), caption: m.text),
            ),
          ],
        ),
      );
} else if (m.mediaUrl != null && m.type == 'video_note') {
  return VideoNoteBubble(
    key: ValueKey(m.id),
    videoUrl: m.mediaUrl!,
    durationSeconds: m.durationSeconds ?? 0,
    timeText: '${m.timestamp.hour}:${m.timestamp.minute.toString().padLeft(2, '0')} م',
    isMe: isMe,
    isSeen: m.readBy.length > 1,
  );
} else if (m.mediaUrl != null && m.type == 'audio') {
  return FutureBuilder<String>(
    future: _getUserPhotoCached(m.senderId),
    initialData: _userPhotoCache[m.senderId],
    builder: (context, snap) {
      final photoUrl = snap.data ?? '';
      return VoiceMessageBubble(
        key: ValueKey(m.id),
        audioUrl: m.mediaUrl!,
        profileImgUrl: photoUrl,
        isMe: isMe,
        duration: Duration(seconds: m.durationSeconds ?? 0),
        timeText: '${m.timestamp.hour}:${m.timestamp.minute.toString().padLeft(2, '0')} م',
        isSeen: m.readBy.length > 1,
        chatId: 'group_${widget.groupId}',
        waveform: m.waveform,
        sortTime: m.timestamp,
      );
    },
  );
} else {
      return Text(m.text, style: TextStyle(color: isMe? Colors.white : Colors.white, fontFamily: 'Tajawal', fontSize: 15));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _messagePager == null) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: Text('يرجى تسجيل الدخول', style: TextStyle(color: Colors.white))),
      );
    }
    final uid = currentUser.uid;
    return StreamBuilder<DocumentSnapshot>(
      stream: _groupStream,
      builder: (context, banSnap) {
        if (banSnap.hasData && banSnap.data!.exists) {
          final bData = banSnap.data!.data() as Map<String, dynamic>?;
          final banned = List<String>.from(bData?['banned']?? []);
          final members = List<String>.from(bData?['members']?? []);
          if (banned.contains(uid) ||!members.contains(uid)) {
            final bannedByMap = Map<String, dynamic>.from(bData?['bannedBy']?? {});
            final bannerName = bannedByMap[uid]?? 'الإدارة';
            return Scaffold(
              backgroundColor: kBg,
              body: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(22),
                        decoration: BoxDecoration(color: kErrorRed.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(Icons.block, size: 64, color: kErrorRed),
                      ),
                      SizedBox(height: 20),
                      Text('قام $bannerName بحظرك من المجموعة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      SizedBox(height: 8),
                      Text('لم تعد تستطيع رؤية الرسائل أو إرسالها', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 13), textAlign: TextAlign.center),
                      SizedBox(height: 28),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
                        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                        child: Text('رجوع', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        }
        bool isUserRestricted = false;
        Timestamp? restrictUntil;
        if (banSnap.hasData && banSnap.data!.exists) {
          final bData = banSnap.data!.data() as Map<String, dynamic>?;
          final restrictedMap = Map<String, dynamic>.from(bData?['restricted']?? {});
          if (restrictedMap.containsKey(uid)) {
            final v = restrictedMap[uid];
            if (v is Timestamp) {
              if (v.toDate().isAfter(DateTime.now())) {
                isUserRestricted = true;
                restrictUntil = v;
              } else {
                FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
                  'restricted.$uid': FieldValue.delete(),
                });
              }
            }
          }
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: _themeStream,
          builder: (context, themeSnap) {
            final tData = themeSnap.data?.data() as Map<String, dynamic>?;
            final String? themeIdFromServer = tData?['themeId'] as String?;
            final String? fontIdFromServer = tData?['fontId'] as String?;

            String? effectiveThemeId;
            String? effectiveFontId;

            if (themeSnap.hasData) {
              effectiveThemeId = themeIdFromServer;
              effectiveFontId = fontIdFromServer;

              if (themeIdFromServer == null || themeIdFromServer.isEmpty) {
                SharedPreferences.getInstance().then((p) {
                  p.remove('theme_${widget.groupId}');
                  p.remove('font_${widget.groupId}');
                });
                _cachedThemeId = null;
                _cachedFontId = null;
              } else if (themeIdFromServer!= _cachedThemeId) {
                _cacheTheme(themeIdFromServer, fontIdFromServer);
              }
            } else {
              effectiveThemeId = _cachedThemeId;
              effectiveFontId = _cachedFontId;
            }

            final currentTheme = _getCurrentTheme(effectiveThemeId);
            final currentFont = _getCurrentFont(effectiveFontId);
            final bool hasCustomTheme = effectiveThemeId!= null && effectiveThemeId.isNotEmpty;

            return Scaffold(
              backgroundColor: kBg,
              appBar: AppBar(
                backgroundColor: kSurface,
                title: Builder(
                  builder: (c) {
                    // Reuse the parent group snapshot rather than opening a duplicate listener.
                    final snap = banSnap;
                    if (!snap.hasData) {
                      return Text('جروب', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal'));
                    }
                    final data = snap.data!.data() as Map<String, dynamic>?;
                    final groupName = data?['groupName']?? 'جروب';
                    _cameraGroupName = groupName.toString();
                    final groupImage = data?['groupImage'] as String?;
                    final members = (data?['members'] as List?)?.cast<String>()?? [];
                    return FutureBuilder<List<String>>(
                      future: _getMemberPhotosCached(members),
                      builder: (context, photoSnap) {
                        final photos = photoSnap.data?? [];
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(groupName, style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('${members.length} عضو', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 12)),
                              ],
                            ),
                            SizedBox(width: 10),
                            _buildAvatar(groupImage, photos, radius: 18),
                          ],
                        );
                      },
                    );
                  },
                ),
                actions: [
                  IconButton(icon: Icon(Icons.info_outline, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupInfoScreen(groupId: widget.groupId)))),
                ],
              ),
              body: Container(
                decoration: hasCustomTheme? BoxDecoration(image: DecorationImage(image: NetworkImage(currentTheme.imageUrl), fit: BoxFit.cover)) : null,
                child: Stack(
                  children: [
                    Positioned.fill(
                      bottom: _composerHeight,
                      child: Consumer<GroupChatProvider>(
                        builder: (context, prov, _) {
                          return AnimatedBuilder(
                            animation: Listenable.merge([_messagePager!, _pendingUploadsRevision]),
                            builder: (c, _) {
                              final pager = _messagePager!;
                              if (!pager.initialized) return Center(child: CircularProgressIndicator(color: kTitiTeal));
                              if (pager.error != null && pager.documents.isEmpty) {
                                return const Center(child: Text('تعذر تحميل الرسائل', style: TextStyle(color: Colors.white70)));
                              }
                              final msgs = pager.documents.map(GroupMessageModel.fromDoc).toList();
                              // أي رسالة جديدة تظهر أثناء فتح المجموعة تُعتبر مقروءة
                              // لدى هذا العضو فوراً، دون الحاجة للخروج والدخول مجدداً.
                              final currentUid = FirebaseAuth.instance.currentUser?.uid;
                              if (currentUid != null) {
                                final newlyUnread = msgs.where((m) =>
                                    m.senderId != currentUid &&
                                    !m.readBy.contains(currentUid) &&
                                    _handledOpenChatReads.add(m.id)).toList().isNotEmpty;
                                if (newlyUnread) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    context.read<GroupChatProvider>().markAsRead(widget.groupId, currentUid);
                                  });
                                }
                              }

                              final pendingCount = _pendingUploads.length;
                              final totalCount = msgs.length + pendingCount + (pager.hasMore || pager.isLoadingMore ? 1 : 0);
                              return CustomScrollView(
                                controller: _scrollController,
                                reverse: true,
                                slivers: [
                                  SliverToBoxAdapter(child: SizedBox.shrink()),
                                  SliverList.builder(
                                    itemCount: totalCount,
                                    itemBuilder: (context, i) {
                                      if (i < pendingCount) {
                                        final pending = _pendingUploads[i];
                                        if (pending.type == 'document') {
                                          final isUploading = _uploadingGroupDocuments.contains(pending.id);
                                          return Container(
                                            key: ValueKey(pending.id),
                                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: Container(
                                                constraints: const BoxConstraints(maxWidth: 265),
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(color: kTitiTeal.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16)),
                                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                  const Icon(Icons.insert_drive_file_outlined, color: Colors.white),
                                                  const SizedBox(width: 10),
                                                  Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                                    Text(pending.fileName ?? 'مستند', maxLines: 1, overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
                                                    const SizedBox(height: 5),
                                                    if (pending.failed)
                                                      TextButton.icon(
                                                        onPressed: isUploading ? null : () => _uploadGroupDocument(pending),
                                                        icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                                                        label: const Text('فشل الإرسال - إعادة المحاولة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 12)),
                                                      )
                                                    else
                                                      const Row(mainAxisSize: MainAxisSize.min, children: [
                                                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                                        SizedBox(width: 8),
                                                        Text('جارٍ رفع المستند...', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 12)),
                                                      ]),
                                                  ])),
                                                ]),
                                              ),
                                            ),
                                          );
                                        }
                                        final isVideo = pending.type == 'video' || pending.type == 'video_note';
                                        final isNote = pending.type == 'video_note';
                                        final pendingRadius = BorderRadius.circular(isNote ? 100 : 12);
                                        return Container(
                                          key: ValueKey(pending.id),
                                          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Container(
                                              padding: EdgeInsets.all(4),
                                              decoration: BoxDecoration(color: kTitiTeal.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16)),
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  ClipRRect(borderRadius: pendingRadius, child: isVideo? Container(width: 200, height: 200, color: kSurface, child: Icon(Icons.videocam, color: Colors.white54, size: 40)) : Image.file(File(pending.localPath), width: 200, height: 200, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(width: 200, height: 200, color: kSurface, child: Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 40)))),
                                                  Container(width: 200, height: 200, decoration: BoxDecoration(color: Colors.black45, borderRadius: pendingRadius), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.white), SizedBox(height: 8), Text('جاري الإرسال...', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Tajawal'))])),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      if (i >= pendingCount + msgs.length) {
                                        return SizedBox(
                                          height: 60,
                                          child: Center(
                                            child: pager.isLoadingMore
                                                ? const CircularProgressIndicator(color: kTitiTeal, strokeWidth: 2)
                                                : TextButton(
                                                    onPressed: pager.loadOlder,
                                                    child: const Text('تحميل رسائل أقدم', style: TextStyle(color: kTitiTeal)),
                                                  ),
                                          ),
                                        );
                                      }
                                      final m = msgs[i - pendingCount];
                                      final isMe = m.senderId == uid;
                                      final bubbleColor = isMe? (hasCustomTheme? currentTheme.bubbleMe : kTitiTeal) : kSurface;
                                      final textColor = isMe && hasCustomTheme? Colors.black : Colors.white;
                                      return Container(
                                        key: ValueKey(m.id),
                                        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        child: Column(
                                          crossAxisAlignment: isMe? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                          children: [
                                              if (!isMe)
                                              FutureBuilder<String>(
                                                future: _getUserPhotoCached(m.senderId),
                                                initialData: _userPhotoCache[m.senderId],
                                                builder: (context, snap) {
                                                  final photo = snap.data ?? '';
                                                  return Padding(
                                                    padding: EdgeInsets.only(bottom: 4),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        CircleAvatar(
                                                          radius: 11,
                                                          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                                                          backgroundColor: kFieldFill,
                                                          child: photo.isEmpty ? Icon(Icons.person, size: 11, color: Colors.white54) : null,
                                                        ),
                                                        SizedBox(width: 6),
                                                        Text(m.senderName, style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 11)),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            if (m.replyTo!= null)
                                              Container(
                                                padding: EdgeInsets.all(8),
                                                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(8), border: Border(right: BorderSide(color: kTitiTeal, width: 3))),
                                                child: Text(m.replyTo!['text']?? '', style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 12)),
                                              ),
GestureDetector(
  onLongPress: () => setState(() => _replyTo = m),
  onTap: () {
    if (m.viewOnce && (m.type == 'image' || m.type == 'video')) { _openViewOnce(m, isMe); return; }
    if (m.mediaUrl!= null && (m.type == 'image' || m.type == 'video')) _openMediaViewer(m.mediaUrl!, m.type);
  },
  child: (m.type == 'audio' || m.type == 'video_note')
      ? _buildMessageContent(m, isMe, bubbleColor)
      : Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildMessageContent(m, isMe, bubbleColor),
              SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${m.timestamp.hour}:${m.timestamp.minute.toString().padLeft(2, '0')}', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  if (isMe)...[
                    SizedBox(width: 4),
                    Icon(m.readBy.length > 1? Icons.done_all : Icons.done, size: 14, color: m.readBy.length > 1? Colors.white : Colors.white54),
                  ]
                ],
              ),
            ],
          ),
        ),
),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  SliverToBoxAdapter(
                                    child: Builder(
                                      builder: (context) {
                                        final gData = banSnap.data?.data() as Map<String, dynamic>?;
                                        final groupName = gData?['groupName']?? 'jimo';
                                        final groupImage = gData?['groupImage'] as String?;
                                        final members = (gData?['members'] as List?)?.cast<String>()?? [];
                                        return FutureBuilder<List<String>>(
                                          future: _getMemberPhotosCached(members),
                                          builder: (context, pSnap) {
                                            final photos = pSnap.data?? [];
                                            return Column(
                                              children: [
                                                SizedBox(height: 24),
                                                _buildAvatar(groupImage, photos, radius: 52),
                                                SizedBox(height: 12),
                                                Text(groupName, style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 22)),
                                                SizedBox(height: 4),
                                                GestureDetector(
                                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupInfoScreen(groupId: widget.groupId))),
                                                  child: Text('تغيير الاسم والصورة', style: TextStyle(color: Color(0xFF6B8AFF), fontFamily: 'Tajawal', fontSize: 13)),
                                                ),
                                                SizedBox(height: 28),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: NotificationListener<SizeChangedLayoutNotification>(
                        onNotification: (_) {
                          WidgetsBinding.instance.addPostFrameCallback((_) => _updateComposerHeight());
                          return false;
                        },
                        child: SizeChangedLayoutNotifier(
                          child: Column(
                            key: _composerKey,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_replyTo!= null)
                            Container(
                              color: kSurface,
                              padding: EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  IconButton(icon: Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() => _replyTo = null)),
                                  Expanded(child: Text(_replyTo!.text, style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal'), maxLines: 1, textAlign: TextAlign.right)),
                                ],
                              ),
                            ),
                          if (isUserRestricted)
                            Container(
                              color: kSurface,
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.block, color: kErrorRed, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(child: Text(restrictUntil!= null? 'تم تقييدك - باقي ${_formatRestrictTime(restrictUntil)}' : 'تم تقييدك من الإرسال', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 14), textAlign: TextAlign.center)),
                                ],
                              ),
                            )
                          else
                            TitiInputBar(
                          cameraRecipientName: _cameraGroupName,
                          allowMultiMedia: true,
                          textController: _controller,
                          onSendText: (text) async {
                            if (text.trim().isEmpty) return;
                            final gDoc = await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).get();
                            final banned = List<String>.from(gDoc.data()?['banned']?? []);
                            if (banned.contains(uid)) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('انت محظور من هذه المجموعة', style: TextStyle(fontFamily: 'Tajawal'))));
                              return;
                            }
                            final restrictedMap = Map<String, dynamic>.from(gDoc.data()?['restricted']?? {});
                            if (restrictedMap.containsKey(uid)) {
                              final v = restrictedMap[uid];
                              if (v is Timestamp && v.toDate().isAfter(DateTime.now())) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('انت مقيد من الإرسال', style: TextStyle(fontFamily: 'Tajawal'))));
                                return;
                              }
                            }
                            context.read<GroupChatProvider>().sendMessage(groupId: widget.groupId, text: text.trim(), replyTo: _replyTo!= null? {'id': _replyTo!.id, 'text': _replyTo!.text, 'senderName': _replyTo!.senderName} : null);
                            _controller.clear();
                            setState(() => _replyTo = null);
                            _scrollToBottom();
                          },
                          onSendVoice: (path, duration, waveform) async {
                            final file = File(path);
                            final compressedFile = await VideoProcessor.compressChatVoice(file);
                            final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
                            final objectName = 'group_media/${widget.groupId}/$fileName';
                            final url = await R2Service().uploadFile(compressedFile, objectName);
                            await context.read<GroupChatProvider>().sendVoice(groupId: widget.groupId, mediaUrl: url, durationSeconds: duration.inSeconds, waveform: waveform);
                            _scrollToBottom();
                          },
                          onPickLocation: () async {
                            try {
                              final loc = await TiniChatAttachments.pickLocation(context);
                              if (loc == null || !mounted) return;
                              await context.read<GroupChatProvider>().sendMessage(groupId: widget.groupId, text: loc.url, type: 'location');
                            } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الموقع: $e'))); }
                          },
                          onPickDocument: () async {
                            if (_pickingGroupDocument) return;
                            _pickingGroupDocument = true;
                            try {
                              final doc = await TiniChatAttachments.pickDocument();
                              if (doc == null || !mounted) return;
                              if (doc.path == null) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر الوصول إلى المستند المختار. اختر ملفاً آخر.')));
                                return;
                              }
                              final pending = _PendingUpload(
                                id: 'document_${DateTime.now().microsecondsSinceEpoch}',
                                localPath: doc.path!, type: 'document', fileName: doc.name,
                              );
                              setState(() => _pendingUploads.insert(0, pending));
                              _scrollToBottom();
                              await _uploadGroupDocument(pending);
                            } catch (e) {
                              if (mounted) {
                                final message = e.toString();
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
                                  message.contains('50 ميغابايت')
                                      ? 'حجم المستند يتجاوز الحد المسموح (50 MB). اختر ملفاً أصغر.'
                                      : 'تعذر اختيار المستند: $e',
                                )));
                              }
                            } finally {
                              _pickingGroupDocument = false;
                            }
                          },
                          onPickFile: () async {
                            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaPickerScreen(isForChat: true)));
                            if (result!= null && result is List<String> && result.isNotEmpty) {
                              if (!mounted) return;
                              // معاينة متعددة (حد أقصى 5) مع شرح توضيحي لكل عنصر
                              final out = await Navigator.push(
                                context,
                                MultiMediaPreviewScreen.route(
                                  items: result.map((p) => PreviewMediaItem.fromPath(p)).toList(),
                                  recipientName: _cameraGroupName,
                                  popCameraToo: false,
                                ),
                              );
                              await _sendGroupMediaAlbum(MultiMediaPreviewScreen.normalizeResult(out)
                                  .map((e) => Map<String, dynamic>.from(e)).toList());
                            }
                          },
                          onPickCamera: () async {
                            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatCameraScreen()));
                            if (result is Map && result['items'] is List) {
                              await _sendGroupMediaAlbum(MultiMediaPreviewScreen.normalizeResult(result)
                                  .map((e) => Map<String, dynamic>.from(e)).toList());
                            } else if (result is Map && result['paths'] is List) {
                              await _sendGroupMediaAlbum((result['paths'] as List)
                                  .map((path) => <String, dynamic>{'path': path.toString()}).toList());
                            } else if (result!= null && result is Map && result['path'] != null) {
                              await _sendGroupMediaMessages([result['path']], caption: result['caption'] ?? '', isVideoForce: result['isVideo'] ?? false, isVideoNote: result['isVideoNote'] == true, viewOnce: result['viewOnce'] == true);
                            }
                          },
                          onSendMediaAlbum: _sendGroupMediaAlbum,
                          onSendMedia: (path, caption, isVideo) async {
                            await _sendGroupMediaMessages([path], caption: caption, isVideoForce: isVideo);
                          },
                          onSendViewOnce: (path, isVideo) async {
                            await _sendGroupMediaMessages([path], isVideoForce: isVideo, viewOnce: true);
                          },
                          onSendVideoNote: (path) async {
                            await _sendGroupMediaMessages([path], isVideoForce: true, isVideoNote: true);
                          },
                          onPickEmoji: () {},
                        ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AudioMessageBubble extends StatefulWidget {
  final String url;
  final bool isMe;
  final Duration duration;
  const _AudioMessageBubble({super.key, required this.url, required this.isMe, this.duration = Duration.zero});
  @override
  State<_AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<_AudioMessageBubble> {
  final ap.AudioPlayer _player = ap.AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _isPlaying = s == ap.PlayerState.playing); });
    _player.onDurationChanged.listen((d) => setState(() => _duration = d));
    _player.onPositionChanged.listen((p) => setState(() => _position = p));
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  String _fmt(Duration d) { final m = d.inMinutes.remainder(60).toString().padLeft(2, '0'); final s = d.inSeconds.remainder(60).toString().padLeft(2, '0'); return '$m:$s'; }

  @override
  Widget build(BuildContext context) {
    final displayDuration = _duration > Duration.zero? _duration : widget.duration;
    return Container(
      width: 200,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: Icon(_isPlaying? Icons.pause : Icons.play_arrow, color: Colors.white), onPressed: () async { if (_isPlaying) { await _player.pause(); } else { await _player.play(ap.UrlSource(widget.url)); } }),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [LinearProgressIndicator(value: displayDuration.inMilliseconds > 0? _position.inMilliseconds / displayDuration.inMilliseconds : 0, backgroundColor: Colors.white24, color: Colors.white), SizedBox(height: 4), Text(_isPlaying? _fmt(_position) : _fmt(displayDuration), style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Tajawal'))])),
        ],
      ),
    );
  }
}

class ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  const ImageViewerScreen({super.key, required this.imageUrl});
  @override
  Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black), body: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: Image.network(imageUrl)))); }
}

class VideoViewerScreen extends StatefulWidget {
  final String videoUrl;
  const VideoViewerScreen({super.key, required this.videoUrl});
  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.addListener(() {
            if (mounted) setState(() {});
          });
          _controller.play();
        }
      });
  }

  void _togglePlay() {
    if (!_isInitialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      final v = _controller.value;
      if (v.position >= v.duration - const Duration(milliseconds: 150)) {
        _controller.seekTo(Duration.zero);
      }
      _controller.play();
    }
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
   Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: _isInitialized
            ? InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlay,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
                    if (!_controller.value.isPlaying)
                      Container(
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(14),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 44),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: VideoProgressIndicator(_controller, allowScrubbing: true, colors: VideoProgressColors(playedColor: kTitiTeal)),
                    ),
                  ],
                ),
              ),
              )
            : CircularProgressIndicator(color: kTitiTeal),
      ),
    );
  }
}

class VideoThumbnail extends StatelessWidget {
  final String videoUrl;
  const VideoThumbnail({super.key, required this.videoUrl});

  @override
  Widget build(BuildContext context) {
    return TiniChatVideoThumbnail(videoUrl: videoUrl);
  }
}

