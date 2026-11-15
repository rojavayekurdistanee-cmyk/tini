import 'banner_manager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <-- اضافة 1
import 'app_navigator.dart';
import 'home_screen.dart';
import 'post_view_screen.dart';
import 'profile_screen.dart'; // <-- اضافة جديدة للـ follow
import 'visits_screen.dart';
import 'dart:convert';
import 'chat_screen.dart'; // <-- اضافة جديدة للشات
import 'messages_tab.dart'; // <-- صندوق الوارد
import 'banner_video_navigation.dart';
import 'group_chat_screen.dart';
import 'audience_access.dart';

// Diagnostic logs contain identifiers/status only, never tokens or message text.
void _traceSaveShare(Map<String, dynamic> data, String stage, String status,
    [Map<String, Object?> details = const {}]) {
  if (!const {'save', 'bookmark', 'favorite', 'saves', 'repost', 'reposts', 'share'}
      .contains(data['type'])) {
    return;
  }
  debugPrint('[Tini SaveShare] ${jsonEncode({
    'activityId': data['activityId'],
    'type': data['type'],
    'postId': data['postId'],
    'fromUid': data['fromUid'],
    'stage': stage,
    'status': status,
    ...details,
  })}');
}

String _pushDiagnosticErrorCode(Object error) {
  if (error is FirebaseException) return error.code;
  if (error is PlatformException) return error.code;
  return error.runtimeType.toString();
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  var stage = 'background_initialization';
  _traceSaveShare(message.data, stage, 'MESSAGE_RECEIVED', {
    'messageId': message.messageId,
    'hasNotificationPayload': message.notification != null,
  });
  try {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (message.data['type'] == 'message' || message.data['type'] == 'chat') {
    try {
      await FirebaseFirestore.instance.collection('chat_rooms').doc(message.data['roomId']).collection('messages').doc(message.data['messageId']).update({'isDelivered': true});
    } catch(e){}
  }
  // FCM displays notification+data messages in the system tray while
  // backgrounded. Do not generate a duplicate local push for these three types.
  final backgroundType = (message.data['type'] ?? '').toString();
  if (message.notification != null &&
      const {'like', 'comment', 'follow', 'new_follower', 'new_followers'}
          .contains(backgroundType)) {
    return;
  }

  final service = NotificationService();
  stage = 'background_local_initialization';
  await service.initForBackground();
  _traceSaveShare(message.data, stage, 'INITIALIZED');

  final data = message.data;
  final avatarUrl = data['avatar']?? "";
  final title = data['title']?? "Tini";
  final body = data['body']?? "";

  stage = 'background_render';
  await service.showBackgroundNotification(title, body, avatarUrl, data);
  } catch (error) {
    _traceSaveShare(message.data, stage, 'FAILED', {
      'errorCode': _pushDiagnosticErrorCode(error),
    });
    rethrow;
  }
}

class NotificationService {
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // Verify the current post and owner before downloading rich notification media.
  // A background isolate has its own access state and must verify on the server.
  Future<bool> _mayShowPostNotification(Map<String, dynamic> data, {
    String diagnosticStage = 'audience_check',
  }) async {
    final type = (data['type'] ?? '').toString();
    if (type == 'message' || type == 'chat' || type == 'group' || type == 'private_message') return true;
    final postId = (data['postId'] ?? '').toString();
    if (postId.isEmpty) {
      // Do not expose an unidentifiable post thumbnail from an older payload.
      final allowed = !['postImage', 'bigPicture', 'imageUrl', 'mediaUrl', 'thumbnailUrl']
          .any((key) => (data[key] ?? '').toString().isNotEmpty);
      _traceSaveShare(data, diagnosticStage,
          allowed ? 'AUDIENCE_ALLOWED' : 'DISPLAY_SKIPPED', {
        'reason': allowed ? 'no_post_media' : 'post_id_missing_with_media',
      });
      return allowed;
    }
    _traceSaveShare(data, diagnosticStage, 'AUDIENCE_CHECK_STARTED');
    final timer = Stopwatch()..start();
    try {
      final allowed = await AudienceAccess.instance.verifyPost(postId);
      _traceSaveShare(data, diagnosticStage,
          allowed ? 'AUDIENCE_ALLOWED' : 'DISPLAY_SKIPPED', {
        'reason': allowed ? 'verified' : 'audience_verification_not_granted',
        'elapsedMs': timer.elapsedMilliseconds,
      });
      return allowed;
    } catch (error) {
      _traceSaveShare(data, diagnosticStage, 'DISPLAY_SKIPPED', {
        'reason': 'audience_check_exception',
        'errorCode': _pushDiagnosticErrorCode(error),
        'elapsedMs': timer.elapsedMilliseconds,
      });
      return false;
    }
  }

