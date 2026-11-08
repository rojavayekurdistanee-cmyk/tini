import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math';

// ألوانك
const kBG = Color(0xFF0F1720);
const kSurface = Color(0xFF1A222C);
const kField = Color(0xFF1C1C1E);
const kTeal = Colors.teal;
const kError = Color(0xFFE53935);
const kLink = Color(0xFFFF3B30);

class GroupInviteLinkScreen extends StatefulWidget {
  final String groupId;
  const GroupInviteLinkScreen({super.key, required this.groupId});
  @override
  State<GroupInviteLinkScreen> createState() => _GroupInviteLinkScreenState();
}

class _GroupInviteLinkScreenState extends State<GroupInviteLinkScreen> {
  bool enabled = false;
  String code = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ref = FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId);
    final doc = await ref.get();
    var currentCode = doc.data()?['inviteCode'] as String?;
    if (currentCode == null || currentCode.isEmpty) {
      currentCode = _genCode();
      await ref.update({'inviteCode': currentCode});
    }
    setState(() {
      enabled = doc.data()?['inviteEnabled'] ?? false;
      code = currentCode!;
      loading = false;
    });
  }

  String get link => 'https://tini.app/j/$code';

  String _genCode() {
    const chars = 'abcdefg1234567890';
    return String.fromCharCodes(Iterable.generate(16, (_) => chars.codeUnitAt(Random().nextInt(chars.length))));
  }

  Future<void> _toggle(bool v) async {
    if (v && code.isEmpty) code = _genCode();
    setState(() => enabled = v);
    await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
      'inviteEnabled': v,
      'inviteCode': code,
    });
  }

  Future<void> _reset() async {
    final newCode = _genCode();
    setState(() => code = newCode);
    await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({
      'inviteCode': newCode,
      'inviteEnabled': true,
    });
    if (mounted) Navigator.pop(context);
  }

  void _showResetSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: EdgeInsets.all(20),
            child: Text('في حالة إعادة تعيين الرابط، ستنتهي صلاحية الرابط الحالي وسيتم إنشاء رابط جديد. لن يتمكن أي شخص من الانضمام إلى هذه الدردشة الجماعية باستخدام الرابط الذي انتهت صلاحيته.',
              style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 14, height: 1.6), textAlign: TextAlign.center),
          ),
          Divider(color: Colors.white12),
          ListTile(
            onTap: _reset,
            title: Text('إعادة تعيين الرابط', style: TextStyle(color: kError, fontFamily: 'Tajawal', fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
          SizedBox(height: 10),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return Scaffold(backgroundColor: kBG, body: Center(child: CircularProgressIndicator(color: kTeal)));
    return Scaffold(
      backgroundColor: kBG,
      appBar: AppBar(
        backgroundColor: kBG,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_forward, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: Text('رابط الدعوة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          SizedBox(height: 10),
          // سطر السويتش والرابط - نفس الصورة 2
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Switch(
                  value: enabled,
                  onChanged: _toggle,
                  activeColor: Colors.white,
                  activeTrackColor: kTeal,
                  inactiveThumbColor: Colors.white54,
                  inactiveTrackColor: kField,
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('رابط الدعوة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text(link, style: TextStyle(color: enabled ? kLink : Colors.white38, fontFamily: 'Tajawal', fontSize: 13), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('يمكن لأي شخص الانضمام إلى دردشتك الجماعية من خلال هذا الرابط. تعرف على المزيد',
              style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 13, height: 1.5), textAlign: TextAlign.right),
          ),
          if (enabled) ...[
            SizedBox(height: 30),
            _item(icon: Icons.copy, label: 'نسخ', onTap: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: kSurface, content: Text('تم نسخ الرابط', style: TextStyle(fontFamily: 'Tajawal'))));
            }),
            _item(icon: Icons.send_outlined, label: 'إرسال في Tini', onTap: () {}),
            _item(icon: Icons.qr_code_scanner, label: 'رمز QR', trailing: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: kTeal, borderRadius: BorderRadius.circular(12)),
              child: Text('جديد', style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Tajawal')),
            ), onTap: () {}),
            _item(icon: Icons.share, label: 'مشاركة', onTap: () => Share.share(link)),
            SizedBox(height: 20),
            _item(icon: Icons.refresh, label: 'إعادة تعيين الرابط', color: kError, onTap: _showResetSheet),
          ]
        ],
      ),
    );
  }

  Widget _item({required IconData icon, required String label, Widget? trailing, Color color = Colors.white, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(children: [
          if (trailing != null) trailing,
          Spacer(),
          Text(label, style: TextStyle(color: color, fontFamily: 'Tajawal', fontSize: 16)),
          SizedBox(width: 16),
          Icon(icon, color: color, size: 26),
        ]),
      ),
    );
  }
}