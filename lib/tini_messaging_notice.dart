import 'package:flutter/material.dart';
import 'chat_provider.dart';

/// [Tini - Messaging] عرض نتائج المراسلة فقط؛ لا يغيّر قواعد السماح أو حفظ الرسائل.
/// يُستخدم من المحادثة والقصص ونوافذ المشاركة لتوحيد شكل الإشعار.
enum _TiniMessageNoticeKind { privacy, success, error, info }

class TiniMessagingNotice {
  TiniMessagingNotice._();

  static const Color _surface = Color(0xFF1A222C);
  static const Color _errorRed = Color(0xFFE53935);

  static void _show(
    ScaffoldMessengerState? messenger, {
    required String title,
    String? description,
    required _TiniMessageNoticeKind kind,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onRetry,
  }) {
    if (messenger == null || !messenger.mounted) return;

    IconData icon = Icons.info_outline;
    Color iconColor = Colors.white54;
    switch (kind) {
      case _TiniMessageNoticeKind.privacy:
        icon = Icons.shield_outlined;
        iconColor = Colors.white54;
        break;
      case _TiniMessageNoticeKind.success:
        icon = Icons.check_circle_outline;
        iconColor = Colors.teal;
        break;
      case _TiniMessageNoticeKind.error:
        icon = Icons.error_outline;
        iconColor = _errorRed;
        break;
      case _TiniMessageNoticeKind.info:
        icon = Icons.info_outline;
        iconColor = Colors.white54;
        break;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: _surface,
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      duration: duration,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      action: kind == _TiniMessageNoticeKind.error && onRetry != null
          ? SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.teal,
              onPressed: onRetry,
            )
          : null,
    ));
  }

  // لا نفترض أن permission-denied أو تعذّر قراءة الخصوصية خطأ تقني؛
  // هذه الأسباب غير حاسمة، لذا تحصل على إشعار محايد لا يضلّل المستخدم.
  static bool _isTechnicalFailure(ChatFailureReason reason) {
    return reason == ChatFailureReason.technicalError ||
        reason == ChatFailureReason.roomNotFound;
  }

  static _TiniMessageNoticeKind _failureKind(ChatFailureReason? reason) {
    if (reason == null) return _TiniMessageNoticeKind.error;
    if (reason.isPrivacyRestriction) return _TiniMessageNoticeKind.privacy;
    return _isTechnicalFailure(reason)
        ? _TiniMessageNoticeKind.error
        : _TiniMessageNoticeKind.info;
  }

  /// الرفض من إعدادات الخصوصية محايد؛ الفشل التقني فقط يحمل أيقونة حمراء.
  static void showFailure(
    ScaffoldMessengerState? messenger,
    ChatFailureReason? reason, {
    String action = 'إرسال الرسالة',
    VoidCallback? onRetry,
  }) {
    final kind = _failureKind(reason);
    _show(
      messenger,
      title: kind == _TiniMessageNoticeKind.privacy
          ? 'خصوصية المراسلة'
          : 'تعذّر $action',
      description: reason?.userMessage ??
          'تعذّر إتمام العملية. تحقق من اتصالك وحاول مرة أخرى.',
      kind: kind,
      onRetry: kind == _TiniMessageNoticeKind.error ? onRetry : null,
    );
  }

  static void showAccess(
    ScaffoldMessengerState? messenger,
    ChatFailureReason? reason,
  ) {
    showFailure(messenger, reason, action: 'فتح المحادثة');
  }

  static void showSuccess(
    ScaffoldMessengerState? messenger,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    _show(messenger,
        title: message, kind: _TiniMessageNoticeKind.success,
        duration: duration);
  }

  static void showInfo(
    ScaffoldMessengerState? messenger,
    String message, {
    String? title,
  }) {
    _show(messenger,
        title: title ?? message,
        description: title == null ? null : message,
        kind: _TiniMessageNoticeKind.info);
  }

  static void showTechnicalError(
    ScaffoldMessengerState? messenger,
    String title, {
    String description = 'تعذّر إتمام العملية. تحقق من اتصالك وحاول مرة أخرى.',
    VoidCallback? onRetry,
  }) {
    _show(messenger,
        title: title,
        description: description,
        kind: _TiniMessageNoticeKind.error,
        onRetry: onRetry);
  }

  /// null = تم حفظ المشاركة. لا تختلط نتائج المستلمين عند الإرسال المتزامن.
  static void showShareOutcome(
    ScaffoldMessengerState? messenger,
    List<ChatFailureReason?> results, {
    String itemLabel = 'المشاركة',
  }) {
    if (messenger == null || !messenger.mounted || results.isEmpty) return;

    final failureCounts = <ChatFailureReason, int>{};
    for (final reason in results) {
      if (reason != null) {
        failureCounts.update(reason, (count) => count + 1,
            ifAbsent: () => 1);
      }
    }
    final failed = failureCounts.values.fold<int>(0, (sum, count) => sum + count);
    final successful = results.length - failed;
    final title = failed == 0
        ? 'تمت المشاركة مع $successful'
        : successful > 0
            ? 'تمت المشاركة مع $successful من أصل ${results.length}، وفشل $failed'
            : 'تعذّر إرسال $itemLabel إلى $failed';

    final details = failureCounts.entries.toList();
    final reasonText = details.isEmpty
        ? ''
        : details.length == 1
            ? details.first.key.userMessage
            : [
                ...details.take(2).map((entry) =>
                    '${entry.value}: ${entry.key.userMessage}'),
                if (details.length > 2)
                  'وأسباب أخرى لدى ${details.skip(2).fold<int>(0, (sum, entry) => sum + entry.value)} حسابات.',
              ].join('\n');
    final hasTechnicalError = failureCounts.keys.any(_isTechnicalFailure);
    final hasOtherRestriction = failureCounts.keys.any(
        (reason) => !reason.isPrivacyRestriction);
    _show(
      messenger,
      title: title,
      description: reasonText,
      duration: Duration(seconds: failed == 0 ? 3 : 5),
      kind: failed == 0
          ? _TiniMessageNoticeKind.success
          : hasTechnicalError
              ? _TiniMessageNoticeKind.error
              : hasOtherRestriction
                  ? _TiniMessageNoticeKind.info
                  : _TiniMessageNoticeKind.privacy,
    );
  }
}
