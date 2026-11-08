import 'package:cloud_firestore/cloud_firestore.dart';

class GroupMessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String senderImg;
  final String text;
  final String type;
  final String? mediaUrl;
  final List<Map<String, dynamic>> mediaItems;
  final DateTime timestamp;
  final List<String> deliveredTo;
  final List<String> readBy;
  final Map<String, dynamic>? replyTo;
  final int? durationSeconds;
  final List<int>? waveform;
  final bool viewOnce;
  final List<String> viewedBy;

  GroupMessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderImg,
    required this.text,
    required this.type,
    this.mediaUrl,
    this.mediaItems = const [],
    required this.timestamp,
    required this.deliveredTo,
    required this.readBy,
    this.replyTo,
    this.durationSeconds,
    this.waveform,
    this.viewOnce = false,
    this.viewedBy = const [],
  });

  factory GroupMessageModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = data['timestamp'] as Timestamp?;
    return GroupMessageModel(
      id: doc.id,
      senderId: data['senderId']?? '',
      senderName: data['senderName']?? 'مستخدم',
      senderImg: data['senderImg']?? '',
      text: data['text']?? '',
      type: data['type']?? 'text',
      mediaUrl: data['mediaUrl'],
      mediaItems: (data['mediaItems'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? const [],
      timestamp: ts?.toDate()?? DateTime.now(),
      deliveredTo: List<String>.from(data['deliveredTo']?? []),
      readBy: List<String>.from(data['readBy']?? []),
      replyTo: data['replyTo']!= null? Map<String, dynamic>.from(data['replyTo']) : null,
      durationSeconds: data['durationSeconds'] as int?,
      waveform: (data['waveform'] as List?)?.map((e) => (e as num).toInt()).toList(),
      viewOnce: data['viewOnce'] == true,
      viewedBy: List<String>.from(data['viewedBy'] ?? []),
    );
  }
}