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
  Set<String> _selectedQueries = {};

  final List<String> _arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SearchProvider>().loadRecentSearches();
    });
  }

  String _formatTime(DateTime dt) {
    int hour = dt.hour;
    String period = hour >= 12? 'م' : 'ص';
    int hour12 = hour % 12;
    if (hour12 == 0) hour12 = 12;
    String minute = dt.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }

  String _getDateGroup(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (itemDate == today) return 'اليوم';
    if (itemDate == yesterday) return 'أمس';
    return '${dt.day} ${_arabicMonths[dt.month - 1]}';
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(List<Map<String, dynamic>> list) {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in list) {
      Timestamp ts = item['timestamp'] is Timestamp? item['timestamp'] : Timestamp.now();
      DateTime dt = ts.toDate();
      String group = _getDateGroup(dt);
      if (!grouped.containsKey(group)) grouped[group] = [];
      grouped[group]!.add(item);
    }
    return grouped;
  }

  void _toggleSelect(String query) {
    setState(() {
      if (_selectedQueries.contains(query)) _selectedQueries.remove(query);
      else _selectedQueries.add(query);
    });
  }

  void _selectAll(List<Map<String, dynamic>> all) {
    setState(() {
      if (_selectedQueries.length == all.length) _selectedQueries.clear();
      else _selectedQueries = all.map((e) => e['query'] as String).toSet();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedQueries.isEmpty) return;
    await context.read<SearchProvider>().removeRecentSearches(_selectedQueries.toList());
    setState(() {
      _selectedQueries.clear();
      _isSelectionMode = false;
    });
  }

  void _onItemTap(Map<String, dynamic> item) {
    if (_isSelectionMode) {
      _toggleSelect(item['query'] as String);
    } else {
      final query = item['query'] as String;
      context.read<SearchProvider>().addRecentSearch(query);
      Navigator.push(context, MaterialPageRoute(builder: (_) => SearchResultsScreen(initialQuery: query)));
    }
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
             ? TextButton(onPressed: () => setState(() {_isSelectionMode = false; _selectedQueries.clear();}), child: const Text('إلغاء', style: TextStyle(color: Colors.white, fontSize: 14)))
              : TextButton(onPressed: () => setState(() => _isSelectionMode = true), child: const Text('حدد', style: TextStyle(color: Colors.white, fontSize: 14))),
          leadingWidth: 80,
          title: const Text('سجل البحث', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          actions: [IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))],
        ),
        body: Consumer<SearchProvider>(
          builder: (context, provider, _) {
            final detailed = provider.recentSearchesDetailed;
            if (detailed.isEmpty) {
              return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search, size: 70, color: Colors.white.withValues(alpha:0.1)), const SizedBox(height: 10), const Text('لا يوجد سجل بحث', style: TextStyle(color: Colors.white54))]));
            }
            final grouped = _groupByDate(detailed);
            final sortedGroups = grouped.keys.toList();

            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: sortedGroups.length,
                    itemBuilder: (context, groupIndex) {
                      String groupTitle = sortedGroups[groupIndex];
                      List<Map<String, dynamic>> items = grouped[groupTitle]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(groupTitle, style: TextStyle(color: titiTeal.withValues(alpha:0.8), fontSize: 13, fontWeight: FontWeight.bold))),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              children: items.map((item) {
                                Timestamp ts = item['timestamp'] is Timestamp? item['timestamp'] : Timestamp.now();
                                DateTime dt = ts.toDate();
                                String query = item['query'] as String;
                                bool isSelected = _selectedQueries.contains(query);
                                return InkWell(
                                  onTap: () => _onItemTap(item),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        if (_isSelectionMode)
                                          Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isSelected? titiTeal : Colors.white24, width: 1.5), color: isSelected? titiTeal : Colors.transparent), child: isSelected? const Icon(Icons.check, size: 14, color: Colors.white) : null)
                                        else
                                          Icon(Icons.search, color: Colors.white70, size: 20),
                                        const SizedBox(width: 12),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(query, style: const TextStyle(color: Colors.white, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 3), Text(_formatTime(dt), style: const TextStyle(color: Colors.white38, fontSize: 11))])),
                                        if (!_isSelectionMode) const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 12),
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
                if (_isSelectionMode)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: BoxDecoration(color: surfaceColor, border: Border(top: BorderSide(color: Colors.white10))),
                    child: Row(
                      children: [
                        ElevatedButton(
                          onPressed: _selectedQueries.isEmpty? null : _deleteSelected,
                          style: ElevatedButton.styleFrom(backgroundColor: titiTeal, foregroundColor: Colors.white, minimumSize: const Size(90, 40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), disabledBackgroundColor: Colors.white12),
                          child: const Text('حذف', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: InkWell(onTap: () => _selectAll(detailed), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [const Text('تحديد كل سجلات البحث', style: TextStyle(color: Colors.white, fontSize: 13)), const SizedBox(width: 8), Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _selectedQueries.length == detailed.length? titiTeal : Colors.white24, width: 1.5), color: _selectedQueries.length == detailed.length? titiTeal : Colors.transparent), child: _selectedQueries.length == detailed.length? const Icon(Icons.check, size: 14, color: Colors.white) : null)]))),
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