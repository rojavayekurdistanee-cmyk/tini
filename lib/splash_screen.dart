import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom; // [الإضافة الذهبية]: حل التضارب هنا أيضاً
import 'app_navigator.dart';
import 'titi_single_engine.dart';
import 'post_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // [إضافة حماية]: متغير لمنع تكرار محاولة التنقل وإرهاق المعالج
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  void _navigateToNextScreen() async {
    // [إصلاح إشعار البوست]: إذا التطبيق فتح PostViewScreen من إشعار، لا تمسحو
    if (navigatorKey.currentState != null && navigatorKey.currentState!.canPop()) {
      return; 
    }
    if (_isNavigating) return;

    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);

    if (!authProvider.isAuthChecked) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _navigateToNextScreen();
      });
      return;
    }

    _isNavigating = true;
    final User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      if (authProvider.profileCompleted) {
        // [Tini - Instant Open]: سخن المحرك وجيب البوستات هون بالسبلاش
        try {
          TitiSingleEngine().ensureInitialized();
          final postProvider = Provider.of<PostProvider>(context, listen: false);
          await postProvider.fetchInitialPostsForSplash();
          if (postProvider.initialPosts.isNotEmpty) {
            final firstData = postProvider.initialPosts.first.data() as Map<String, dynamic>;
            final firstUrl = firstData['videoUrl'] ?? "";
            if (firstUrl.isNotEmpty) {
              await TitiSingleEngine().playUrl(firstUrl, autoPlay: false);
            }
            // [تحسين بدون تخريب]: حمل صور اول 3 فيديوهات بالرام مشان ما يصير وميض
            for (var doc in postProvider.initialPosts.take(3)) {
              try {
                final d = doc.data() as Map<String, dynamic>;
                final thumb = d['thumbnailUrl'] as String? ?? "";
                if (thumb.isNotEmpty) {
                  precacheImage(NetworkImage(thumb), context);
                }
              } catch (_) {}
            }
          }
        } catch (e) {
          debugPrint("Splash preload error: $e");
        }
        if (mounted) Navigator.pushReplacementNamed(context, '/home');
      } else {
        if (mounted) Navigator.pushReplacementNamed(context, '/nameSelection');
      }
    } else {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    // [تم التعديل]: لون الخلفية صار نفس لون خلفية الصورة + استدعاء صورة Tini الجديدة
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Container(
        color: const Color(0xFF000000),
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
  Image.asset(
    'assets/titi_splash.png',
    width: 300,
    fit: BoxFit.contain,
  ),
  const SizedBox(height: 25),
  ShaderMask(
  shaderCallback: (bounds) => const LinearGradient(
    colors: [
      Color(0xFF009688), // teal
      Color(0xFFFF1744), // red
      Color(0xFFFFEB3B), // yellow
    ],
  ).createShader(bounds),
  child: const Text(
    '𝕬𝖗𝖆𝖘',
    style: TextStyle(
      color: Colors.white, // لازم يبقى أبيض ليشتغل التدرج
      fontSize: 15,
      fontWeight: FontWeight.bold,
      letterSpacing: 2.0,
    ),
  ),
),
  const SizedBox(height: 25),
  const _BouncingDots(),
],
          ),
        ),
      ),
    );
  }
}

// [إضافة جديدة]: ويدجت حركة الدودة - 3 نقط أخضر أحمر أصفر
class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot({required Color color, required double delay}) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double value = (_controller.value - delay) % 1.0;
        if (value < 0) value += 1.0;
        double scale = 0.5 + (0.8 * (1 - (value - 0.5).abs() * 2).clamp(0.0, 1.0));
        double translateY = -15 * (1 - (value - 0.5).abs() * 2).clamp(0.0, 1.0);

        return Transform.translate(
          offset: Offset(0, translateY),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha:0.6),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDot(color: const Color(0xFF009688), delay: 0.0),
          const SizedBox(width: 12),
          _buildDot(color: const Color(0xFFFF1744), delay: 0.15),
          const SizedBox(width: 12),
          _buildDot(color: const Color(0xFFFFEB3B), delay: 0.30),
        ],
      ),
    );
  }
}