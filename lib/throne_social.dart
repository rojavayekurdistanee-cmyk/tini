import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crown_provider.dart';
import 'profile_screen.dart';
import 'throne_badges.dart';
import 'throne_celebration.dart';

class ThroneSocial extends StatefulWidget {
  const ThroneSocial({super.key});
  @override
  State<ThroneSocial> createState() => _ThroneSocialState();
}

class _ThroneSocialState extends State<ThroneSocial> {
  CrownProvider? _crown;
  String? _auction;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _competitors;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _state;
  bool _baseline = false;
  String? _lastCoronation;
  bool _reacting = false;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _history = [];
  bool _loadingHistory = false;
  bool _hasMore = true;
  String? _historyError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final crown = context.read<CrownProvider>();
    if (_crown != crown) {
      _crown?.removeListener(_changed);
      _crown = crown;
      crown.addListener(_changed);
      _state = FirebaseFirestore.instance
          .doc('throne_data/current')
          .snapshots();
      _changed();
    }
  }

  void _changed() {
    final crown = _crown!;
    if (_auction != crown.auctionId) {
      _auction = crown.auctionId;
      _competitors = _auction == null
          ? null
          : FirebaseFirestore.instance
                .collection('throne_auctions')
                .doc(_auction)
                .collection('competitors')
                .orderBy('amount', descending: true)
                .limit(3)
                .snapshots();
    }
    // Ignore initial hydration: entering the page is not a coronation event.
    if (!_baseline && crown.auctionId != null) {
      _baseline = true;
      _lastCoronation = crown.coronationId;
    } else if (_baseline && crown.coronationId != _lastCoronation) {
      _lastCoronation = crown.coronationId;
      if (_lastCoronation != null) {
        unawaited(
          _celebrate(
            crown.coronationId!,
            crown.currentKingName,
            crown.currentKingAvatar,
          ),
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _celebrate(String id, String? name, String? avatar) async {
    final prefs = await SharedPreferences.getInstance();
    final key =
        'tini_throne_seen_${FirebaseAuth.instance.currentUser?.uid ?? 'guest'}';
    if (prefs.getString(key) == id) return;
    await prefs.setString(key, id);
    if (!mounted || _crown?.coronationId != id) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFF1A222C),
        content: ThroneCelebration(name: name ?? '', avatar: avatar),
      ),
    );
  }

  Widget _avatar(String? url) => CircleAvatar(
    backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
    child: url == null || url.isEmpty ? const Icon(Icons.person) : null,
  );
  void _profile(String uid) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)),
  );
  Future<void> _loadHistory() async {
    if (_loadingHistory || !_hasMore) return;
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('throne_reigns')
          .where('completed', isEqualTo: true)
          .orderBy('crownedAt', descending: true)
          .limit(20);
      if (_history.isNotEmpty) query = query.startAfterDocument(_history.last);
      final page = await query.get();
      if (!mounted) return;
      setState(() {
        _history.addAll(page.docs);
        _hasMore = page.docs.length == 20;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _historyError = 'تعذر تحميل التاريخ؛ أعد المحاولة');
      }
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _react(String kind) async {
    if (_reacting || _crown?.coronationId == null) return;
    setState(() => _reacting = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('reactToThrone')
          .call({'kind': kind, 'coronationId': _crown!.coronationId});
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر التفاعل')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تحقق من اتصال الإنترنت')));
      }
    } finally {
      if (mounted) setState(() => _reacting = false);
    }
  }

  @override
  void dispose() {
    _crown?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final crown = _crown!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (crown.availabilityMessage != null)
          Text(
            crown.availabilityMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.amber),
          ),
        if (crown.hasPendingBid)
          TextButton(
            onPressed: crown.isLoading
                ? null
                : () async {
                    final accepted = await crown.retryPendingBid();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          accepted
                              ? 'أكد السيرفر قبول طلبك السابق'
                              : crown.lastError ?? 'تعذر تأكيد الطلب',
                        ),
                      ),
                    );
                  },
            child: const Text('تأكيد آخر طلب مزايدة'),
          ),
        Text(
          crown.isThroneLocked
              ? 'فترة حكم الملك — المزايدات مغلقة'
              : 'مزاد العرش — المتصدر لم يُتوّج بعد',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.teal),
        ),
        if (!crown.isThroneLocked)
          Text(
            'الحد الأدنى: ${crown.currentBid + 1} نقطة • المتصدر: ${crown.leaderName ?? "لا مشاركين"}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        Text(
          'نقاطك المحجوزة: ${crown.reservedPoints}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        if (!crown.isThroneLocked && crown.auctionEndsAt != null)
          Text(
            'نهاية المزاد: ${crown.auctionEndsAt!.toDate().toLocal()}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ExpansionTile(
          title: const Text('أقوى ثلاثة منافسين'),
          children: [
            if (_competitors == null)
              const ListTile(title: Text('المزاد بانتظار تفعيل السيرفر'))
            else
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _competitors,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const ListTile(title: Text('تعذر تحميل المنافسين'));
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  if (snapshot.data!.docs.isEmpty) {
                    return const ListTile(title: Text('لا توجد مشاركات بعد'));
                  }
                  return Column(
                    children: snapshot.data!.docs.asMap().entries.map((entry) {
                      final d = entry.value.data();
                      final active =
                          crown.leaderUid == d['uid'] && !crown.isThroneLocked;
                      return ListTile(
                        leading: _avatar(d['avatar']),
                        title: Text('${entry.key + 1}. ${d["name"]}'),
                        subtitle: Text(
                          '${d["amount"]} نقطة • ${active ? "متصدر — محجوز" : "عرض تاريخي — غير محجوز"}',
                        ),
                        onTap: () => _profile(d['uid']),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
        if (crown.isThroneLocked)
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _state,
            builder: (context, snapshot) {
              final counts = snapshot.data?.data()?['reactions'] as Map? ?? {};
              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                children: {'crown': '👑', 'heart': '❤️', 'fire': '🔥'}.entries
                    .map(
                      (e) => TextButton(
                        onPressed: _reacting ? null : () => _react(e.key),
                        child: Text('${e.value} ${counts[e.key] ?? 0}'),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ExpansionTile(
          title: const Text('قاعة الملوك السابقين'),
          onExpansionChanged: (open) {
            if (open && _history.isEmpty) unawaited(_loadHistory());
          },
          children: [
            ..._history.map((doc) {
              final d = doc.data();
              final start = (d['crownedAt'] as Timestamp).toDate().toLocal();
              final end = (d['endsAt'] as Timestamp).toDate().toLocal();
              return ListTile(
                leading: _avatar(d['avatar']),
                title: Row(
                  children: [
                    Flexible(child: Text(d['name'] ?? 'ملك سابق')),
                    const ThroneBadgeImage(
                      kind: ThroneBadgeKind.formerKing,
                      size: 30,
                      animate: false,
                    ),
                  ],
                ),
                subtitle: Text(
                  '$start — $end\n${(d["durationMs"] as num) ~/ 86400000} يوم • ${d["winningBid"]} نقطة • تتويج ${d["coronationCount"]}',
                ),
                onTap: () => _profile(d['uid']),
              );
            }),
            if (_historyError != null) Text(_historyError!),
            if (_history.isEmpty && !_loadingHistory && _historyError == null)
              const Text('لا توجد فترات حكم مكتملة'),
            if (_loadingHistory)
              const LinearProgressIndicator()
            else if (_hasMore)
              TextButton(
                onPressed: _loadHistory,
                child: const Text('تحميل المزيد'),
              ),
          ],
        ),
      ],
    );
  }
}
