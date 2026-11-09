import 'dart:async';
import 'audience_message_gate.dart';
import 'audience_access.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'r2_service.dart';
import 'tini_chat_attachments.dart';
import 'tini_chat_message_pager.dart';
import 'tini_chat_video_thumbnail.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'user_profile_sheet.dart';
import 'media_picker_screen.dart';
import 'chat_provider.dart';
import 'tini_messaging_notice.dart';
import 'private_chat_media_screen.dart';
import 'chat_album_widgets.dart';
import 'story_ring.dart';
import 'activity_status_service.dart'; // [حالة النشاط]
import 'home_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'auth_provider.dart' as custom;
import 'block_service.dart';
import 'video_processor.dart';
import 'voice_message_bubble.dart';
import 'video_note_bubble.dart'; // [ملاحظات الفيديو - الخاص]
import 'titi_input_bar.dart';
import 'view_once_viewer_screen.dart'; // [عرض مرة واحدة - الخاص]
import 'view_once_icon.dart'; // [عرض مرة واحدة - الخاص]

// [Tini - Messaging]: إشعار موحد يميّز قيود الخصوصية عن الأخطاء التقنية.
// تُستخدم الدالة أيضاً في زر المراسلة وفي شريط القصص دون تعديل ChatProvider.
// [Tini - Messaging] موحّد مع إشعارات الردود والمشاركات، دون تغيير صلاحيات المراسلة.
void _showTiniChatAccessNoticeOnMessenger(
  ScaffoldMessengerState messenger,
  ChatFailureReason? reason,
) {
  TiniMessagingNotice.showAccess(messenger, reason);
}

void showTiniChatAccessNotice(BuildContext context, ChatFailureReason? reason) {
  TiniMessagingNotice.showAccess(ScaffoldMessenger.maybeOf(context), reason);
}

class ChatScreen extends StatefulWidget {
  final String viewedUid;
  final String displayFullName;
  final String displayProfileImg;
  final bool isFriend;

  const ChatScreen({
    super.key,
    required this.viewedUid,
    required this.displayFullName,
    required this.displayProfileImg,
    required this.isFriend,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _PendingUpload {
  final String id;
  final String localPath;
  final String type;
  final String? fileName;
  bool failed;
  // [Tini - send result] احتفظ بخيارات الملف الأصلي عند تعذّر حفظ الرسالة.
  final bool viewOnce;
  final bool isVideoNote;
  final bool isVideoForce;
  final String caption;
  final Duration? voiceDuration;
  final List<int>? voiceWaveform;
  final List<Map<String, dynamic>>? albumItems;
  _PendingUpload({required this.id, required this.localPath, required this.type, this.fileName,
    this.failed = false, this.viewOnce = false, this.isVideoNote = false,
    this.isVideoForce = false, this.caption = '', this.voiceDuration, this.voiceWaveform,
    this.albumItems});
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // ارتفاع شريط الكتابة (بما فيه لوحة الإيموجي) لحجز مساحة الرسائل فوقه.
  final GlobalKey _composerKey = GlobalKey();
  double _composerHeight = 85;

  void _updateComposerHeight() {
    if (!mounted) return;
    final render = _composerKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final height = render.size.height;
    // لا نستخدم قياساً غير منطقي من إطار فاشل في بناء الواجهة.
    if (!height.isFinite || height < 0 || height > MediaQuery.sizeOf(context).height) return;
    if ((height - _composerHeight).abs() > 0.5) {
      setState(() => _composerHeight = height);
    }
  }

  late String _chatRoomId;
  TiniChatMessagePager? _messagePager;
  final Set<String> _handledOpenChatReads = <String>{};
  final List<_PendingUpload> _pendingUploads = [];
  final ValueNotifier<int> _pendingUploadsRevision = ValueNotifier<int>(0);
  bool _pickingPrivateDocument = false;
  final Set<String> _uploadingPrivateDocuments = <String>{};
  Map<String, dynamic>? _replyingTo;
  Map<String, dynamic> _participantsInfo = {};
  bool _openingViewOnce = false; // [عرض مرة واحدة - الخاص]

  Stream<QuerySnapshot<Map<String, dynamic>>>? _storiesStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _roomStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _peerStatusStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _myStatusStream;
  Future<bool>? _mutualFriendFuture;

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
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (message.contains('250 MB') || message.contains('25 MB')) {
      TiniMessagingNotice.showInfo(messenger,
          message.replaceFirst('Bad state: ', ''),
          title: 'حجم الوسائط غير صالح');
    } else {
      TiniMessagingNotice.showTechnicalError(messenger, 'تعذّر إرسال الوسائط');
    }
  }

  // [Tini - send result] لا نخلط رفض الخصوصية مع فشل التحميل/الحفظ.
  // [Tini - send result] رفض الخصوصية لا يظهر كفشل تقني أحمر.
  void _showPrivateSendFailure(ChatFailureReason? reason,
      {String action = 'إرسال الرسالة', VoidCallback? onRetry}) {
    if (!mounted) return;
    TiniMessagingNotice.showFailure(
      ScaffoldMessenger.maybeOf(context), reason,
      action: action, onRetry: onRetry,
    );
  }

  // يفرّغ شريط الإدخال نصه فور الضغط على إرسال؛ نعيده إذا رفض Firestore الحفظ.
  void _restoreFailedPrivateText(String text) {
    if (!mounted || text.isEmpty) return;
    final current = _messageController.text;
    final restored = current.trim().isEmpty ? text : '$text\n$current';
    _messageController.value = TextEditingValue(
      text: restored, selection: TextSelection.collapsed(offset: restored.length));
  }


  @override
  void initState() {
    super.initState();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    _generateChatRoomId();
    final firestore = FirebaseFirestore.instance;
    _storiesStream = firestore.collection('stories').doc(widget.viewedUid)
        .collection('items').where('expiresAt', isGreaterThan: Timestamp.now()).snapshots();
    _roomStream = firestore.collection('chat_rooms').doc(_chatRoomId).snapshots();
    _peerStatusStream = firestore.collection('users').doc(widget.viewedUid).snapshots();
    _myStatusStream = firestore.collection('users').doc(currentUid).snapshots();
    _mutualFriendFuture = ActivityStatusService.isMutualFriend(currentUid, widget.viewedUid);
    _messagePager = TiniChatMessagePager(
      query: FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(_chatRoomId)
          .collection('messages')
          .orderBy('timestamp', descending: true),
    )..start();
    _scrollController.addListener(_loadOlderOnScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initChat();
    });
  }

  void _loadOlderOnScroll() {
    final pager = _messagePager;
    if (pager == null || !_scrollController.hasClients) return;
    // reverse:true puts older messages at the end of the scroll extent.
    if (_scrollController.position.extentAfter < 300) {
      pager.loadOlder();
    }
  }

  void _generateChatRoomId() {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;
    List<String> ids = [currentUserId, widget.viewedUid];
    ids.sort();
    _chatRoomId = ids.join("_");
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

  Future<void> _initChat() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || !mounted) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);

  final result = await provider.startChatWithReason(
    viewedUid: widget.viewedUid,
    displayFullName: widget.displayFullName,
    displayProfileImg: widget.displayProfileImg,
    isFriend: widget.isFriend,
  );
  if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;

  if (!result.isSuccess || (result.value ?? '').isEmpty) {
    // احتفظ بمرجع الـ ScaffoldMessenger قبل الرجوع حتى يظهر الإشعار على الشاشة السابقة.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
    if (messenger != null) {
      _showTiniChatAccessNoticeOnMessenger(
        messenger,
        result.failureReason ?? ChatFailureReason.roomNotFound,
      );
    }
    return;
  }

