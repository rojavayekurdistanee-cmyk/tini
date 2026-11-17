import 'package:flutter/material.dart';
import 'galaxy_match_categories.dart';
import 'galaxy_match_provider.dart';
import 'galaxy_match_setup_screen.dart';

class GalaxyMatchDiscoverScreen extends StatelessWidget {
  final GalaxyMatchProvider provider;
  const GalaxyMatchDiscoverScreen({super.key, required this.provider});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: provider,
    builder: (context, _) => Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        title: const Text('النجمة الناقصة'),
        backgroundColor: const Color(0xFF0F1720),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'أقدّم: ${GalaxyMatchCategories.label(provider.preferences?.offer ?? '')}',
            style: const TextStyle(color: Colors.white),
          ),
          Text(
            'أبحث عن: ${GalaxyMatchCategories.label(provider.preferences?.need ?? '')}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: provider.busy || provider.preferences?.enabled != true
                ? null
                : provider.discover,
            icon: const Icon(Icons.auto_awesome),
            label: Text(provider.busy ? 'جارٍ البحث…' : 'اكتشف توافقاً'),
          ),
          TextButton(
            onPressed: provider.busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          GalaxyMatchSetupScreen(provider: provider),
                    ),
                  ),
            child: const Text('تعديل اختياراتي'),
          ),
          if (provider.error != null)
            Text(
              provider.error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          if (!provider.busy && provider.results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'لم نعثر على توافق متبادل حالياً. اضغط للاكتشاف أو جرّب لاحقاً.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          for (final result in provider.results)
            Card(
              color: const Color(0xFF1A222C),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'شخص يستطيع مساعدتك في ${GalaxyMatchCategories.label(result.need)}، ويمكنك مساعدته في ${GalaxyMatchCategories.label(result.offer)}.',
                      style: const TextStyle(color: Colors.white, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: provider.busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('إرسال طلب تعارف'),
                                  content: const Text(
                                    'بإرسال الطلب توافق على كشف هويتك للطرف الآخر إذا قبِل. لن تتغير إعدادات المراسلة الخاصة بك.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('رجوع'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('أوافق وأرسل'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && context.mounted) {
                                await provider.request(result.token);
                              }
                            },
                      child: const Text('إرسال طلب تعارف'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
