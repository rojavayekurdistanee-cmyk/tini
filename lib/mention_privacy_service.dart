import 'user_documents.dart';
// [Tini - Mention Privacy]: فحص صلاحية الذكر باستخدام علاقات المتابعة الفعلية.
// يتم استخدام الخدمة عند اختيار الأشخاص، وكتابة @، وقبل النشر وإرسال التعليقات.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MentionNotAllowedException implements Exception {
  final String username;
  const MentionNotAllowedException(this.username);

  @override
  String toString() => 'لا يسمح لك بذكر @$username وفقاً لإعدادات الخصوصية';
}

class AmbiguousMentionException extends MentionNotAllowedException {
  final String fullName;
  const AmbiguousMentionException(this.fullName) : super(fullName);

  @override
  String toString() =>
      'يوجد أكثر من حساب باسم @$fullName. اختر الشخص من اقتراحات الذكر.';
}

class MentionPrivacyService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // دعم أسماء المستخدمين العربية والإنجليزية كما تظهر بعد @.
  static final RegExp _mentionPattern =
      RegExp(r'@([\p{L}\p{N}_.]+)', unicode: true);

  static List<String> usernamesIn(String text) {
    final precedingCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);
    return _mentionPattern
        .allMatches(text)
        .where((m) => m.start == 0 ||
            !precedingCharacter.hasMatch(text.substring(m.start - 1, m.start)))
        .map((m) => m.group(1)!.replaceAll(RegExp(r'\.+$'), '').toLowerCase())
        .where((username) => username.isNotEmpty)
        .toSet()
        .toList();
  }

  static Future<bool> canMentionUser({
    required String targetUid,
    String? senderUid,
    Map<String, dynamic>? targetData,
  }) async {
    final sender = senderUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (sender.isEmpty || targetUid.isEmpty) return false;
    if (sender == targetUid) return true;

    final Map<String, dynamic> data;
    if (targetData != null) {
      data = targetData;
    } else {
      final snap = await UserDocuments.readable(_db, targetUid).get(
        const GetOptions(source: Source.server),
      );
      if (!snap.exists) return false;
      data = snap.data() ?? {};
    }

    final privacy = data['mentionPrivacy'] ?? 'everyone';
    if (privacy == 'nobody') return false;
    if (privacy == 'everyone') return true;

    // following: الشخص المستهدف يتابع الشخص الذي يريد ذكره.
    final isFollowedByTarget = await _db
        .collection('users')
        .doc(targetUid)
        .collection('following')
        .doc(sender)
        .get(const GetOptions(source: Source.server));
    if (!isFollowedByTarget.exists) return false;
    if (privacy == 'following') return true;

    // friends: متابعة متبادلة؛ لا نكتفي بعداد المتابعين.
    if (privacy == 'friends') {
      final senderFollowsTarget = await _db
          .collection('users')
          .doc(sender)
          .collection('following')
          .doc(targetUid)
          .get(const GetOptions(source: Source.server));
      return senderFollowsTarget.exists;
    }
    return false; // قيمة غير معروفة: منع آمن، وليس سماحاً افتراضياً.
  }

  static Future<List<Map<String, dynamic>>> filterMentionableUsers(
    List<Map<String, dynamic>> users,
  ) async {
    final checks = await Future.wait(users.map((user) async {
      final uid = (user['uid'] ?? '').toString();
      try {
        return await canMentionUser(targetUid: uid, targetData: user);
      } catch (_) {
        return false; // فشل فحص الخصوصية لا يسمح بتجاوزها.
      }
    }));
    return [for (var i = 0; i < users.length; i++) if (checks[i]) users[i]];
  }

  // [Tini - Full Name Mention]: اقتراح حسابات عند كتابة @ بالاسم الظاهر أو اليوزرنيم.
  // الاختيار يعتمد على UID؛ الحسابات المانعة للذكر لا تظهر في الاقتراحات.
  static Future<List<Map<String, dynamic>>> searchMentionableUsers(
      String query, {String? senderUid}) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];
    final results = await Future.wait([
      _db.collection('public_profiles')
          .where('username_lowercase', isGreaterThanOrEqualTo: q)
          .where('username_lowercase', isLessThan: '$q\uf8ff')
          .limit(12).get(const GetOptions(source: Source.server)),
      _db.collection('public_profiles')
          .where('fullName_lowercase', isGreaterThanOrEqualTo: q)
          .where('fullName_lowercase', isLessThan: '$q\uf8ff')
          .limit(12).get(const GetOptions(source: Source.server)),
    ]);
    final users = <String, Map<String, dynamic>>{};
    for (final snap in results) {
      for (final doc in snap.docs) {
        users[doc.id] = {'uid': doc.id, ...doc.data()};
      }
    }
    final sender = senderUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (sender.isEmpty) return [];
    final permitted = await Future.wait(users.values.map((user) async {
      try {
        return await canMentionUser(
            targetUid: user['uid'].toString(),
            senderUid: sender,
            targetData: user);
      } catch (_) {
        return false;
      }
    }));
    final candidates = users.values.toList();
    return [
      for (var i = 0; i < candidates.length; i++)
        if (permitted[i]) candidates[i],
    ];
  }

  // استخراج المنشنات التي قد تحتوي على اسم ظاهر من عدة كلمات.
  // نجرّب الاسم الكامل الأطول أولاً لتفادي اعتبار @أحمد محمد ذكراً لـ @أحمد فقط.
  static final RegExp _displayNameMentionPattern = RegExp(
    r'@([\p{L}\p{N}_.\-]+(?:[ \t]+[\p{L}\p{N}_.\-]+){0,6})',
    unicode: true,
  );

  static Future<Map<String, String>> validateMentions({
    String text = '',
    List<String> selected = const [],
    String? senderUid,
    // للردود أو للاسم الذي اختاره المستخدم من الاقتراحات: الاسم الظاهر -> UID.
    Map<String, String> linkedUserIds = const {},
  }) async {
    if (text.isEmpty && selected.isEmpty) return {};
    final sender = senderUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (sender.isEmpty) throw StateError('يجب تسجيل الدخول قبل الذكر');

    final allowed = <String, String>{};
    final linked = <String, String>{
      for (final entry in linkedUserIds.entries)
        entry.key.toLowerCase().trim(): entry.value,
    };

    Future<void> allowUser(String uid, String label,
        {Map<String, dynamic>? data}) async {
      final userData = data ??
          (await UserDocuments.readable(_db, uid)
                  .get(const GetOptions(source: Source.server))).data();
      if (userData == null ||
          !await canMentionUser(
              targetUid: uid, senderUid: sender, targetData: userData)) {
        throw MentionNotAllowedException(label);
      }
      final username = (userData['username'] ?? label).toString();
      allowed[username] = uid;
    }

    // لا نغيّر عقد الإضافة السابق من شاشة نشر الفيديو: selected يظل usernames.
    for (final value in selected) {
      final username = value.replaceFirst(RegExp(r'^@'), '').toLowerCase().trim();
      if (username.isEmpty) continue;
      final snap = await _db.collection('public_profiles')
          .where('username_lowercase', isEqualTo: username)
          .limit(1).get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) throw MentionNotAllowedException(username);
      await allowUser(snap.docs.first.id, username, data: snap.docs.first.data());
    }

    final precedingCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);
    for (final match in _displayNameMentionPattern.allMatches(text)) {
      if (match.start > 0 &&
          precedingCharacter.hasMatch(text.substring(match.start - 1, match.start))) {
        continue;
      }
      final raw = match.group(1)!.replaceAll(RegExp(r'\.+$'), '').trim();
      if (raw.isEmpty) continue;
      final phrase = raw.toLowerCase();
      final afterAt = text.substring(match.start + 1).toLowerCase();

      // أولوية لحساب مختار فعلياً، حتى لو الاسم الظاهر مكرر بين عدة مستخدمين.
      String? linkedLabel;
      for (final label in linked.keys) {
        final isExactStart = afterAt.startsWith(label) &&
            (afterAt.length == label.length ||
                !RegExp(r'[\p{L}\p{N}_]', unicode: true)
                    .hasMatch(afterAt.substring(label.length, label.length + 1)));
        if (isExactStart) {
          if (linkedLabel == null || label.length > linkedLabel.length) {
            linkedLabel = label;
          }
        }
      }
      if (linkedLabel != null) {
        await allowUser(linked[linkedLabel]!, linkedLabel);
        continue;
      }

      // @الاسم الكامل المكتوب يدوياً: بحث مطابق وليس تخميناً بالاسم الأول.
      // العبارات الأطول تُفحص أولاً؛ الاسم المكرر يتطلب اختياراً من الاقتراحات.
      final words = phrase.split(RegExp(r'[ \t]+'));
      bool resolved = false;
      for (var count = words.length; count >= 1; count--) {
        final candidate = words.take(count).join(' ');
        if (count == 1) {
          // اليوزرنيم الأحادي يحتفظ بمعناه القديم للمنشن في أوصاف الفيديو.
          final byUsername = await _db.collection('public_profiles')
              .where('username_lowercase', isEqualTo: candidate)
              .limit(1).get(const GetOptions(source: Source.server));
          if (byUsername.docs.isNotEmpty) {
            final doc = byUsername.docs.first;
            await allowUser(doc.id, candidate, data: doc.data());
            resolved = true;
            break;
          }
        }
        final byFullName = await _db.collection('public_profiles')
            .where('fullName_lowercase', isEqualTo: candidate)
            .limit(2).get(const GetOptions(source: Source.server));
        if (byFullName.docs.length > 1) {
          throw AmbiguousMentionException(candidate);
        }
        if (byFullName.docs.isNotEmpty) {
          final doc = byFullName.docs.first;
          await allowUser(doc.id, candidate, data: doc.data());
          resolved = true;
          break;
        }
      }
      // @اسم_غير_موجود ليس حساباً، كما في السلوك القديم.
      if (!resolved) continue;
    }
    return allowed;
  }
}
