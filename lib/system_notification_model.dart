enum SystemNotifType { usage, report }

class SystemNotification {
  final String id;
  final SystemNotifType type;
  final String title;
  final String body;
  final DateTime time;
  bool isRead;
  final String avgText;
  final String percentText;
  final int totalSeconds;

  SystemNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
    this.avgText = "",
    this.percentText = "",
    this.totalSeconds = 0,
  });
}