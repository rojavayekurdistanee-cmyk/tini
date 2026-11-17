/// Stable skill keys shared with the server; labels can be localized later.
class GalaxyMatchCategories {
  static const skills = <String, String>{
    'language.english': 'الإنجليزية',
    'language.arabic': 'العربية',
    'language.kurdish': 'الكردية',
    'language.turkish': 'التركية',
    'photography.basics': 'أساسيات التصوير',
    'design.graphics': 'التصميم الجرافيكي',
    'coding.basics': 'أساسيات البرمجة',
    'writing.basics': 'الكتابة',
    'cooking.basics': 'الطبخ',
    'music.basics': 'الموسيقى',
    'video.editing': 'المونتاج',
    'study.math': 'الرياضيات',
    'study.science': 'العلوم',
  };
  static String label(String key) => skills[key] ?? 'مهارة غير متاحة';
}
