import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'search_provider.dart';
import 'search_results_screen.dart';

class SearchHistoryScreen extends StatefulWidget {
  const SearchHistoryScreen({super.key});

  @override
  State<SearchHistoryScreen> createState() => _SearchHistoryScreenState();
}

class _SearchHistoryScreenState extends State<SearchHistoryScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color titiTeal = Colors.teal;

  bool _isSelectionMode = false;
  final _selectedQueries = <String>{};
  late final SearchProvider _provider;
  StreamSubscription<User?>? _authSubscription;
  String? _uid;
  Object? _deleteRequest;
  String? _reopenedQuery;
  Object? _previousSaveFailure;

  final List<String> _arabicMonths = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  @override
  void initState() {
    super.initState();
    _provider = context.read<SearchProvider>();
    _provider.addListener(_pruneSelection);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      setState(() {
        _uid = user?.uid;
        _selectedQueries.clear();
        _isSelectionMode = false;
        _deleteRequest = null;
        _reopenedQuery = null;
        _previousSaveFailure = null;
      });
      unawaited(_provider.loadRecentSearches());
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _provider.removeListener(_pruneSelection);
    super.dispose();
  }

  Set<String> _visibleQueries(List<Map<String, dynamic>> entries) =>
      entries.map((entry) => entry['query'] as String).toSet();

  void _pruneSelection() {
    _selectedQueries.retainAll(
      _visibleQueries(_provider.recentSearchesDetailed),
    );
  }

  String _formatTime(DateTime dt) {
    int hour = dt.hour;
    String period = hour >= 12 ? 'م' : 'ص';
    int hour12 = hour % 12;
    if (hour12 == 0) hour12 = 12;
    String minute = dt.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }

  String _getDateGroup(DateTime? day, DateTime today) {
    if (day == null) return 'تاريخ غير معروف';
    if (day == today) return 'اليوم';
    if (day == DateTime(today.year, today.month, today.day - 1)) return 'أمس';
    final label = '${day.day} ${_arabicMonths[day.month - 1]}';
    return day.year == today.year ? label : '$label ${day.year}';
  }

  DateTime? _dateOf(Map<String, dynamic> item) {
    final timestamp = item['timestamp'];
    return timestamp is Timestamp ? timestamp.toDate().toLocal() : null;
  }

  Map<DateTime?, List<Map<String, dynamic>>> _groupByDate(
    List<Map<String, dynamic>> entries,
  ) {
    final grouped = <DateTime?, List<Map<String, dynamic>>>{};
    for (final item in entries) {
      final date = _dateOf(item);
      final day = date == null
          ? null
          : DateTime(date.year, date.month, date.day);
      grouped.putIfAbsent(day, () => []).add(item);
    }
    return grouped;
  }

  void _toggleSelect(String query) {
    if (_deleteRequest != null) return;
    setState(() {
      if (!_selectedQueries.remove(query)) _selectedQueries.add(query);
    });
  }

  void _selectAll(Set<String> visible) {
    if (_deleteRequest != null) return;
    final allSelected = _selectedQueries.containsAll(visible);
    setState(() {
      _selectedQueries.clear();
      if (!allSelected) _selectedQueries.addAll(visible);
    });
  }

  Future<void> _deleteSelected() async {
    if (_deleteRequest != null) return;
    _pruneSelection();
    if (_selectedQueries.isEmpty) return;
    final uid = _uid;
    final request = Object();
    setState(() => _deleteRequest = request);
    try {
      await _provider.removeRecentSearches(_selectedQueries.toList());
      if (!mounted ||
          !identical(request, _deleteRequest) ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      setState(() {
        _selectedQueries.clear();
        _isSelectionMode = false;
      });
    } catch (_) {
      if (!mounted ||
          !identical(request, _deleteRequest) ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حذف سجلات البحث. حاول مرة أخرى')),
      );
    } finally {
      if (mounted && identical(request, _deleteRequest)) {
        setState(() => _deleteRequest = null);
      }
    }
  }

  void _onItemTap(Map<String, dynamic> item) {
    final query = item['query'] as String;
    if (_isSelectionMode) {
      _toggleSelect(query);
      return;
    }
    setState(() {
      _reopenedQuery = query;
      _previousSaveFailure = _provider.recentSearchSaveFailure?.attempt;
    });
    // The results screen records its initial query when it opens.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(initialQuery: query),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          centerTitle: true,
          leading: _isSelectionMode
              ? TextButton(
                  onPressed: _deleteRequest != null
                      ? null
                      : () => setState(() {
                          _isSelectionMode = false;
                          _selectedQueries.clear();
                        }),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                )
              : TextButton(
                  onPressed: () => setState(() => _isSelectionMode = true),
                  child: const Text(
                    'حدد',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
          leadingWidth: 80,
          title: const Text(
            'سجل البحث',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        body: Consumer<SearchProvider>(
          builder: (context, provider, _) {
            final actualUid = FirebaseAuth.instance.currentUser?.uid;
            final detailed = provider.recentSearchesDetailed;
            if (actualUid != _uid ||
                (provider.recentSearchesLoading && detailed.isEmpty) ||
                (actualUid != null &&
                    !provider.recentSearchesLoaded &&
                    !provider.recentSearchesLoadFailed)) {
              return Center(child: CircularProgressIndicator(color: titiTeal));
            }
            if (detailed.isEmpty && !provider.recentSearchesLoadFailed) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      size: 70,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'لا يوجد سجل بحث',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              );
            }
            final visible = _visibleQueries(detailed);
            final allSelected =
                visible.isNotEmpty && _selectedQueries.containsAll(visible);
            final grouped = _groupByDate(detailed);
            final sortedGroups = grouped.keys.toList()
              ..sort((a, b) {
                if (a == null) return b == null ? 0 : 1;
                if (b == null) return -1;
                return b.compareTo(a);
              });
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final saveFailure = provider.recentSearchSaveFailure;

            return Column(
              children: [
                if (saveFailure != null &&
                    saveFailure.query == _reopenedQuery &&
                    !identical(saveFailure.attempt, _previousSaveFailure))
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'تعذّر تحديث سجل هذا البحث',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                if (provider.recentSearchesLoadFailed)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text(
                          'تعذّر تحميل سجل البحث',
                          style: TextStyle(color: Colors.white70),
                        ),
                        TextButton(
                          onPressed: provider.loadRecentSearches,
                          child: const Text('أعد المحاولة'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: sortedGroups.length,
                    itemBuilder: (context, groupIndex) {
                      final day = sortedGroups[groupIndex];
                      final groupTitle = _getDateGroup(day, today);
                      final items = grouped[day]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                            child: Text(
                              groupTitle,
                              style: TextStyle(
                                color: titiTeal.withValues(alpha: 0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: surfaceColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: items.map((item) {
                                final dt = _dateOf(item);
                                String query = item['query'] as String;
                                bool isSelected = _selectedQueries.contains(
                                  query,
                                );
                                return InkWell(
                                  onTap: () => _onItemTap(item),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        if (_isSelectionMode)
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isSelected
                                                    ? titiTeal
                                                    : Colors.white24,
                                                width: 1.5,
                                              ),
                                              color: isSelected
                                                  ? titiTeal
                                                  : Colors.transparent,
                                            ),
                                            child: isSelected
                                                ? const Icon(
                                                    Icons.check,
                                                    size: 14,
                                                    color: Colors.white,
                                                  )
                                                : null,
                                          )
                                        else
                                          Icon(
                                            Icons.search,
                                            color: Colors.white70,
                                            size: 20,
                                          ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                query,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14.5,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (dt != null) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  _formatTime(dt),
                                                  style: const TextStyle(
                                                    color: Colors.white38,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (!_isSelectionMode)
                                          const Icon(
                                            Icons.arrow_forward_ios,
                                            color: Colors.white10,
                                            size: 12,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (_isSelectionMode && visible.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      border: Border(top: BorderSide(color: Colors.white10)),
                    ),
                    child: Row(
                      children: [
                        ElevatedButton(
                          onPressed:
                              _selectedQueries.isEmpty || _deleteRequest != null
                              ? null
                              : _deleteSelected,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: titiTeal,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(90, 40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            disabledBackgroundColor: Colors.white12,
                          ),
                          child: _deleteRequest != null
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'حذف',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectAll(visible),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Text(
                                  'تحديد كل سجلات البحث',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: allSelected
                                          ? titiTeal
                                          : Colors.white24,
                                      width: 1.5,
                                    ),
                                    color: allSelected
                                        ? titiTeal
                                        : Colors.transparent,
                                  ),
                                  child: allSelected
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}