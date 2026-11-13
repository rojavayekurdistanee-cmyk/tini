import 'dart:async';
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

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (message.data['type'] == 'message' || message.data['type'] == 'chat') {
    try {
      await FirebaseFirestore.instance.collection('chat_rooms').doc(message.data['roomId']).collection('messages').doc(message.data['messageId']).update({'isDelivered': true});
    } catch(e){}
  }
  final service = NotificationService();
  await service.initForBackground();

  final data = message.data;
  final avatarUrl = data['avatar']?? "";
  final title = data['title']?? "Tini";
  final body = data['body']?? "";

  await service.showBackgroundNotification(title, body, avatarUrl, data);
}

class NotificationService {
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // Verify the current post and owner before downloading rich notification media.
  // A background isolate has its own access state and must verify on the server.
  Future<bool> _mayShowPostNotification(Map<String, dynamic> data) async {
    final type = (data['type'] ?? '').toString();
    if (type == 'message' || type == 'chat' || type == 'group' || type == 'private_message') return true;
    final postId = (data['postId'] ?? '').toString();
    if (postId.isEmpty) {
      // Do not expose an unidentifiable post thumbnail from an older payload.
      return !['postImage', 'bigPicture', 'imageUrl', 'mediaUrl', 'thumbnailUrl']
          .any((key) => (data[key] ?? '').toString().isNotEmpty);
    }
    try {
      return await AudienceAccess.instance.verifyPost(postId);
    } catch (_) {
      return false;
    }
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
      // Banner presentation and the device notification are independent.
      // A handled/seen/grouped banner must never consume the FCM delivery.
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(BannerManager.instance.handleForegroundActivity(message.data)
            .then<void>((_) {}, onError: (Object error, StackTrace stack) {
          debugPrint('Foreground banner processing failed: $error');
        }));
      }
      await _showNotification(message, androidChannel);
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

    Future<void> showBackgroundNotification(String title, String body, String avatarUrl, Map<String, dynamic> data) async {
    final notificationViewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (!await _mayShowPostNotification(data)) return;

        // [Titi Update] - معاينة الرسائل الخاصة (خلفية) + زر following
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
        return;
      }
      final mutedGroups = prefs.getStringList('muted_group_rooms')?? [];
      if (data['groupId']!= null && mutedGroups.contains(data['groupId'].toString())) {
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

    FilePathAndroidBitmap? largeIcon;
    BigPictureStyleInformation? bigPictureStyle;

    final postImageUrl = privateViewOnce ? "" : (data['postImage']?? data['bigPicture']?? data['imageUrl']?? data['mediaUrl']?? data['thumbnailUrl']?? "");
    if (privateViewOnce && previewEnabled) {
      body = "لديك رسالة لمرة واحدة";
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

    if (FirebaseAuth.instance.currentUser?.uid != notificationViewerUid) return;
    if (!await _mayShowPostNotification(data)) return;
    if (FirebaseAuth.instance.currentUser?.uid != notificationViewerUid) return;
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
  }

    Future<void> _showNotification(RemoteMessage message, AndroidNotificationChannel channel) async {
    final notification = message.notification;
    final data = message.data;
    final notificationViewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (!await _mayShowPostNotification(data)) return;

        // [Titi Update] - معاينة الرسائل الخاصة + زر following
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
        return;
      }
      final mutedGroups = prefs.getStringList('muted_group_rooms')?? [];
      if (data['groupId']!= null && mutedGroups.contains(data['groupId'].toString())) {
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
    }

final payloadData = jsonEncode({'postId': message.data['postId'], 'commentId': message.data['commentId'], 'type': message.data['type'], 'fromUid': message.data['fromUid'], 'roomId': message.data['roomId'], 'groupId': message.data['groupId']});

    if (FirebaseAuth.instance.currentUser?.uid != notificationViewerUid) return;
    if (!await _mayShowPostNotification(data)) return;
    if (FirebaseAuth.instance.currentUser?.uid != notificationViewerUid) return;
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