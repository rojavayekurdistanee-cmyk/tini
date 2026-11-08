import 'package:flutter/material.dart';

class CommentFilteredReviewScreen extends StatelessWidget {
  const CommentFilteredReviewScreen({super.key});
  @override 
  Widget build(BuildContext context) {
    final Color commentReviewBgColor = const Color(0xFF0F1720);
    final Color commentReviewSurfaceColor = const Color(0xFF1A222C);
    return Scaffold(
      backgroundColor: commentReviewBgColor,
      appBar: AppBar(
        backgroundColor: commentReviewBgColor, 
        elevation: 0, 
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)), 
        title: const Text("مراجعة التعليقات التي تم تصفيتها", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)), 
        centerTitle: true
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(), 
        padding: const EdgeInsets.all(16), 
        children: [
          Container(
            height: 200, 
            decoration: BoxDecoration(color: commentReviewSurfaceColor, borderRadius: BorderRadius.circular(18)), 
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.filter_list_off_rounded, color: Colors.white24, size: 48), 
              const SizedBox(height: 12), 
              Text("لا توجد تعليقات للمراجعة", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14))
            ])
          ),
        ]
      ),
    );
  }
}