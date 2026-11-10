import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:firebase_app_check/firebase_app_check.dart'; 

// [Tini Heritage]: محرك الميديا وإدارة الحالة
import 'package:media_kit/media_kit.dart'; 
import 'package:audio_session/audio_session.dart'; 
import 'login_screen.dart';
import 'home_screen.dart'; 
import 'splash_screen.dart'; 
import 'auth_provider.dart' as custom; 
import 'post_provider.dart'; 
import 'music_provider.dart'; // تم الإضافة: استيراد محرك الموسيقى
import 'chat_provider.dart'; // تم الإضافة: استيراد مزود المحادثات
import 'group_chat_provider.dart';
import 'app_colors.dart'; // [تأكيد]: استيراد ملف الألوان لتوحيد الهوية
import 'search_provider.dart'; // تم الإضافة: استيراد مزود البحث
import 'story_provider.dart'; // تم الإضافة: استيراد مزود الستوري
import 'wallet_provider.dart' hide navigatorKey; // تم الإضافة: استيراد مزود المحفظة
import 'box_provider.dart'; // <<< أضفت هذا السطر: عشان الـ BoxProvider
import 'system_notifications_provider.dart';
import 'notification_service.dart'; // <<< حط هاد هون
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app_navigator.dart';
import 'global_banner_overlay.dart';
import 'activity_status_service.dart'; // [حالة النشاط] السيرفيس يلي خلصناه
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  // 1. تأمين استقرار التهيئة
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  // 2. [Tini]: تهيئة محرك الميديا
  MediaKit.ensureInitialized();

  // 3. [إصلاح الصوت النهائي]: إيقاظ قناة الصوت في النظام
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
    avAudioSessionMode: AVAudioSessionMode.moviePlayback,
    avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.movie,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  ));
  await session.setActive(true);

  // 4. تهيئة Firebase
  await Firebase.initializeApp();
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  // 4.1 [جديد]: تشغيل موتور الإشعارات
  await NotificationService().init();

  // 5. [App Check Debug]: تفعيل وضع التطوير
  const debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

  await FirebaseAppCheck.instance.activate(
    providerAndroid: AndroidDebugProvider(
      debugToken: debugToken.isEmpty ? null : debugToken,
    ),
    providerApple: const AppleDebugProvider(),
  );

  // 6. [الهوية البصرية]: ضبط ألوان النظام لتلتحم مع أشرطة Tini المعتمدة
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, 
    statusBarIconBrightness: Brightness.light, // أيقونات بيضاء فوق الزيتي
    systemNavigationBarColor: Colors.teal, 
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(
    MultiProvider(
      providers: [
                ChangeNotifierProvider(
  create: (_) {
    final auth = custom.AuthProvider();
    auth.fetchUserData().then((_) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc){
          if(doc.exists && doc.data()?['showActivityStatus'] != false){
            ActivityStatusService().init();
          }
        });
      }
    });
    return auth;
  },
),
        ChangeNotifierProxyProvider<custom.AuthProvider, PostProvider>(
          create: (_) => PostProvider(),
          update: (_, auth, post) {
            if (post != null) {
              post.syncHardBlockedFromCenter(auth.blockedUsers.toSet());
            }
            return post!;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => MusicProvider(), // تم الإضافة: تسجيل مزود الموسيقى
        ),
        ChangeNotifierProvider(
          create: (_) {
            final chat = ChatProvider();
            chat.initialize();
            return chat;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final group = GroupChatProvider();
            group.initialize();
            return group;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => SearchProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => StoryProvider(), // تم الإضافة: تسجيل مزود الستوري
        ),
        ChangeNotifierProvider(
          create: (_) => WalletProvider(), // تم الإضافة: تسجيل مزود المحفظة
        ),
        ChangeNotifierProvider(
          create: (_) => BoxProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => SystemNotificationsProvider(), // <-- جديد إشعارات النظام
        ),
      ],
      child: const TitiApp(),
    ),
  );
}

class TitiApp extends StatelessWidget {
  const TitiApp({super.key});

    @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // [Tini: إضافة IAP] - هذا السطر إجباري عشان الشرا
      debugShowCheckedModeBanner: false,
      title: 'Tini',
builder: (context, child) {
  return GlobalBannerOverlay(child: child!);
},
      // [حل مشكلة العمى اللوني]: إجبار التطبيق على قراءة سمات الوضع الداكن
      themeMode: ThemeMode.dark,  
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, // يضمن تحويل النصوص للأبيض تلقائياً
        scaffoldBackgroundColor: AppColors.background, // استخدام الزيتي من الملف مباشرة
        primaryColor: AppColors.primary, 
        
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          surface: AppColors.surface, 
          onSurface: Colors.white,
          error: AppColors.error, 
        ),
        
        fontFamily: 'Tajawal',
        
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.teal,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Tajawal', 
            fontWeight: FontWeight.bold, 
            fontSize: 18, 
            color: Colors.white
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),

        inputDecorationTheme: InputDecorationTheme(
          fillColor: AppColors.fieldFill, // استخدام الرمادي الفحمي من الملف
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        ),

        textTheme: const TextTheme(
          displayLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70), 
        ),
      ),
      
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) {
  final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
  return HomeScreen(openPostId: args?['postId']);
},
      },

      home: const SplashScreen(), 
    );
  }
}