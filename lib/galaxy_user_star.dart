import 'package:flutter/material.dart';

/// Public identity bound to a world position, never to a screen pixel.
@immutable
class GalaxyUserStar {
  final String uid;
  final String username;
  final String fullName;
  final String profileImg;
  final Offset position;
  final bool visible;
  String get id => uid;

  const GalaxyUserStar({
    required this.uid,
    required this.username,
    required this.fullName,
    required this.profileImg,
    required this.position,
    this.visible = true,
  });

  factory GalaxyUserStar.fromProfile(
    String uid,
    Map<String, dynamic> data,
    Offset position,
  ) => GalaxyUserStar(
    uid: uid,
    username: (data['username'] ?? '').toString(),
    fullName: (data['fullName'] ?? '').toString(),
    profileImg: (data['profileImg'] ?? '').toString(),
    position: position,
  );
}