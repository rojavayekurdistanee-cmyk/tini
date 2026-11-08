import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'activity_status_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});
  @override
  State<NotificationsSettingsPage> createState() => _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color fieldColor = const Color(0xFF1C1C1E);
  final Color titiTeal = Colors.teal;

  Map<String, bool> interactions = {
    "likes": true, "saves": true, "comments": true, "new_followers": true,
    "profile_visits": false, "reposts": true,
  };
  Map<String, bool> messages = {
    "private": true, "preview": true, "activity_status": true,
  };
  Map<String, bool> postSuggestions = {"following": true, "custom": true};
  Map<String, bool> forYou = {"people_you_may_know": true,};
  Map<String, bool> other = {"people_you_may_know_2": true,};

  @override
  void initState() {
    super.initState();
    _loadActivityStatus();
    _loadAll();
  }

  DocumentReference<Map<String, dynamic>> _prefsDoc(String uid) {
    return FirebaseFirestore.instance.doc('users/$uid/notificationSettings/preferences');
  }

    Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    // قيم افتراضية من المحلي (ببلاش)
    bool likesVal = prefs.getBool('interactions_likes') ?? true;
    bool savesVal = prefs.getBool('interactions_saves') ?? true;
    bool commentsVal = prefs.getBool('interactions_comments') ?? true;
    bool newFollowersVal = prefs.getBool('interactions_new_followers') ?? true;
    bool repostsVal = prefs.getBool('interactions_reposts') ?? true;
    bool followingVal = prefs.getBool('post_following') ?? true;
    bool customVal = prefs.getBool('post_custom') ?? true;
    bool pymkVal = prefs.getBool('people_you_may_know') ?? true;
    bool pymk2Val = prefs.getBool('people_you_may_know_2') ?? true;
    bool privateVal = prefs.getBool('messages_private') ?? true;
    bool previewVal = prefs.getBool('messages_preview') ?? true;

    if (uid != null) {
      try {
        final newDoc = await _prefsDoc(uid).get(); // قراءة وحدة بس بدال 7
        if (newDoc.exists) {
          final d = newDoc.data()!;
          if (d['likes'] is bool) likesVal = d['likes'];
          if (d['saves'] is bool) savesVal = d['saves'];
          if (d['comments'] is bool) commentsVal = d['comments'];
          if (d['new_followers'] is bool) newFollowersVal = d['new_followers'];
          if (d['reposts'] is bool) repostsVal = d['reposts'];
          if (d['following'] is bool) followingVal = d['following'];
          if (d['custom'] is bool) customVal = d['custom'];
          if (d['people_you_may_know'] is bool) pymkVal = d['people_you_may_know'];
          if (d['people_you_may_know_2'] is bool) pymk2Val = d['people_you_may_know_2'];
          if (d['private'] is bool) privateVal = d['private'];
          if (d['preview'] is bool) previewVal = d['preview'];
        } else {
          // للمرة الاولى بس اذا المستخدم قديم
          final oldDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final old = oldDoc.data()?['notificationSettings'];
          if (old != null) {
            if (old['likes'] is bool) likesVal = old['likes'];
            if (old['saves'] is bool) savesVal = old['saves'];
            if (old['comments'] is bool) commentsVal = old['comments'];
            if (old['new_followers'] is bool) newFollowersVal = old['new_followers'];
            if (old['reposts'] is bool) repostsVal = old['reposts'];
            if (old['following'] is bool) followingVal = old['following'];
            if (old['custom'] is bool) customVal = old['custom'];
            if (old['people_you_may_know'] is bool) pymkVal = old['people_you_may_know'];
            if (old['people_you_may_know_2'] is bool) pymk2Val = old['people_you_may_know_2'];
            if (old['private'] is bool) privateVal = old['private'];
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      interactions["likes"] = likesVal;
      interactions["saves"] = savesVal;
      interactions["comments"] = commentsVal;
      interactions["new_followers"] = newFollowersVal;
      interactions["reposts"] = repostsVal;
      postSuggestions["following"] = followingVal;
      postSuggestions["custom"] = customVal;
      forYou["people_you_may_know"] = pymkVal;
      other["people_you_may_know_2"] = pymk2Val;
      messages["private"] = privateVal;
      messages["preview"] = previewVal;
    });
  }





  Future<void> _saveFollowing(bool v) async {
    setState(() => postSuggestions["following"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('post_following', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'following': v}, SetOptions(merge: true));
  }



  Future<void> _saveCustom(bool v) async {
    setState(() => postSuggestions["custom"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('post_custom', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'custom': v}, SetOptions(merge: true));
  }



  Future<void> _savePYMK(bool v) async {
    setState(() => forYou["people_you_may_know"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('people_you_may_know', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'people_you_may_know': v}, SetOptions(merge: true));
  }



  Future<void> _savePYMK2(bool v) async {
    setState(() => other["people_you_may_know_2"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('people_you_may_know_2', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'people_you_may_know_2': v}, SetOptions(merge: true));
  }

    Future<void> _saveLikes(bool v) async {
    setState(() => interactions["likes"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interactions_likes', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'likes': v}, SetOptions(merge: true));
  }

    Future<void> _saveSaves(bool v) async {
    setState(() => interactions["saves"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interactions_saves', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'saves': v}, SetOptions(merge: true));
  }

    Future<void> _saveComments(bool v) async {
    setState(() => interactions["comments"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interactions_comments', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'comments': v}, SetOptions(merge: true));
  }

    Future<void> _saveNewFollowers(bool v) async {
    setState(() => interactions["new_followers"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interactions_new_followers', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'new_followers': v}, SetOptions(merge: true));
  }

    Future<void> _saveReposts(bool v) async {
    setState(() => interactions["reposts"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interactions_reposts', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'reposts': v}, SetOptions(merge: true));
  }



    Future<void> _savePrivate(bool v) async {
    setState(() => messages["private"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('messages_private', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'private': v}, SetOptions(merge: true));
  }



  Future<void> _savePreview(bool v) async {
    setState(() => messages["preview"] = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('messages_preview', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'preview': v}, SetOptions(merge: true));
  }

  Future<void> _clearForYouInterests() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('hashtagInterests')
          .get();
      for (var doc in snap.docs) {
        await doc.reference.delete();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم مسح اهتمامات For You وسيتم التعلم من جديد"),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("خطأ: $e")),
      );
    }
  }

  Future<void> _loadActivityStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get(const GetOptions(source: Source.server));
      if (doc.exists && mounted) {
        final val = doc.data()?['showActivityStatus'];
        setState(() { messages["activity_status"] = (val is bool) ? val : true; });
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("الإشعارات", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _buildSectionHeader("الإعدادات العامة"),
          _buildSettingsGroup([
            _buildNavigationTile(Iconsax.notification_bing, "إشعارات داخل التطبيق", "كل الإشعارات وأنت فاتح التطبيق", onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => _InAppNotificationsPage(bgColor: bgColor, surfaceColor: surfaceColor)));
            }),
            _buildNavigationTile(Iconsax.moon, "جدول الإشعارات اللحظية", "إيقاف الإشعارات وقت النوم 12ص - 8ص", onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => _DoNotDisturbPage(bgColor: bgColor, surfaceColor: surfaceColor, fieldColor: fieldColor)));
            }),
          ]),
          _buildSectionHeader("التفاعلات"),
          _buildSettingsGroup([
            _buildSwitchTile(Iconsax.heart, "تسجيلات الإعجاب", interactions["likes"]!, (v) => _saveLikes(v)),
            _buildSwitchTile(Iconsax.save_2, "مرات الإضافة إلى المحفوظات", interactions["saves"]!, (v) => _saveSaves(v)),
            _buildSwitchTile(Iconsax.message, "التعليقات", interactions["comments"]!, (v) => _saveComments(v)),
            _buildSwitchTile(Iconsax.user_add, "متابعون جدد", interactions["new_followers"]!, (v) => _saveNewFollowers(v)),
            _buildSwitchTile(Iconsax.eye, "زيارات الملف الشخصي", interactions["profile_visits"]!, (v) => setState(() => interactions["profile_visits"] = v)),
            _buildSwitchTile(Iconsax.repeat, "منشورات معاد نشرها", interactions["reposts"]!, (v) => _saveReposts(v)),
          ]),
          _buildSectionHeader("الرسائل"),
          _buildSettingsGroup([
            _buildSwitchTile(Iconsax.direct, "رسائل خاصة", messages["private"]!, (v) => _savePrivate(v)),
            _buildSwitchTile(Iconsax.eye, "معاينة الرسائل الخاصة", messages["preview"]!, (v) => _savePreview(v)),
            _buildActivityTile(),
          ]),
          _buildSectionHeader("اقتراحات للمنشورات"),
          _buildSettingsGroup([
          _buildSwitchTile(Iconsax.people, "منشورات من الحسابات التي تتابعها", postSuggestions["following"]!, (v) => _saveFollowing(v)),
          _buildSwitchTile(Iconsax.lamp, "اقتراحات منشورات مخصصة", postSuggestions["custom"]!, (v) => _saveCustom(v)),
          ]),
          _buildSectionHeader("منشورات قد تعجبك"),
          _buildSettingsGroup([
            _buildSwitchTile(Iconsax.user_search, "منشورات من أشخاص قد تعرفهم", forYou["people_you_may_know"]!, (v) => _savePYMK(v)),
            _buildNavigationTile(Iconsax.refresh, "مسح اهتمامات For You", "إعادة ضبط الخوارزمية وبدء التعلم من جديد", onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  backgroundColor: surfaceColor,
                  title: const Text("إعادة تعيين؟", style: TextStyle(color: Colors.white)),
                  content: const Text("هل أنت متأكد؟ سيتم مسح كل اهتماماتك وسيبدأ For You بالتعلم من جديد.", style: TextStyle(color: Colors.white70, fontSize: 13)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("إلغاء", style: TextStyle(color: Colors.white54))),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("مسح", style: TextStyle(color: Colors.teal))),
                  ],
                ),
              );
              if (confirm == true) {
                await _clearForYouInterests();
              }
            }),
          ]),
          _buildSectionHeader("آخر"),
          _buildSettingsGroup([
            _buildSwitchTile(Iconsax.people, "أشخاص قد تعرفهم", other["people_you_may_know_2"]!, (v) => _savePYMK2(v)),
          ]),
        ],
      ),
    );
  }

  Widget _buildActivityTile() { return InkWell(onTap: () async { final v = !messages["activity_status"]!; final uid = FirebaseAuth.instance.currentUser!.uid; setState(() { messages["activity_status"] = v; }); try { await ActivityStatusService().setShowActivityStatus(v, uid); } catch (e) { if(mounted) setState(() => messages["activity_status"] = !v); } }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Row(children: [const Icon(Iconsax.activity, color: Colors.white54, size: 22), const SizedBox(width: 16), const Expanded(child: Text("حالة النشاط", style: TextStyle(color: Colors.white, fontSize: 14.5))), Switch(value: messages["activity_status"]!, onChanged: (v) async { final uid = FirebaseAuth.instance.currentUser!.uid; setState(() { messages["activity_status"] = v; }); try { await ActivityStatusService().setShowActivityStatus(v, uid); } catch(e){ if(mounted) setState(() => messages["activity_status"] = !v); } }, activeThumbColor: Colors.white, activeTrackColor: Colors.teal, inactiveThumbColor: Colors.white54, inactiveTrackColor: const Color(0xFF2A3542))]))); }
  Widget _buildSectionHeader(String title) { return Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 25, bottom: 10), child: Text(title, style: TextStyle(color: Colors.teal.shade300, fontSize: 13, fontWeight: FontWeight.bold))); }
  Widget _buildSettingsGroup(List<Widget> tiles) { return Container(margin: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(18)), child: Column(children: tiles)); }
  Widget _buildNavigationTile(IconData icon, String title, String subtitle, {required VoidCallback onTap}) { return Material(color: Colors.transparent, child: ListTile(onTap: onTap, leading: Icon(icon, color: Colors.white70, size: 22), title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)), subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)), trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 14), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4))); }
  Widget _buildSwitchTile(IconData icon, String title, bool value, Function(bool) onChanged, {bool isLoading = false}) { return Material(color: Colors.transparent, child: ListTile(leading: Icon(icon, color: Colors.white54, size: 22), title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5)), trailing: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)) : Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.white, activeTrackColor: Colors.teal, inactiveThumbColor: Colors.white54, inactiveTrackColor: const Color(0xFF2A3542)), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2))); }
}

