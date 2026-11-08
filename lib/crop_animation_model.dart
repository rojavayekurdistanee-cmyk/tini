/// Animation settings belong to one timeline clip, not the whole video.
/// Start and End play once; Group repeats while the clip is visible.
enum CropAnimationTab { start, end, group }

class CropAnimationPreset {
  final String id;
  final String title;
  final CropAnimationTab tab;
  const CropAnimationPreset(this.id, this.title, this.tab);
}

class CropAnimationCatalog {
  static const presets = <CropAnimationPreset>[
    CropAnimationPreset('fade_in', 'ظهور تدريجي', CropAnimationTab.start),
    CropAnimationPreset('slide_in', 'شريحة للداخل', CropAnimationTab.start),
    CropAnimationPreset('slide_in_left', 'تمرير', CropAnimationTab.start),
    CropAnimationPreset('rise_in', 'Flash In Up', CropAnimationTab.start),
    CropAnimationPreset('zoom_in', 'تكبير', CropAnimationTab.start),
    CropAnimationPreset('fold_in', 'طي وفرد', CropAnimationTab.start),
    CropAnimationPreset('fade_out', 'اختفاء تدريجي', CropAnimationTab.end),
    CropAnimationPreset('slide_out', 'شريحة للخارج', CropAnimationTab.end),
    CropAnimationPreset('slide_out_left', 'تمرير', CropAnimationTab.end),
    CropAnimationPreset('fall_out', 'طي وفرد', CropAnimationTab.end),
    CropAnimationPreset('zoom_out', 'تصغير', CropAnimationTab.end),
    CropAnimationPreset('fold_out', 'انطواء', CropAnimationTab.end),
    CropAnimationPreset('dynamic_shake', 'اهتزاز ديناميكي', CropAnimationTab.group),
    CropAnimationPreset('vertical_glitch', 'خلل عمودي', CropAnimationTab.group),
    CropAnimationPreset('pendulum', 'البندول', CropAnimationTab.group),
    CropAnimationPreset('pulse', 'نبض', CropAnimationTab.group),
    CropAnimationPreset('float', 'طفو', CropAnimationTab.group),
    CropAnimationPreset('rock', 'تأرجح', CropAnimationTab.group),
    // Ten additional, individually named start animations.
    CropAnimationPreset('spin_in', 'دوران كامل', CropAnimationTab.start),
    CropAnimationPreset('drop_in', 'هبوط من الأعلى', CropAnimationTab.start),
    CropAnimationPreset('diagonal_in', 'دخول قطري', CropAnimationTab.start),
    CropAnimationPreset('mirror_in', 'قلب أفقي', CropAnimationTab.start),
    CropAnimationPreset('blur_in', 'وضوح تدريجي', CropAnimationTab.start),
    CropAnimationPreset('flash_in', 'وميض ضوئي', CropAnimationTab.start),
    CropAnimationPreset('mono_in', 'عودة الألوان', CropAnimationTab.start),
    CropAnimationPreset('negative_in', 'تحوّل الصورة', CropAnimationTab.start),
    CropAnimationPreset('bounce_in', 'قفزة مرنة', CropAnimationTab.start),
    CropAnimationPreset('shutter_in', 'قلب عمودي', CropAnimationTab.start),
    // Ten additional, individually named end animations.
    CropAnimationPreset('spin_out', 'دوران للخروج', CropAnimationTab.end),
    CropAnimationPreset('lift_out', 'صعود للأعلى', CropAnimationTab.end),
    CropAnimationPreset('diagonal_out', 'خروج قطري', CropAnimationTab.end),
    CropAnimationPreset('mirror_out', 'قلب للخروج', CropAnimationTab.end),
    CropAnimationPreset('blur_out', 'ضباب النهاية', CropAnimationTab.end),
    CropAnimationPreset('flash_out', 'وميض الختام', CropAnimationTab.end),
    CropAnimationPreset('mono_out', 'زوال الألوان', CropAnimationTab.end),
    CropAnimationPreset('negative_out', 'عكس الألوان', CropAnimationTab.end),
    CropAnimationPreset('bounce_out', 'قفزة النهاية', CropAnimationTab.end),
    CropAnimationPreset('shutter_out', 'انقلاب عمودي', CropAnimationTab.end),
    // Ten additional, individually named group animations.
    CropAnimationPreset('orbit', 'مدار دائري', CropAnimationTab.group),
    CropAnimationPreset('full_spin', 'دوران مستمر', CropAnimationTab.group),
    CropAnimationPreset('rainbow', 'ألوان الطيف', CropAnimationTab.group),
    CropAnimationPreset('strobe', 'وميض متقطع', CropAnimationTab.group),
    CropAnimationPreset('flip_h_loop', 'مرآة متكررة', CropAnimationTab.group),
    CropAnimationPreset('flip_v_loop', 'انعكاس عمودي', CropAnimationTab.group),
    CropAnimationPreset('negative_loop', 'عكس متكرر', CropAnimationTab.group),
    CropAnimationPreset('greyscale_loop', 'أبيض وأسود', CropAnimationTab.group),
    CropAnimationPreset('grid_flash', 'شبكة ضوئية', CropAnimationTab.group),
    CropAnimationPreset('exposure_wave', 'موجة الإضاءة', CropAnimationTab.group),
  ];

