import 'package:flutter/material.dart';

class FilterModel {
  final String id;
  final String name;
  final String category;
  final List<double> matrix;
  final String thumbnailAsset;
  final Widget Function(Widget child)? effectBuilder; // ← الجديد: للإفكتات الحركية

  const FilterModel({
    required this.id,
    required this.name,
    required this.category,
    required this.matrix,
    required this.thumbnailAsset,
    this.effectBuilder, // ← اختياري. اذا موجود منشغل إفكت، اذا لأ منشغل matrix
  });

  ColorFilter get colorFilter => ColorFilter.matrix(matrix);

  // هل هذا فلتر لوني ولا إفكت حركي؟
  bool get isEffect => effectBuilder != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}