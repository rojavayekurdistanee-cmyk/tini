import 'filter_model.dart';
import 'effect_widget.dart'; // ← عشان الإفكتات الحركية

class FiltersRepository {
  static List<FilterModel> allFilters = [
    // --- الفلاتر اللونية العادية ---
    FilterModel(
      id: 'none',
      name: 'عادي',
      category: 'أساسية',
      thumbnailAsset: 'none',
      matrix: [
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    FilterModel(
      id: 'retro',
      name: 'RETRO',
      category: 'الرائج',
      thumbnailAsset: 'retro',
      matrix: [
        0.393, 0.769, 0.189, 0, 0,
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    FilterModel(
      id: 'darklight',
      name: 'DarkLight',
      category: 'Vibe',
      thumbnailAsset: 'darklight',
      matrix: [
        0.6, 0, 0, 0, 0,
        0, 0.6, 0, 0, 0,
        0, 0, 0.6, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    FilterModel(
      id: 'darkme',
      name: 'DarkMe By TJ Ahmed',
      category: 'Vibe',
      thumbnailAsset: 'darkme',
      matrix: [
        0.4, 0, 0, 0, 0,
        0, 0.4, 0, 0, 0,
        0, 0, 0.5, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    FilterModel(
      id: 'blackkoko',
      name: 'Black KoKo By TJ Ahmed',
      category: 'Vibe',
      thumbnailAsset: 'blackkoko',
      matrix: [
        0.3, 0.3, 0.3, 0, 0,
        0.3, 0.3, 0.3, 0, 0,
        0.3, 0.3, 0.3, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    FilterModel(
      id: 'cute_polaroid',
      name: 'Cute Polaroid',
      category: 'مذهلة',
      thumbnailAsset: 'cute_polaroid',
      matrix: [
        1.2, 0, 0, 0, 0,
        0, 1.0, 0, 0, 0,
        0, 0, 0.8, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),

    // --- الإفكتات الحركية 🔥 ---
    FilterModel(
      id: 'shake',
      name: 'هزة',
      category: 'إفكتات',
      thumbnailAsset: 'shake',
      matrix: [1,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => ShakeWidget(child: child),
    ),
    FilterModel(
      id: 'zoom_pulse',
      name: 'نبض',
      category: 'إفكتات',
      thumbnailAsset: 'zoom',
      matrix: [1,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => ZoomPulseWidget(child: child),
    ),
    FilterModel(
      id: 'glitch',
      name: 'تشويش',
      category: 'إفكتات',
      thumbnailAsset: 'glitch',
      matrix: [1,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => GlitchColorWidget(child: child),
    ),
    FilterModel(
      id: 'earthquake',
      name: 'زلزال',
      category: 'إفكتات',
      thumbnailAsset: 'earthquake',
      matrix: [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => EarthquakeWidget(child: child),
    ),
    FilterModel(
      id: 'flash_cut',
      name: 'وميض',
      category: 'إفكتات',
      thumbnailAsset: 'flash',
      matrix: [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => FlashCutWidget(child: child),
    ),
    FilterModel(
      id: 'card_flip_3d',
      name: 'قلبة 3D',
      category: 'إفكتات',
      thumbnailAsset: 'flip',
      matrix: [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => CardFlip3DWidget(child: child),
    ),
    FilterModel(
      id: 'jello',
      name: 'جيلي',
      category: 'إفكتات',
      thumbnailAsset: 'jello',
      matrix: [1,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => JelloWidget(child: child),
    ),
    FilterModel(
      id: 'vhs',
      name: 'VHS قديم',
      category: 'إفكتات',
      thumbnailAsset: 'vhs',
      matrix: [1,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => VHSWidget(child: child),
    ),
    FilterModel(
      id: 'zoom_punch',
      name: 'لكمة زوم',
      category: 'إفكتات',
      thumbnailAsset: 'punch',
      matrix: [1,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => ZoomPunchWidget(child: child),
    ),
    FilterModel(
      id: 'rgb_split',
      name: 'فصل ألوان',
      category: 'إفكتات',
      thumbnailAsset: 'rgb',
      matrix: [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => RGBSplitWidget(child: child),
    ),
    FilterModel(
      id: 'bounce_scale',
      name: 'ارتداد دخول',
      category: 'إفكتات',
      thumbnailAsset: 'bounce',
      matrix: [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => BounceScaleWidget(child: child),
    ),
    FilterModel(
      id: 'ghost_trail',
      name: 'أثر شبحي',
      category: 'إفكتات',
      thumbnailAsset: 'ghost',
      matrix: [1,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0],
      effectBuilder: (child) => GhostTrailWidget(child: child),
    ),
  ];

  static List<String> get categories {
    return allFilters.map((e) => e.category).toSet().toList();
  }

  static List<FilterModel> getByCategory(String category) {
    return allFilters.where((f) => f.category == category).toList();
  }
}