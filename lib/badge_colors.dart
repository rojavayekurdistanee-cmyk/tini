import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Color getBadgeCommentColor(String? badge, DateTime? endsAt) {
  // إذا ما في شارة، أو انتهت مدتها، رجع أبيض
  if (badge == null) return Colors.white;
  if (endsAt != null && endsAt.isBefore(DateTime.now())) {
    return Colors.white;
  }

  switch (badge.toLowerCase()) {
    case 'diamond':
      return const Color(0xFF00E5FF);
    case 'gold':
      return const Color(0xFFFFD700);
    case 'silver':
      return const Color(0xFFC0C0C0);
    case 'bronze':
      return const Color(0xFFCD7F32);
    default:
      return Colors.white;
  }
}

// Helper إذا بدك تمرر Timestamp مباشرة من Firestore
Color getBadgeCommentColorFromTimestamp(String? badge, Timestamp? endsAt) {
  return getBadgeCommentColor(badge, endsAt?.toDate());
}