import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'system_notification_model.dart';

class SystemNotificationsProvider extends ChangeNotifier {
  final List<SystemNotification> _items = [];
  bool weeklyEnabled = true;
  final _pendingUsageNotifications = <String>{};

  static const String _historyKey = 'tini_system_notifications_history_v1';
  late final Future<void> _historyReady = _loadHistory();
  Future<void> _saveTail = Future<void>.value();
  bool _historyAvailable = false;
  bool _disposed = false;

  SystemNotificationsProvider() {
    _historyReady;
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) {
          throw const FormatException('Invalid system notifications history');
        }
        final restored = decoded.map((value) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid system notification');
          }
          return SystemNotification(
            id: value['id'] as String,
            type: SystemNotifType.values.byName(value['type'] as String),
            title: value['title'] as String,
            body: value['body'] as String,
            time: DateTime.parse(value['time'] as String),
            isRead: value['isRead'] as bool? ?? false,
            avgText: value['avgText'] as String? ?? '',
            percentText: value['percentText'] as String? ?? '',
            totalSeconds: value['totalSeconds'] as int? ?? 0,
          );
        }).toList();
        final existingIds = _items.map((item) => item.id).toSet();
        _items.addAll(restored.where((item) => !existingIds.contains(item.id)));
        _items.sort((a, b) => b.time.compareTo(a.time));
      }
      _historyAvailable = true;
      if (!_disposed) notifyListeners();
    } catch (error) {
      // Do not overwrite a history that could not be decoded or loaded.
      debugPrint('System notifications history load failed: $error');
    }
  }

  Future<void> _saveHistory() async {
    await _historyReady;
    if (!_historyAvailable) return;
    final snapshot = jsonEncode(_items.map((item) => {
      'id': item.id,
      'type': item.type.name,
      'title': item.title,
      'body': item.body,
      'time': item.time.toIso8601String(),
      'isRead': item.isRead,
      'avgText': item.avgText,
      'percentText': item.percentText,
      'totalSeconds': item.totalSeconds,
    }).toList());
    final operation = _saveTail.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_historyKey, snapshot)) {
        throw StateError('System notifications history could not be saved');
      }
    });
    _saveTail = operation.catchError((Object error) {
      debugPrint('System notifications history save failed: $error');
    });
    await operation;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<SystemNotification> get all => _items;
  List<SystemNotification> get updates =>
      _items.where((e) => e.type == SystemNotifType.usage).toList();
  List<SystemNotification> get reports =>
      _items.where((e) => e.type == SystemNotifType.report).toList();

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

    final date = "${now.year}-${now.month}-${now.day}";
    final request = 'weekly-$date';
    if (!_pendingUsageNotifications.add(request)) return;
    try {
      await _historyReady;
      final prefs = await SharedPreferences.getInstance();
      if (!weeklyEnabled ||
          prefs.getString('last_weekly_report_date') == date) {
        return;
      }
      if (!await prefs.setString('last_weekly_report_date', date)) {
        throw StateError('Weekly usage reminder could not be recorded');
      }
      _items.insert(
        0,
        SystemNotification(
          id: now.millisecondsSinceEpoch.toString(),
          type: SystemNotifType.usage,
          title: 'تقريرك الأسبوعي',
          body:
              'قضيت $hoursText خلال الأسبوع الماضي على Tini. حافظ على توازنك!',
          time: now,
          avgText: avgText,
          percentText: percentText,
          totalSeconds: totalSeconds,
        ),
      );
      notifyListeners();
      await _saveHistory();
    } finally {
      _pendingUsageNotifications.remove(request);
    }
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

  Future<void> addDailyLimitReached({
    required int limitMinutes,
    required int usedSeconds,
    DateTime? usageDay,
  }) async {
    final now = DateTime.now();
    final day = usageDay ?? now;
    final key = "${day.year}-${day.month}-${day.day}-daily-limit";
    final savedKey = 'titi_usage_notice_$key';
    if (!_pendingUsageNotifications.add(key)) return;
    try {
      await _historyReady;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(savedKey) == true ||
          prefs.getString('last_daily_limit_date') == key) {
        return;
      }
      if (!await prefs.setBool(savedKey, true)) {
        throw StateError('Daily usage reminder could not be recorded');
      }

      final hours = usedSeconds ~/ 3600;
      final minutes = usedSeconds ~/ 60 % 60;
      final duration = hours == 0
          ? '$minutes د'
          : minutes == 0
          ? '$hours س'
          : '$hours س $minutes د';
      final today =
          day.year == now.year && day.month == now.month && day.day == now.day;
      final when = today ? 'اليوم' : 'في ${day.day}/${day.month}/${day.year}';
      _items.insert(
        0,
        SystemNotification(
          id: now.millisecondsSinceEpoch.toString(),
          type: SystemNotifType.usage,
          title: 'تجاوزت الحد اليومي',
          body: 'قضيت $duration $when والحد هو $limitMinutes دقيقة',
          time: now,
          avgText: "",
          percentText: "",
          totalSeconds: usedSeconds,
        ),
      );
      notifyListeners();
      await _saveHistory();
    } finally {
      _pendingUsageNotifications.remove(key);
    }
  }

  void markAllRead() {
    for (final item in _items) {
      item.isRead = true;
    }
    notifyListeners();
    _saveHistory().catchError((Object error) {
      debugPrint('System notifications read state save failed: $error');
    });
  }

  void setWeeklyEnabled(bool v) {
    weeklyEnabled = v;
    notifyListeners();
  }
}
