// [Tini - Privacy]: صفحة الذكر والإشارات، بإعداد مشترك مثل التصميم المتفق عليه.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

class MentionTagPrivacyScreen extends StatelessWidget {
  const MentionTagPrivacyScreen({super.key});

  static const Color _bg = Color(0xFF0F1720);
  static const Color _surface = Color(0xFF1A222C);
  static const Color _teal = Colors.teal;

  String _label(String value) {
    switch (value) {
      case 'following':
        return 'الأشخاص الذين تتابعهم';
      case 'friends':
        return 'الأصدقاء';
      case 'nobody':
        return 'لا أحد';
      default:
        return 'الجميع';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<custom.AuthProvider>();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'الذِكر والإشارات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
        children: [
          Material(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openPrivacySheet(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.chevron_left, color: Colors.white54, size: 23),
                        const SizedBox(width: 4),
                        Text(_label(auth.mentionPrivacy),
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const Spacer(),
                        const Text('السماح بالذكر من',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 13),
                    const Text(
                      'اختر من يمكنه ذكرك في أوصاف الفيديوهات والتعليقات والردود.',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPrivacySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MentionPrivacyOptionsSheet(),
    );
  }
}

class _MentionPrivacyOptionsSheet extends StatefulWidget {
  const _MentionPrivacyOptionsSheet();

  @override
  State<_MentionPrivacyOptionsSheet> createState() => _MentionPrivacyOptionsSheetState();
}

class _MentionPrivacyOptionsSheetState extends State<_MentionPrivacyOptionsSheet> {
  bool _saving = false;

  Future<void> _choose(String value) async {
    if (_saving) return;
    final auth = context.read<custom.AuthProvider>();
    if (auth.mentionPrivacy == value) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      await auth.updateMentionPrivacy(value);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFE53935),
          content: Text('تعذّر حفظ الإعداد. تحقق من الاتصال وحاول مجدداً.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _option(String value, String title, String selected, {String? subtitle}) {
    final checked = selected == value;
    return InkWell(
      onTap: _saving ? null : () => _choose(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Icon(
              checked ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: checked ? Colors.teal : Colors.white38,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(title,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle, textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = context.watch<custom.AuthProvider>().mentionPrivacy;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F1720),
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white)),
                  const Spacer(),
                  const Text('الذِكر والإشارات',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A222C),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 20, 18, 15),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text('من يمكنه ذكرك في أوصاف الفيديوهات والتعليقات والردود؟',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, height: 1.5)),
                      ),
                    ),
                    _option('everyone', 'الجميع', value),
                    _option('following', 'الأشخاص الذين تتابعهم', value),
                    _option('friends', 'الأصدقاء', value,
                        subtitle: 'الأشخاص الذين تتابعهم ويتابعونك'),
                    _option('nobody', 'لا أحد', value),
                    if (_saving) const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(color: Colors.teal, minHeight: 2),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