class _InAppNotificationsPage extends StatefulWidget {
  final Color bgColor;
  final Color surfaceColor;

  const _InAppNotificationsPage({
    required this.bgColor,
    required this.surfaceColor,
  });

  @override
  State<_InAppNotificationsPage> createState() => 
      _InAppNotificationsPageState();
}

class _InAppNotificationsPageState extends State<_InAppNotificationsPage> {
  Map<String, bool> inApp = {
    "likes": true,
    "comments": true,
    "new_followers": true,
    "mentions": true,
    "activity": true,
    "profile_visits": true,
  };

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      inApp["activity"] = prefs.getBool('notify_activity_banner') ?? true;
      inApp["likes"] = prefs.getBool('notify_like_banner') ?? true;
      inApp["comments"] = prefs.getBool('notify_comment_banner') ?? true;
      inApp["new_followers"] = prefs.getBool('notify_new_followers_banner') ?? true;
      inApp["mentions"] = prefs.getBool('notify_mentions_banner') ?? true;
      inApp["profile_visits"] = prefs.getBool('notify_profile_visits_banner') ?? true;
    });
  }

  Future<void> _saveActivity(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_activity_banner', v);
    setState(() => inApp["activity"] = v);
  }

  Future<void> _saveLikeBanner(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_like_banner', v);
    setState(() => inApp["likes"] = v);
  }

  Future<void> _saveCommentBanner(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_comment_banner', v);
    setState(() => inApp["comments"] = v);
  }

    Future<void> _saveFollowBanner(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_new_followers_banner', v);
    setState(() => inApp["new_followers"] = v);
  }

  Future<void> _saveMentionBanner(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_mentions_banner', v);
    setState(() => inApp["mentions"] = v);
  }

  Future<void> _saveVisitBanner(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_profile_visits_banner', v);
    setState(() => inApp["profile_visits"] = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.bgColor,
      appBar: AppBar(
        backgroundColor: widget.bgColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "إشعارات داخل التطبيق",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 20, bottom: 40),
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: widget.surfaceColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _switchTile(Iconsax.heart, "إعجابات", inApp["likes"]!, (v) => _saveLikeBanner(v)),
                _switchTile(Iconsax.message, "تعليقات", inApp["comments"]!, (v) => _saveCommentBanner(v)),
                _switchTile(Iconsax.user_add, "متابعون جدد", inApp["new_followers"]!, (v) => _saveFollowBanner(v)),
                _switchTile(Iconsax.tag, "الذِكر والإشارات", inApp["mentions"]!, (v) => _saveMentionBanner(v)),
                _switchTile(Iconsax.activity, "حالة النشاط", inApp["activity"]!, (v) => _saveActivity(v)),
                _switchTile(Iconsax.eye, "زيارات الملف الشخصي", inApp["profile_visits"]!, (v) => _saveVisitBanner(v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(
    IconData icon,
    String title,
    bool value,
    Function(bool) onChanged,
  ) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: Colors.white54, size: 22),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 14.5),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: Colors.teal,
          inactiveThumbColor: Colors.white54,
          inactiveTrackColor: const Color(0xFF2A3542),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 2,
        ),
      ),
    );
  }
}

