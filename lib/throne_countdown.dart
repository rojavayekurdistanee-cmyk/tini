import 'dart:async';
import 'package:flutter/material.dart';

/// A display clock only: reaching zero never writes to Firebase.
class ThroneCountdown extends StatefulWidget {
  final DateTime? deadline;
  final bool reign;
  final DateTime Function() now;
  const ThroneCountdown({
    super.key,
    required this.deadline,
    required this.reign,
    required this.now,
  });
  @override
  State<ThroneCountdown> createState() => _ThroneCountdownState();
}

class _ThroneCountdownState extends State<ThroneCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
      setState(() {});
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadline?.difference(widget.now());
    final label = widget.reign ? 'الحكم' : 'المزاد';
    final text = remaining == null
        ? 'بانتظار تفعيل المزاد من السيرفر'
        : remaining <= Duration.zero
        ? 'انتهى $label؛ بانتظار تأكيد السيرفر'
        : '$label: ${remaining.inDays}ي ${remaining.inHours % 24}س ${remaining.inMinutes % 60}د ${remaining.inSeconds % 60}ث';
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.teal),
    );
  }
}