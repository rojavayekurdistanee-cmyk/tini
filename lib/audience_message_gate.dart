import 'package:flutter/widgets.dart';
import 'audience_access.dart';
import 'r2_service.dart';

/// Retains the source of shared account media without restricting independent
/// private chat uploads. Historical copies without a source cannot be inferred
/// from a sender id: the sender may be forwarding somebody else's content.
class AudienceMessagePolicy {
  static Map<String, dynamic> sourceFields(Map<String, dynamic> message) {
    final source = <String, dynamic>{};
    for (final key in [
      'sourceType',
      'sourceOwnerUid',
      'sourceStoryId',
      'sourcePostId',
    ]) {
      if (message[key] != null) source[key] = message[key];
    }
    if (source.isNotEmpty) return source;
    final url = (message['mediaUrl'] ?? message['url'] ?? '').toString();
    final uri = Uri.tryParse(url);
    final origin = Uri.parse(R2Service.publicUrl);
    if (uri == null || uri.scheme != origin.scheme || uri.host != origin.host) {
      return source;
    }
    final segments = uri.pathSegments;
    if (segments.length >= 4 &&
        segments[0] == 'stories' &&
        segments[1].isNotEmpty) {
      source['sourceType'] = 'story';
      source['sourceOwnerUid'] = segments[1];
      source['sourceStoryId'] = segments.last.split('.').first;
    } else if (segments.isNotEmpty &&
        (segments[0] == 'videos' || segments[0] == 'thumbnails')) {
      // A recognizable post URL still needs its canonical post before display.
      source['sourceType'] = 'post_url';
      if (segments.length > 1) source['sourceOwnerUid'] = segments[1];
    }
    return source;
  }

  static bool canView(
    Map<String, dynamic> message, {
    AudienceAccess? audience,
  }) {
    if (message['type'] == 'profile_share') {
      return (audience ?? AudienceAccess.instance).canViewProfile(
        (message['profileUid'] ?? '').toString(),
      );
    }
    final source = sourceFields(message);
    if (source.isEmpty) return true;
    final access = audience ?? AudienceAccess.instance;
    final postId = (source['sourcePostId'] ?? '').toString();
    if (postId.isNotEmpty) {
      return access.canViewPost({
        'uid': source['sourceOwnerUid'],
        'videoUrl': message['mediaUrl'] ?? message['url'],
      }, postId: postId);
    }
    if (source['sourceType'] == 'story') {
      return access.canViewProfile((source['sourceOwnerUid'] ?? '').toString());
    }
    if (source['sourceType'] == 'post_url') {
      return access.isViewerAdult ||
          (access.viewerUid != null &&
              access.viewerUid == source['sourceOwnerUid']) ||
          access.canPlayUrl(
            (message['mediaUrl'] ?? message['url'] ?? '').toString(),
          );
    }
    // Explicit provenance with missing identifiers is unknown, not adult.
    return false;
  }
}

class AudienceMessageGate extends StatelessWidget {
  final Map<String, dynamic> message;
  final Widget child;
  const AudienceMessageGate({
    super.key,
    required this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AudienceAccess.instance,
    builder: (context, _) => AudienceMessagePolicy.canView(message)
        ? child
        : const SizedBox.shrink(),
  );
}