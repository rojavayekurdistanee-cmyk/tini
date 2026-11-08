import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart' as custom;

class CommentAllowFromSheet extends StatefulWidget {
  const CommentAllowFromSheet({super.key});
  @override State<CommentAllowFromSheet> createState() => _CommentAllowFromSheetState();
}

class _CommentAllowFromSheetState extends State<CommentAllowFromSheet> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color fieldFill = const Color(0xFF1C1C1E);
  final Color titiTeal = Colors.teal;
  String? _selectedCommentValue;

  @override 
  void initState() { 
    super.initState(); 
    final auth = Provider.of<custom.AuthProvider>(context, listen: false); 
    _selectedCommentValue = auth.commentPrivacy; 
  }

  void _handleCommentSelection(String newValue) async {
    final auth = Provider.of<custom.AuthProvider>(context, listen: false);
    setState(() => _selectedCommentValue = newValue);
    await auth.updateCommentPrivacy(newValue);
    if (mounted) { 
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: surfaceColor, content: const Text("تم الحفظ", style: TextStyle(color: Colors.white)), duration: const Duration(seconds: 1))
      ); 
    }
  }

  Widget _buildCommentOption({required String value, required String title, required String subtitle, required IconData icon}) {
    final bool isSelected = _selectedCommentValue == value;
    return InkWell(
      onTap: () => _handleCommentSelection(value), 
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), 
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), 
        decoration: BoxDecoration(
          color: isSelected ? fieldFill : surfaceColor, 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: isSelected ? titiTeal : Colors.transparent, width: 1.2)
        ), 
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: isSelected ? titiTeal : Colors.white54, size: 20)), 
          const SizedBox(width: 12), 
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12))])), 
          Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? titiTeal : Colors.white54, size: 22)
        ])
      )
    );
  }

  @override 
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: bgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))), 
      padding: const EdgeInsets.all(16), 
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))), 
        const SizedBox(height: 16), 
        Row(children: [IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)), const Spacer(), const Text("التحكم في التعليقات", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const Spacer(), const SizedBox(width: 48)]), 
        const SizedBox(height: 8), 
        Align(alignment: Alignment.centerRight, child: Text("من يمكنه التعليق على منشوراتك", style: TextStyle(color: Colors.white70, fontSize: 13))), 
        const SizedBox(height: 16), 
        _buildCommentOption(value: 'comment_everyone', title: 'الجميع', subtitle: 'يمكن لأي شخص التعليق', icon: Icons.public), 
        _buildCommentOption(value: 'comment_friends', title: 'الأصدقاء', subtitle: 'المتابعون الذين تتابعهم فقط', icon: Icons.people), 
        _buildCommentOption(value: 'comment_nobody', title: 'لا أحد', subtitle: 'لا يمكن لأحد التعليق', icon: Icons.block), 
        const SizedBox(height: 10), 
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), decoration: BoxDecoration(color: surfaceColor.withOpacity(0.7), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: Row(children: [Icon(Icons.info_outline_rounded, color: titiTeal, size: 20), const SizedBox(width: 10), Expanded(child: Text("سيتم تطبيق هذا على منشوراتك الجديدة فقط.", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13.5, height: 1.5)))])), 
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 10)
      ])
    );
  }
}