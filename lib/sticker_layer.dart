import 'package:flutter/material.dart';

class StickerLayer {
  final String id;
  final String path; // مسار الصورة أو نص الايموجي
  double x; // نسبة من عرض الشاشة 0.0 - 1.0
  double y; // نسبة من ارتفاع الشاشة 0.0 - 1.0
  double scale;
  double rotation; // بالراديان
  final bool isEmoji;
  final bool isGif;
  final bool isFromGallery;
  bool isFavorite;
  bool isSelected;

  StickerLayer({
    required this.id,
    required this.path,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.isEmoji = false,
    this.isGif = false,
    this.isFromGallery = false,
    this.isFavorite = false,
    this.isSelected = true,
  });

  StickerLayer copyWith({
    String? id,
    String? path,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    bool? isEmoji,
    bool? isGif,
    bool? isFromGallery,
    bool? isFavorite,
    bool? isSelected,
  }) {
    return StickerLayer(
      id: id?? this.id,
      path: path?? this.path,
      x: x?? this.x,
      y: y?? this.y,
      scale: scale?? this.scale,
      rotation: rotation?? this.rotation,
      isEmoji: isEmoji?? this.isEmoji,
      isGif: isGif?? this.isGif,
      isFromGallery: isFromGallery?? this.isFromGallery,
      isFavorite: isFavorite?? this.isFavorite,
      isSelected: isSelected?? this.isSelected,
    );
  }
}