class _DoNotDisturbPage extends StatefulWidget {
  final Color bgColor; final Color surfaceColor; final Color fieldColor;
  const _DoNotDisturbPage({required this.bgColor, required this.surfaceColor, required this.fieldColor});
  @override State<_DoNotDisturbPage> createState() => _DoNotDisturbPageState();
}
class _DoNotDisturbPageState extends State<_DoNotDisturbPage> {
  bool isEnabled = true;
  TimeOfDay startTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 8, minute: 0);

  DocumentReference<Map<String, dynamic>> _prefsDoc(String uid) {
    return FirebaseFirestore.instance.doc('users/$uid/notificationSettings/preferences');
  }

  

  @override
  void initState() {
    super.initState();
    _loadDnd();
  }

  Future<void> _loadDnd() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _prefsDoc(uid).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        setState(() {
          if (data?['dnd_enabled'] is bool) isEnabled = data!['dnd_enabled'];
          if (data?['dnd_start_hour'] is int) {
            startTime = TimeOfDay(hour: data!['dnd_start_hour'], minute: data['dnd_start_min'] ?? 0);
          }
          if (data?['dnd_end_hour'] is int) {
            endTime = TimeOfDay(hour: data!['dnd_end_hour'], minute: data['dnd_end_min'] ?? 0);
          }
        });
      }
    } catch(e){}
  }

  Future<void> _saveEnabled(bool v) async {
    setState(() => isEnabled = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dnd_enabled', v);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'dnd_enabled': v}, SetOptions(merge: true));
  }

  Future<void> _saveStart(TimeOfDay t) async {
    setState(() => startTime = t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dnd_start_hour', t.hour);
    await prefs.setInt('dnd_start_min', t.minute);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'dnd_start_hour': t.hour, 'dnd_start_min': t.minute}, SetOptions(merge: true));
  }

  Future<void> _saveEnd(TimeOfDay t) async {
    setState(() => endTime = t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dnd_end_hour', t.hour);
    await prefs.setInt('dnd_end_min', t.minute);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _prefsDoc(uid).set({'dnd_end_hour': t.hour, 'dnd_end_min': t.minute}, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.bgColor,
      appBar: AppBar(backgroundColor: widget.bgColor, elevation: 0, title: const Text("جدول الإشعارات اللحظية", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          decoration: BoxDecoration(color: widget.surfaceColor, borderRadius: BorderRadius.circular(18)),
          child: Material(
            color: Colors.transparent,
            child: SwitchListTile(
              title: const Text("تعيين جدول", style: TextStyle(color: Colors.white)),
              subtitle: const Text("إيقاف كل الإشعارات اللحظية بهالفترة", style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: isEnabled, onChanged: (v) => _saveEnabled(v),
              activeThumbColor: Colors.white, activeTrackColor: Colors.teal,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(color: widget.surfaceColor, borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Iconsax.clock, color: Colors.white54),
                title: const Text("البدء", style: TextStyle(color: Colors.white)),
                trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: widget.fieldColor, borderRadius: BorderRadius.circular(8)), child: Text(startTime.format(context), style: const TextStyle(color: Colors.white))),
                onTap: () async { final picked = await showTimePicker(context: context, initialTime: startTime); if(picked != null) _saveStart(picked); },
              ),
            ),
            const Divider(color: Colors.white10, height: 1, indent: 20, endIndent: 20),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Iconsax.clock, color: Colors.white54),
                title: const Text("إنهاء", style: TextStyle(color: Colors.white)),
                trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: widget.fieldColor, borderRadius: BorderRadius.circular(8)), child: Text(endTime.format(context), style: const TextStyle(color: Colors.white))),
                onTap: () async { final picked = await showTimePicker(context: context, initialTime: endTime); if(picked != null) _saveEnd(picked); },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}