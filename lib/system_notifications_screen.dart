import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'system_notifications_provider.dart';
import 'system_notification_model.dart';
import 'system_notification_detail_screen.dart';

class SystemNotificationsScreen extends StatefulWidget {
  const SystemNotificationsScreen({super.key});
  @override
  State<SystemNotificationsScreen> createState() => _SystemNotificationsScreenState();
}

class _SystemNotificationsScreenState extends State<SystemNotificationsScreen> {
  int selected = 0;
  Timer? _timeRefreshTimer;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('ar', timeago.ArMessages());
    _timeRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timeRefreshTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '$h ساعات و $m دقيقة';
    return '$m دقيقة';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SystemNotificationsProvider>();
    List<SystemNotification> list;
    if (selected == 1) list = provider.updates;
    else if (selected == 2) list = provider.reports;
    else list = provider.all;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        title: const Text('إشعارات النظام', style: TextStyle(fontFamily: 'Tajawal', color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _filter('الكل', 0),
                const SizedBox(width: 8),
                _filter('تحديثات الحساب', 1),
                const SizedBox(width: 8),
                _filter('إبلاغ', 2),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
            ? const Center(child: Text('لا يوجد إشعارات', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal')))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final item = list[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SystemNotificationDetailScreen(
                                hoursText: _formatDuration(item.totalSeconds),
                                avgText: item.avgText,
                                percentText: item.percentText,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A222C),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Icon(Icons.more_horiz, color: Colors.white38, size: 18),
                                  Row(
                                    children: [
                                      Text(
                                        item.type == SystemNotifType.usage? 'تحديثات الحساب' : 'إبلاغ',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Tajawal'),
                                      ),
                                      const SizedBox(width: 6),
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: item.type == SystemNotifType.usage? const Color(0xFF2196F3) : const Color(0xFFE53935),
                                        child: Icon(item.type == SystemNotifType.usage? Icons.arrow_upward : Icons.flag, size: 14, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Tajawal'), textAlign: TextAlign.right),
                              const SizedBox(height: 6),
                              Text(item.body, style: const TextStyle(color: Colors.white60, fontSize: 13, fontFamily: 'Tajawal'), textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(
                                timeago.format(item.time, locale: 'ar'),
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  fontFamily: 'Tajawal',
                                ),
                                textAlign: TextAlign.right,
                              ),
                              const SizedBox(height: 12),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text('عرض المزيد >', style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Tajawal')),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filter(String label, int index) {
    final isSel = selected == index;
    return InkWell(
      onTap: () => setState(() => selected = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSel? const Color(0xFFFF9800) : const Color(0xFF1A222C),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: isSel? Colors.white : Colors.white70, fontFamily: 'Tajawal', fontSize: 13, fontWeight: isSel? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}
