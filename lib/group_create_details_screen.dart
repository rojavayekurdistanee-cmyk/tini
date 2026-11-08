import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'group_chat_provider.dart';
import 'group_chat_screen.dart';

const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kFieldFill = Color(0xFF1C1C1E);
const Color kTitiTeal = Colors.teal;

class GroupCreateDetailsScreen extends StatefulWidget {
  final String? groupId;
  const GroupCreateDetailsScreen({super.key, this.groupId});
  @override
  State<GroupCreateDetailsScreen> createState() => _GroupCreateDetailsScreenState();
}

class _GroupCreateDetailsScreenState extends State<GroupCreateDetailsScreen> {
  final TextEditingController _groupName = TextEditingController();
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _suggested = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _selectedIds = [];
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() {
      setState(() {
        if (_search.text.isEmpty) _filtered = _suggested;
        else _filtered = _suggested.where((u) => u['username'].toString().toLowerCase().contains(_search.text.toLowerCase())).toList();
      });
    });
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('following').limit(50).get();
    List<Map<String, dynamic>> temp = [];
    List<String> existingMembers = [];
    if (widget.groupId!= null) {
      final doc = await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId!).get();
      if (doc.exists) existingMembers = List<String>.from((doc.data()!['members']?? []));
    }
    for (var doc in snap.docs) {
      if (existingMembers.contains(doc.id)) continue;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(doc.id).get();
      if (!userDoc.exists) continue;
      final data = userDoc.data()!;
      data['uid'] = doc.id;
      temp.add(data);
    }
    setState(() { _suggested = temp; _filtered = temp; });
  }

  Future<void> _createGroup() async {
    if (_selectedIds.isEmpty || _isCreating) return;
    setState(() => _isCreating = true);
    try {
      if (widget.groupId!= null) {
        await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId!).update({
          'members': FieldValue.arrayUnion(_selectedIds),
        });
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }

      final prov = context.read<GroupChatProvider>();
      final currentUid = FirebaseAuth.instance.currentUser!.uid;
      final id = await prov.createGroup(
        name: _groupName.text.trim().isEmpty? 'مجموعة جديدة' : _groupName.text.trim(),
        memberIds: _selectedIds,
      );
      await FirebaseFirestore.instance.collection('group_chats').doc(id).set({
        'createdBy': currentUid,
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: id)),
        (r) => r.isFirst,
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAddMode = widget.groupId!= null;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Colors.white), onPressed: ()=> Navigator.pop(context)),
        title: Text(isAddMode? 'إضافة أعضاء' : 'دردشة جماعية جديدة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                if (!isAddMode)
                Container(
                  decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
                  child: TextField(
                    controller: _groupName,
                    style: TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(hintText: 'اسم المجموعة (اختياري)', hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Tajawal'), border: InputBorder.none, contentPadding: EdgeInsets.all(16)),
                  ),
                ),
                if (!isAddMode) SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(color: kFieldFill, borderRadius: BorderRadius.circular(30)),
                  child: TextField(
                    controller: _search,
                    style: TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(hintText: 'بحث', hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Tajawal'), prefixIcon: Icon(Icons.search, color: Colors.white54), border: InputBorder.none, contentPadding: EdgeInsets.all(12)),
                  ),
                ),
              ],
            ),
          ),
          if (!isAddMode)
          ListTile(
            onTap: () {},
            trailing: CircleAvatar(backgroundColor: kSurface, radius: 32, child: Icon(Icons.link, color: Colors.white, size: 28)),
            title: Text('إنشاء مجموعة مع رابط', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold), textAlign: TextAlign.right),
            subtitle: Text('يمكن لأي شخص لديه الرابط الانضمام إلى المجموعة.', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 12), textAlign: TextAlign.right),
          ),
          if (!isAddMode) Divider(color: Colors.white10),
          Padding(padding: EdgeInsets.all(16), child: Align(alignment: Alignment.centerRight, child: Text('الاقتراحات', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)))),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (context, i) {
                final user = _filtered[i];
                final sel = _selectedIds.contains(user['uid']);
                return ListTile(
                  onTap: () => setState(() { sel? _selectedIds.remove(user['uid']) : _selectedIds.add(user['uid']); }),
                  leading: IconButton(icon: Icon(Icons.close, color: Colors.white54, size: 20), onPressed: ()=> setState(()=> _filtered.removeAt(i))),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (sel) Icon(Icons.check_circle, color: kTitiTeal),
                    SizedBox(width: 8),
                    CircleAvatar(backgroundImage: NetworkImage(user['profileImg']?? ''), radius: 26, backgroundColor: kFieldFill),
                  ]),
                  title: Text(user['fullName']?? user['username']?? '', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal'), textAlign: TextAlign.right),
                  subtitle: Text(user['username']?? '', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 12), textAlign: TextAlign.right),
                  tileColor: sel? kSurface : kBg,
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selectedIds.isEmpty? null : Container(
        color: kBg,
        padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isCreating? null : _createGroup,
              style: ElevatedButton.styleFrom(
                backgroundColor: kTitiTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isCreating
             ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(isAddMode? 'إضافة (${_selectedIds.length})' : 'إنشاء دردشة جماعية (${_selectedIds.length})', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ),
      ),
    );
  }
}