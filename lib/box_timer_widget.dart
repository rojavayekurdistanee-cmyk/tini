import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BoxCountdownTimer extends StatefulWidget {
  final Timestamp? boxOpenedAt;
  
  const BoxCountdownTimer({super.key, required this.boxOpenedAt});

  @override
  State<BoxCountdownTimer> createState() => _BoxCountdownTimerState();
}

class _BoxCountdownTimerState extends State<BoxCountdownTimer> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    if (widget.boxOpenedAt == null) return;
    
    final openedTime = widget.boxOpenedAt!.toDate();
    final expiryTime = openedTime.add(const Duration(hours: 24));
    final now = DateTime.now();
    
    if (mounted) {
      setState(() {
        _remaining = expiryTime.difference(now);
      });
    }
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return "00:00:00";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.boxOpenedAt == null || _remaining.isNegative) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      constraints: const BoxConstraints(maxWidth: 130), // ← حد أقصى للعرض
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha:0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center, // ← بالنص
        children: [
          const Icon(Icons.access_time, color: Colors.orangeAccent, size: 14),
          const SizedBox(width: 4),
          Flexible( // ← مهم عشان يصغر
            child: FittedBox( // ← مهم عشان يصغر النص كامل
              fit: BoxFit.scaleDown,
              child: Text(
                'يختفي خلال ${_formatDuration(_remaining)}',
                textAlign: TextAlign.center, // ← بالنص
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}