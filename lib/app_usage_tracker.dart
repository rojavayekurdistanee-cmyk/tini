import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'system_notifications_provider.dart';

const _storageKey = 'titi_app_usage_v2';
const _microsecondsPerSecond = Duration.microsecondsPerSecond;

String usageDateKey(DateTime date) =>
    "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

DateTime usageWeekStart(DateTime date, int offset) => DateTime(
  date.year,
  date.month,
  date.day - (date.weekday + 1) % 7 - offset * 7,
);

class UsageDay {
  const UsageDay({this.day = 0, this.night = 0, this.unknown = 0});

  // Retain fractions across pauses, boundaries and writes.
  final int day;
  final int night;
  final int unknown;
  int get total => day + night + unknown;

  UsageDay operator +(UsageDay other) => UsageDay(
    day: day + other.day,
    night: night + other.night,
    unknown: unknown + other.unknown,
  );

  List<int> toJson() => [day, night, unknown];
}

Map<String, UsageDay> splitUsage(DateTime start, DateTime end) {
  final result = <String, UsageDay>{};
  var cursor = start.toLocal();
  while (cursor.isBefore(end)) {
    final hour = cursor.hour;
    final daytime = hour >= 6 && hour < 18;
    final boundary = DateTime(
      cursor.year,
      cursor.month,
      cursor.day + (hour >= 18 ? 1 : 0),
      hour < 6
          ? 6
          : daytime
          ? 18
          : 0,
    );
    final until = boundary.isBefore(end) ? boundary : end;
    final elapsed = until.difference(cursor).inMicroseconds;
    final key = usageDateKey(cursor);
    final segment = daytime ? UsageDay(day: elapsed) : UsageDay(night: elapsed);
    result.update(
      key,
      (previous) => previous + segment,
      ifAbsent: () => segment,
    );
    cursor = until;
  }
  return result;
}

class AppUsageTracker extends ChangeNotifier with WidgetsBindingObserver {
  AppUsageTracker(
    this._notifications, {
    DateTime Function()? now,
    Stopwatch? stopwatch,
  }) : _now = now ?? DateTime.now,
       _stopwatch = stopwatch ?? Stopwatch();

  final SystemNotificationsProvider _notifications;
  final DateTime Function() _now;
  final Stopwatch _stopwatch;
  final _days = <String, UsageDay>{};
  final _dailyNotices = <String>{};
  final _weeklyNotices = <String>{};
  late final Future<void> ready;
  SharedPreferences? _prefs;
  File? _historyFile;
  bool _primaryHistoryValid = false;
  Timer? _saveRetry;
  int _retrySeconds = 1;
  DateTime? _sessionAnchor;
  int _accountedMicroseconds = 0;
  Timer? _timer;
  String? _measuredFrom;
  bool _disposed = false;
  bool _started = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _dirty = false;
  bool _dailyEnabled = false;
  bool _weeklyEnabled = false;
  int _limitMinutes = 60;
  Future<void> _settingsTail = Future<void>.value();
  StreamSubscription<User?>? _authStateSubscription;
  String? _cloudSettingsUid;
  String? _cloudSyncUid;
  Future<void>? _cloudSyncFuture;

  bool get loading => _loading;
  bool get loadFailed => _loadFailed;
  bool get dailyEnabled => _dailyEnabled;
  bool get weeklyEnabled => _weeklyEnabled;
  int get limitMinutes => _limitMinutes;
  DateTime get now => _now();

  UsageDay usageOn(DateTime date) =>
      _days[usageDateKey(date)] ?? const UsageDay();

  bool hasMeasurement(DateTime date) {
    final key = usageDateKey(date);
    return key.compareTo(usageDateKey(now)) <= 0 &&
        (_days.containsKey(key) ||
            (_measuredFrom != null && key.compareTo(_measuredFrom!) >= 0));
  }

