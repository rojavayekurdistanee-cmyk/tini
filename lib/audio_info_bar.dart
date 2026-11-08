import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'auth_provider.dart' as custom;

class AudioInfoBar extends StatefulWidget {
  final Map<String, dynamic> postData;
  final custom.AuthProvider auth;

  const AudioInfoBar({
    super.key,
    required this.postData,
    required this.auth,
  });

  @override
  State<AudioInfoBar> createState() => _AudioInfoBarState();
}

class _AudioInfoBarState extends State<AudioInfoBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // المسميات الموحدة
    final String cover = widget.postData['songCover'] ?? '';
    final String title = widget.postData['songTitle'] ?? 'صوت أصلي';
    final String artist = widget.postData['songArtist'] ?? widget.postData['username'] ?? 'مستخدم';
    
    // إضافة متغير المصدر للتوثيق القانوني
    final String source = widget.postData['songSource'] ?? 'original'; 

    return Container(
      color: Colors.teal, // اللون المعتمد للهوية البصرية
      height: MediaQuery.of(context).size.height * 0.0695,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // أيقونة تتغير بناءً على مصدر الصوت للشفافية القانونية
          Icon(
            source == 'itunes' ? Icons.music_note : Icons.mic, 
            color: Colors.white, 
            size: 20
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$title - $artist",
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          RotationTransition(
            turns: _controller,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: cover.isNotEmpty ? cover : widget.auth.profileImg,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}