import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'throne_badges.dart';

/// Eligibility comes exclusively from a server-written entitlement, never comment metadata.
ThroneBadgeKind? earnedThroneKind({
  required DateTime now,
  DateTime? currentUntil,
  required bool formerKing,
}) {
  if (currentUntil != null && currentUntil.isAfter(now)) {
    return ThroneBadgeKind.currentKing;
  }
  if (formerKing || currentUntil != null) return ThroneBadgeKind.formerKing;
  return null;
}

class _Entry {
  final value = ValueNotifier<Map<String, dynamic>?>(null);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;
  int references = 0;
}

class _Entitlements {
  static final Map<String, _Entry> _entries = {};
  static _Entry acquire(String uid) {
    final entry = _entries.putIfAbsent(uid, () {
      final next = _Entry();
      next.subscription = FirebaseFirestore.instance
          .collection('throne_entitlements')
          .doc(uid)
          .snapshots()
          .listen(
            (doc) => next.value.value = doc.data(),
            onError: (Object error) => next.value.value = null,
          );
      return next;
    });
    entry.references++;
    return entry;
  }

  static void release(String uid, _Entry entry) {
    if (--entry.references == 0) {
      _entries.remove(uid);
      unawaited(entry.subscription?.cancel());
      entry.value.dispose();
    }
  }
}

/// One live subscription per distinct visible user, shared across repeated names.
class EarnedThroneBadge extends StatefulWidget {
  final String uid;
  const EarnedThroneBadge({super.key, required this.uid});
  @override
  State<EarnedThroneBadge> createState() => _EarnedThroneBadgeState();
}

class _EarnedThroneBadgeState extends State<EarnedThroneBadge> {
  late _Entry _entry;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    _entry = _Entitlements.acquire(widget.uid);
  }

  @override
  void didUpdateWidget(covariant EarnedThroneBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _expiry?.cancel();
      _Entitlements.release(oldWidget.uid, _entry);
      _entry = _Entitlements.acquire(widget.uid);
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _Entitlements.release(widget.uid, _entry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: _entry.value,
        builder: (context, data, child) {
          final end = (data?['currentUntil'] as Timestamp?)?.toDate();
          final now = DateTime.now();
          final kind = earnedThroneKind(
            now: now,
            currentUntil: end,
            formerKing: data?['formerKing'] == true,
          );
          _expiry?.cancel();
          if (kind == ThroneBadgeKind.currentKing) {
            _expiry = Timer(end!.difference(now), () {
              if (mounted) setState(() {});
            });
          }
          if (kind == null) return const SizedBox.shrink();
          return Semantics(
            label: kind == ThroneBadgeKind.currentKing
                ? 'الملك الحالي'
                : 'الملك السابق',
            child: ThroneBadgeImage(
              kind: kind,
              size: 30,
              animate: !MediaQuery.disableAnimationsOf(context),
            ),
          );
        },
      );
}