  // A cold-start background isolate can receive a save/share push before the
  // initial server-confirmed audience reads settle. Never bypass the audience
  // gate: retry a temporary denial, and display only after a verified grant.
  Future<bool> _mayShowBackgroundSaveSharePost(
    Map<String, dynamic> data, {
    required String diagnosticStage,
  }) async {
    final type = (data['type'] ?? '').toString();
    if (!const {
      'save', 'bookmark', 'favorite', 'saves', 'repost', 'reposts', 'share'
    }.contains(type)) {
      return _mayShowPostNotification(data, diagnosticStage: diagnosticStage);
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        _traceSaveShare(data, diagnosticStage, 'AUDIENCE_RETRY_STARTED', {
          'attempt': attempt + 1,
        });
        await Future<void>.delayed(
          Duration(milliseconds: attempt == 1 ? 350 : 700),
        );
      }
      if (await _mayShowPostNotification(
        data,
        diagnosticStage: diagnosticStage,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<void> init() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload!= null && details.payload!.isNotEmpty) {
          _handleFromPayload(details.payload!, isFromTerminated: false); // <-- تعديل 1
        } else {
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    const androidChannel = AndroidNotificationChannel(
      'titi_star_channel',
      'Tini',
      description: 'إشعارات Tini',
      importance: Importance.high,
    );

    await _localNotifications
  .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
  ?.createNotificationChannel(androidChannel);

    await _saveToken();

    _messaging.onTokenRefresh.listen((newToken) {
      _saveToken(token: newToken);
    });

    FirebaseMessaging.onMessage.listen((message) async {
      _traceSaveShare(message.data, 'foreground_receive', 'MESSAGE_RECEIVED', {
        'messageId': message.messageId,
        'hasNotificationPayload': message.notification != null,
      });
      try {
      // Keep existing in-app banner handling. The three requested social
      // events must ALSO produce an external notification while Tini is open.
      final type = (message.data['type'] ?? '').toString();
      final requiresExternalPush =
          const {'like', 'comment', 'follow', 'new_follower', 'new_followers'}
              .contains(type);
      final handledByBanner =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
              await BannerManager.instance.handleForegroundActivity(message.data);
      if (handledByBanner && !requiresExternalPush) {
        _traceSaveShare(message.data, 'foreground_banner', 'DISPLAY_SKIPPED', {
          'reason': 'handled_by_in_app_banner',
        });
        return;
      }
      await _showNotification(message, androidChannel);
      } catch (error) {
        _traceSaveShare(message.data, 'foreground_handler', 'FAILED', {
          'errorCode': _pushDiagnosticErrorCode(error),
        });
        rethrow;
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleMessage(message, isFromTerminated: false); // <-- تعديل 2
    });

    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage!= null) {
      _handleMessage(initialMessage, isFromTerminated: true); // <-- تعديل 4
    }

    // <-- تعديل: نفتح الإشعار فقط إذا انفتح التطبيق فعلاً من الضغط على الإشعار
    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchPayload != null && launchPayload.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 1400), () {
          _handleFromPayload(launchPayload, isFromTerminated: true);
        });
      }
    }

    // تنظيف أي قيمة قديمة انحفظت بالنسخة السابقة
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_notification');
  }

  void _handleMessage(RemoteMessage message, {bool isFromTerminated = false}) async { // <-- تعديل 6
    final postId = message.data['postId'];
    final commentId = message.data['commentId'];
    final type = (message.data['type']?? "general").toString();
    final fromUid = message.data['fromUid']?.toString()?? "";
    final groupId = message.data['groupId']?.toString()?? "";

        // اذا view افتح VisitsScreen
    if (type == "view") {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (isFromTerminated) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const VisitsScreen()),
          (route) => false,
        );
      } else {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const VisitsScreen()),
        );
      }
    });
  });
  return;
}
    // --- تعديل جديد: اذا follow افتح البروفايل ---
    if (type == "follow" && fromUid.isNotEmpty) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (isFromTerminated) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => ProfileScreen(userId: fromUid)),
          (route) => false,
        );
      } else {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ProfileScreen(userId: fromUid)),
        );
      }
    });
  });
    return;
}

                                // --- اذا رسالة شات خاص ---
    if ((type == "message" || type == "chat") && fromUid.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (isFromTerminated) {
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => ChatScreen(
                viewedUid: fromUid,
                displayFullName: 'مستخدم',
                displayProfileImg: '',
                isFriend: false,
              )),
              (route) => false,
            );
          } else {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => ChatScreen(
                viewedUid: fromUid,
                displayFullName: 'مستخدم',
                displayProfileImg: '',
                isFriend: false,
              )),
            );
          }
        });
      });
      return;
    }

    // --- اذا رسالة جروب ---
    if (type == "group" && groupId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (isFromTerminated) {
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: groupId)),
              (route) => false,
            );
          } else {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: groupId)),
            );
          }
        });
      });
      return;
    }

    if (postId == null || postId.toString().isEmpty) {
      return;
    }

    try {
      var doc = await FirebaseFirestore.instance.collection('posts').doc(postId.toString()).get();

      if (!doc.exists) {
        final q = await FirebaseFirestore.instance.collection('posts').where('postId', isEqualTo: postId.toString()).limit(1).get();
        if (q.docs.isNotEmpty) doc = q.docs.first;
      }

      if (!doc.exists) {
        return;
      }


      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 1400), () {
          _openNotificationPost(doc, type: type, commentId: commentId?.toString(),
              isFromTerminated: isFromTerminated);
        });
      });
    } catch (e) {
    }
  }

  void _handleFromPayload(String payload, {bool isFromTerminated = true}) async { // <-- تعديل 9
    try {
      final data = jsonDecode(payload);
      final postId = data['postId'];
      final commentId = data['commentId'];
      final type = (data['type']?? "general").toString();
      final fromUid = data['fromUid']?.toString()?? "";
      final groupId = data['groupId']?.toString()?? "";

            // اذا view افتح VisitsScreen
      if (type == "view") {
  if (isFromTerminated) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const VisitsScreen()),
      (route) => false,
    );
  } else {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const VisitsScreen()),
    );
  }
  return;
}
      // --- تعديل جديد: اذا follow افتح البروفايل ---
      if (type == "follow" && fromUid.isNotEmpty) {
  if (isFromTerminated) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: fromUid)),
      (route) => false,
    );
  } else {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: fromUid)),
    );
  }
    return;
}

                                                // --- اذا رسالة شات خاص ---
      if ((type == "message" || type == "chat") && fromUid.isNotEmpty) {
        if (isFromTerminated) {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => ChatScreen(
              viewedUid: fromUid,
              displayFullName: 'مستخدم',
              displayProfileImg: '',
              isFriend: false,
            )),
            (route) => false,
          );
        } else {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => ChatScreen(
              viewedUid: fromUid,
              displayFullName: 'مستخدم',
              displayProfileImg: '',
              isFriend: false,
            )),
          );
        }
        return;
      }

      // --- اذا رسالة جروب ---
      if (type == "group" && groupId.isNotEmpty) {
        if (isFromTerminated) {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: groupId)),
            (route) => false,
          );
        } else {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: groupId)),
          );
        }
        return;
      }

      if (postId == null || postId.toString().isEmpty) {
        return;
      }

      var doc = await FirebaseFirestore.instance.collection('posts').doc(postId.toString()).get();

      if (!doc.exists) {
        final q = await FirebaseFirestore.instance.collection('posts').where('postId', isEqualTo: postId.toString()).limit(1).get();
        if (q.docs.isNotEmpty) doc = q.docs.first;
      }

      if (!doc.exists) {
        return;
      }


      await _openNotificationPost(doc, type: type,
          commentId: commentId?.toString(), isFromTerminated: isFromTerminated);
    } catch (e) {
      if (payload.isEmpty) {
        return;
      }
      try {
        var doc = await FirebaseFirestore.instance.collection('posts').doc(payload).get();
        if (!doc.exists) {
          return;
        }
        await _openNotificationPost(doc, type: 'general',
            isFromTerminated: isFromTerminated);
      } catch (err) {
      }
    }
  }

  // Every external video entry point uses the same ownership handoff as the
  // in-app video banners. A non-video return destination must remain silent.
  Future<void> _openNotificationPost(
    DocumentSnapshot doc, {
    required String type,
    String? commentId,
    required bool isFromTerminated,
  }) async {
    final viewer = FirebaseAuth.instance.currentUser?.uid;
    if (viewer == null) return;
    // Resolve the access check before the playback scope's first activation.
    // Otherwise a newly received post may still be pending at that frame.
    await AudienceAccess.instance.verifyPost(doc.id);
    if (FirebaseAuth.instance.currentUser?.uid != viewer) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final hls = (data['hlsPath'] ?? '').toString().trim();
    final url = hls.isNotEmpty ? hls : (data['videoUrl'] ?? '').toString().trim();
    final openComments = const ['comment', 'reply', 'comment_like'].contains(type);
    await BannerVideoNavigation.open(
      navigator: navigator,
      url: url,
      replaceStack: isFromTerminated,
      onPushed: () {},
      child: PostViewScreen(
        posts: [doc],
        initialIndex: 0,
        openComments: openComments,
        highlightCommentId: openComments ? commentId : null,
        isFromTerminated: isFromTerminated,
        isBannerNavigation: true,
      ),
    );
  }

  Future<void> initForBackground() async {
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {},
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  Future<void> showBackgroundNotification(String title, String body,
      String avatarUrl, Map<String, dynamic> data) async {
    _traceSaveShare(data, 'background_render', 'RENDER_STARTED');
    try {
      await _renderBackgroundNotification(title, body, avatarUrl, data);
    } catch (error) {
      _traceSaveShare(data, 'background_render', 'FAILED', {
        'errorCode': _pushDiagnosticErrorCode(error),
      });
      rethrow;
    }
  }

    Future<void> _renderBackgroundNotification(String title, String body, String avatarUrl, Map<String, dynamic> data) async {
    final backgroundType = (data['type'] ?? '').toString();
    final isSaveShare = const {
      'save', 'bookmark', 'favorite', 'saves', 'repost', 'reposts', 'share'
    }.contains(backgroundType);
    String? readyViewerUid;
    if (isSaveShare) {
      // The first auth-state event is emitted after Firebase Auth has loaded
      // the persisted session in this background isolate.
      try {
        final viewer = await FirebaseAuth.instance.authStateChanges().first
            .timeout(const Duration(seconds: 3));
        if (viewer == null) {
          _traceSaveShare(data, 'background_auth', 'DISPLAY_SKIPPED', {
            'reason': 'viewer_not_authenticated',
          });
          return;
        }
        readyViewerUid = viewer.uid;
        _traceSaveShare(data, 'background_auth', 'VIEWER_READY');
      } catch (error) {
        _traceSaveShare(data, 'background_auth', 'AUTH_READINESS_CHECK_FAILED', {
          'errorCode': _pushDiagnosticErrorCode(error),
        });
        // Keep the existing verified-audience path if the session is already
        // available; never display a stale push for a signed-out viewer.
        if (FirebaseAuth.instance.currentUser == null) return;
      }
    }
    final notificationViewerUid =
        readyViewerUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (!await _mayShowBackgroundSaveSharePost(data, diagnosticStage: 'background_audience_before_media')) return;

        // [Titi Update] - معاينة الرسائل الخاصة (خلفية) + زر following
    _traceSaveShare(data, 'background_preferences', 'PREFERENCES_READ_STARTED');
    final prefs = await SharedPreferences.getInstance();
    final bool previewEnabled = prefs.getBool('messages_preview') ?? true;
    final String type = (data['type'] ?? "").toString();
    // [عرض مرة واحدة - الخاص] منع عرض أو تحميل الوسائط في الإشعارات
    final bool privateViewOnce = (type == 'chat' || type == 'message') &&
        (data['viewOnce'] == true || data['viewOnce']?.toString() == 'true');
    // [كتم حقيقي اكيد - محلي ما بيعتمد على Auth]
    try {
      final mutedRooms = prefs.getStringList('muted_rooms')?? [];
      if (data['roomId']!= null && mutedRooms.contains(data['roomId'].toString())) {
        _traceSaveShare(data, 'local_mute_check', 'DISPLAY_SKIPPED', {
          'reason': 'room_muted',
        });
        return;
      }
      final mutedGroups = prefs.getStringList('muted_group_rooms')?? [];
      if (data['groupId']!= null && mutedGroups.contains(data['groupId'].toString())) {
        _traceSaveShare(data, 'local_mute_check', 'DISPLAY_SKIPPED', {
          'reason': 'group_muted',
        });
        return;
      }
    } catch (e) {}

    // --- DND Check - جدول تعيين الاشعارات ---
    final bool dndEnabled = prefs.getBool('dnd_enabled') ?? false;
    if (dndEnabled) {
      final int startH = prefs.getInt('dnd_start_hour') ?? 0;
      final int startM = prefs.getInt('dnd_start_min') ?? 0;
      final int endH = prefs.getInt('dnd_end_hour') ?? 8;
      final int endM = prefs.getInt('dnd_end_min') ?? 0;
      final now = DateTime.now();
      final int nowMin = now.hour * 60 + now.minute;
      final int startMin = startH * 60 + startM;
      final int endMin = endH * 60 + endM;
      bool isInDnd;
      if (startMin <= endMin) {
        isInDnd = nowMin >= startMin && nowMin < endMin;
      } else {
        isInDnd = nowMin >= startMin || nowMin < endMin;
      }
      if (isInDnd) {
        _traceSaveShare(data, 'background_settings', 'DISPLAY_SKIPPED', {
          'reason': 'do_not_disturb_schedule',
          'nowMinute': nowMin, 'startMinute': startMin, 'endMinute': endMin,
        });
        return;
      }
    }

    if (type == 'following_post') {
      final bool followingEnabled = prefs.getBool('post_following') ?? true;
      if (!followingEnabled) {
        return;
      }
    }

        if (type == 'custom_suggestion') {
      final bool customEnabled = prefs.getBool('post_custom') ?? true;
      if (!customEnabled) {
        return;
      }
    }
    // [Titi Update] - تفعيل زر اشخاص قد تعرفهم - خلفية
    if (type == 'people_you_may_know_post') {
      final bool pymkEnabled = prefs.getBool('people_you_may_know') ?? true;
      if (!pymkEnabled) {
        return;
      }
    }
    if ((type == 'message' || privateViewOnce) && !previewEnabled) {
  body = "لديك رسالة جديدة";
  data['postImage'] = "";
}

    const androidChannel = AndroidNotificationChannel(
      'titi_star_channel',
      'Tini',
      description: 'إشعارات Tini',
      importance: Importance.high,
    );

    _traceSaveShare(data, 'background_media', 'MEDIA_PREPARATION_STARTED');
    FilePathAndroidBitmap? largeIcon;
    BigPictureStyleInformation? bigPictureStyle;

    final postImageUrl = privateViewOnce ? "" : (data['postImage']?? data['bigPicture']?? data['imageUrl']?? data['mediaUrl']?? data['thumbnailUrl']?? "");
    if (privateViewOnce && previewEnabled) {
      body = "لديك رسالة لمرة واحدة";
    }

    // [Tini Fix] - لا تنشئ إشعاراً خارجياً فارغاً باسم Tini فقط.
    // لا تغيّر مسار إشعارات الحفظ والمشاركة والتعليقات التي تحمل محتوى فعلياً.
    final isEmptyTiniPlaceholder = title.trim() == 'Tini' &&
        body.trim().isEmpty &&
        avatarUrl.trim().isEmpty &&
        postImageUrl.toString().trim().isEmpty;
    if (isEmptyTiniPlaceholder) {
      debugPrint('[Tini Push] Skipped empty background placeholder; '
          'type=$backgroundType');
      return;
    }

    if (avatarUrl.isNotEmpty) {
      final avatarPath = await _createAvatarWithBadge(avatarUrl, DateTime.now().millisecond);
      if (avatarPath!= null) {
        largeIcon = FilePathAndroidBitmap(avatarPath);
      }
    } else {
      final letterPath = await _createLetterAvatar(title, DateTime.now().millisecond);
      if (letterPath!= null) {
        largeIcon = FilePathAndroidBitmap(letterPath);
      }
    }

    if (postImageUrl.isNotEmpty) {
      final bigPicPath = await _downloadImage(postImageUrl, "big_${DateTime.now().millisecond}");
      if (bigPicPath!= null) {
        bigPictureStyle = BigPictureStyleInformation(
          FilePathAndroidBitmap(bigPicPath),
          
          largeIcon: largeIcon,
          hideExpandedLargeIcon: true,
        );
      }
    } else if (largeIcon!= null && type!= 'chat' && type!= 'message' && type!= 'group') {
      bigPictureStyle = BigPictureStyleInformation(
        largeIcon,
        contentTitle: title,
        summaryText: body,
        largeIcon: largeIcon,
        hideExpandedLargeIcon: false,
      );
    }

final payloadData = jsonEncode({'postId': data['postId'], 'commentId': data['commentId'], 'type': data['type'], 'fromUid': data['fromUid'], 'roomId': data['roomId'], 'groupId': data['groupId']});

    // (تم حذف حفظ pending_notification من هنا: كان يفتح الإشعار بدون ما المستخدم يضغط عليه)

    if (FirebaseAuth.instance.currentUser?.uid != notificationViewerUid) {
      _traceSaveShare(data, 'background_identity', 'DISPLAY_SKIPPED', {
        'reason': 'account_changed_during_render',
      });
      return;
    }
    if (!await _mayShowBackgroundSaveSharePost(data, diagnosticStage: 'background_audience_before_show')) return;
    if (FirebaseAuth.instance.currentUser?.uid != notificationViewerUid) {
      _traceSaveShare(data, 'background_identity', 'DISPLAY_SKIPPED', {
        'reason': 'account_changed_during_render',
      });
      return;
    }
    _traceSaveShare(data, 'background_platform_show', 'PLATFORM_SHOW_STARTED', {
      'hasLargeIcon': largeIcon != null,
      'hasBigPicture': bigPictureStyle != null,
    });
    await _localNotifications.show(
      id: data['type'] == 'custom_suggestion' ? 8888 : DateTime.now().millisecond,
      title: title,
      body: body,
      payload: payloadData,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          androidChannel.id,
          androidChannel.name,
          channelDescription: androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          largeIcon: largeIcon?? const DrawableResourceAndroidBitmap('@drawable/ic_notification'),
          styleInformation: bigPictureStyle,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
    _traceSaveShare(data, 'background_platform_show', 'PLATFORM_SHOW_COMPLETED', {
      'visualDisplayConfirmed': false,
    });
  }

  Future<void> _showNotification(RemoteMessage message,
      AndroidNotificationChannel channel) async {
    _traceSaveShare(message.data, 'foreground_render', 'RENDER_STARTED');
    try {
      await _renderForegroundNotification(message, channel);
    } catch (error) {
      _traceSaveShare(message.data, 'foreground_render', 'FAILED', {
        'errorCode': _pushDiagnosticErrorCode(error),
      });
      rethrow;
    }
  }

    Future<void> _renderForegroundNotification(RemoteMessage message, AndroidNotificationChannel channel) async {
    final notification = message.notification;
    final data = message.data;
    final notificationViewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (!await _mayShowPostNotification(data, diagnosticStage: 'foreground_audience_before_media')) return;

        // [Titi Update] - معاينة الرسائل الخاصة + زر following
    _traceSaveShare(data, 'foreground_preferences', 'PREFERENCES_READ_STARTED');
    final prefs = await SharedPreferences.getInstance();
    final bool previewEnabled = prefs.getBool('messages_preview') ?? true;
    final String type = (data['type'] ?? "").toString();
    // [عرض مرة واحدة - الخاص] منع عرض أو تحميل الوسائط في الإشعارات
    final bool privateViewOnce = (type == 'chat' || type == 'message') &&
        (data['viewOnce'] == true || data['viewOnce']?.toString() == 'true');
    // [كتم حقيقي اكيد - محلي]
    try {
      final mutedRooms = prefs.getStringList('muted_rooms')?? [];
      if (data['roomId']!= null && mutedRooms.contains(data['roomId'].toString())) {
        _traceSaveShare(data, 'local_mute_check', 'DISPLAY_SKIPPED', {
          'reason': 'room_muted',
        });
        return;
      }
      final mutedGroups = prefs.getStringList('muted_group_rooms')?? [];
      if (data['groupId']!= null && mutedGroups.contains(data['groupId'].toString())) {
        _traceSaveShare(data, 'local_mute_check', 'DISPLAY_SKIPPED', {
          'reason': 'group_muted',
        });
        return;
      }
    } catch (e) {}

    // --- DND Check - جدول تعيين الاشعارات ---
    final bool dndEnabled = prefs.getBool('dnd_enabled') ?? false;
    if (dndEnabled) {
      final int startH = prefs.getInt('dnd_start_hour') ?? 0;
      final int startM = prefs.getInt('dnd_start_min') ?? 0;
      final int endH = prefs.getInt('dnd_end_hour') ?? 8;
      final int endM = prefs.getInt('dnd_end_min') ?? 0;
      final now = DateTime.now();
      final int nowMin = now.hour * 60 + now.minute;
      final int startMin = startH * 60 + startM;
      final int endMin = endH * 60 + endM;
      bool isInDnd;
      if (startMin <= endMin) {
        isInDnd = nowMin >= startMin && nowMin < endMin;
      } else {
        isInDnd = nowMin >= startMin || nowMin < endMin;
      }
      if (isInDnd) {
        _traceSaveShare(data, 'foreground_settings', 'DISPLAY_SKIPPED', {
          'reason': 'do_not_disturb_schedule',
          'nowMinute': nowMin, 'startMinute': startMin, 'endMinute': endMin,
        });
        return;
      }
    }

    if (type == 'following_post') {
      final bool followingEnabled = prefs.getBool('post_following') ?? true;
      if (!followingEnabled) {
        return;
      }
    }

        if (type == 'custom_suggestion') {
      final bool customEnabled = prefs.getBool('post_custom') ?? true;
      if (!customEnabled) {
        return;
      }
    }
    // [Titi Update] - تفعيل زر اشخاص قد تعرفهم - واجهة
    if (type == 'people_you_may_know_post') {
      final bool pymkEnabled = prefs.getBool('people_you_may_know') ?? true;
      if (!pymkEnabled) {
        return;
      }
    }

    String titleToShow = notification?.title?? data['title']?? "Tini";
    String bodyToShow = notification?.body?? data['body']?? "";

    String? avatarUrl = data['avatar'];
    String? postImageUrl = privateViewOnce ? null : (data['postImage']?? data['bigPicture']?? data['imageUrl']?? data['mediaUrl']?? data['thumbnailUrl']);
    if (privateViewOnce && previewEnabled) {
      bodyToShow = "لديك رسالة لمرة واحدة";
    }

    if ((type == 'message' || privateViewOnce) && !previewEnabled) {
  bodyToShow = "لديك رسالة جديدة";
  postImageUrl = null;
}

    BigPictureStyleInformation? bigPictureStyle;
    _traceSaveShare(data, 'foreground_media', 'MEDIA_PREPARATION_STARTED');
    FilePathAndroidBitmap? largeIcon;

    try {
      if (avatarUrl!= null && avatarUrl.isNotEmpty) {
        final avatarWithBadge = await _createAvatarWithBadge(avatarUrl, message.hashCode);
        if (avatarWithBadge!= null) {
          largeIcon = FilePathAndroidBitmap(avatarWithBadge);
        }
      } else {
        final letterPath = await _createLetterAvatar(titleToShow, message.hashCode);
        if (letterPath!= null) {
          largeIcon = FilePathAndroidBitmap(letterPath);
        }
      }

      if (postImageUrl!= null && postImageUrl.isNotEmpty) {
        final bigPicPath = await _downloadImage(postImageUrl, "big_${message.hashCode}");
        if (bigPicPath!= null) {
          bigPictureStyle = BigPictureStyleInformation(
            FilePathAndroidBitmap(bigPicPath),
            contentTitle: titleToShow,
            summaryText: bodyToShow,
            largeIcon: largeIcon,
            hideExpandedLargeIcon: true,
          );
        }
      } else if (largeIcon!= null && type!= 'chat' && type!= 'message' && type!= 'group') {
        bigPictureStyle = BigPictureStyleInformation(
          largeIcon,
          contentTitle: titleToShow,
          summaryText: bodyToShow,
          largeIcon: largeIcon,
          hideExpandedLargeIcon: false,
        );
      }
    } catch (e) {
      _traceSaveShare(data, 'foreground_media', 'WARNING_CONTINUING', {
        'reason': 'media_preparation_failed',
        'errorCode': _pushDiagnosticErrorCode(e),
      });
    }

final payloadData = jsonEncode({'postId': message.data['postId'], 'commentId': message.data['commentId'], 'type': message.data['type'], 'fromUid': message.data['fromUid'], 'roomId': message.data['roomId'], 'groupId': message.data['groupId']});

    if (FirebaseAuth.instance.currentUser?.uid != notificationViewerUid) {
      _traceSaveShare(data, 'foreground_identity', 'DISPLAY_SKIPPED', {
        'reason': 'account_changed_during_render',
      });
      return;
    }
    if (!await _mayShowPostNotification(data, diagnosticStage: 'foreground_audience_before_show')) return;
    if (FirebaseAuth.instance.currentUser?.uid != notificationViewerUid) {
      _traceSaveShare(data, 'foreground_identity', 'DISPLAY_SKIPPED', {
        'reason': 'account_changed_during_render',
      });
      return;
    }
    _traceSaveShare(data, 'foreground_platform_show', 'PLATFORM_SHOW_STARTED', {
      'hasLargeIcon': largeIcon != null,
      'hasBigPicture': bigPictureStyle != null,
    });
    await _localNotifications.show(
      id: data['type'] == 'custom_suggestion' ? 8888 : message.hashCode,
      title: titleToShow,
      body: bodyToShow,
      payload: payloadData,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          largeIcon: largeIcon?? const DrawableResourceAndroidBitmap('@drawable/ic_notification'),
          styleInformation: bigPictureStyle,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
    _traceSaveShare(data, 'foreground_platform_show', 'PLATFORM_SHOW_COMPLETED', {
      'visualDisplayConfirmed': false,
    });
  }

    Future<String?> _downloadImage(String url, String name) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode!= 200) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name.jpg');
      try {
        img.Image? decoded = img.decodeImage(res.bodyBytes);
        if (decoded != null) {
          decoded = img.bakeOrientation(decoded);
          await file.writeAsBytes(img.encodeJpg(decoded, quality: 90));
        } else {
          await file.writeAsBytes(res.bodyBytes);
        }
      } catch (_) {
        await file.writeAsBytes(res.bodyBytes);
      }
      return file.path;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _createAvatarWithBadge(String avatarUrl, int id) async {
    try {
      final res = await http.get(Uri.parse(avatarUrl));
      if (res.statusCode!= 200) return null;
     img.Image? avatar = img.decodeImage(res.bodyBytes);
      if (avatar == null) return null;
      avatar = img.bakeOrientation(avatar);

      const size = 256;
      int minSide = min(avatar.width, avatar.height);
      avatar = img.copyCrop(avatar, x: (avatar.width - minSide) ~/ 2, y: (avatar.height - minSide) ~/ 2, width: minSide, height: minSide);
      avatar = img.copyResize(avatar, width: size, height: size);

      img.Image circle = img.Image(width: size, height: size, numChannels: 4);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          int dx = x - size ~/ 2, dy = y - size ~/ 2;
          if (dx * dx + dy * dy <= size ~/ 2 * size ~/ 2) {
            circle.setPixel(x, y, avatar.getPixel(x, y));
          }
        }
      }
      avatar = circle;

      try {
        final badgeData = await rootBundle.load('assets/icon.png');
        img.Image? badge = img.decodeImage(badgeData.buffer.asUint8List());
        if (badge!= null) {
          badge = img.copyResize(badge, width: 80, height: 80);
          img.Image badgeCircle = img.Image(width: 80, height: 80, numChannels: 4);
          for (int y = 0; y < 80; y++) {
            for (int x = 0; x < 80; x++) {
              int dx = x - 40, dy = y - 40;
              if (dx * dx + dy * dy <= 1600) {
                badgeCircle.setPixel(x, y, badge.getPixel(x, y));
              }
            }
          }
          img.compositeImage(avatar, badgeCircle, dstX: size - 85, dstY: size - 85);
        }
      } catch (e) {
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/notif_$id.png');
      await file.writeAsBytes(img.encodePng(avatar));
      return file.path;
    } catch (e) {
      return null;
    }
  }

Future<String?> _createLetterAvatar(String name, int id) async {
  try {
    const size = 256;
    String letter = "?";
    if (name.trim().isNotEmpty) {
      letter = name.trim()[0].toUpperCase();
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // نفس لونك 0,150,136
    final paint = Paint()..color = const Color(0xFF009688);
    canvas.drawCircle(const Offset(128, 128), 128, paint);

    // الحرف - بيدعم عربي + انكليزي
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 120)
    )
     ..pushStyle(ui.TextStyle(
        color: Colors.white,
        fontSize: 120,
        fontWeight: FontWeight.bold
      ))
     ..addText(letter);

    final paragraph = builder.build()
     ..layout(const ui.ParagraphConstraints(width: 256));

    // توسيط بالنص
    canvas.drawParagraph(
      paragraph,
      Offset(0, (size - paragraph.height) / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/letter_$id.png');
    await file.writeAsBytes(byteData!.buffer.asUint8List());
    return file.path;
  } catch (e) {
    return null;
  }
}

  Future<void> _saveToken({String? token}) async {
    try {
      String? fcmToken = token?? await _messaging.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (user!= null && fcmToken!= null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmTokens': FieldValue.arrayUnion([fcmToken]),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
    }
  }
}

