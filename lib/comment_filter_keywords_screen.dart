import 'package:flutter/material.dart';

class CommentFilterKeywordsScreen extends StatefulWidget {
  const CommentFilterKeywordsScreen({super.key});
  @override State<CommentFilterKeywordsScreen> createState() => _CommentFilterKeywordsScreenState();
}

class _CommentFilterKeywordsScreenState extends State<CommentFilterKeywordsScreen> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color fieldFill = const Color(0xFF1C1C1E);
  final Color titiTeal = Colors.teal;
  final TextEditingController _commentKeywordController = TextEditingController();
  bool _isCommentKeywordEnabled = true;
  List<String> _commentKeywords = ["سبام", "إعلان"];

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(backgroundColor: bgColor, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)), title: const Text("تصفية كلمات رئيسية محددة", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), centerTitle: true),
      body: ListView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Switch(value: _isCommentKeywordEnabled, onChanged: (v) => setState(() => _isCommentKeywordEnabled = v), activeThumbColor: Colors.white, activeTrackColor: titiTeal, inactiveThumbColor: Colors.white, inactiveTrackColor: Colors.white24), const Text("تفعيل تصفية الكلمات", style: TextStyle(color: Colors.white, fontSize: 14.5))])),
        const SizedBox(height: 16),
        TextField(controller: _commentKeywordController, style: const TextStyle(color: Colors.white), decoration: InputDecoration(filled: true, fillColor: fieldFill, hintText: "أضف كلمة مفتاحية", hintStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), suffixIcon: IconButton(icon: Icon(Icons.add, color: titiTeal), onPressed: _addCommentKeyword)), onSubmitted: (_) => _addCommentKeyword()),
        const SizedBox(height: 20),
        ..._commentKeywords.map((k) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)), child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: Colors.white, fontSize: 14))), InkWell(onTap: () => setState(() => _commentKeywords.remove(k)), child: const Icon(Icons.close, color: Colors.white54, size: 18))]))),
      ]),
    );
  }
  void _addCommentKeyword() { if (_commentKeywordController.text.trim().isEmpty) return; setState(() { _commentKeywords.add(_commentKeywordController.text.trim()); _commentKeywordController.clear(); }); }
}