import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'app_usage_tracker.dart';

class TimeOnAppScreen extends StatefulWidget {
  const TimeOnAppScreen({super.key});

  @override
  State<TimeOnAppScreen> createState() => _TimeOnAppScreenState();
}

class _TimeOnAppScreenState extends State<TimeOnAppScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);

  Timer? _tooltipTimer;
  Timer? _toastTimer;
  OverlayEntry? _toast;
  int _currentWeekOffset = 0;
  int _selectedIndex = -1;
  bool _showInfoTooltip = false;

  final List<String> _arabicMonths = [
    "يناير",
    "فبراير",
    "مارس",
    "أبريل",
    "مايو",
    "يونيو",
    "يوليو",
    "أغسطس",
    "سبتمبر",
    "أكتوبر",
    "نوفمبر",
    "ديسمبر",
  ];

  @override
  void dispose() {
    _tooltipTimer?.cancel();
    _toastTimer?.cancel();
    _toast?.remove();
    super.dispose();
  }

  List<DateTime> _getWeekDays(DateTime now, int offset) {
    final start = usageWeekStart(now, offset);
    return List.generate(
      7,
      (i) => DateTime(start.year, start.month, start.day + i),
    );
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
    _toastTimer?.cancel();
    _toast?.remove();
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
            decoration: BoxDecoration(
              color: const Color(0xFF2A3542),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Text(
              msg,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    _toast = entry;
    overlay.insert(entry);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toast?.remove();
      _toast = null;
    });
  }

  void _toggleInfoTooltip() {
    setState(() => _showInfoTooltip = true);
    _tooltipTimer?.cancel();
    _tooltipTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showInfoTooltip = false);
    });
  }

  Future<void> _toggleDailyLimit(bool v) async {
    final tracker = context.read<AppUsageTracker>();
    final saved = await tracker.setDailyEnabled(v);
    if (!mounted) return;
    if (!saved) {
      _showTopToast('تعذّر حفظ الإعداد');
      return;
    }
    _showTopToast(
      v
          ? "تم ضبط مدة الاستخدام اليومية إلى ${_formatLimit(tracker.limitMinutes)}"
          : "تم إيقاف تشغيل مدة الاستخدام اليومية",
    );
  }

  void _showDailyLimitSheet() {
    final tracker = context.read<AppUsageTracker>();
    if (!tracker.dailyEnabled) return;
    final currentLimit = tracker.limitMinutes;
    final options = [10, 15, 20, 30, 60, 120];
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "الحد اليومي الأقصى",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: options.map((m) {
                        bool selected = m == currentLimit;
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
                            final saved = await tracker.setLimitMinutes(m);
                            if (!mounted || !ctx.mounted) return;
                            if (!saved) {
                              _showTopToast('تعذّر حفظ الإعداد');
                              return;
                            }
                            if (ModalRoute.of(ctx)?.isCurrent == true) {
                              Navigator.pop(ctx);
                            }
                            _showTopToast(
                              "تم ضبط مدة الاستخدام اليومية إلى ${_formatLimit(m)}",
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF14B8A6)
                                          : Colors.white24,
                                      width: 2,
                                    ),
                                    color: selected
                                        ? const Color(0xFF14B8A6)
                                        : Colors.transparent,
                                  ),
                                  child: selected
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.7),
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B8A6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "تم",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleWeeklyUpdate(bool value) async {
    final saved = await context.read<AppUsageTracker>().setWeeklyEnabled(value);
    if (!mounted) return;
    _showTopToast(
      !saved
          ? 'تعذّر حفظ الإعداد'
          : value
          ? 'تم تفعيل التحديثات الأسبوعية'
          : 'تم إيقاف التحديثات الأسبوعية',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "مدة الاستخدام",
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Selector<AppUsageTracker, (bool, bool)>(
        selector: (_, tracker) => (tracker.loading, tracker.loadFailed),
        builder: (_, state, _) {
          if (state.$1) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.teal),
            );
          }
          if (state.$2) {
            return const Center(
              child: Text(
                'تعذّر تحميل سجل مدة الاستخدام',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Consumer<AppUsageTracker>(
                builder: (_, tracker, _) => _buildUsage(tracker),
              ),
              Selector<AppUsageTracker, (bool, bool, int)>(
                selector: (_, tracker) => (
                  tracker.dailyEnabled,
                  tracker.weeklyEnabled,
                  tracker.limitMinutes,
                ),
                builder: (_, settings, _) =>
                    _buildSettings(settings.$1, settings.$2, settings.$3),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUsage(AppUsageTracker tracker) {
    final now = tracker.now;
    final currentWeekDays = _getWeekDays(now, _currentWeekOffset);
    final previousWeekDays = _getWeekDays(now, _currentWeekOffset + 1);
    final chartData = <Map<String, dynamic>>[
      for (final date in currentWeekDays)
        {
          'date': date,
          'usage': tracker.usageOn(date),
          'dayTime':
              tracker.usageOn(date).day ~/ Duration.microsecondsPerSecond,
          'nightTime':
              tracker.usageOn(date).night ~/ Duration.microsecondsPerSecond,
          'total':
              tracker.usageOn(date).total ~/ Duration.microsecondsPerSecond,
        },
    ];
    final currentTotal = chartData.fold<int>(
      0,
      (sum, row) => sum + (row['total'] as int),
    );
    final prevTotal =
        previousWeekDays.fold<int>(
          0,
          (sum, date) => sum + tracker.usageOn(date).total,
        ) ~/
        Duration.microsecondsPerSecond;
    final measuredDays = currentWeekDays.where(tracker.hasMeasurement).length;
    final avgSeconds = measuredDays == 0 ? 0 : currentTotal ~/ measuredDays;
    final percentChange = prevTotal == 0
        ? 0.0
        : (currentTotal - prevTotal) * 100 / prevTotal;
    final isUp = percentChange >= 0;
    final maxReal = chartData.fold<int>(0, (max, row) {
      final total = row['total'] as int;
      return total > max ? total : max;
    });
    const interval = 3 * 3600;
    final maxSec = maxReal <= 6 * 3600
        ? 6 * 3600
        : ((maxReal + interval - 1) ~/ interval) * interval;
    final yLabels = [0, maxSec ~/ 3, maxSec * 2 ~/ 3, maxSec];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        "المتوسط اليومي",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _toggleInfoTooltip,
                        child: Icon(
                          Icons.info_outline,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  if (_showInfoTooltip)
                    Positioned(
                      top: 28,
                      right: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A3542),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Text(
                          "تتضمن المقاييس الوقت الذي تقضيه في تطبيق Tini فقط، ويُحسب المتوسط من الأيام التي يغطيها القياس في الأسبوع المعروض.",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.6,
                          ),
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
                  Text(
                    _formatDuration(avgSeconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (prevTotal > 0)
                    Row(
                      children: [
                        Icon(
                          isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          color: isUp ? Colors.white38 : Colors.teal,
                          size: 24,
                        ),
                        Text(
                          "${percentChange.abs().toStringAsFixed(0)}% من الأسبوع الماضي",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      "أول أسبوع لك",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () {
                  if (_currentWeekOffset > 0) {
                    setState(() {
                      _currentWeekOffset--;
                      _selectedIndex = -1;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _currentWeekOffset == 0
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white10,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color: _currentWeekOffset == 0
                        ? Colors.white10
                        : Colors.white54,
                    size: 12,
                  ),
                ),
              ),
              Text(
                _formatRange(currentWeekDays),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              InkWell(
                onTap: () => setState(() {
                  _currentWeekOffset++;
                  _selectedIndex = -1;
                }),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white10,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.white54,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 14),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 180,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, cons) {
                          return Stack(
                            children: [
                              Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: yLabels.reversed.map((_) {
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 1,
                                          child: Row(
                                            children: List.generate(
                                              100,
                                              (i) => Expanded(
                                                child: Container(
                                                  margin: EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                  ),
                                                  height: 1,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.15),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(chartData.length, (
                                  index,
                                ) {
                                  final d = chartData[index];
                                  int total = d["total"] as int;
                                  bool isSelected = index == _selectedIndex;
                                  double hFactor = total / maxSec;
                                  double totalH = (hFactor * 160).clamp(0, 160);
                                  final usage = d["usage"] as UsageDay;
                                  final dayH = usage.total == 0
                                      ? 0.0
                                      : totalH * usage.day / usage.total;
                                  final nightH = usage.total == 0
                                      ? 0.0
                                      : totalH * usage.night / usage.total;
                                  final unknownH = usage.total == 0
                                      ? 0.0
                                      : totalH * usage.unknown / usage.total;

                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(
                                        () => _selectedIndex = index,
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        height: 160,
                                        child: Stack(
                                          alignment: Alignment.bottomCenter,
                                          clipBehavior: Clip.none,
                                          children: [
                                            if (isSelected)
                                              SizedBox(
                                                width: double.infinity,
                                                height: double.infinity,
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF3B82F6,
                                                    ).withValues(alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            Align(
                                              alignment: Alignment.bottomCenter,
                                              child: SizedBox(
                                                width: double.infinity,
                                                height: totalH < 4 && total > 0
                                                    ? 4
                                                    : totalH,
                                                child: total == 0
                                                    ? null
                                                    : Opacity(
                                                        opacity: isSelected
                                                            ? 1
                                                            : 0.55,
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .end,
                                                          children: [
                                                            if (unknownH > 0)
                                                              Container(
                                                                height:
                                                                    unknownH,
                                                                color: Colors
                                                                    .white38,
                                                              ),
                                                            if (nightH > 0)
                                                              Container(
                                                                height: nightH,
                                                                decoration: BoxDecoration(
                                                                  color: const Color(
                                                                    0xFF00E5FF,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius.vertical(
                                                                        top:
                                                                            Radius.circular(
                                                                              4,
                                                                            ),
                                                                      ),
                                                                ),
                                                              ),
                                                            if (dayH > 0)
                                                              Container(
                                                                height: dayH,
                                                                decoration: BoxDecoration(
                                                                  color: const Color(
                                                                    0xFF1E90FF,
                                                                  ),
                                                                  borderRadius: BorderRadius.vertical(
                                                                    top:
                                                                        nightH ==
                                                                            0
                                                                        ? Radius.circular(
                                                                            4,
                                                                          )
                                                                        : Radius
                                                                              .zero,
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                              ),
                                            ),
                                            if (isSelected && total > 0)
                                              Positioned(
                                                bottom: totalH + 10,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.2,
                                                            ),
                                                        blurRadius: 10,
                                                      ),
                                                    ],
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        "${d["date"].day} ${_arabicMonths[d["date"].month - 1]}",
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height: 1,
                                                        width: 90,
                                                        child: DecoratedBox(
                                                          decoration:
                                                              BoxDecoration(
                                                                color: Colors
                                                                    .black12,
                                                              ),
                                                        ),
                                                      ),
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 8,
                                                            height: 8,
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: Color(
                                                                    0xFF1E90FF,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        2,
                                                                      ),
                                                                ),
                                                          ),
                                                          SizedBox(width: 6),
                                                          Text(
                                                            "${_formatHM(d["dayTime"])} وقت النهار",
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .black87,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 8,
                                                            height: 8,
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: Color(
                                                                    0xFF00E5FF,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        2,
                                                                      ),
                                                                ),
                                                          ),
                                                          SizedBox(width: 6),
                                                          Text(
                                                            "${_formatHM(d["nightTime"])} وقت الليل",
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .black54,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      if (usage.unknown > 0)
                                                        Text(
                                                          "${_formatDuration(usage.unknown ~/ Duration.microsecondsPerSecond)} بلا تقسيم زمني",
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .black54,
                                                                fontSize: 11,
                                                              ),
                                                        ),
                                                    ],
                                                  ),
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
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: yLabels.reversed.map((lbl) {
                          int h = lbl ~/ 3600;
                          return Row(
                            children: [
                              Text(
                                "←",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(width: 2),
                              Text(
                                "$h س",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          );
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
                        bool isToday =
                            usageDateKey(d["date"] as DateTime) ==
                                usageDateKey(now) &&
                            _currentWeekOffset == 0;
                        String label = isToday
                            ? "اليوم"
                            : "${d["date"].day}/${d["date"].month}";
                        bool isSel = i == _selectedIndex;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: isSel
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                                fontSize: 10,
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
                            ),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legend(const Color(0xFF1E90FF), "وقت النهار"),
                  const SizedBox(width: 16),
                  _legend(const Color(0xFF00E5FF), "وقت الليل"),
                ],
              ),
              if (chartData.any(
                (entry) => (entry['usage'] as UsageDay).unknown > 0,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _legend(Colors.white38, 'وقت بلا تقسيم زمني'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettings(
    bool isDailyLimitEnabled,
    bool isWeeklyUpdateEnabled,
    int limitMinutes,
  ) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Switch(
                      value: isDailyLimitEnabled,
                      onChanged: _toggleDailyLimit,
                      activeThumbColor: Colors.white,
                      activeTrackColor: const Color(0xFF14B8A6),
                      inactiveThumbColor: Colors.white54,
                      inactiveTrackColor: const Color(0xFF2A3542),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            "مدة الاستخدام اليومية",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "احصل على إشعارات إذا وصلت إلى الحد الذي عيّنته على Tini.",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                color: Colors.white.withValues(alpha: 0.06),
                height: 1,
                indent: 20,
                endIndent: 20,
              ),
              Opacity(
                opacity: isDailyLimitEnabled ? 1 : 0.4,
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    enabled: isDailyLimitEnabled,
                    title: const Text(
                      "الحد اليومي الأقصى",
                      style: TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.right,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isDailyLimitEnabled
                              ? _formatLimit(limitMinutes)
                              : "إيقاف تشغيل",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_back_ios,
                          color: Colors.white24,
                          size: 14,
                        ),
                      ],
                    ),
                    onTap: _showDailyLimitSheet,
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildCard(
          title: "تحديثات مدة الاستخدام الأسبوعية",
          subtitle: "ابق منتبّهًا لوقتك من صندوق الوارد.",
          value: isWeeklyUpdateEnabled,
          onChanged: _toggleWeeklyUpdate,
        ),
      ],
    );
  }

  Widget _legend(Color c, String t) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        t,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 12,
        ),
      ),
    ],
  );

  Widget _buildCard({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    String? bottomTitle,
    String? bottomValue,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.teal,
                  inactiveThumbColor: Colors.white54,
                  inactiveTrackColor: const Color(0xFF2A3542),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (bottomTitle != null) ...[
            Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
              indent: 20,
              endIndent: 20,
            ),
            ListTile(
              title: Text(
                bottomTitle,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.right,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bottomValue ?? "",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.white24,
                    size: 14,
                  ),
                ],
              ),
              onTap: () {},
            ),
          ],
        ],
      ),
    );
  }
}
