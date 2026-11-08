import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'system_notification_model.dart';

class SystemNotificationsProvider extends ChangeNotifier {
  final List<SystemNotification> _items = [];
  bool weeklyEnabled = true;

  List<SystemNotification> get all => _items;
  List<SystemNotification> get updates => _items.where((e) => e.type == SystemNotifType.usage).toList();
  List<SystemNotification> get reports => _items.where((e) => e.type == SystemNotifType.report).toList();

  int get unreadCount => _items.where((e) => !e.isRead).length;
  SystemNotification? get last => _items.isNotEmpty ? _items.first : null;

  // ديناميك 100% - هلا بتاخد كل القيم ديناميك
  Future<void> addWeeklyReportIfSaturday({
    required String hoursText,
    required String avgText,
    required String percentText,
    required int totalSeconds,
  }) async {
    if (!weeklyEnabled) return;
    
    final now = DateTime.now();
    
    if (now.weekday != DateTime.saturday) {
      debugPrint("اليوم مو سبت، ما رح نعمل اشعار");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString('last_weekly_report_date');
    final todayStr = "${now.year}-${now.month}-${now.day}";

    if (lastDate == todayStr) {
      debugPrint("اشعار هالسبت انبعت قبل");
      return;
    }

    _items.insert(0, SystemNotification(
      id: now.millisecondsSinceEpoch.toString(),
      type: SystemNotifType.usage,
      title: 'تقريرك الأسبوعي',
      body: 'قضيت $hoursText هذا الأسبوع على Tini. حافظ على توازنك!',
      time: now,
      avgText: avgText,
      percentText: percentText,
      totalSeconds: totalSeconds,
    ));

    await prefs.setString('last_weekly_report_date', todayStr);
    notifyListeners();
  }

  // للتوافق مع الكود القديم - ديناميك كمان
  void addWeeklyReport({
    required String hoursText,
    String avgText = "",
    String percentText = "",
    int totalSeconds = 0,
  }) {
    addWeeklyReportIfSaturday(
      hoursText: hoursText,
      avgText: avgText,
      percentText: percentText,
      totalSeconds: totalSeconds,
    );
  }

  Future<void> addDailyLimitReached({required int limitMinutes, required int usedSeconds}) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final todayKey = "${now.year}-${now.month}-${now.day}-daily-limit";
    final last = prefs.getString('last_daily_limit_date');
    if (last == todayKey) return;

    String format(int s) {
      int h = s ~/ 3600;
      int m = (s % 3600) ~/ 60;
      if (h == 0) return "$m د";
      if (m == 0) return "$h س";
      return "$h س $m د";
    }

    _items.insert(0, SystemNotification(
      id: now.millisecondsSinceEpoch.toString(),
      type: SystemNotifType.usage,
      title: 'تجاوزت الحد اليومي',
      body: 'قضيت ${format(usedSeconds)} اليوم والحد هو $limitMinutes دقيقة',
      time: now,
      avgText: "",
      percentText: "",
      totalSeconds: usedSeconds,
    ));

    await prefs.setString('last_daily_limit_date', todayKey);
    notifyListeners();
  }

  void markAllRead() {
    for (var e in _items) e.isRead = true;
    notifyListeners();
  }

  void setWeeklyEnabled(bool v) {
    weeklyEnabled = v;
    notifyListeners();
  }
}