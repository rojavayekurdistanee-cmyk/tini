import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;
import 'comment_allow_from_sheet.dart';
import 'comment_filter_keywords_screen.dart';
import 'comment_filtered_review_screen.dart';

class CommentSettingsScreen extends StatefulWidget {
  const CommentSettingsScreen({super.key});

  @override
  State<CommentSettingsScreen> createState() => _CommentSettingsScreenState();
}

class _CommentSettingsScreenState extends State<CommentSettingsScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color fieldFill = const Color(0xFF1C1C1E);
  final Color titiTeal = Colors.teal;
  final Color errorRed = const Color(0xFFE53935);
  final Color highlightRed = const Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<custom.AuthProvider>(context);
    
    String commentPrivacyText = "الجميع";
    if (auth.commentPrivacy == 'comment_friends') commentPrivacyText = "الأصدقاء";
    if (auth.commentPrivacy == 'comment_nobody') commentPrivacyText = "لا أحد";
    
    bool commentFilterAll = false;
    bool commentFilterSpam = true;
    try {
      commentFilterAll = (auth as dynamic).commentFilterAll ?? false;
      commentFilterSpam = (auth as dynamic).commentFilterSpam ?? true;
    } catch (_) {}

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("التحكم في التعليقات", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildCommentNavigationCard(title: "السماح بالتعليقات من", value: commentPrivacyText, onTap: () => _openCommentAllowSheet(context)),
          const SizedBox(height: 24),
          Padding(padding: const EdgeInsets.only(right: 4, bottom: 8), child: Text("تصفية التعليقات", style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.right)),
          Container(
            decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _buildCommentSwitchTile(title: "تصفية كل التعليقات", subtitle: "سيتم إخفاء التعليقات الأخيرة على الفيديو الذي أنشأته ما لم توافق عليها. يقتصر هذا على 5 تغييرات في اليوم الواحد.", value: commentFilterAll, onChanged: (v) => setState(() {})),
                _buildCommentDivider(),
                _buildCommentSwitchTile(title: "تصفية التعليقات غير المرغوب فيها", subtitle: "سيتم إخفاء التعليقات الأخيرة التي قد تكون مسيئة أو غير مرغوب فيها ما لم توافق عليها", value: commentFilterSpam, onChanged: (v) => setState(() {})),
                _buildCommentDivider(),
                _buildCommentNavigationTile(title: "تصفية كلمات رئيسية محددة", subtitle: "سيتم إخفاء التعليقات الأخيرة التي تحتوي على الكلمات الرئيسية المحددة على فيديوهاتك ما لم توافق عليها", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommentFilterKeywordsScreen()))),
                _buildCommentDivider(),
                _buildCommentNavigationTile(title: "مراجعة التعليقات التي تم تصفيتها", subtitle: "سيتم عرض التعليقات التي تمت الموافقة عليها فقط", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommentFilteredReviewScreen()))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentNavigationCard({required String title, required String value, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(Icons.chevron_left, color: Colors.white54, size: 20), const SizedBox(width: 8), Text(value, style: TextStyle(color: Colors.white54, fontSize: 14)), const Spacer(), Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600))])));
  }

  Widget _buildCommentSwitchTile({required String title, required String subtitle, required bool value, required Function(bool) onChanged}) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Switch(value: value, onChanged: onChanged, activeColor: Colors.white, activeTrackColor: titiTeal, inactiveThumbColor: Colors.white, inactiveTrackColor: Colors.white24), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600), textAlign: TextAlign.right))]), const SizedBox(height: 8), Text(subtitle, style: TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.5), textAlign: TextAlign.right)]));
  }

  Widget _buildCommentNavigationTile({required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.chevron_left, color: Colors.white54, size: 20), const Spacer(), Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600), textAlign: TextAlign.right)]), const SizedBox(height: 8), Text(subtitle, style: TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.5), textAlign: TextAlign.right)])));
  }

  Widget _buildCommentDivider() => Divider(color: Colors.white10, height: 1, indent: 16, endIndent: 16);

  void _openCommentAllowSheet(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (_) => const CommentAllowFromSheet());
  }
}