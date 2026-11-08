import 'dart:async';
import 'package:flutter/widgets.dart';

/// Debounces committed editor snapshots. It never publishes or changes UI state.
/// A single task runs at a time; committed work can finish for incremental reuse.
class TiniEditWarmup with WidgetsBindingObserver {
  Timer? _timer;
  String? _wanted, _completed;
  Future<void> Function(bool Function())? _work;
  int _cancellationEpoch = 0;
  bool _running = false, _closed = false, _foreground = true;
  Object? lastError;
  TiniEditWarmup() {
    WidgetsBinding.instance.addObserver(this);
  }
  void update(String? signature, Future<void> Function(bool Function())? work) {
    if (_closed || signature == _wanted) return;
    _wanted = signature;
    _work = work;
    // Keep an already-running committed edit alive when another committed
    // edit arrives. Its checkpoint is the next edit's incremental parent.
    // Explicitly clearing work (e.g. playback) still cancels the warmup.
    if (signature == null || work == null) _cancellationEpoch++;
    _timer?.cancel();
    _schedule();
  }

  void _schedule() {
    if (_closed ||
        !_foreground ||
        _running ||
        _wanted == null ||
        _wanted == _completed) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1600), _start);
  }

  Future<void> _start() async {
    if (_closed || !_foreground || _running || _work == null) return;
    final cancellationEpoch = _cancellationEpoch;
    final signature = _wanted;
    final work = _work!;
    _running = true;
    bool stopped() => _closed || !_foreground ||
        cancellationEpoch != _cancellationEpoch;
    try {
      await work(stopped);
      if (!stopped()) {
        _completed = signature;
        lastError = null;
      }
    } catch (error) {
      if (!stopped()) {
        lastError = error;
        _completed = signature;
      }
    } finally {
      _running = false;
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _cancellationEpoch++;
      _timer?.cancel();
    } else {
      _schedule();
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _cancellationEpoch++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
