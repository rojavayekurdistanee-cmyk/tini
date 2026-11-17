import 'package:flutter/material.dart';
import 'galaxy_match_categories.dart';
import 'galaxy_match_models.dart';
import 'galaxy_match_provider.dart';
import 'profile_screen.dart';

class GalaxyMatchInboxScreen extends StatelessWidget {
  final GalaxyMatchProvider provider;
  const GalaxyMatchInboxScreen({super.key, required this.provider});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: AnimatedBuilder(
      animation: provider,
      builder: (context, _) => Scaffold(
        backgroundColor: const Color(0xFF0F1720),
        appBar: AppBar(
          title: const Text('توافقاتي'),
          backgroundColor: const Color(0xFF0F1720),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'واردة'),
              Tab(text: 'مرسلة'),
              Tab(text: 'مقبولة'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (provider.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  provider.error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _list(context, 0),
                  _list(context, 1),
                  _list(context, 2),
                ],
              ),
            ),
            if (provider.hasMore)
              TextButton(
                onPressed: provider.busy ? null : provider.loadMore,
                child: const Text('تحميل المزيد'),
              ),
          ],
        ),
      ),
    ),
  );
  Widget _list(BuildContext context, int tab) {
    final list = provider.items
        .where(
          (i) => tab == 2
              ? i.status == GalaxyMatchStatus.accepted
              : i.status != GalaxyMatchStatus.accepted &&
                    i.direction == (tab == 0 ? 'received' : 'sent'),
        )
        .toList();
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد طلبات هنا حالياً',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final item in list)
          Card(
            color: const Color(0xFF1A222C),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (item.peerUid != null) ...[
                    Text(
                      item.peerName ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    Text(
                      '@${item.peerUsername ?? ''}',
                      style: const TextStyle(color: Color(0xFF80CBC4)),
                    ),
                  ] else
                    const Text(
                      'توافق متبادل دون كشف الهوية',
                      style: TextStyle(color: Colors.white),
                    ),
                  Text(
                    'تقدّم ${GalaxyMatchCategories.label(item.offer)} وتبحث عن ${GalaxyMatchCategories.label(item.need)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    item.statusLabel,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  if (item.status == GalaxyMatchStatus.pending &&
                      item.expiresAt.isAfter(DateTime.now()))
                    if (item.direction == 'received')
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: provider.busy
                                ? null
                                : () async {
                                    final agree = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('قبول التوافق'),
                                        content: const Text(
                                          'سيُكشف اسمك وحسابك للطرف الآخر، وتظهر لك هويته. هل توافق؟',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('رجوع'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('أوافق'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (agree == true && context.mounted) {
                                      await provider.respond(item.id, true);
                                    }
                                  },
                            child: const Text('قبول'),
                          ),
                          TextButton(
                            onPressed: provider.busy
                                ? null
                                : () => provider.respond(item.id, false),
                            child: const Text('رفض'),
                          ),
                        ],
                      )
                    else
                      TextButton(
                        onPressed: provider.busy
                            ? null
                            : () => provider.manage(item.id, 'cancel'),
                        child: const Text('إلغاء الطلب'),
                      ),
                  if (item.peerUid != null)
                    TextButton(
                      onPressed: () {
                        if (!provider.items.any(
                          (current) =>
                              current.id == item.id &&
                              current.status == GalaxyMatchStatus.accepted &&
                              current.peerUid == item.peerUid,
                        )) {
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ProfileScreen(userId: item.peerUid),
                          ),
                        );
                      },
                      child: const Text('زيارة الملف الشخصي'),
                    ),
                  if (item.status == GalaxyMatchStatus.accepted)
                    TextButton(
                      onPressed: provider.busy
                          ? null
                          : () => provider.manage(item.id, 'end'),
                      child: const Text('إنهاء التوافق'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
