import 'package:flutter/material.dart';

class AppColors {
  // --- ألوان المساحات والخلفيات (Structure) ---
  // الخلفية الأساسية (BG): الأساس الزيتي الداكن (Tini Heritage)
  static const Color background = Color(0xFF0F1720);
  
  // خلفية الحاويات (Surface): للبطاقات والقوائم المرتفعة
  static const Color surface = Color(0xFF1A222C);
  
  // خلفية حقول الإدخال (Field Fill): لمربعات النصوص (لتمييزها عن الزيتي)
  static const Color fieldFill = Color(0xFF1C1C1E);

  // --- ألوان الأكشن والنجاح (Action & Success) ---
  // لون التميز والنجاح (Titi Teal): للأزرار الأساسية والتأكيد
  static const Color primary = Colors.teal;
  static const Color success = Colors.teal;

  // --- ألوان التنبيه والحذف والكلمات الخاصة (Alert & Highlight) ---
  // لون الحذف والخطأ (Error Red): للحذف النهائي ورسائل الخطأ
  static const Color error = Color(0xFFE53935);
  
  // لون الروابط والكلمات المميزة: لايف، نشر، نسيت كلمة السر؟
  static const Color highlight = Color(0xFFFF3B30);

  // --- ألوان النصوص والأيقونات (Typography) ---
  // النص الأساسي: للعناوين (أبيض ناصع)
  static const Color textPrimary = Colors.white;
  static const Color black = Color(0xFF000000); // إبقاء الأسود للاحتياج
  
  // [حل المشكلة]: إعادة الاسم القديم مع قيمة واضحة فوق الزيتي
  static const Color greyText = Color(0xFFBDC3C7); // رمادي فاتح جداً للشروحات
  
  // الأيقونات الثانوية: للعناصر غير النشطة
  static const Color iconInactive = Colors.white54;

  // --- ألوان التواصل الاجتماعي ---
  static const Color facebookBlue = Color(0xFF1877F2);
  static const Color googleRed = Color(0xFFDB4437);
  static const Color lightGrey = Color(0xFFF1F1F2);
}