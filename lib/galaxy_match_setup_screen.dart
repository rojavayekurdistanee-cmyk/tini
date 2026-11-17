import 'package:flutter/material.dart';
import 'galaxy_match_categories.dart';
import 'galaxy_match_provider.dart';

class GalaxyMatchSetupScreen extends StatefulWidget {
  final GalaxyMatchProvider provider;
  const GalaxyMatchSetupScreen({super.key, required this.provider});
  @override
  State<GalaxyMatchSetupScreen> createState() => _GalaxyMatchSetupScreenState();
}

class _GalaxyMatchSetupScreenState extends State<GalaxyMatchSetupScreen> {
  String? _offer, _need;
  String? _owner;
  bool _enabled = true;
  bool _initialized = false;
  @override
  void initState() {
    super.initState();
    _owner = widget.provider.userId;
    _initialized = widget.provider.ready;
    final p = widget.provider.preferences;
    _offer = p?.offer;
    _need = p?.need;
    _enabled = p?.enabled ?? true;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.provider,
    builder: (context, _) {
      if (_owner != widget.provider.userId) {
        _owner = widget.provider.userId;
        _offer = widget.provider.preferences?.offer;
        _need = widget.provider.preferences?.need;
        _enabled = widget.provider.preferences?.enabled ?? true;
        _initialized = false;
      }
      if (!_initialized && widget.provider.ready) {
        _offer = widget.provider.preferences?.offer;
        _need = widget.provider.preferences?.need;
        _enabled = widget.provider.preferences?.enabled ?? true;
        _initialized = true;
      }
      return Scaffold(
        backgroundColor: const Color(0xFF0F1720),
        appBar: AppBar(
          title: const Text('إعداد النجمة الناقصة'),
          backgroundColor: const Color(0xFF0F1720),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'اكتشف من يكملك',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'مشاركة اختيارية لتبادل المهارات للحسابات العامة الظاهرة في المجرة. يلزم توفر بيانات عمر صالحة، وتكون المطابقة ضمن الفئة العمرية نفسها. لا تظهر هويتك قبل إرسال طلب وقبوله.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            _choice(
              'ماذا تستطيع أن تقدم للآخرين؟',
              _offer,
              (v) => setState(() => _offer = v),
            ),
            const SizedBox(height: 20),
            _choice(
              'ماذا تريد أن تتعلم؟',
              _need,
              (v) => setState(() => _need = v),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text(
                'المشاركة في التوافقات',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'إيقاف المشاركة يوقف الاكتشاف والطلبات الجديدة، وتبقى توافقاتك المقبولة',
                style: TextStyle(color: Colors.white60),
              ),
              activeTrackColor: Colors.teal,
              value: _enabled,
              onChanged: widget.provider.busy
                  ? null
                  : (v) => setState(() => _enabled = v),
            ),
            if (widget.provider.error != null)
              Text(
                widget.provider.error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: widget.provider.busy || _offer == null || _need == null
                  ? null
                  : () async {
                      final saved = await widget.provider.save(
                        _offer!,
                        _need!,
                        _enabled,
                      );
                      if (context.mounted && saved) {
                        Navigator.pop(context, true);
                      }
                    },
              child: Text(
                widget.provider.busy
                    ? 'جارٍ الحفظ…'
                    : _enabled
                    ? 'حفظ وتفعيل البحث'
                    : 'حفظ وإيقاف المشاركة',
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _choice(String title, String? value, ValueChanged<String?> changed) =>
      DropdownButtonFormField<String>(
        key: ValueKey('$_owner:$title:$_initialized'),
        initialValue: GalaxyMatchCategories.skills.containsKey(value)
            ? value
            : null,
        isExpanded: true,
        dropdownColor: const Color(0xFF1A222C),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: title,
          labelStyle: const TextStyle(color: Color(0xFF80CBC4)),
          filled: true,
          fillColor: const Color(0xFF1A222C),
          border: const OutlineInputBorder(),
        ),
        items: GalaxyMatchCategories.skills.entries
            .map((s) => DropdownMenuItem(value: s.key, child: Text(s.value)))
            .toList(),
        onChanged: widget.provider.busy ? null : changed,
      );
}