  // [FIX] نستخدم نفس الـ roomId اللي رجع، ونادي markAsRead اللي بيفرق بين زر مفعل/مطفي
  _chatRoomId = result.value!;
  try {
    await provider.markAsRead(_chatRoomId, currentUserId);
    final roomDoc = await FirebaseFirestore.instance.collection('chat_rooms').doc(_chatRoomId).get();
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
    final data = roomDoc.data();
    if (data != null) {
      setState(() {
        _participantsInfo = Map<String, dynamic>.from(data['participantsInfo'] ?? {});
      });
    }
  } catch (e) {
    // فشل تحديث حالة القراءة لا يجب أن يُسقط شاشة محادثة فُتحت بنجاح.
    debugPrint('Error loading chat room after opening: $e');
  }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_loadOlderOnScroll);
    _messagePager?.dispose();
    _pendingUploadsRevision.dispose();
    _messageController.dispose();
     _scrollController.dispose();
    super.dispose();
  }

  void _showProfileSheet() {
    UserProfileSheet.show(
      context,
      fullName: widget.displayFullName,
      username: widget.viewedUid,
      profileImg: widget.displayProfileImg,
      uid: widget.viewedUid,
      isFollowing: widget.isFriend,
      onFollowTap: () {},
    );
  }

  Future<void> _sendTextMessage(String currentUserId, String submittedText) async {
    final text = submittedText.trim();
    if (text.isEmpty) return;
    // TitiInputBar.clear() happens immediately after calling onSendText.
    await Future<void>.value();
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
    final blockedSet = Provider.of<custom.AuthProvider>(context, listen: false).blockedUsersSet;
    if (blockedSet.contains(widget.viewedUid)) {
      _restoreFailedPrivateText(text);
      _showPrivateSendFailure(ChatFailureReason.blocked);
      return;
    }

    final provider = Provider.of<ChatProvider>(context, listen: false);
    final selectedReply = _replyingTo;
    Map<String, dynamic>? replyData;
    if (selectedReply != null) {
      replyData = {
        'messageId': selectedReply['messageId'],
        'text': selectedReply['text'],
        'type': selectedReply['type'],
        'senderId': selectedReply['senderId'],
        'mediaUrl': selectedReply['mediaUrl'],
        ...AudienceMessagePolicy.sourceFields(selectedReply),
      };
    }

    final result = await provider.sendMessageWithReason(
      roomId: _chatRoomId,
      senderId: currentUserId,
      receiverId: widget.viewedUid,
      type: 'text',
      text: text,
      isFriend: widget.isFriend,
      replyTo: replyData,
    );
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
    if (!result.isSuccess) {
      _restoreFailedPrivateText(text);
      _showPrivateSendFailure(result.failureReason);
      return;
    }
    if (selectedReply != null && identical(_replyingTo, selectedReply)) {
      setState(() => _replyingTo = null);
    }
    _scrollToBottom();
  }

  Future<void> _sendMediaMessages(List<String> paths, String currentUserId, {bool viewOnce = false, bool isVideoNote = false, String caption = '', bool isVideoForce = false}) async {
    if (FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);

    for (int i = 0; i < paths.length; i++) {
      final path = paths[i];
      final file = File(path);
      if (!await file.exists()) {
        _notifyMediaUploadError(StateError('الملف غير موجود: $path'));
        continue;
      }

      final isVideo = isVideoNote || isVideoForce || path.toLowerCase().endsWith('.mp4') ||
          path.toLowerCase().endsWith('.mov') ||
          path.toLowerCase().endsWith('.avi');

      final type = isVideoNote ? 'video_note' : (isVideo ? 'video' : 'image');
      final pendingId = '${DateTime.now().microsecondsSinceEpoch}_$i';

      if (!mounted) return;
      final pending = _PendingUpload(
        id: pendingId, localPath: path, type: type, viewOnce: viewOnce,
        isVideoNote: isVideoNote, caption: caption, isVideoForce: isVideoForce,
      );
      _pendingUploads.insert(0, pending);
      _pendingUploadsRevision.value++;

      final fileName = '${DateTime.now().microsecondsSinceEpoch}_$i${isVideo? '.mp4' : '.jpg'}';
      final objectName = 'chat_media/$_chatRoomId/$fileName';
      final r2 = R2Service();

      var sent = false;
      try {
        await _validateChatMediaSize(file, isVideo);
        File fileToUpload = file;
        if (isVideo) {
          fileToUpload = await VideoProcessor.compressChatVideo(path);
        }

        final url = await r2.uploadFile(fileToUpload, objectName);
        if (FirebaseAuth.instance.currentUser?.uid != currentUserId) return;

        final selectedReply = _replyingTo;
        Map<String, dynamic>? replyData;
        if (selectedReply != null) {
          replyData = {
            'messageId': selectedReply['messageId'],
            'text': selectedReply['text'],
            'type': selectedReply['type'],
            'senderId': selectedReply['senderId'],
            'mediaUrl': selectedReply['mediaUrl'],
            ...AudienceMessagePolicy.sourceFields(selectedReply),
          };
        }

        final result = await provider.sendMessageWithReason(
          roomId: _chatRoomId,
          senderId: currentUserId,
          receiverId: widget.viewedUid,
          type: type,
          mediaUrl: url,
          text: caption,
          isFriend: widget.isFriend,
          replyTo: replyData,
          viewOnce: viewOnce, // [عرض مرة واحدة - الخاص]
        );
        if (!result.isSuccess) {
          if (mounted && FirebaseAuth.instance.currentUser?.uid == currentUserId) {
            pending.failed = true;
            _showPrivateSendFailure(result.failureReason, action: 'إرسال الوسائط');
          }
          continue;
        }
        sent = true;
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
        if (selectedReply != null && identical(_replyingTo, selectedReply)) {
          setState(() => _replyingTo = null);
        }
        _scrollToBottom();
      } catch (e) {
        debugPrint('Upload error: $e');
        pending.failed = true;
        if (mounted && FirebaseAuth.instance.currentUser?.uid == currentUserId) {
          _notifyMediaUploadError(e);
        }
      } finally {
        if (mounted) {
          // عند فشل الحفظ، نُبقي الملف المحلي وزر إعادة المحاولة.
          if (sent || FirebaseAuth.instance.currentUser?.uid != currentUserId) {
            _pendingUploads.removeWhere((p) => p.id == pendingId);
          }
          _pendingUploadsRevision.value++;
        }
      }
    }
  }

  // لا نحذف التسجيل المحلي إن فشل الرفع أو رفضت قواعد المراسلة حفظه.
  Future<void> _sendPrivateVoice(String path, Duration duration, List<int> waveform,
      String currentUserId, {_PendingUpload? retryPending}) async {
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
    final pending = retryPending ?? _PendingUpload(
      id: 'voice_${DateTime.now().microsecondsSinceEpoch}', localPath: path,
      type: 'audio', voiceDuration: duration, voiceWaveform: waveform);
    if (retryPending == null) _pendingUploads.insert(0, pending);
    pending.failed = false;
    _pendingUploadsRevision.value++;
    var sent = false;
    try {
      final file = File(path);
      if (!await file.exists()) throw StateError('التسجيل الصوتي غير موجود');
      final compressedFile = await VideoProcessor.compressChatVoice(file);
      final fileName = 'voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      final objectName = 'chat_media/$_chatRoomId/$fileName';
      final url = await R2Service().uploadFile(compressedFile, objectName);
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
      final result = await context.read<ChatProvider>().sendMessageWithReason(
        roomId: _chatRoomId,
        senderId: currentUserId,
        receiverId: widget.viewedUid,
        type: 'audio',
        mediaUrl: url,
        isFriend: widget.isFriend,
        durationSeconds: duration.inSeconds,
        extraData: {'waveform': waveform},
      );
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
      if (!result.isSuccess) {
        pending.failed = true;
        _showPrivateSendFailure(result.failureReason, action: 'إرسال التسجيل الصوتي');
        return;
      }
      sent = true;
      _scrollToBottom();
    } catch (e) {
      debugPrint('Private voice upload error: $e');
      if (mounted && FirebaseAuth.instance.currentUser?.uid == currentUserId) {
        pending.failed = true;
        _showPrivateSendFailure(ChatFailureReason.technicalError, action: 'إرسال التسجيل الصوتي');
      }
    } finally {
      if (mounted) {
        if (sent || FirebaseAuth.instance.currentUser?.uid != currentUserId) {
          _pendingUploads.removeWhere((p) => p.id == pending.id);
        }
        _pendingUploadsRevision.value++;
      }
    }
  }

  Future<void> _sendPrivateLocation(TiniFixedLocation location, String uid) async {
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
    try {
      final result = await context.read<ChatProvider>().sendMessageWithReason(
        roomId: _chatRoomId, senderId: uid,
        receiverId: widget.viewedUid, type: 'location', text: location.url,
        isFriend: widget.isFriend,
        extraData: {'latitude': location.latitude, 'longitude': location.longitude,
          'locationName': location.label},
      );
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      if (result.isSuccess) {
        _scrollToBottom();
      } else {
        _showPrivateSendFailure(result.failureReason, action: 'إرسال الموقع',
          onRetry: () { _sendPrivateLocation(location, uid); });
      }
    } catch (e) {
      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
        _showPrivateSendFailure(ChatFailureReason.technicalError, action: 'إرسال الموقع',
          onRetry: () { _sendPrivateLocation(location, uid); });
      }
    }
  }

  // إظهار المستند أثناء الرفع، مع منع تكرار الرفع وإتاحة إعادة المحاولة.
  Future<void> _uploadPrivateDocument(_PendingUpload pending) async {
    final uploadingUid = FirebaseAuth.instance.currentUser?.uid;
    if (uploadingUid == null || _uploadingPrivateDocuments.contains(pending.id)) return;
    _uploadingPrivateDocuments.add(pending.id);
    if (mounted) setState(() => pending.failed = false);
    try {
      final file = File(pending.localPath);
      final size = await file.length();
      if (size > TiniChatAttachments.maxDocumentBytes) {
        throw StateError('حجم المستند يتجاوز الحد المسموح (50 ميغابايت). يرجى اختيار ملف أصغر.');
      }
      if (size <= 0) throw StateError('المستند فارغ');
      final name = pending.fileName ?? pending.localPath.split(Platform.pathSeparator).last;
      final objectName = 'private_media/$_chatRoomId/doc_${DateTime.now().microsecondsSinceEpoch}_$name';
      final url = await R2Service().uploadDocument(file, objectName);
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uploadingUid) return;
      final result = await context.read<ChatProvider>().sendMessageWithReason(
        roomId: _chatRoomId,
        senderId: uploadingUid,
        receiverId: widget.viewedUid,
        type: 'document', text: name, mediaUrl: url,
        isFriend: widget.isFriend,
        extraData: {'fileSize': size},
      );
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uploadingUid) return;
      if (!result.isSuccess) {
        if (mounted) {
          setState(() => pending.failed = true);
          _showPrivateSendFailure(result.failureReason, action: 'إرسال المستند');
        }
        return;
      }
      if (mounted) {
        setState(() => _pendingUploads.removeWhere((p) => p.id == pending.id));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => pending.failed = true);
        final message = e.toString();
        if (message.contains('50 ميغابايت')) {
          TiniMessagingNotice.showInfo(ScaffoldMessenger.maybeOf(context),
              'حجم المستند يتجاوز الحد المسموح (50 MB). اختر ملفاً أصغر.',
              title: 'حجم المستند غير صالح');
        } else {
          TiniMessagingNotice.showTechnicalError(
              ScaffoldMessenger.maybeOf(context), 'تعذّر إرسال المستند',
              description: 'تعذّر إرسال المستند. يمكنك إعادة المحاولة.');
        }
      }
    } finally {
      _uploadingPrivateDocuments.remove(pending.id);
    }
  }

  // رفع عدة وسائط ثم حفظها برسالة واحدة، مع الإبقاء على إرسال العنصر الواحد كما هو.
  Future<void> _sendPrivateMediaAlbum(List<Map<String, dynamic>> items) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!mounted || uid == null || items.isEmpty) return;
    if (items.length == 1 || items.any((e) => e['viewOnce'] == true || e['isVideoNote'] == true)) {
      for (final item in items) {
        final path = item['path']?.toString();
        if (path != null) await _sendMediaMessages([path], uid, viewOnce: item['viewOnce'] == true, isVideoNote: item['isVideoNote'] == true, caption: (item['caption'] ?? '').toString(), isVideoForce: item['isVideo'] == true);
      }
      return;
    }
    final provider = context.read<ChatProvider>();
    final uploaded = <Map<String, dynamic>>[];
    final pendingId = 'album_${DateTime.now().microsecondsSinceEpoch}';
    final firstPath = items.first['path'].toString();
    final firstPathLower = firstPath.toLowerCase();
    final firstIsVideo = items.first['isVideo'] == true ||
        firstPathLower.endsWith('.mp4') ||
        firstPathLower.endsWith('.mov') ||
        firstPathLower.endsWith('.avi');
    final pending = _PendingUpload(
      id: pendingId, localPath: firstPath,
      type: firstIsVideo ? 'video' : 'image',
      albumItems: items.map((item) => Map<String, dynamic>.from(item)).toList(growable: false),
    );
    if (mounted) setState(() => _pendingUploads.insert(0, pending));
    var sent = false;
    try {
      for (var i = 0; i < items.length; i++) {
        final path = items[i]['path']?.toString() ?? '';
        final file = File(path);
        if (!await file.exists()) throw StateError('الملف غير موجود: $path');
        final lower = path.toLowerCase();
        final isVideo = items[i]['isVideo'] == true || lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi');
        await _validateChatMediaSize(file, isVideo);
        final ext = isVideo ? '.mp4' : (lower.endsWith('.png') ? '.png' : lower.endsWith('.webp') ? '.webp' : lower.endsWith('.gif') ? '.gif' : '.jpg');
        final objectName = 'chat_media/$_chatRoomId/album_${DateTime.now().microsecondsSinceEpoch}_$i$ext';
        final upload = isVideo ? await VideoProcessor.compressChatVideo(path) : file;
        final url = await R2Service().uploadFile(upload, objectName);
        if (FirebaseAuth.instance.currentUser?.uid != uid) return;
        uploaded.add({'url': url, 'isVideo': isVideo, 'caption': (items[i]['caption'] ?? '').toString()});
      }
      Map<String, dynamic>? replyData;
      if (_replyingTo != null) {
        replyData = {
          'messageId': _replyingTo!['messageId'],
          'text': _replyingTo!['text'],
          'type': _replyingTo!['type'],
          'senderId': _replyingTo!['senderId'],
          'mediaUrl': _replyingTo!['mediaUrl'],
        ...AudienceMessagePolicy.sourceFields(_replyingTo!),
        };
      }
      final selectedReply = _replyingTo;
      final result = await provider.sendMessageWithReason(
        roomId: _chatRoomId, senderId: uid, receiverId: widget.viewedUid,
        type: 'album', isFriend: widget.isFriend, replyTo: replyData,
        text: items.map((e) => (e['caption'] ?? '').toString()).where((s) => s.isNotEmpty).join(' '),
        extraData: {'mediaItems': uploaded},
      );
      if (!result.isSuccess) {
        if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
          pending.failed = true;
          _showPrivateSendFailure(result.failureReason, action: 'إرسال مجموعة الوسائط');
        }
        return;
      }
      sent = true;
      if (mounted && replyData != null && identical(_replyingTo, selectedReply)) {
        setState(() => _replyingTo = null);
      }
      _scrollToBottom();
    } catch (e) {
      debugPrint('Private album upload error: $e');
      pending.failed = true;
      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
        if (e.toString().contains('250 MB') || e.toString().contains('25 MB')) {
          _notifyMediaUploadError(e);
        } else {
          _showPrivateSendFailure(ChatFailureReason.technicalError, action: 'إرسال مجموعة الوسائط');
        }
      }
    } finally {
      if (mounted) {
        if (sent || FirebaseAuth.instance.currentUser?.uid != uid) {
          _pendingUploads.removeWhere((p) => p.id == pendingId);
        }
        _pendingUploadsRevision.value++;
      }
    }
  }

  // ===== [عرض مرة واحدة - الدردشات الخاصة] =====
  void _viewOnceSnack(String message) {
    if (!mounted) return;
    TiniMessagingNotice.showInfo(ScaffoldMessenger.maybeOf(context), message);
  }

  Future<void> _openPrivateViewOnce(String messageId, Map<String, dynamic> message, bool isMe) async {
    if (_openingViewOnce || !AudienceMessagePolicy.canView(message)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final url = message['mediaUrl'] as String?;
    final viewed = List<String>.from(message['viewedBy'] ?? []);
    if (isMe) {
      _viewOnceSnack('لا يمكنك فتح رسالة العرض مرة واحدة التي أرسلتها');
      return;
    }
    if (url == null || url.isEmpty || message['mediaDeleted'] == true || viewed.contains(uid)) {
      _viewOnceSnack('تم فتح هذه الرسالة مسبقاً');
      return;
    }
    _openingViewOnce = true;
    try {
      final agreed = await showViewOnceIntro(context);
      if (!agreed || !mounted || !AudienceMessagePolicy.canView(message)) return;
      final provider = Provider.of<ChatProvider>(context, listen: false);
      // [عرض مرة واحدة - الخاص] نبدأ تهيئة الفيديو بالتوازي مع تسجيل المشاهدة.
      // لا نعرض أي إطار قبل نجاح claimViewOnce.
      final isVideo = message['type'] == 'video';
      final preparedVideo = isVideo
          ? VideoPlayerController.networkUrl(Uri.parse(url))
          : null;
      final preparation = preparedVideo?.initialize();
      // نمسك فشل التهيئة هنا حتى لا يظهر خطأ غير معالج أثناء انتظار Firebase.
      final safePreparation = preparation?.then<bool>((_) => true).catchError((_) => false);
      bool handedToViewer = false;
      try {
        final claimed = await provider.claimViewOnce(roomId: _chatRoomId, messageId: messageId);
        if (!claimed) {
          _viewOnceSnack('تعذر فتح الرسالة');
          return;
        }
        try {
          if (!mounted || !AudienceMessagePolicy.canView(message)) return;
          handedToViewer = true;
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AudienceMessageGate(message: message,
              child: ViewOnceViewerScreen(
              url: url,
              isVideo: isVideo,
              senderName: widget.displayFullName,
              preparedVideo: preparedVideo,
              preparedVideoReady: safePreparation,
            ))),
          );
        } finally {
          await provider.cleanupViewOnce(roomId: _chatRoomId, messageId: messageId);
        }
      } finally {
        if (!handedToViewer && preparedVideo != null) {
          await safePreparation;
          await preparedVideo.dispose();
        }
      }
    } catch (e) {
      debugPrint('Private view once error: $e');
      _viewOnceSnack('تعذر فتح الرسالة');
    } finally {
      _openingViewOnce = false;
    }
  }

  Widget _buildPrivateViewOnceContent(Map<String, dynamic> message, bool isMe, Color defaultColor) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final viewed = List<String>.from(message['viewedBy'] ?? []);
    final gone = message['mediaUrl'] == null || message['mediaUrl'] == '' || message['mediaDeleted'] == true;
    final consumed = gone || (isMe ? viewed.isNotEmpty : viewed.contains(uid));
    final label = consumed ? 'تم فتحها' : (message['type'] == 'video' ? 'مقطع فيديو' : 'صورة');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? defaultColor : const Color(0xFF1A222C),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ViewOnceIcon(size: 24, color: consumed ? Colors.white54 : Colors.white),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(
              color: consumed ? Colors.white70 : Colors.white,
              fontSize: 15,
              fontStyle: consumed ? FontStyle.italic : FontStyle.normal,
            )),
          ],
        ),
      ),
    );
  }

  void _openMediaViewer(String url, String type,
      {Map<String, dynamic>? source}) {
    final message = source ?? {'mediaUrl': url, 'type': type};
    if (!AudienceMessagePolicy.canView(message)) return;
    if (type == 'image') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudienceMessageGate(message: message,
            child: ImageViewerScreen(imageUrl: url, source: message)),
        ),
      );
    } else if (type == 'video') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudienceMessageGate(message: message,
            child: VideoViewerScreen(videoUrl: url, source: message)),
        ),
      );
    }
  }

  void _startReply(String messageId, Map<String, dynamic> message) {
    if (!AudienceMessagePolicy.canView(message)) return;
    setState(() {
      _replyingTo = {
        'messageId': messageId,
        'text': message['text'],
        'type': message['type'],
        'senderId': message['senderId'],
        'mediaUrl': message['mediaUrl'],
        ...AudienceMessagePolicy.sourceFields(message),
      };
    });
    // Keep the keyboard open while choosing a message to reply to.
  }

  // Forward recipients: recent conversations, mutual friends, and searchable users.
  // Do not query the first 30 unrelated users from the entire application.
  Future<List<Map<String, String>>> _loadForwardRecipients(String uid) async {
    final firestore = FirebaseFirestore.instance;
    final recipients = <String, Map<String, String>>{};
    final roomSnap = await firestore.collection('chat_rooms')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageTime', descending: true)
        .limit(80).get();
    for (final room in roomSnap.docs) {
      final data = room.data();
      final hidden = Map<String, dynamic>.from(data['deletedFor'] ?? {});
      if (hidden[uid] == true) continue;
      final others = List<String>.from(data['participants'] ?? <String>[])
          .where((id) => id != uid);
      if (others.isEmpty) continue;
      final other = others.first;
      final info = Map<String, dynamic>.from(
          Map<String, dynamic>.from(data['participantsInfo'] ?? {})[other] ?? {});
      recipients[other] = {
        'uid': other,
        'name': (info['name'] ?? 'مستخدم').toString(),
        'image': (info['profileImg'] ?? '').toString(),
      };
    }
    // Friends in Tini are mutual followers. Read a bounded set, not every user.
    final userRef = firestore.collection('users').doc(uid);
    final relationResults = await Future.wait([
      userRef.collection('following').limit(100).get(),
      userRef.collection('followers').limit(100).get(),
    ]);
    final followingIds = relationResults[0].docs.map((d) => d.id).toSet();
    final followerIds = relationResults[1].docs.map((d) => d.id).toSet();
    final newFriendIds = followingIds.intersection(followerIds)
        .where((id) => id != uid && !recipients.containsKey(id)).toList();
    // Firestore whereIn is bounded; fetch friends in small chunks.
    for (var offset = 0; offset < newFriendIds.length; offset += 20) {
      final last = offset + 20 < newFriendIds.length ? offset + 20 : newFriendIds.length;
      final batch = newFriendIds.sublist(offset, last);
      final snapshot = await firestore.collection('users')
          .where(FieldPath.documentId, whereIn: batch).get();
      for (final user in snapshot.docs) {
        final data = user.data();
        recipients[user.id] = {
          'uid': user.id,
          'name': (data['fullName'] ?? data['username'] ?? 'مستخدم').toString(),
          'image': (data['profileImg'] ?? '').toString(),
        };
      }
    }
    return recipients.values.toList();
  }

  Future<List<Map<String, String>>> _searchForwardRecipients(String search) async {
    final value = search.trim();
    if (value.length < 3) return [];
    final snapshot = await FirebaseFirestore.instance.collection('users')
        .where('username', isGreaterThanOrEqualTo: value)
        .where('username', isLessThanOrEqualTo: '$value')
        .limit(20).get();
    return snapshot.docs.map((d) => <String, String>{
      'uid': d.id,
      'name': (d.data()['fullName'] ?? d.data()['username'] ?? 'مستخدم').toString(),
      'image': (d.data()['profileImg'] ?? '').toString(),
    }).toList();
  }

  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    if (!AudienceMessagePolicy.canView(message)) return;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final recipientsFuture = _loadForwardRecipients(currentUserId);
    final blocked = context.read<custom.AuthProvider>().blockedUsersSet;
    var search = '';
    Future<List<Map<String, String>>> remoteResults = Future.value([]);
    Timer? debounce;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A222C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.65,
          child: StatefulBuilder(builder: (sheetContext, refresh) {
            return Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'ابحث عن صديق أو اسم مستخدم',
                    hintStyle: TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.search, color: Colors.white54),
                  ),
                  onChanged: (value) {
                    debounce?.cancel();
                    refresh(() { search = value.trim(); });
                    if (search.length >= 3) {
                      debounce = Timer(const Duration(milliseconds: 350), () {
                        if (sheetContext.mounted) {
                          refresh(() => remoteResults = _searchForwardRecipients(search));
                        }
                      });
                    } else {
                      remoteResults = Future.value([]);
                    }
                  },
                ),
              ),
              Expanded(child: FutureBuilder<List<Map<String, String>>>(
                future: recipientsFuture,
                builder: (context, recentSnap) {
                  if (!recentSnap.hasData && !recentSnap.hasError) {
                    return const Center(child: CircularProgressIndicator(color: Colors.teal));
                  }
                  return FutureBuilder<List<Map<String, String>>>(
                    future: remoteResults,
                    builder: (context, remoteSnap) {
                      final recipients = <String, Map<String, String>>{};
                      for (final item in recentSnap.data ?? <Map<String, String>>[]) {
                        recipients[item['uid']!] = item;
                      }
                      for (final item in remoteSnap.data ?? <Map<String, String>>[]) {
                        recipients[item['uid']!] = item;
                      }
                      final q = search.toLowerCase();
                      final filtered = recipients.values.where((entry) {
                        final id = entry['uid'] ?? '';
                        if (id == currentUserId || blocked.contains(id)) return false;
                        return q.isEmpty || id.toLowerCase().contains(q) ||
                            (entry['name'] ?? '').toLowerCase().contains(q);
                      }).toList();
                      if (filtered.isEmpty) {
                        return Center(child: Text(recentSnap.hasError
                            ? 'تعذر تحميل جهات الاتصال'
                            : 'لا توجد نتائج مطابقة',
                            style: const TextStyle(color: Colors.white70)));
                      }
                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          final uid = item['uid']!;
                          final name = item['name'] ?? 'مستخدم';
                          final img = item['image'] ?? '';
                          return ListTile(
                            leading: img.isEmpty
                                ? const CircleAvatar(child: Icon(Icons.person))
                                : CircleAvatar(backgroundImage: CachedNetworkImageProvider(img)),
                            title: Text(name, style: const TextStyle(color: Colors.white)),
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              if (FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
                              // ← السطر المضاف: افحص الصداقة الحقيقية
                              final isForwardFriend = await provider.checkIfFriend(currentUserId, uid);
                              if (!AudienceMessagePolicy.canView(message)) return;
                              final startResult = await provider.startChatWithReason(
                                viewedUid: uid,
                                displayFullName: name,
                                displayProfileImg: img,
                                isFriend: isForwardFriend,
                              );
                              if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
                              if (!startResult.isSuccess || startResult.value == null) {
                                _showPrivateSendFailure(startResult.failureReason, action: 'فتح المحادثة لإعادة التوجيه');
                                return;
                              }
                              if (!AudienceMessagePolicy.canView(message)) return;
                              final result = await provider.sendMessageWithReason(
                                roomId: startResult.value!,
                                senderId: currentUserId,
                                receiverId: uid,
                                type: message['type'],
                                text: message['text'],
                                mediaUrl: message['mediaUrl'],
                                extraData: AudienceMessagePolicy.sourceFields(message),
                                isFriend: isForwardFriend,
                              );
                              if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
                              if (result.isSuccess) {
                                TiniMessagingNotice.showSuccess(
                                    ScaffoldMessenger.maybeOf(this.context),
                                    'تمت إعادة التوجيه');
                              } else {
                                _showPrivateSendFailure(result.failureReason, action: 'إعادة التوجيه');
                              }
                            },
                          );
                        },
                      );
                    },
                  );
                },
              )),
            ]);
          }),
        ),
      ),
    );
    debounce?.cancel();
  }

  Future<void> _createSticker(String? mediaUrl) async {
    if (mediaUrl == null) return;
    try {
      final res = await http.get(Uri.parse(mediaUrl));
      final dir = await getTemporaryDirectory();
      // Preserve the original image format (especially PNG transparency).
      final sourcePath = Uri.parse(mediaUrl).path.toLowerCase();
      final extension = sourcePath.endsWith('.png') ? 'png'
          : sourcePath.endsWith('.webp') ? 'webp'
          : sourcePath.endsWith('.gif') ? 'gif' : 'jpg';
      final file = File('${dir.path}/sticker_${DateTime.now().millisecondsSinceEpoch}.$extension');
      await file.writeAsBytes(res.bodyBytes);
      await Gal.putImage(file.path, album: 'Stickers');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء الملصق'), backgroundColor: Color(0xFF009688)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إنشاء الملصق: $e')),
        );
      }
    }
  }

  Future<void> _changeBubbleStyle(String messageId) async {
    final colors = [
      const Color(0xFF009688),
      const Color(0xFF3F51B5),
      const Color(0xFFE91E63),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A222C),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: colors.map((c) => GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(_chatRoomId)
          .collection('messages')
          .doc(messageId)
          .update({'bubbleColor': c.value});
                },
                child: CircleAvatar(backgroundColor: c, radius: 24),
              )).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showMessageOptions(BuildContext context, {
    required String type,
    String? text,
    String? mediaUrl,
    required String messageId,
    required bool isMe,
    required Map<String, dynamic> messageData,
  }) {
    final emojis = ['🤔','😡','😭','😂','❤','👍'];
    const Color olive = Color(0xFF0F1720);
    const Color titiTeal = Color(0xFF009688);

    if (!AudienceMessagePolicy.canView(messageData)) return;
    if (messageData['viewOnce'] == true) return; // [عرض مرة واحدة] بلا مشاركة أو حفظ أو رد
    final isMedia = type == 'image' || type == 'video';

    final List<Map<String, dynamic>> options = isMedia
? [
            {'title': 'رد', 'icon': Icons.reply},
            {'title': 'إعادة توجيه', 'icon': Icons.forward},
            {'title': 'إنشاء ملصق', 'icon': Icons.content_cut},
            {'title': 'حذف لدي', 'icon': Icons.delete},
          ]
      : [
            {'title': 'رد', 'icon': Icons.reply},
            {'title': 'إعادة توجيه', 'icon': Icons.forward},
            {'title': 'نسخ', 'icon': Icons.copy},
            {'title': 'نمط الفقاعة', 'icon': Icons.palette_outlined},
            {'title': 'حذف لدي', 'icon': Icons.delete},
          ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: emojis.map((e) => GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                        if (currentUserId == null) return;
                        await FirebaseFirestore.instance
                .collection('chat_rooms')
                .doc(_chatRoomId)
                .collection('messages')
                .doc(messageId)
                .update({'reactions.$currentUserId': e});
                      },
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: olive,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: options.map((opt) => Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: Icon(opt['icon'] as IconData, color: titiTeal),
                        title: Text(opt['title'] as String, textAlign: TextAlign.right, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white)),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final title = opt['title'] as String;
                          if (title != 'حذف لدي' && !AudienceMessagePolicy.canView(messageData)) return;
                          if (title == 'نسخ' && text!= null) {
                            await Clipboard.setData(ClipboardData(text: text));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم النسخ'), backgroundColor: titiTeal),
                              );
                            }
                          } else if (title == 'حذف لدي') {
                            await FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(_chatRoomId)
                  .collection('messages')
                  .doc(messageId)
                  .delete();
                          } else if (title == 'رد') {
                            _startReply(messageId, messageData);
                          } else if (title == 'إعادة توجيه') {
                            _forwardMessage(messageData);
                          } else if (title == 'إنشاء ملصق') {
                            _createSticker(mediaUrl);
                          } else if (title == 'نمط الفقاعة') {
                            _changeBubbleStyle(messageId);
                          }
                        },
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingTo == null) return const SizedBox.shrink();
    return AudienceMessageGate(message: _replyingTo!,
      child: Builder(builder: (_) => _buildReplyPreviewAllowed()));
  }

  Widget _buildReplyPreviewAllowed() {
    if (_replyingTo == null) return const SizedBox.shrink();
    final type = _replyingTo!['type'];
    final text = _replyingTo!['text']?? '';
    final mediaUrl = _replyingTo!['mediaUrl'] as String?;
    final isMedia = type == 'image' || type == 'video';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1720),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Color(0xFF009688), width: 3)),
      ),
      child: Row(
        children: [
          if (isMedia && mediaUrl!= null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 40,
                height: 40,
                child: type == 'image'
        ? Image.network(mediaUrl, width: 40, height: 40, fit: BoxFit.cover)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoThumbnail(videoUrl: mediaUrl),
                        Container(color: Colors.black26),
                        const Icon(Icons.play_arrow, color: Colors.white70, size: 20),
                      ],
                    ),
              ),
            ),
          if (isMedia && mediaUrl!= null) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('رد على', style: TextStyle(color: Color(0xFF009688), fontSize: 12)),
                Text(isMedia? 'صورة / فيديو' : text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(Map<String, dynamic> message, bool isMe, Color defaultColor) {
    return AudienceMessageGate(message: message,
      child: Builder(builder: (_) => _buildMessageContentAllowed(message, isMe, defaultColor)));
  }

  Widget _buildMessageContentAllowed(Map<String, dynamic> message, bool isMe, Color defaultColor) {
    final String? mediaUrl = message['mediaUrl'] as String?;
    final String type = message['type']?? 'text';
    final String? text = message['text'] as String?;
    final int? bubbleColor = message['bubbleColor'] as int?;
    final Color bubble = bubbleColor!= null? Color(bubbleColor) : defaultColor;

    if (message['viewOnce'] == true && (type == 'image' || type == 'video')) {
      return _buildPrivateViewOnceContent(message, isMe, defaultColor);
    }

    Widget content;
    if (type == 'location' || type == 'document') {
      content = TiniChatAttachments.message(type: type, text: (message['text'] ?? '').toString(), mediaUrl: mediaUrl);
    } else if (type == 'album' && message['mediaItems'] is List) {
      final items = (message['mediaItems'] as List).whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)).toList();
      content = ChatAlbumGrid(items: items);
    } else if (mediaUrl!= null && type == 'image') {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          mediaUrl,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 200,
              height: 200,
              color: const Color(0xFF1A222C),
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF009688), strokeWidth: 2)),
            );
          },
        ),
      );
    } else if (mediaUrl!= null && type == 'video') {
      content = Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF1A222C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 200,
                height: 200,
                child: VideoThumbnail(videoUrl: mediaUrl),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
            ),
          ],
        ),
      );
    } else if (mediaUrl!= null && type == 'audio') {
      final durSec = message['durationSeconds'] as int? ?? 0;
      // احنا هون بس بنرجع content فاضي لأن البناء الحقيقي صار برا عشان ناخد timeString و isSeen
      content = const SizedBox.shrink();
        } else if (type == 'profile_share') {
      final profileUid = message['profileUid'] as String?;
      final profileImg = message['profileImg'] as String?;
      final profileName = message['profileName'] as String?;
      final profileUsername = message['profileUsername'] as String?;
      content = GestureDetector(
        onTap: () {
          if (profileUid == null || profileUid.isEmpty) return;
          UserProfileSheet.show(
            context,
            uid: profileUid,
            fullName: profileName ?? 'مستخدم',
            username: profileUsername ?? '',
            profileImg: profileImg ?? '',
            isFollowing: false,
            onFollowTap: () {},
          );
        },
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A222C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF009688), width: 1),
          ),
          child: Column(
            children: [
                            profileImg!= null && profileImg.isNotEmpty
                 ? CachedNetworkImage(
                      imageUrl: profileImg,
                      cacheKey: profileImg,
                      imageBuilder: (context, imageProvider) => CircleAvatar(radius: 28, backgroundImage: imageProvider, backgroundColor: Colors.white10),
                      placeholder: (context, url) => const CircleAvatar(radius: 28, backgroundColor: Colors.white10),
                      errorWidget: (context, url, error) => CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white10,
                        child: Text(profileName!= null && profileName.isNotEmpty? profileName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                    )
                  : CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white10,
                      child: Text(profileName!= null && profileName.isNotEmpty? profileName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
              const SizedBox(height: 8),
              Text(
                profileName?? 'مستخدم',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '@${profileUsername?? ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF009688),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'عرض الملف الشخصي',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      content = Text(
        text?? "",
        style: const TextStyle(color: Colors.white, fontSize: 16),
      );
    }

    // [تنسيق وسائط الخاص] عرض الوسائط والشرح ضمن عرض مدمج ثابت الحد الأعلى.
    // لا نغيّر الرسائل النصية أو الصوتية أو ملاحظات الفيديو أو العرض مرة واحدة.
    final bool isRegularMedia = type == 'album' ||
        (mediaUrl != null && (type == 'image' || type == 'video'));
    if (isRegularMedia) {
      content = SizedBox(
        width: type == 'album' ? 230 : 200,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: content,
            ),
            if (text != null && text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _PrivateMediaCaption(text: text),
              ),
          ],
        ),
      );
    }

    final reply = message['replyTo'] as Map<String, dynamic>?;
    Widget replyWidget = const SizedBox.shrink();
    if (reply!= null) {
      final rType = reply['type'];
      final rText = reply['text']?? '';
      final rMedia = reply['mediaUrl'] as String?;
      final rIsMedia = rType == 'image' || rType == 'video';
      replyWidget = Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: const Border(left: BorderSide(color: Colors.white54, width: 2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rIsMedia && rMedia!= null)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: rType == 'image'
          ? Image.network(rMedia, width: 32, height: 32, fit: BoxFit.cover)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoThumbnail(videoUrl: rMedia),
                          Container(color: Colors.black26),
                          const Icon(Icons.play_arrow, color: Colors.white70, size: 18),
                        ],
                      ),
                ),
              ),
            if (rIsMedia && rMedia!= null) const SizedBox(width: 6),
            Flexible(
              child: Text(
                rIsMedia? 'صورة / فيديو' : rText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      );
      replyWidget = AudienceMessageGate(message: reply, child: replyWidget);
    }

    return Container(
      padding: isRegularMedia || mediaUrl != null
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: isMe? bubble : const Color(0xFF1A222C),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isRegularMedia && isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          replyWidget,
          content,
        ],
      ),
    );
  }

  Widget _buildReactionsWidget(Map<String, dynamic> reactions) {
    const Color surfaceCard = Color(0xFF1A222C);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: reactions.entries.map((entry) {
          final uid = entry.key;
          final emoji = entry.value.toString();
          final info = _participantsInfo[uid] as Map<String, dynamic>?;
          final img = info?['profileImg'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                                if (img.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: img,
                    cacheKey: img,
                    imageBuilder: (context, imageProvider) => CircleAvatar(radius: 8, backgroundImage: imageProvider),
                    placeholder: (context, url) => const CircleAvatar(radius: 8, backgroundColor: Colors.white10),
                    errorWidget: (context, url, error) => const CircleAvatar(radius: 8, backgroundColor: Colors.white10),
                  ),
                const SizedBox(width: 2),
                Text(emoji, style: const TextStyle(fontSize: 14)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color bgDark = Color(0xFF0F1720);
    const Color surfaceCard = Color(0xFF1A222C);
    const Color titiTeal = Color(0xFF009688);
    const Color textGrey = Color(0xFF9E9E9E);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _messagePager == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1720),
        body: Center(child: Text('يرجى تسجيل الدخول', style: TextStyle(color: Colors.white))),
      );
    }
    final String currentUserId = currentUser.uid;

    return Scaffold(
      backgroundColor: bgDark,
appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            }
          },
        ),
        title: InkWell(
          onTap: _showProfileSheet,
          child: Row(
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: _storiesStream,
                builder: (context, snap) {
                  final docs = snap.data?.docs?? [];
                  final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
                  final hasStories = docs.isNotEmpty;
                  final hasUnviewed = docs.any((d) {
                    final viewedBy = List<String>.from(d['viewedBy']?? []);
                    return!viewedBy.contains(currentUid);
                  });
                  final bool hasImage = widget.displayProfileImg.isNotEmpty;
                  final String initial = widget.displayFullName.isNotEmpty? widget.displayFullName[0].toUpperCase() : '?';
                  if (hasStories) {
                    return StoryRing(
                      imageUrl: widget.displayProfileImg,
                      size: 36,
                      hasStories: true,
                      hasUnviewed: hasUnviewed,
                      heroTag: 'chat-avatar-${widget.viewedUid}',
                    );
                  } else if (hasImage) {
                    return CachedNetworkImage(
                      imageUrl: widget.displayProfileImg,
                      cacheKey: widget.displayProfileImg,
                      useOldImageOnUrlChange: false,
                      imageBuilder: (context, imageProvider) => CircleAvatar(radius: 18, backgroundImage: imageProvider),
                      placeholder: (context, url) => const CircleAvatar(radius: 18, backgroundColor: Color(0xFF1A222C)),
                      errorWidget: (context, url, error) => CircleAvatar(radius: 18, backgroundColor: Color(0xFF1A222C), child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    );
                  } else {
                    return CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF1A222C),
                      child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    );
                  }
                },
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.displayFullName, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  FutureBuilder<bool>(
                    future: _mutualFriendFuture,
                    builder: (context, friendSnap) {
                      if (friendSnap.data!= true) return const SizedBox.shrink();
                      return StreamBuilder<DocumentSnapshot>(
                        stream: _peerStatusStream,
                        builder: (context, targetSnap) {
                          if (!targetSnap.hasData ||!targetSnap.data!.exists) return const SizedBox.shrink();
                          final targetData = targetSnap.data!.data();
                          if (targetData is! Map<String, dynamic>) return const SizedBox.shrink();
                          final bool targetShow = targetData['showActivityStatus']?? true;
                          final bool isOnline = targetData['isOnline']?? false;
                          final Timestamp? lastSeen = targetData['lastSeen'] as Timestamp?;
                          return StreamBuilder<DocumentSnapshot>(
                            stream: _myStatusStream,
                            builder: (context, mySnap) {
                              final myData = mySnap.data?.data() as Map<String, dynamic>?;
                              final bool myShow = myData?['showActivityStatus']?? true;
                              if (!ActivityStatusService.canViewStatus(myShowActivity: myShow, targetShowActivity: targetShow)) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                ActivityStatusService.formatLastSeenFromTimestamp(lastSeen, isOnline),
                                style: TextStyle(
                                  color: isOnline? Colors.greenAccent : Colors.white54,
                                  fontSize: 11,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        // [جديد] 3 نقاط عمودية - مع تحذير قبل إلغاء الحظر
        actions: [
          Consumer<custom.AuthProvider>(
            builder: (context, auth, _) {
              final bool isBlocked = auth.blockedUsersSet.contains(widget.viewedUid) || auth.isBlocked(widget.viewedUid);
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white), // عمودية
                color: const Color(0xFF1A222C),
                onSelected: (value) async {
                  if (value == 'media') {
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PrivateChatMediaScreen(roomId: _chatRoomId),
                      ),
                    );
                    return;
                  }
                  if (value == 'block') {
                    if (isBlocked) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: const Color(0xFF1A222C),
                          title: Text('إلغاء حظر ${widget.displayFullName}؟', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          content: Text('هل أنت متأكد من إلغاء حظر ${widget.displayFullName}؟', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد', style: TextStyle(color: Color(0xFF009688), fontWeight: FontWeight.bold))),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      await BlockService.unblockUser(widget.viewedUid, context: context);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم إلغاء حظر ${widget.displayFullName}'),
                            backgroundColor: const Color(0xFF009688),
                          ),
                        );
                      }
                    } else {
                      await BlockService.blockUser(context, widget.viewedUid);
                    }
                  }
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                itemBuilder: (ctx) => [
                  const PopupMenuItem<String>(
                    value: 'media',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.perm_media_outlined, color: Color(0xFF009688), size: 20),
                        SizedBox(width: 12),
                        Text('الوسائط', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem<String>(
                    value: 'block',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isBlocked ? Icons.lock_open : Icons.block, color: const Color(0xFFE53935), size: 20),
                        const SizedBox(width: 12),
                        Text(isBlocked ? 'إلغاء الحظر' : 'حظر',
                          style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            bottom: _composerHeight,
            child: Column(
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: _roomStream,
                  builder: (context, snap) {
                    if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
                    final data = snap.data!.data();
                    if (data is! Map<String, dynamic>) return const SizedBox.shrink();
                    final bool isReq = data['isRequest'] ?? false;
                    final String lastSender = data['lastMessageSenderId'] ?? '';
                    final bool isMeSender = lastSender == currentUserId;
                    final bool isMeReceiver = lastSender != '' && !isMeSender;
                    final bool canSend = (data['canSendMore'] ?? {})[currentUserId] ?? true;
                    final bool amIFriend = (data['participantsInfo'] ?? {})[currentUserId]?['isFriend'] ?? false;

                    if (isReq && isMeSender && !canSend && !amIFriend) {
                      return Container(
                        width: double.infinity,
                        color: const Color(0xFF1A222C),
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          'لا يمكنك إرسال المزيد من الرسائل حتى يوافق الطرف الآخر على طلبك أو يقوم بالرد عليك',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      );
                    }

                    if (isReq && isMeReceiver && !amIFriend) {
                      return Container(
                        width: double.infinity,
                        color: const Color(0xFF1A222C),
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          'إذا قمت بالموافقة أو الرد على الرسالة، سيتمكن المرسل من مراسلتك',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      );
                    }

                    return const SizedBox.shrink();
                  },
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_messagePager!, _pendingUploadsRevision]),
                    builder: (context, _) {
                      final pager = _messagePager!;
                      if (!pager.initialized) {
                        return const Center(child: CircularProgressIndicator(color: titiTeal));
                      }
                      if (pager.error != null && pager.documents.isEmpty) {
                        return Center(child: Text('تعذر تحميل الرسائل', style: TextStyle(color: titiTeal)));
                      }

                      final messages = pager.documents;
                      if (messages.isNotEmpty) {
                        var hasUnseen = false;
                        for (final d in messages) {
                          final data = d.data();
                          if (data['senderId'] != currentUserId &&
                              (data['isSeen'] == false || data['seen'] == false) &&
                              _handledOpenChatReads.add(d.id)) {
                            hasUnseen = true;
                          }
                        }
                        if (hasUnseen) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            Provider.of<ChatProvider>(context, listen: false).markAsRead(_chatRoomId, currentUserId);
                          });
                        }
                      }
                      final pendingCount = _pendingUploads.length;
                      final totalCount = messages.length + pendingCount + (pager.hasMore || pager.isLoadingMore ? 1 : 0);

                      return ListView.builder(
                        key: ValueKey(_chatRoomId),
                        controller: _scrollController,
                        reverse: true,
                        padding: EdgeInsets.zero,
                        itemCount: totalCount,
                        itemBuilder: (context, index) {
                          if (index < pendingCount) {
                            final pending = _pendingUploads[index];
                            if (pending.type == 'document') {
                              final isUploading = _uploadingPrivateDocuments.contains(pending.id);
                              return Padding(
                                key: ValueKey(pending.id),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 265),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: titiTeal.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(15)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.insert_drive_file_outlined, color: Colors.white),
                                      const SizedBox(width: 10),
                                      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                        Text(pending.fileName ?? 'مستند', maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white)),
                                        const SizedBox(height: 5),
                                        if (pending.failed)
                                          TextButton.icon(
                                            onPressed: isUploading ? null : () => _uploadPrivateDocument(pending),
                                            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                                            label: const Text('فشل الإرسال - إعادة المحاولة', style: TextStyle(color: Colors.white, fontSize: 12)),
                                          )
                                        else
                                          const Row(mainAxisSize: MainAxisSize.min, children: [
                                            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                            SizedBox(width: 8),
                                            Text('جارٍ رفع المستند...', style: TextStyle(color: Colors.white, fontSize: 12)),
                                          ]),
                                      ])),
                                    ]),
                                  ),
                                ),
                              );
                            }
                            if (pending.type == 'audio') {
                              return Padding(
                                key: ValueKey(pending.id),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 270),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: titiTeal.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(15)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.mic, color: Colors.white),
                                      const SizedBox(width: 10),
                                      Flexible(child: pending.failed
                                        ? TextButton.icon(
                                            onPressed: () {
                                              final uid = FirebaseAuth.instance.currentUser?.uid;
                                              if (uid != null && pending.voiceDuration != null && pending.voiceWaveform != null) {
                                                _sendPrivateVoice(pending.localPath,
                                                  pending.voiceDuration!, pending.voiceWaveform!, uid,
                                                  retryPending: pending);
                                              }
                                            },
                                            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                                            label: const Text('فشل الإرسال - إعادة المحاولة',
                                              style: TextStyle(color: Colors.white, fontSize: 12)),
                                          )
                                        : const Text('جارٍ إرسال التسجيل الصوتي...',
                                            style: TextStyle(color: Colors.white, fontSize: 12))),
                                      if (pending.failed) IconButton(
                                        tooltip: 'إزالة التسجيل',
                                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                                        onPressed: () {
                                          _pendingUploads.removeWhere((p) => p.id == pending.id);
                                          _pendingUploadsRevision.value++;
                                        },
                                      ),
                                    ]),
                                  ),
                                ),
                              );
                            }
                            final bool isVideo = pending.type == 'video' || pending.type == 'video_note';
                            Widget preview;
                            if (isVideo) {
                              preview = Container(
                                width: 200,
                                height: 200,
                                color: surfaceCard,
                                child: const Icon(Icons.videocam, color: Colors.white54, size: 40),
                              );
                            } else {
                              preview = Image.file(
                                File(pending.localPath),
                                width: 200,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 200,
                                  height: 200,
                                  color: surfaceCard,
                                  child: const Icon(Icons.image_not_supported_outlined,
                                      color: Colors.white54, size: 40),
                                ),
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: titiTeal.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: preview,
                                          ),
                                          Container(
                                            width: 200,
                                            height: 200,
                                            decoration: BoxDecoration(
                                              color: Colors.black45,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: pending.failed
                                              ? Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    TextButton.icon(
                                                      onPressed: () async {
                                                        final uid = FirebaseAuth.instance.currentUser?.uid;
                                                        if (uid == null) return;
                                                        _pendingUploads.removeWhere((p) => p.id == pending.id);
                                                        _pendingUploadsRevision.value++;
                                                        if (pending.albumItems != null) {
                                                          await _sendPrivateMediaAlbum(pending.albumItems!);
                                                        } else {
                                                          await _sendMediaMessages([pending.localPath], uid,
                                                            viewOnce: pending.viewOnce,
                                                            isVideoNote: pending.isVideoNote,
                                                            caption: pending.caption,
                                                            isVideoForce: pending.isVideoForce);
                                                        }
                                                      },
                                                      icon: const Icon(Icons.refresh, color: Colors.white),
                                                      label: const Text('إعادة المحاولة',
                                                        style: TextStyle(color: Colors.white)),
                                                    ),
                                                    TextButton(
                                                      onPressed: () {
                                                        _pendingUploads.removeWhere((p) => p.id == pending.id);
                                                        _pendingUploadsRevision.value++;
                                                      },
                                                      child: const Text('إزالة',
                                                        style: TextStyle(color: Colors.white70)),
                                                    ),
                                                  ],
                                                )
                                              : const Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    CircularProgressIndicator(color: Colors.white),
                                                    SizedBox(height: 8),
                                                    Text('جاري الإرسال...', style: TextStyle(color: Colors.white, fontSize: 12)),
                                                  ],
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text('الآن', style: TextStyle(color: textGrey, fontSize: 10)),
                                  ],
                                ),
                              ),
                            );
                          }

                          if (index >= pendingCount + messages.length) {
                            return SizedBox(
                              height: 60,
                              child: Center(
                                child: pager.isLoadingMore
                                    ? const CircularProgressIndicator(color: titiTeal, strokeWidth: 2)
                                    : TextButton(
                                        onPressed: pager.loadOlder,
                                        child: const Text('تحميل رسائل أقدم', style: TextStyle(color: titiTeal)),
                                      ),
                              ),
                            );
                          }
                          final messageIndex = index - pendingCount;
                          final doc = messages[messageIndex];
                          final message = doc.data() as Map<String, dynamic>;
                          final String messageId = doc.id;
                          final bool isMe = message['senderId'] == currentUserId;

                          Timestamp? timestamp = message['timestamp'] as Timestamp?;
                          String timeString = timestamp != null
                              ? DateFormat('hh:mm a').format(timestamp.toDate())
                              : "";

                          final String? mediaUrl = message['mediaUrl'] as String?;
                          final String type = message['type'] ?? 'text';

                          final reactionsMap = message['reactions'] as Map<String, dynamic>?;

                          return Padding(
                            key: ValueKey(messageId),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            child: Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Builder(
                                    builder: (context) {
                                      final bool isAudio = type == 'audio' && mediaUrl != null;
                                      final bool isVideoNote = type == 'video_note' && mediaUrl != null;
                                      final bool isSeen = message['isSeen'] == true || message['seen'] == true;
                                      final int durSec = message['durationSeconds'] as int? ?? 0;

                                      if (isAudio) {
                                        return GestureDetector(
                                          onLongPress: () => _showMessageOptions(
                                            context,
                                            type: type,
                                            text: message['text'],
                                            mediaUrl: mediaUrl,
                                            messageId: messageId,
                                            isMe: isMe,
                                            messageData: message,
                                          ),
                                          child: VoiceMessageBubble(
                                            audioUrl: mediaUrl!,
                                            profileImgUrl: isMe ? (_participantsInfo[currentUserId]?['profileImg'] ?? '') : widget.displayProfileImg,
                                            isMe: isMe,
                                            duration: Duration(seconds: durSec),
                                            timeText: timeString,
                                            isSeen: isSeen,
                                            chatId: 'private_$_chatRoomId',
                                            waveform: (message['waveform'] as List?)?.map((e) => (e as num).toInt()).toList(),
                                            sortTime: timestamp?.toDate(),
                                          ),
                                        );
                                      }

                                      if (isVideoNote) {
                                        return GestureDetector(
                                          onLongPress: () => _showMessageOptions(
                                            context,
                                            type: type,
                                            text: message['text'],
                                            mediaUrl: mediaUrl,
                                            messageId: messageId,
                                            isMe: isMe,
                                            messageData: message,
                                          ),
                                          child: VideoNoteBubble(
                                            key: ValueKey(messageId),
                                            videoUrl: mediaUrl!,
                                            durationSeconds: durSec,
                                            timeText: timeString,
                                            isMe: isMe,
                                            isSeen: isSeen,
                                          ),
                                        );
                                      }

                                      return GestureDetector(
                                        onLongPress: message['viewOnce'] == true ? null : () => _showMessageOptions(
                                          context,
                                          type: type,
                                          text: message['text'],
                                          mediaUrl: mediaUrl,
                                          messageId: messageId,
                                          isMe: isMe,
                                          messageData: message,
                                        ),
                                        onTap: () {
                                           if (message['viewOnce'] == true && (type == 'image' || type == 'video')) {
                                             _openPrivateViewOnce(messageId, message, isMe);
                                           } else if (mediaUrl != null && (type == 'image' || type == 'video')) {
                                             _openMediaViewer(mediaUrl, type, source: message);
                                           }
                                        },
                                        child: _buildMessageContent(message, isMe, titiTeal),
                                      );
                                    },
                                  ),
                                  if (reactionsMap != null && reactionsMap.isNotEmpty)
                                    _buildReactionsWidget(reactionsMap),
                                  const SizedBox(height: 4),
                                  if (type != 'video_note') Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        timeString,
                                        style: const TextStyle(color: textGrey, fontSize: 10),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        Builder(
                                          builder: (context) {
                                            final bool isSeen = message['isSeen'] == true || message['seen'] == true;
                                            final bool hasDeliveredField = message.containsKey('isDelivered') || message.containsKey('delivered');
                                            final bool isDelivered = message['isDelivered'] == true || message['delivered'] == true || !hasDeliveredField;

                                            if (isSeen) {
                                              return const Icon(Icons.done_all, size: 14, color: Color(0xFF009688));
                                            }
                                            if (isDelivered) {
                                              return const Icon(Icons.done_all, size: 14, color: Color(0xFF9E9E9E));
                                            }
                                            return const Icon(Icons.done, size: 14, color: Color(0xFF9E9E9E));
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
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
                    Consumer<custom.AuthProvider>(
                  builder: (context, auth, _) {
                    final bool isBlocked = auth.blockedUsersSet.contains(widget.viewedUid) || auth.isBlocked(widget.viewedUid);
                    final bool isBlockedBy = auth.blockedBySet.contains(widget.viewedUid);
                    if (!isBlocked && !isBlockedBy) return const SizedBox.shrink();

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A222C),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        children: [
                          Text(
                            isBlocked? 'لقد حظرت هذا الحساب' : 'لا يمكنك مراسلة هذا الحساب',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isBlocked
                            ? 'لن تتمكن من إرسال رسالة إلى ${widget.displayFullName} حتى تقوم بإلغاء حظره.'
                            : 'قد يكون هذا الحساب غير متاح حاليا.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (isBlocked)...[
                                Expanded(
                                  child: TextButton(
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          backgroundColor: const Color(0xFF1A222C),
                                          title: Text('إلغاء حظر ${widget.displayFullName}؟', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                          content: Text('هل أنت متأكد من إلغاء حظر ${widget.displayFullName}؟', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
                                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد', style: TextStyle(color: Color(0xFF009688), fontWeight: FontWeight.bold))),
                                          ],
                                        ),
                                      );
                                      if (confirm != true) return;
                                      await BlockService.unblockUser(widget.viewedUid, context: context);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('تم إلغاء حظر ${widget.displayFullName}'),
                                            backgroundColor: const Color(0xFF009688),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text('إلغاء الحظر', style: TextStyle(color: Color(0xFF009688), fontWeight: FontWeight.bold, fontSize: 15)),
                                  ),
                                ),
                                Container(width: 1, height: 24, color: Colors.white12),
                              ],
                              Expanded(
                                child: TextButton(
                                  onPressed: () async {
                                    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                                    await chatProvider.hideChatRooms([_chatRoomId]);
                                    if (context.mounted) Navigator.pop(context);
                                  },
                                  child: const Text('حذف المحادثة', style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold, fontSize: 15)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Consumer<custom.AuthProvider>(
                  builder: (context, auth, _) {
                    final bool isBlocked = auth.blockedUsersSet.contains(widget.viewedUid) || auth.isBlocked(widget.viewedUid);
                    final bool isBlockedBy = auth.blockedBySet.contains(widget.viewedUid);
                    final bool disabled = isBlocked || isBlockedBy;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyingTo != null)
                          Container(
                            color: surfaceCard,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: _buildReplyPreview(),
                          ),
                        IgnorePointer(
                          ignoring: disabled,
                          child: Opacity(
                            opacity: disabled? 0.4 : 1.0,
                            child: TitiInputBar(
                              textController: _messageController,
                              allowMultiMedia: true,
                              cameraRecipientName: widget.displayFullName,
                              onSendMediaAlbum: _sendPrivateMediaAlbum,
                              onSendVideoNote: (path) async {
                                await _sendPrivateMediaAlbum([{'path': path, 'isVideo': true, 'isVideoNote': true}]);
                              },
                              onSendViewOnce: (path, isVideo) async {
                                await _sendPrivateMediaAlbum([{'path': path, 'isVideo': isVideo, 'viewOnce': true}]);
                              },
                              onSendMedia: (path, caption, isVideo) async {
                                await _sendPrivateMediaAlbum([{'path': path, 'caption': caption, 'isVideo': isVideo}]);
                              },
                              onSendText: (text) {
                                _sendTextMessage(currentUserId, text);
                              },
                              onSendVoice: (path, duration, waveform) async {
                                await _sendPrivateVoice(path, duration, waveform, currentUserId);
                              },
                              onPickLocation: () async {
                                try {
                                  final loc = await TiniChatAttachments.pickLocation(context);
                                  if (loc == null || !mounted || FirebaseAuth.instance.currentUser?.uid != currentUserId) return;
                                  await _sendPrivateLocation(loc, currentUserId);
                                } catch (e) {
                                  if (mounted) _showPrivateSendFailure(ChatFailureReason.technicalError,
                                    action: 'إرسال الموقع');
                                }
                              },
                              onPickDocument: () async {
                                if (_pickingPrivateDocument) return;
                                _pickingPrivateDocument = true;
                                try {
                                  final doc = await TiniChatAttachments.pickDocument();
                                  if (doc == null || !mounted) return;
                                  if (doc.path == null) {
                                    TiniMessagingNotice.showInfo(
                                        ScaffoldMessenger.maybeOf(context),
                                        'تعذّر الوصول إلى المستند المختار. اختر ملفاً آخر.',
                                        title: 'المستند غير متاح');
                                    return;
                                  }
                                  final pending = _PendingUpload(
                                    id: 'document_${DateTime.now().microsecondsSinceEpoch}',
                                    localPath: doc.path!, type: 'document', fileName: doc.name,
                                  );
                                  setState(() => _pendingUploads.insert(0, pending));
                                  _scrollToBottom();
                                  await _uploadPrivateDocument(pending);
                                } catch (e) {
                                  if (mounted) {
                                    final message = e.toString();
                                    if (message.contains('50 ميغابايت')) {
                                      TiniMessagingNotice.showInfo(
                                          ScaffoldMessenger.maybeOf(context),
                                          'حجم المستند يتجاوز الحد المسموح (50 MB). اختر ملفاً أصغر.',
                                          title: 'حجم المستند غير صالح');
                                    } else {
                                      TiniMessagingNotice.showTechnicalError(
                                          ScaffoldMessenger.maybeOf(context),
                                          'تعذّر اختيار المستند');
                                    }
                                  }
                                } finally {
                                  _pickingPrivateDocument = false;
                                }
                              },
                              onPickCamera: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const MediaPickerScreen(isForChat: true)),
                                );
                                if (result!= null && result is List<String> && result.isNotEmpty) {
                                 await _sendPrivateMediaAlbum(result.map((path) => <String, dynamic>{'path': path}).toList());
                                }
                              },
                              onPickFile: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const MediaPickerScreen(isForChat: true)),
                                );
                                if (result!= null && result is List<String> && result.isNotEmpty) {
                                 await _sendPrivateMediaAlbum(result.map((path) => <String, dynamic>{'path': path}).toList());
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);
  }
}


class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final Map<String, dynamic>? source;
  const ImageViewerScreen({super.key, required this.imageUrl, this.source});

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _isSaving = false;

  bool get _canView => AudienceMessagePolicy.canView(
      widget.source ?? {'mediaUrl': widget.imageUrl, 'type': 'image'});

  Future<void> _saveImage() async {
    if (!_canView) return;
    setState(() => _isSaving = true);
    try {
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (!mounted || !_canView) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(response.bodyBytes);
      if (!mounted || !_canView) return;
      await Gal.putImage(file.path, album: 'Tini');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الصورة'), backgroundColor: Color(0xFF009688)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: _isSaving
    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.download, color: Colors.white),
            onPressed: _isSaving? null : _saveImage,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(widget.imageUrl),
        ),
      ),
    );
  }
}

