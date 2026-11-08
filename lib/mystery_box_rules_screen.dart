import 'package:flutter/material.dart';
import 'app_colors.dart';

class MysteryBoxRulesScreen extends StatefulWidget {
  final String rarity; // bronze, silver, gold, diamond

  const MysteryBoxRulesScreen({
    super.key,
    required this.rarity,
  });

  @override
  State<MysteryBoxRulesScreen> createState() => _MysteryBoxRulesScreenState();
}

class _MysteryBoxRulesScreenState extends State<MysteryBoxRulesScreen> {
  bool _check1 = false;
  bool _check2 = false;
  bool _check3 = false;

  bool get _allAccepted => _check1 && _check2 && _check3;

  String _getRarityName() {
    switch (widget.rarity) {
      case 'bronze':
        return 'البرونزي';
      case 'silver':
        return 'الفضي';
      case 'gold':
        return 'الذهبي';
      case 'diamond':
        return 'الماسي';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          'شروط نشر الصندوق ${_getRarityName()}',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. قسم المحتوى المسموح
                _buildSectionTitle('المحتوى المسموح - ما الذي يستحق النشر؟'),
                const SizedBox(height: 12),
                _buildRuleItem('لقطات نادرة لا يمكن تكرارها: أحداث فريدة، مشاهد حصرية.'),
                _buildRuleItem('خبرتك التي توفر المال: شروحات، حلول، طرق ربح.'),
                _buildRuleItem('موهبتك الفريدة: غناء، تمثيل، رسم، عزف أمام الكاميرا.'),
                _buildRuleItem('كواليس وأسرار: ما وراء الكواليس في المطاعم، المصانع، المهن.'),
                _buildRuleItem('تحديات ورهانات: تحديات يتم تنفيذها فعليًا أمام المشاهد.'),
                
                const SizedBox(height: 24),

                // 2. قسم المحتوى الممنوع
                _buildSectionTitle('المحتوى الممنوع - أسباب حذف الصندوق', isNegative: true),
                const SizedBox(height: 12),
                _buildRuleItem('المحتوى المسروق: من يوتيوب، تيك توك، أو أي منصة أخرى.', isNegative: true),
                _buildRuleItem('المحتوى التافه: تصوير حائط، كوب، شاشة سوداء بلا قيمة.', isNegative: true),
                _buildRuleItem('إعادة النشر: رفع فيديو اشتريته من مستخدم آخر في التطبيق.', isNegative: true),
                _buildRuleItem('المحتوى المخالف: عنف، تحريض، محتوى جنسي، سياسة.', isNegative: true),
                _buildRuleItem('الغش والخداع: عنوان مضلل لا يطابق محتوى الفيديو.', isNegative: true),

                const SizedBox(height: 24),

                // 3. قسم العقوبات
                _buildPenaltyCard(),
              ],
            ),
          ),

          // 4. قسم التعهد والأزرار
          _buildAgreementSection(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {bool isNegative = false}) {
    return Text(
      title,
      style: TextStyle(
        color: isNegative ? AppColors.error : AppColors.primary,
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildRuleItem(String text, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isNegative ? Icons.cancel_outlined : Icons.check_circle_outline,
            color: isNegative ? AppColors.error : AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPenaltyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'العقوبات المطبقة:',
            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 10),
          Text(
            '• محتوى مسروق أو مخالف = حذف الصندوق + حظر 30 يوم.\n'
            '• محتوى تافه بلا قيمة = رفض الصندوق + منع من النشر لأسبوع.\n'
            '• استلام 3 بلاغات موثوقة = حذف الصندوق + منع من النشر لأسبوع.',
            style: TextStyle(color: AppColors.textPrimary, height: 1.7, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildAgreementSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.iconInactive, width: 0.5)),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: _check1,
            onChanged: (v) => setState(() => _check1 = v ?? false),
            title: const Text('أتعهد أن الفيديو من تصويري الخاص', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            activeColor: AppColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          CheckboxListTile(
            value: _check2,
            onChanged: (v) => setState(() => _check2 = v ?? false),
            title: const Text('أقر أن المحتوى حصري وغير منشور في أي منصة أخرى', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            activeColor: AppColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          CheckboxListTile(
            value: _check3,
            onChanged: (v) => setState(() => _check3 = v ?? false),
            title: const Text('أتحمل مسؤولية المحتوى وأوافق على حذفه في حال المخالفة', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            activeColor: AppColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _allAccepted
                  ? () => Navigator.pop(context, true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.iconInactive,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _allAccepted ? 'موافق والنشر الآن' : 'يجب الموافقة على جميع الشروط',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}