  static List<CropAnimationPreset> forTab(CropAnimationTab tab) =>
      presets.where((p) => p.tab == tab).toList(growable: false);

  /// Deterministic colour hue per effect; UI applies saturation and alpha.
  /// Keeping colour metadata numeric avoids a Material dependency in render code.
  static double hueFor(String id) {
    final index = presets.indexWhere((preset) => preset.id == id);
    return index < 0 ? 180.0 : (index * 137.507764) % 360.0;
  }

}

class CropAnimationSettings {
  final String? start;
  final String? end;
  final String? group;
  final double startSeconds;
  final double endSeconds;
  final double groupSeconds;

  const CropAnimationSettings({
    this.start,
    this.end,
    this.group,
    this.startSeconds = 0.7,
    this.endSeconds = 0.7,
    this.groupSeconds = 1.0,
  });

  bool get hasEffects => start != null || end != null || group != null;

  String? effect(CropAnimationTab tab) {
    switch (tab) {
      case CropAnimationTab.start: return start;
      case CropAnimationTab.end: return end;
      case CropAnimationTab.group: return group;
    }
  }

  double seconds(CropAnimationTab tab) {
    switch (tab) {
      case CropAnimationTab.start: return startSeconds;
      case CropAnimationTab.end: return endSeconds;
      case CropAnimationTab.group: return groupSeconds;
    }
  }

  /// An explicit nullable effect setter permits choosing 'لا شيء'.
  CropAnimationSettings withEffect(CropAnimationTab tab, String? id) =>
      CropAnimationSettings(
        start: tab == CropAnimationTab.start ? id : start,
        end: tab == CropAnimationTab.end ? id : end,
        group: tab == CropAnimationTab.group ? id : group,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        groupSeconds: groupSeconds,
      );

  CropAnimationSettings withSeconds(CropAnimationTab tab, double value) =>
      CropAnimationSettings(
        start: start,
        end: end,
        group: group,
        startSeconds: tab == CropAnimationTab.start ? value : startSeconds,
        endSeconds: tab == CropAnimationTab.end ? value : endSeconds,
        groupSeconds: tab == CropAnimationTab.group ? value : groupSeconds,
      );

  /// Preserve an entry only on the first half and an exit only on the last.
  CropAnimationSettings get firstHalf => CropAnimationSettings(
    start: start, group: group, startSeconds: startSeconds,
    endSeconds: endSeconds, groupSeconds: groupSeconds);

  CropAnimationSettings get secondHalf => CropAnimationSettings(
    end: end, group: group, startSeconds: startSeconds,
    endSeconds: endSeconds, groupSeconds: groupSeconds);

  @override
  bool operator ==(Object other) => other is CropAnimationSettings &&
      start == other.start && end == other.end && group == other.group &&
      startSeconds == other.startSeconds && endSeconds == other.endSeconds &&
      groupSeconds == other.groupSeconds;

  @override
  int get hashCode => Object.hash(
      start, end, group, startSeconds, endSeconds, groupSeconds);
}
