import 'package:flutter/material.dart';

class TextLayer {
  String text;
  Color color;
  String fontFamily;
  double x;
  double y;
  double scale;
  double rotation;
  TextAlign align;
  Color? backgroundColor;
  double backgroundOpacity;

  TextLayer({
    required this.text,
    this.color = Colors.white,
    this.fontFamily = 'Roboto',
    this.x = 100,
    this.y = 200,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.align = TextAlign.center,
    this.backgroundColor,
    this.backgroundOpacity = 0.7,
  });

  TextLayer copyWith({
    String? text,
    Color? color,
    String? fontFamily,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    TextAlign? align,
    Color? backgroundColor,
    bool setBackgroundColorToNull = false,
    double? backgroundOpacity,
  }) {
    return TextLayer(
      text: text?? this.text,
      color: color?? this.color,
      fontFamily: fontFamily?? this.fontFamily,
      x: x?? this.x,
      y: y?? this.y,
      scale: scale?? this.scale,
      rotation: rotation?? this.rotation,
      align: align?? this.align,
      backgroundColor: setBackgroundColorToNull? null : backgroundColor?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity?? this.backgroundOpacity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'color': color.value,
      'fontFamily': fontFamily,
      'x': x,
      'y': y,
      'scale': scale,
      'rotation': rotation,
      'align': align.index,
      'backgroundColor': backgroundColor?.value,
      'backgroundOpacity': backgroundOpacity,
    };
  }

  factory TextLayer.fromJson(Map<String, dynamic> json) {
    return TextLayer(
      text: json['text'],
      color: Color(json['color']),
      fontFamily: json['fontFamily'],
      x: json['x'],
      y: json['y'],
      scale: json['scale'],
      rotation: json['rotation'],
      align: TextAlign.values[json['align']],
      backgroundColor: json['backgroundColor']!= null? Color(json['backgroundColor']) : null,
      backgroundOpacity: json['backgroundOpacity']?? 0.7,
    );
  }
}