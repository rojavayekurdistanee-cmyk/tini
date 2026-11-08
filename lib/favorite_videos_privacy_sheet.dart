import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

// [Tini - Favorite Videos Privacy]: نافذة التحكم بعرض قائمة الفيديوهات المفضلة.
class FavoriteVideosPrivacySheet extends StatefulWidget {
  const FavoriteVideosPrivacySheet({super.key});

  @override
  State<FavoriteVideosPrivacySheet> createState() => _FavoriteVideosPrivacySheetState();
}

class _FavoriteVideosPrivacySheetState extends State<FavoriteVideosPrivacySheet> {
  bool _saving = false;

  Future<void> _choose(String value) async {
    if (_saving) return;
    final auth = context.read<custom.AuthProvider>();
    if (auth.favoriteVideosPrivacy == value) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      await auth.updateFavoriteVideosPrivacy(value);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFE53935),
          content: Text('تعذّر حفظ إعداد المفضلة. حاول مجدداً.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _option(String value, String label, String current) {
    final bool checked = current == value;
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
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<custom.AuthProvider>().favoriteVideosPrivacy;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F1720),
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                const Spacer(),
                const Text(
                  'فيديوهاتك المفضلة',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
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
                      child: Text(
                        'السماح بعرض قائمة فيديوهات المفضلة بواسطة',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, height: 1.5),
                      ),
                    ),
                  ),
                  _option('everyone', 'الجميع', selected),
                  _option('only_me', 'لك فقط', selected),
                  if (_saving)
                    const Padding(
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
    );
  }
}
