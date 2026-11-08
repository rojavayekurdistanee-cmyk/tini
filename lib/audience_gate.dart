import 'package:flutter/widgets.dart';
import 'audience_access.dart';

class AudiencePostGate extends StatelessWidget {
  final Map<String, dynamic> post;
  final String? postId;
  final Widget child;
  final Widget? placeholder;
  final AudienceAccess? access;
  const AudiencePostGate({
    super.key,
    required this.post,
    this.postId,
    required this.child,
    this.placeholder,
    this.access,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: access ?? AudienceAccess.instance,
    builder: (context, _) =>
        (access ?? AudienceAccess.instance).canViewPost(post, postId: postId)
        ? child
        : placeholder ?? const SizedBox.shrink(),
  );
}

class AudienceProfileGate extends StatelessWidget {
  final String uid;
  final Widget child;
  final Widget? placeholder;
  final AudienceAccess? access;
  const AudienceProfileGate({
    super.key,
    required this.uid,
    required this.child,
    this.placeholder,
    this.access,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: access ?? AudienceAccess.instance,
    builder: (context, _) =>
        (access ?? AudienceAccess.instance).canViewProfile(uid)
        ? child
        : placeholder ?? const SizedBox.shrink(),
  );
}