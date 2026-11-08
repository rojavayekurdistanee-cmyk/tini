import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'system_notifications_provider.dart';

class TimeOnAppScreen extends StatefulWidget {
  const TimeOnAppScreen({super.key});

  @override
  State<TimeOnAppScreen> createState() => _TimeOnAppScreenState();
}

class _TimeOnAppScreenState extends State<TimeOnAppScreen> with WidgetsBindingObserver {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);

  bool isDailyLimitEnabled = false;
  bool isWeeklyUpdateEnabled = false;
  int _dailyLimitMinutes = 60;

  Timer? _saveTimer;
  Timer? _uiTimer;
  DateTime? _sessionStart;
  int _currentWeekOffset = 0;
  int _selectedIndex = -1;
  bool _showInfoTooltip = false;

  Map<String, int> _usageByDay = {};
  bool _loading = true;

  final List<String> _arabicMonths = ["يناير","فبراير","مارس","أبريل","مايو","يونيو","يوليو","أغسطس","سبتمبر","أكتوبر","نوفمبر","ديسمبر"];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _startSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSession();
    _saveTimer?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSession();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stopSession();
    }
  }

  void _startSession() {
    _sessionStart = DateTime.now();
    _saveTimer?.cancel();
    _uiTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveTick());
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopSession() async {
    await _saveTick();
    _saveTimer?.cancel();
    _uiTimer?.cancel();
    _sessionStart = null;
  }

  Future<void> _saveTick() async {
    if (_sessionStart == null) return;
    final now = DateTime.now();
    final diff = now.difference(_sessionStart!).inSeconds;
    if (diff < 1) return;
    final key = _dateKey(now);
    _usageByDay[key] = (_usageByDay[key]?? 0) + diff;
    _sessionStart = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('usage_$key', _usageByDay[key]!);
    await prefs.setStringList('usage_days', _usageByDay.keys.toList());

    if (isDailyLimitEnabled) {
      int limitSecs = _dailyLimitMinutes * 60;
      if (_usageByDay[key]! >= limitSecs) {
        if (mounted) {
          context.read<SystemNotificationsProvider>().addDailyLimitReached(
            limitMinutes: _dailyLimitMinutes,
            usedSeconds: _usageByDay[key]!,
          );
        }
      }
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    isDailyLimitEnabled = prefs.getBool('titi_daily_limit')?? false;
    isWeeklyUpdateEnabled = prefs.getBool('titi_weekly_update')?? false;
    _dailyLimitMinutes = prefs.getInt('titi_daily_limit_minutes')?? 60;
    final days = prefs.getStringList('usage_days')?? [];
    Map<String, int> map = {};
    for (var d in days) {
      map[d] = prefs.getInt('usage_$d')?? 0;
    }
    final todayKey = _dateKey(DateTime.now());
    map.putIfAbsent(todayKey, () => 0);
    setState(() {
      _usageByDay = map;
      _loading = false;
    });
  }

  String _dateKey(DateTime dt) => "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";

  DateTime _getWeekStart(int offset) {
    final now = DateTime.now();
    int daysSinceSaturday = (now.weekday + 1) % 7;
    DateTime thisSaturday = now.subtract(Duration(days: daysSinceSaturday));
    return thisSaturday.subtract(Duration(days: offset * 7));
  }

  List<DateTime> _getWeekDays(int offset) {
    final start = _getWeekStart(offset);
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  String _formatRange(List<DateTime> days) {
    final first = days.first;
    final last = days.last;
    if (first.month == last.month) {
      return "${first.day} - ${last.day} ${_arabicMonths[last.month - 1]}";
    } else {
      return "${first.day} ${_arabicMonths[first.month - 1]} - ${last.day} ${_arabicMonths[last.month - 1]}";
    }
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds < 60) return "$totalSeconds ث";
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h == 0) return "$m د";
    if (m == 0) return "$h س";
    return "$h س $m د";
  }

  String _formatHM(int secs) {
    int h = secs ~/ 3600;
    int m = (secs % 3600) ~/ 60;
    if (h == 0) return "$m د";
    if (m == 0) return "$h س";
    return "$h س $m د";
  }

  String _formatLimit(int mins) {
    if (mins < 60) {
      return "$mins د";
    }
    if (mins == 60) {
      return "1 س";
    }
    if (mins == 120) {
      return "ساعتان";
    }
    int h = mins ~/ 60;
    int m = mins % 60;
    if (m == 0) {
      return "$h س";
    }
    return "$h س $m د";
  }

  void _showTopToast(String msg) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 40,
        right: 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFF2A3542), borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10)]),
            child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.center),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  void _toggleInfoTooltip() {
    setState(() => _showInfoTooltip = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showInfoTooltip = false);
    });
  }

  Future<void> _toggleDailyLimit(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('titi_daily_limit', v);
    setState(() => isDailyLimitEnabled = v);
    if (v) {
      _showTopToast("تم ضبط مدة الاستخدام اليومية إلى ${_formatLimit(_dailyLimitMinutes)}");
    } else {
      _showTopToast("تم إيقاف تشغيل مدة الاستخدام اليومية");
    }
  }

  void _showDailyLimitSheet() {
    if (!isDailyLimitEnabled) return;
    final options = [10, 15, 20, 30, 60, 120];
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                const Text("الحد اليومي الأقصى", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: options.map((m) {
                        bool selected = m == _dailyLimitMinutes;
                        String label;
                        if (m == 10) {
                          label = "من الدقائق 10";
                        } else if (m == 15) {
                          label = "من الدقائق 15";
                        } else if (m == 20) {
                          label = "من الدقائق 20";
                        } else if (m == 30) {
                          label = "من الدقائق 30";
                        } else if (m == 60) {
                          label = "ساعة واحدة";
                        } else {
                          label = "ساعتان";
                        }
                        return InkWell(
                          onTap: () async {
                            final p = await SharedPreferences.getInstance();
                            await p.setInt('titi_daily_limit_minutes', m);
                            setState(() => _dailyLimitMinutes = m);
                            if (mounted) Navigator.pop(context);
                            _showTopToast("تم ضبط مدة الاستخدام اليومية إلى ${_formatLimit(m)}");
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected? const Color(0xFF14B8A6) : Colors.white24, width: 2), color: selected? const Color(0xFF14B8A6) : Colors.transparent),
                                  child: selected? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                                ),
                                Text(label, style: TextStyle(color: selected? Colors.white : Colors.white.withValues(alpha: 0.7), fontSize: 14, fontWeight: selected? FontWeight.bold : FontWeight.normal)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF14B8A6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("تم", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _tryGenerateSaturdayReport(int currentTotal, int avgSeconds, double percentChange, bool isUp, int prevTotal) {
    if (!isWeeklyUpdateEnabled) return;
    if (_currentWeekOffset!= 0) return;
    if (DateTime.now().weekday!= DateTime.saturday) return;

    final avgText = "${_formatDuration(avgSeconds)} يومياً";
    final percentText = prevTotal == 0? "أول أسبوع لك" : "${percentChange.abs().toStringAsFixed(0)}% ${isUp? 'أكثر' : 'أقل'} من الأسبوع الماضي";

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SystemNotificationsProvider>().addWeeklyReportIfSaturday(
        hoursText: _formatDuration(currentTotal),
        avgText: avgText,
        percentText: percentText,
        totalSeconds: currentTotal,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(backgroundColor: bgColor, body: const Center(child: CircularProgressIndicator(color: Colors.teal)));
    }

    final currentWeekDays = _getWeekDays(_currentWeekOffset);
    final prevWeekDays = _getWeekDays(_currentWeekOffset + 1);

    int currentTotal = 0;
    List<Map<String, dynamic>> chartData = [];
    for (var day in currentWeekDays) {
      int secs = _usageByDay[_dateKey(day)]?? 0;
      if (_currentWeekOffset == 0 && _dateKey(day) == _dateKey(DateTime.now()) && _sessionStart!= null) {
        secs += DateTime.now().difference(_sessionStart!).inSeconds;
      }
      currentTotal += secs;
      int dayTime = (secs * 0.7).toInt();
      int nightTime = secs - dayTime;
      chartData.add({"date": day, "dayTime": dayTime, "nightTime": nightTime, "total": secs});
    }

    int prevTotal = 0;
    for (var day in prevWeekDays) {
      prevTotal += _usageByDay[_dateKey(day)]?? 0;
    }

    int avgSeconds = currentTotal ~/ 7;
    double percentChange = 0;
    bool isUp = true;
    if (prevTotal > 0) {
      percentChange = ((currentTotal - prevTotal) / prevTotal * 100);
      isUp = percentChange >= 0;
    }

    _tryGenerateSaturdayReport(currentTotal, avgSeconds, percentChange, isUp, prevTotal);

    int maxReal = chartData.map((e) => e["total"] as int).fold(0, (a, b) => a > b? a : b);
    int maxSec;
    int minSec;
    if (maxReal < 6 * 3600) {
      maxSec = 6 * 3600;
      minSec = 0;
    } else {
      maxSec = ((maxReal / 3600).ceil() + 1) * 3600;
      minSec = maxSec - 6 * 3600;
      if (minSec < 0) {
        minSec = 0;
      }
    }
    int range = maxSec - minSec;
    if (range <= 0) {
      range = 6 * 3600;
    }

    List<int> yLabels = [minSec, minSec + range ~/ 3, minSec + (range * 2 ~/ 3), maxSec];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("مدة الاستخدام", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text("المتوسط اليومي", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _toggleInfoTooltip,
                      child: Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.5), size: 18),
                    ),
                  ]),
                  if (_showInfoTooltip)
                    Positioned(
                      top: 28,
                      right: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A3542),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)],
                        ),
                        child: Text(
                          "تتضمن المقاييس الوقت الذي تقضيه في تطبيق Tini فقط، ويتم حسابه من آخر 7 أيام.",
                          style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.6),
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                textDirection: TextDirection.rtl,
                children: [
                  Text(_formatDuration(avgSeconds), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  if (prevTotal > 0)
                    Row(children: [
                      Icon(isUp? Icons.arrow_drop_up : Icons.arrow_drop_down, color: isUp? Colors.white38 : Colors.teal, size: 24),
                      Text("${percentChange.abs().toStringAsFixed(0)}% من الأسبوع الماضي", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                    ])
                  else
                    Text("أول أسبوع لك", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                ],
              ),
            ]),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              InkWell(
                onTap: () {
                  if (_currentWeekOffset > 0) {
                    setState(() { _currentWeekOffset--; _selectedIndex = -1; });
                  }
                },
                child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _currentWeekOffset == 0? Colors.white.withValues(alpha: 0.05) : Colors.white10, shape: BoxShape.circle), child: Icon(Icons.arrow_forward_ios, color: _currentWeekOffset == 0? Colors.white10 : Colors.white54, size: 12)),
              ),
              Text(_formatRange(currentWeekDays), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: () => setState(() { _currentWeekOffset++; _selectedIndex = -1; }),
                child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle), child: const Icon(Icons.arrow_back_ios, color: Colors.white54, size: 12)),
              ),
            ]),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(16, 18, 8, 14),
            decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                SizedBox(
                  height: 180,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: LayoutBuilder(builder: (context, cons) {
                          return Stack(
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: yLabels.reversed.map((_) {
                                  return Row(children: [Expanded(child: SizedBox(height: 1, child: Row(children: List.generate(100, (i) => Expanded(child: Container(margin: EdgeInsets.symmetric(horizontal: 2), height: 1, color: Colors.white.withValues(alpha: 0.15)))))))]);
                                }).toList(),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(chartData.length, (index) {
                                  final d = chartData[index];
                                  int total = d["total"] as int;
                                  bool isSelected = index == _selectedIndex;
                                  double hFactor = total <= minSec? 0 : (total - minSec) / range;
                                  double totalH = (hFactor * 160).clamp(0, 160);
                                  double dayRatio = total > 0? (d["dayTime"] as int) / total : 0;
                                  double dayH = totalH * dayRatio;
                                  double nightH = totalH - dayH;

                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedIndex = index),
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        height: 160,
                                        child: Stack(
                                          alignment: Alignment.bottomCenter,
                                          clipBehavior: Clip.none,
                                          children: [
                                            if (isSelected)
                                              SizedBox(width: double.infinity, height: double.infinity, child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFF3B82F6).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)))),
                                            Align(
                                              alignment: Alignment.bottomCenter,
                                              child: SizedBox(
                                                width: double.infinity,
                                                height: totalH < 4 && total > 0? 4 : totalH,
                                                child: total == 0? null : Opacity(
                                                  opacity: isSelected? 1 : 0.55,
                                                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                                    if (nightH > 0) Container(height: nightH, decoration: BoxDecoration(color: const Color(0xFF00E5FF), borderRadius: BorderRadius.vertical(top: Radius.circular(4)))),
                                                    if (dayH > 0) Container(height: dayH, decoration: BoxDecoration(color: const Color(0xFF1E90FF), borderRadius: BorderRadius.vertical(top: nightH == 0? Radius.circular(4) : Radius.zero))),
                                                  ]),
                                                ),
                                              ),
                                            ),
                                            if (isSelected && total > 0)
                                              Positioned(
                                                bottom: totalH + 10,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10)]),
                                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                    Text("${d["date"].day} ${_arabicMonths[d["date"].month - 1]}", style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold)),
                                                    SizedBox(height: 1, width: 90, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black12))),
                                                    Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: Color(0xFF1E90FF), borderRadius: BorderRadius.circular(2))), SizedBox(width: 6), Text("${_formatHM(d["dayTime"])} وقت النهار", style: TextStyle(color: Colors.black87, fontSize: 11))]),
                                                    SizedBox(height: 4),
                                                    Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: Color(0xFF00E5FF), borderRadius: BorderRadius.circular(2))), SizedBox(width: 6), Text("${_formatHM(d["nightTime"])} وقت الليل", style: TextStyle(color: Colors.black54, fontSize: 11))]),
                                                  ]),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          );
                        }),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: yLabels.reversed.map((lbl) {
                            int h = lbl ~/ 3600;
                            return Row(children: [
                              Text("←", style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                              SizedBox(width: 2),
                              Text("$h س", style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: List.generate(chartData.length, (i) {
                          final d = chartData[i];
                          bool isToday = _dateKey(d["date"] as DateTime) == _dateKey(DateTime.now()) && _currentWeekOffset == 0;
                          String label = isToday? "اليوم" : "${d["date"].day}/${d["date"].month}";
                          bool isSel = i == _selectedIndex;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(label, style: TextStyle(color: isSel? Colors.white : Colors.white.withValues(alpha: 0.4), fontSize: 10, fontWeight: isSel? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _legend(const Color(0xFF1E90FF), "وقت النهار"),
                  const SizedBox(width: 16),
                  _legend(const Color(0xFF00E5FF), "وقت الليل"),
                ])
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(children: [
                  Switch(value: isDailyLimitEnabled, onChanged: _toggleDailyLimit, activeThumbColor: Colors.white, activeTrackColor: const Color(0xFF14B8A6), inactiveThumbColor: Colors.white54, inactiveTrackColor: const Color(0xFF2A3542)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text("مدة الاستخدام اليومية", style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                      const SizedBox(height: 4),
                      Text("احصل على إشعارات إذا وصلت إلى الحد الذي عيّنته على Tini.", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, height: 1.4), textAlign: TextAlign.right),
                    ]),
                  )
                ]),
              ),
              Divider(color: Colors.white.withValues(alpha: 0.06), height: 1, indent: 20, endIndent: 20),
              Opacity(
                opacity: isDailyLimitEnabled? 1 : 0.4,
                child: ListTile(
                  enabled: isDailyLimitEnabled,
                  title: const Text("الحد اليومي الأقصى", style: TextStyle(color: Colors.white, fontSize: 14), textAlign: TextAlign.right),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(isDailyLimitEnabled? _formatLimit(_dailyLimitMinutes) : "إيقاف تشغيل", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_back_ios, color: Colors.white24, size: 14)
                  ]),
                  onTap: _showDailyLimitSheet,
                ),
              ),
            ]),
          ),
          _buildCard(
            title: "تحديثات مدة الاستخدام الأسبوعية",
            subtitle: "ابق منتبّهًا لوقتك من صندوق الوارد.",
            value: isWeeklyUpdateEnabled,
            onChanged: (v) async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('titi_weekly_update', v);
              setState(() => isWeeklyUpdateEnabled = v);

              if (mounted) {
                final sysProvider = Provider.of<SystemNotificationsProvider>(context, listen: false);
                sysProvider.setWeeklyEnabled(v);
                if (v) {
                  final avgText2 = "${_formatDuration(avgSeconds)} يومياً";
                  final percentText2 = prevTotal == 0? "أول أسبوع لك" : "${percentChange.abs().toStringAsFixed(0)}% ${isUp? 'أكثر' : 'أقل'} من الأسبوع الماضي";
                  sysProvider.addWeeklyReportIfSaturday(
                    hoursText: _formatDuration(currentTotal),
                    avgText: avgText2,
                    percentText: percentText2,
                    totalSeconds: currentTotal,
                  );
                }
              }
              _showTopToast(v? "تم تفعيل التحديثات الأسبوعية" : "تم إيقاف التحديثات الأسبوعية");
            }
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String t) => Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 6), Text(t, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12))]);

  Widget _buildCard({required String title, required String subtitle, required bool value, required Function(bool) onChanged, String? bottomTitle, String? bottomValue}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), child: Row(children: [
          Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.white, activeTrackColor: Colors.teal, inactiveThumbColor: Colors.white54, inactiveTrackColor: const Color(0xFF2A3542)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, height: 1.4), textAlign: TextAlign.right),
          ]))
        ])),
        if (bottomTitle!= null)...[
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1, indent: 20, endIndent: 20),
          ListTile(title: Text(bottomTitle, style: const TextStyle(color: Colors.white, fontSize: 14), textAlign: TextAlign.right), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(bottomValue?? "", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)), const SizedBox(width: 6), const Icon(Icons.arrow_back_ios, color: Colors.white24, size: 14)]), onTap: () {}),
        ]
      ]),
    );
  }
}