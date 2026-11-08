import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/*
  [Tini Project Rules]:
    1. File Name: account_history_screen.dart
    2. Concept: Account Login History (مثل تيك توك - سجل الحساب)
    3. UI Style: Dark Surface (0xFF1A222C), Background (0xFF0F1720), Teal Accents.
    4. Design Ref: صور تيك توك المرفقة - مقسم بالتاريخ + كارد فيه الجهاز والمكان والوقت
*/

class AccountHistoryScreen extends StatefulWidget {
  const AccountHistoryScreen({super.key});

  @override
  State<AccountHistoryScreen> createState() => _AccountHistoryScreenState();
}

class _AccountHistoryScreenState extends State<AccountHistoryScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  List<QueryDocumentSnapshot> _allLogs = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  int _currentLimit = 30;
  bool _newestFirst = true;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().first.then((_) {
      _listenWithLimit(_currentLimit);
    });
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        _fetchMore();
      }
    });
  }

  void _listenWithLimit(int limit) {
    _sub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _hasMore = false;
        });
      }
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('login_history')
        .orderBy('timestamp', descending: _newestFirst)
        .limit(limit)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _allLogs = snap.docs;
        _hasMore = snap.docs.length == limit;
        _isLoadingMore = false;
        _isInitialLoading = false;
      });
    }, onError: (e) {
      debugPrint("AccountHistory Error: $e");
      if (!mounted) return;
      setState(() {
        _isInitialLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
    });
  }

  void _fetchMore() {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    _currentLimit += 30;
    _listenWithLimit(_currentLimit);
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
          const Text('ترتيب حسب',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 10),
          ListTile(
            title: const Text('الأحدث للأقدم',
                style: TextStyle(color: Colors.white)),
            trailing: _newestFirst
                ? Icon(Icons.check_circle, color: titiTeal)
                : const Icon(Icons.circle_outlined, color: Colors.white24),
            onTap: () {
              setState(() {
                _newestFirst = true;
                _currentLimit = 30;
                _isInitialLoading = true;
              });
              _listenWithLimit(_currentLimit);
              Navigator.pop(context);
            },
          ),
          ListTile(
            title: const Text('من الأقدم إلى الأحدث',
                style: TextStyle(color: Colors.white)),
            trailing: !_newestFirst
                ? Icon(Icons.check_circle, color: titiTeal)
                : const Icon(Icons.circle_outlined, color: Colors.white24),
            onTap: () {
              setState(() {
                _newestFirst = false;
                _currentLimit = 30;
                _isInitialLoading = true;
              });
              _listenWithLimit(_currentLimit);
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Map<String, List<QueryDocumentSnapshot>> _groupByDate(
      List<QueryDocumentSnapshot> docs) {
    final Map<String, List<QueryDocumentSnapshot>> grouped = {};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['timestamp'] as Timestamp?;
      if (ts == null) continue;
      final key = _getDateKey(ts);
      grouped.putIfAbsent(key, () => []).add(doc);
    }
    return grouped;
  }

  String _getDateKey(Timestamp ts) {
    final d = ts.toDate();
    final months = [
      'يناير','فبراير','مارس','أبريل','مايو','يونيو',
      'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'
    ];
    final now = DateTime.now();
    if (d.year != now.year) {
      return "${d.day} ${months[d.month - 1]}، ${d.year}";
    } else {
      return "${d.day} ${months[d.month - 1]}";
    }
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    int hour = d.hour;
    final minute = d.minute.toString().padLeft(2, '0');
    final isAm = hour < 12;
    if (hour == 0) hour = 12;
    if (hour > 12) hour -= 12;
    return "$hour:$minute ${isAm ? 'ص' : 'م'}";
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupedLogs = _groupByDate(_allLogs);
    final dateKeys = groupedLogs.keys.toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: const Text("سجل الحساب",
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: surfaceColor.withValues(alpha: 0.6),
            child: const Text(
              "سيظهر سجل الحساب من السنة الماضية. إذا لم تتعرف على أي نشاط، فيمكنك مراجعة معلومات الحساب لديك أو إدارة الأجهزة.",
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: Colors.white54, fontSize: 12.5, height: 1.6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _showSortSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        _newestFirst ? 'الأحدث للأقدم' : 'من الأقدم إلى الأحدث',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                    const SizedBox(width: 6),
                    const Icon(Iconsax.arrow_down_1,
                        size: 14, color: Colors.white70),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isInitialLoading
                ? Center(child: CircularProgressIndicator(color: titiTeal))
                : _allLogs.isEmpty
                    ? Center(
                        child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Iconsax.security_safe,
                              size: 70,
                              color: Colors.white.withValues(alpha: 0.1)),
                          const SizedBox(height: 12),
                          const Text('لا يوجد سجل حساب',
                              style: TextStyle(color: Colors.white54)),
                        ],
                      ))
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 30),
                        itemCount: dateKeys.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == dateKeys.length) {
                            return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                    child: CircularProgressIndicator(
                                        color: titiTeal, strokeWidth: 2)));
                          }
                          final dateKey = dateKeys[index];
                          final logsForDate = groupedLogs[dateKey]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 20, left: 20, top: 18, bottom: 10),
                                child: Text(
                                  dateKey,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              ...logsForDate.map((doc) {
                                final data =
                                    doc.data() as Map<String, dynamic>;
                                final ts = data['timestamp'] as Timestamp?;
                                final deviceName =
                                    data['deviceName'] ?? data['device'] ?? '';
                                final location = data['location'] ?? '';
                                final city = data['city'] ?? '';
                                final country = data['country'] ?? '';
                                String deviceText = deviceName.isNotEmpty
                                    ? deviceName
                                    : 'جهاز غير معروف';
                                String locationText = location.isNotEmpty
                                    ? location
                                    : (city.isNotEmpty && country.isNotEmpty
                                        ? "$city، $country"
                                        : country);
                                return _buildLoginCard(
                                  timestamp: ts,
                                  deviceText: deviceText,
                                  locationText: locationText,
                                );
                              }),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard({
    required Timestamp? timestamp,
    required String deviceText,
    required String locationText,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                "الحساب مسجل الدخول",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Iconsax.login_1,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "لقد سجلت الدخول إلى حسابك",
            textAlign: TextAlign.right,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            locationText.isNotEmpty
                ? "من $deviceText في $locationText"
                : "من $deviceText",
            textAlign: TextAlign.right,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            _formatTime(timestamp),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
          ),
        ],
      ),
    );
  }
}