class VideoViewerScreen extends StatefulWidget {
  final String videoUrl;
  final Map<String, dynamic>? source;
  const VideoViewerScreen({super.key, required this.videoUrl, this.source});

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isSaving = false;
  bool _showControls = true;
  bool _isMuted = false;

  bool _initializationStarted = false;
  bool get _canView => AudienceMessagePolicy.canView(
      widget.source ?? {'mediaUrl': widget.videoUrl, 'type': 'video'});

  void _onAudienceChanged() {
    if (!mounted) return;
    if (!_canView) {
      unawaited(_controller.setVolume(0));
      unawaited(_controller.pause());
    } else if (!_initializationStarted) {
      _initializeVideo();
    }
  }

  Future<void> _playAuthorized() async {
    if (!mounted || !_canView) return;
    await _controller.play();
    if (!mounted || !_canView) {
      await _controller.setVolume(0);
      await _controller.pause();
    }
  }

  Future<void> _initializeVideo() async {
    if (_initializationStarted || !_canView) return;
    _initializationStarted = true;
    try {
      await _controller.initialize();
      if (!mounted || !_canView) return;
      setState(() => _isInitialized = true);
      await _controller.setVolume(_isMuted ? 0 : 1);
      await _playAuthorized();
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (_) {
      if (mounted && _canView) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    AudienceAccess.instance.addListener(_onAudienceChanged);
    _initializeVideo();
  }

  @override
  void dispose() {
    AudienceAccess.instance.removeListener(_onAudienceChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveVideo() async {
    if (!_canView) return;
    setState(() => _isSaving = true);
    try {
      final response = await http.get(Uri.parse(widget.videoUrl));
      if (!mounted || !_canView) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await file.writeAsBytes(response.bodyBytes);
      if (!mounted || !_canView) return;
      await Gal.putVideo(file.path, album: 'Tini');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الفيديو'), backgroundColor: Color(0xFF009688)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _togglePlayPause() {
    if (!_canView) return;
    setState(() {
      _controller.value.isPlaying? _controller.pause() : _playAuthorized();
      _showControls = true;
    });
  }

  void _toggleMute() {
    if (!_canView) return;
    setState(() {
      _isMuted =!_isMuted;
      _controller.setVolume(_isMuted? 0.0 : 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: _isSaving
    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.download, color: Colors.white),
            onPressed: _isSaving? null : _saveVideo,
          ),
        ],
      ),
      body: Center(
        child: _isInitialized
? InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: GestureDetector(
              onTap: () {
                setState(() => _showControls =!_showControls);
              },
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_controller),
                    if (_showControls)...[
                      VideoProgressIndicator(_controller, allowScrubbing: true),
                      Align(
                        alignment: Alignment.center,
                        child: IconButton(
                          icon: Icon(
                            _controller.value.isPlaying? Icons.pause_circle : Icons.play_circle,
                            color: Colors.white,
                            size: 64,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                      ),
                    ],
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isMuted? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                          ),
                          onPressed: _toggleMute,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            )
            : const CircularProgressIndicator(color: Color(0xFF009688)),
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

// [تنسيق وسائط الخاص] شرح مختصر قابل للتوسيع دون تغيير النص المحفوظ.
class _PrivateMediaCaption extends StatefulWidget {
  final String text;
  const _PrivateMediaCaption({required this.text});

  @override
  State<_PrivateMediaCaption> createState() => _PrivateMediaCaptionState();
}

class _PrivateMediaCaptionState extends State<_PrivateMediaCaption> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _PrivateMediaCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.text.trim();
    if (caption.isEmpty) return const SizedBox.shrink();
    final isLong = caption.length > 25 || caption.contains('\n');
    const style = TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 14);
    if (_expanded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(caption, style: style, textAlign: TextAlign.right, textDirection: ui.TextDirection.rtl),
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
      textDirection: ui.TextDirection.rtl,
      children: [
        Expanded(child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: style, textAlign: TextAlign.right, textDirection: ui.TextDirection.rtl)),
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
