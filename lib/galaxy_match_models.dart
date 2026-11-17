import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

DateTime matchDate(dynamic value) => value is Timestamp
    ? value.toDate()
    : value is num
    ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
    : DateTime.fromMillisecondsSinceEpoch(0);

@immutable
class GalaxyMatchPreferences {
  final String offer, need;
  final bool enabled;
  const GalaxyMatchPreferences({
    required this.offer,
    required this.need,
    required this.enabled,
  });
  factory GalaxyMatchPreferences.fromMap(Map<String, dynamic> data) =>
      GalaxyMatchPreferences(
        offer: (data['offer'] ?? '').toString(),
        need: (data['need'] ?? '').toString(),
        enabled: data['enabled'] == true,
      );
}

@immutable
class GalaxyMatchPreview {
  final String token, offer, need;
  final DateTime expiresAt;
  const GalaxyMatchPreview({
    required this.token,
    required this.offer,
    required this.need,
    required this.expiresAt,
  });
  factory GalaxyMatchPreview.fromMap(Map<String, dynamic> data) =>
      GalaxyMatchPreview(
        token: data['token'].toString(),
        offer: data['offer'].toString(),
        need: data['need'].toString(),
        expiresAt: matchDate(data['expiresAt']),
      );
}

enum GalaxyMatchStatus {
  pending,
  accepted,
  rejected,
  cancelled,
  expired,
  ended,
}

@immutable
class GalaxyMatchInvite {
  final String id, direction, offer, need;
  final GalaxyMatchStatus status;
  final DateTime updatedAt, expiresAt;
  final String? peerUid, peerName, peerUsername;
  const GalaxyMatchInvite({
    required this.id,
    required this.direction,
    required this.offer,
    required this.need,
    required this.status,
    required this.updatedAt,
    required this.expiresAt,
    this.peerUid,
    this.peerName,
    this.peerUsername,
  });
  factory GalaxyMatchInvite.fromMap(String id, Map<String, dynamic> data) {
    final status = GalaxyMatchStatus.values.firstWhere(
      (s) => s.name == data['status'],
      orElse: () => GalaxyMatchStatus.cancelled,
    );
    final peer = status == GalaxyMatchStatus.accepted && data['peer'] is Map
        ? data['peer'] as Map
        : null;
    return GalaxyMatchInvite(
      id: id,
      direction: (data['direction'] ?? '').toString(),
      offer: (data['offer'] ?? '').toString(),
      need: (data['need'] ?? '').toString(),
      status: status,
      updatedAt: matchDate(data['updatedAt']),
      expiresAt: matchDate(data['expiresAt']),
      peerUid: peer?['uid']?.toString(),
      peerName: peer?['fullName']?.toString(),
      peerUsername: peer?['username']?.toString(),
    );
  }
  String get statusLabel {
    if (status == GalaxyMatchStatus.pending &&
        !expiresAt.isAfter(DateTime.now())) {
      return 'منتهي الصلاحية';
    }
    return switch (status) {
      GalaxyMatchStatus.pending => 'بانتظار الرد',
      GalaxyMatchStatus.accepted => 'توافق مقبول',
      GalaxyMatchStatus.rejected => 'مرفوض',
      GalaxyMatchStatus.cancelled => 'ملغى',
      GalaxyMatchStatus.expired => 'منتهي الصلاحية',
      GalaxyMatchStatus.ended => 'توافق منتهٍ',
    };
  }
}