  void start() {
    if (_started) return;
    _started = true;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final lifecycle = binding.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) _resume();
    ready = _load();
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (user == null) {
          _cloudSettingsUid = null;
          _cloudSyncUid = null;
          _cloudSyncFuture = null;
          return;
        }
        unawaited(_syncCloudSettings(user));
      },
      onError: (Object error) {
        debugPrint('Usage settings auth listener failed: $error');
      },
    );
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, UsageDay>? saved;
      var needsRecoveryWrite = false;
      if (!kIsWeb) {
        final directory = await getApplicationSupportDirectory();
        final file = File('${directory.path}/tini_usage_history.json');
        _historyFile = file;
        final backup = File('${file.path}.bak');
        if (await file.exists()) {
          try {
            saved = _readDays(prefs, await file.readAsString());
            _primaryHistoryValid = true;
          } catch (error) {
            debugPrint('Primary usage history is invalid: $error');
          }
        }
        if (saved == null && await backup.exists()) {
          try {
            saved = _readDays(prefs, await backup.readAsString());
            needsRecoveryWrite = true;
          } catch (error) {
            debugPrint('Usage history backup is invalid: $error');
          }
        }
        if (saved == null && await file.exists()) {
          // Never silently replace a damaged history with empty data.
          final legacy = prefs.getString(_storageKey);
          if (legacy == null &&
              !prefs.getKeys().any(
                (key) => RegExp(r'^usage_\d{4}-\d{2}-\d{2}$').hasMatch(key),
              )) {
            throw StateError('No valid usage history or backup is available');
          }
        }
      }
      if (_disposed) return;
      saved ??= _readDays(prefs, prefs.getString(_storageKey));
      for (final entry in saved.entries) {
        _days.update(
          entry.key,
          (pending) => entry.value + pending,
          ifAbsent: () => entry.value,
        );
      }
      _measuredFrom ??= usageDateKey(now);
      _dailyEnabled = prefs.getBool('titi_daily_limit') ?? false;
      _weeklyEnabled = prefs.getBool('titi_weekly_update') ?? false;
      _limitMinutes = prefs.getInt('titi_daily_limit_minutes') ?? 60;
      _prefs = prefs;
      _notifications.setWeeklyEnabled(_weeklyEnabled);
      _dirty = _dirty || needsRecoveryWrite || !_primaryHistoryValid;
    } catch (error) {
      _loadFailed = true;
      debugPrint('Usage history initialization failed: $error');
    } finally {
      if (!_disposed) {
        _loading = false;
        _checkpoint();
        _flush();
        notifyListeners();
      }
    }
  }

  Future<void> _syncCloudSettings(User user) async {
    final uid = user.uid;
    if (_cloudSettingsUid == uid) return;
    if (_cloudSyncUid == uid && _cloudSyncFuture != null) {
      await _cloudSyncFuture;
      return;
    }

    _cloudSyncUid = uid;
    final operation = () async {
      await ready;
      if (_disposed || FirebaseAuth.instance.currentUser?.uid != uid) return;
      final prefs = _prefs;
      if (prefs == null) return;

      try {
        final reference = FirebaseFirestore.instance.collection('users').doc(uid);
        final snapshot = await reference.get();
        if (_disposed || FirebaseAuth.instance.currentUser?.uid != uid) return;

        final stored = snapshot.data()?['appUsageSettings'];
        if (stored is Map) {
          final daily = stored['dailyEnabled'];
          final weekly = stored['weeklyEnabled'];
          final limit = stored['limitMinutes'];
          final restoredDaily = daily is bool ? daily : _dailyEnabled;
          final restoredWeekly = weekly is bool ? weekly : _weeklyEnabled;
          final restoredLimit = limit is num
              ? limit.toInt().clamp(1, 1440)
              : _limitMinutes;

          await prefs.setBool('titi_daily_limit', restoredDaily);
          await prefs.setBool('titi_weekly_update', restoredWeekly);
          await prefs.setInt('titi_daily_limit_minutes', restoredLimit);

          if (_disposed || FirebaseAuth.instance.currentUser?.uid != uid) return;
          _dailyEnabled = restoredDaily;
          _weeklyEnabled = restoredWeekly;
          _limitMinutes = restoredLimit;
          _notifications.setWeeklyEnabled(_weeklyEnabled);
        } else {
          await reference.set({
            'appUsageSettings': {
              'dailyEnabled': _dailyEnabled,
              'weeklyEnabled': _weeklyEnabled,
              'limitMinutes': _limitMinutes,
            },
          }, SetOptions(merge: true));
        }

        if (!_disposed && FirebaseAuth.instance.currentUser?.uid == uid) {
          _cloudSettingsUid = uid;
          notifyListeners();
        }
      } catch (error) {
        debugPrint('Usage settings cloud sync failed: $error');
      }
    }();

    _cloudSyncFuture = operation;
    await operation;
    if (_cloudSyncUid == uid) {
      _cloudSyncUid = null;
      _cloudSyncFuture = null;
    }
  }

  Future<void> _saveCloudSettingsIfReady() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _cloudSettingsUid != user.uid) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'appUsageSettings': {
          'dailyEnabled': _dailyEnabled,
          'weeklyEnabled': _weeklyEnabled,
          'limitMinutes': _limitMinutes,
        },
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Usage settings cloud save failed: $error');
    }
  }

  Map<String, UsageDay> _readDays(SharedPreferences prefs, String? stored) {
    if (stored != null) {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      final days = data['days'] as Map<String, dynamic>;
      final decoded = <String, UsageDay>{
        for (final entry in days.entries)
          entry.key: UsageDay(
            day: (entry.value as List)[0] as int,
            night: (entry.value as List)[1] as int,
            unknown: (entry.value as List)[2] as int,
          ),
      };
      final first = data['measuredFrom'] as String?;
      if (first != null &&
          (_measuredFrom == null || first.compareTo(_measuredFrom!) < 0)) {
        _measuredFrom = first;
      }
      return decoded;
    }
    return {
      for (final key in prefs.getKeys())
        if (RegExp(r'^usage_\d{4}-\d{2}-\d{2}$').hasMatch(key))
          key.substring(6): UsageDay(
            unknown: (prefs.getInt(key) ?? 0) * _microsecondsPerSecond,
          ),
    };
  }

  void _resume() {
    if (_sessionAnchor != null) return;
    _sessionAnchor = now;
    _measuredFrom ??= usageDateKey(_sessionAnchor!);
    _accountedMicroseconds = 0;
    _stopwatch
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _checkpoint());
  }

  void _pause() {
    if (_sessionAnchor == null) return;
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    _checkpoint();
    _sessionAnchor = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      _resume();
      if (!_loading && _prefs != null) notifyListeners();
    } else {
      _pause();
    }
  }

  void _checkpoint() {
    final anchor = _sessionAnchor;
    if (anchor == null) return;
    final elapsed = _stopwatch.elapsedMicroseconds;
    final start = anchor.add(Duration(microseconds: _accountedMicroseconds));
    final end = anchor.add(Duration(microseconds: elapsed));
    _accountedMicroseconds = elapsed;
    final portions = splitUsage(start, end);
    for (final entry in portions.entries) {
      _days.update(
        entry.key,
        (current) => current + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    if (portions.isNotEmpty) _dirty = true;
    if (_loading || _prefs == null) return;
    _flush();
    if (!_disposed) {
      for (final key in portions.keys) {
        _checkDaily(DateTime.parse(key));
      }
      _checkWeekly();
      if (portions.isNotEmpty) notifyListeners();
    }
  }

  void _flush() {
    if (_saving || !_dirty || _prefs == null) return;
    _saveRetry?.cancel();
    _saveRetry = null;
    _saving = true;
    unawaited(_write());
  }

  Future<void> _write() async {
    try {
      while (_dirty) {
        _dirty = false;
        final value = jsonEncode({
          'measuredFrom': _measuredFrom,
          'days': _days.map((key, day) => MapEntry(key, day.toJson())),
        });
        final file = _historyFile;
        if (file != null) {
          // Keep the last valid snapshot as a recoverable backup.
          // A corrupt primary must never overwrite a good backup.
          if (_primaryHistoryValid && await file.exists()) {
            final backup = File('${file.path}.bak');
            final backupStaging = File('${backup.path}.tmp');
            await file.copy(backupStaging.path);
            if (await backup.exists()) await backup.delete();
            await backupStaging.rename(backup.path);
          }
          final staging = File('${file.path}.tmp');
          await staging.writeAsString(value, flush: true);
          await staging.rename(file.path);
          _primaryHistoryValid = true;
        } else if (!await _prefs!.setString(_storageKey, value)) {
          throw StateError('Usage history was not saved');
        }
        _retrySeconds = 1;
      }
    } catch (error) {
      _dirty = true;
      debugPrint('Usage history save failed: $error');
      if (_prefs != null) {
        // Continue a pending save even if the widget/provider was disposed.
        _saveRetry = Timer(Duration(seconds: _retrySeconds), _flush);
        _retrySeconds = (_retrySeconds * 2).clamp(1, 10);
      }
    } finally {
      _saving = false;
    }
  }

  void _checkDaily(DateTime date) {
    final key = usageDateKey(date);
    final used = usageOn(date).total ~/ _microsecondsPerSecond;
    if (!_dailyEnabled ||
        used < _limitMinutes * 60 ||
        !_dailyNotices.add(key)) {
      return;
    }
    unawaited(
      _notifications
          .addDailyLimitReached(
            limitMinutes: _limitMinutes,
            usedSeconds: used,
            usageDay: date,
          )
          .catchError((Object error) {
            _dailyNotices.remove(key);
            debugPrint('Usage limit notification failed: $error');
          }),
    );
  }

  void _checkWeekly() {
    final current = now;
    if (!_weeklyEnabled || current.weekday != DateTime.saturday) return;
    final key = usageDateKey(current);
    final start = usageWeekStart(current, 1);
    final days = List.generate(
      7,
      (i) => DateTime(start.year, start.month, start.day + i),
    );
    final measured = days.where(hasMeasurement).toList();
    if (measured.isEmpty || !_weeklyNotices.add(key)) return;
    final total =
        days.fold<int>(0, (sum, day) => sum + usageOn(day).total) ~/
        _microsecondsPerSecond;
    final older = usageWeekStart(current, 2);
    final previous =
        List.generate(
          7,
          (i) => DateTime(older.year, older.month, older.day + i),
        ).fold<int>(0, (sum, day) => sum + usageOn(day).total) ~/
        _microsecondsPerSecond;
    final change = previous == 0 ? 0.0 : (total - previous) * 100 / previous;
    unawaited(
      _notifications
          .addWeeklyReportIfSaturday(
            hoursText: _notificationDuration(total),
            avgText:
                '${_notificationDuration(total ~/ measured.length)} يومياً',
            percentText: previous == 0
                ? 'أول أسبوع لك'
                : "${change.abs().toStringAsFixed(0)}% ${change >= 0 ? 'أكثر' : 'أقل'} من الأسبوع الماضي",
            totalSeconds: total,
          )
          .catchError((Object error) {
            _weeklyNotices.remove(key);
            debugPrint('Weekly usage notification failed: $error');
          }),
    );
  }

  String _notificationDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = seconds ~/ 60 % 60;
    if (hours == 0) return minutes == 0 ? '$seconds ث' : '$minutes د';
    return minutes == 0 ? '$hours س' : '$hours س $minutes د';
  }

  Future<bool> _setPreference(
    Future<bool> Function(SharedPreferences) save,
    VoidCallback update,
  ) async {
    await ready;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && _cloudSettingsUid != currentUser.uid) {
      await _syncCloudSettings(currentUser);
    }
    if (_prefs == null || _disposed) return false;
    var succeeded = false;
    final operation = _settingsTail.then((_) async {
      if (_disposed) return;
      try {
        if (!await save(_prefs!)) return;
        if (_disposed) return;
        update();
        succeeded = true;
        notifyListeners();
        await _saveCloudSettingsIfReady();
      } catch (error) {
        debugPrint('Usage preference save failed: $error');
      }
    });
    _settingsTail = operation;
    await operation;
    return succeeded;
  }

  Future<bool> setDailyEnabled(bool value) =>
      _setPreference((prefs) => prefs.setBool('titi_daily_limit', value), () {
        _dailyEnabled = value;
        _checkDaily(now);
      });

  Future<bool> setLimitMinutes(int value) => _setPreference(
    (prefs) => prefs.setInt('titi_daily_limit_minutes', value),
    () {
      _limitMinutes = value;
      _checkDaily(now);
    },
  );

  Future<bool> setWeeklyEnabled(bool value) =>
      _setPreference((prefs) => prefs.setBool('titi_weekly_update', value), () {
        _weeklyEnabled = value;
        _notifications.setWeeklyEnabled(value);
        _checkWeekly();
      });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authStateSubscription?.cancel();
    _disposed = true;
    _pause();
    // _pause checkpoints the final interval. Keep pending writes/retries alive
    // until they succeed, rather than cancelling them during disposal.
    _flush();
    super.dispose();
  }
}