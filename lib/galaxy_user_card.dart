import 'package:flutter/material.dart';
import 'galaxy_user_star.dart';

class GalaxyUserCard extends StatelessWidget {
  final GalaxyUserStar star;
  final VoidCallback onVisit;
  const GalaxyUserCard({super.key, required this.star, required this.onVisit});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFF163A40),
            child: ClipOval(
              child: star.profileImg.isEmpty
                  ? _initial()
                  : Image.network(
                      star.profileImg,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stack) => _initial(),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            star.fullName,
            style: const TextStyle(color: Colors.white, fontSize: 19),
          ),
          Text(
            '@${star.username}',
            style: const TextStyle(color: Color(0xFF80CBC4)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onVisit,
            child: const Text('زيارة الملف الشخصي'),
          ),
        ],
      ),
    ),
  );
  Widget _initial() => Text(
    star.fullName.trim().isEmpty ? '؟' : star.fullName.trim().characters.first,
    style: const TextStyle(color: Colors.white, fontSize: 26),
  );
}