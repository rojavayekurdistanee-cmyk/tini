import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'system_notifications_provider.dart';
import 'system_notifications_screen.dart';

class SystemNotificationsBanner extends StatelessWidget {
  const SystemNotificationsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SystemNotificationsProvider>();
    final count = provider.unreadCount;
    final last = provider.last;

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SystemNotificationsScreen()));
        provider.markAllRead();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A222C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFF1C1C1E),
                  child: Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('إشعارات النظام',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Tajawal'),
                          textAlign: TextAlign.right),
                      const SizedBox(height: 2),
                      Text(
                        count > 0? (last?.title?? '') : 'لا يوجد إشعارات جديدة',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Tajawal'),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (count > 0)
            Positioned(
              top: -4, right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFF0F1720), width: 2),
                ),
                child: Text(count > 99? '99+' : '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
                    textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}