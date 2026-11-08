import 'crop_effects_catalog.dart';

/// Per-clip, non-destructive visual effects, measured on the output timeline
/// (after speed curves); no source clip or media file is modified.
class TiniAppliedEffect {
  final String id;
  final double startSeconds;
  final double endSeconds;

  const TiniAppliedEffect({required this.id, required this.startSeconds,
      required this.endSeconds});

  TiniEffectDescriptor? get descriptor => TiniEffectsCatalog.find(id);

  TiniAppliedEffect copyWith({double? startSeconds, double? endSeconds}) =>
      TiniAppliedEffect(id: id, startSeconds: startSeconds ?? this.startSeconds,
          endSeconds: endSeconds ?? this.endSeconds);

  bool active(double time) => time >= startSeconds && time < endSeconds;

  @override
  bool operator ==(Object other) => other is TiniAppliedEffect &&
      id == other.id && startSeconds == other.startSeconds &&
      endSeconds == other.endSeconds;

  @override
  int get hashCode => Object.hash(id, startSeconds, endSeconds);
}

bool sameTiniEffects(List<TiniAppliedEffect> a, List<TiniAppliedEffect> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
