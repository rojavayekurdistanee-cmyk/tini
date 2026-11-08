import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_provider.dart';
import 'auth_provider.dart' as custom;
import 'chat_screen.dart';
import 'story_ring.dart'; // [Tini]: جديد عشان دائرة الستوري

class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedRoomIds = {};

  // [Tini]: ألوان تطبيقك المعتمدة
  static const Color bgDark = Color(0xFF0F1720);
  static const Color surfaceCard = Color(0xFF1A222C);
  static const Color fieldFill = Color(0xFF1C1C1E);
  static const Color titiTeal = Colors.teal;
  static const Color titiRed = Color(0xFFE53935);
  static const Color highlightRed = Color(0xFFFF3B30);
  static const Color textSecondary = Colors.white70;
  static const Color iconSecondary = Colors.white54;

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('hh:mm a').format(dt);
    }
    return DateFormat('dd/MM').format(dt);
  }

  void _toggleSelectRoom(String roomId) {
    setState(() {
      if (_selectedRoomIds.contains(roomId)) {
        _selectedRoomIds.remove(roomId);
        if (_selectedRoomIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedRoomIds.add(roomId);
      }
    });
  }

  void _startSelectionMode(String roomId) {
    setState(() {
      _isSelectionMode = true;
      _selectedRoomIds.add(roomId);
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedRoomIds.clear();
    });
  }

  void _markAllAsRead() {
    _cancelSelection();
  }

  Future<void> _showOptionsMenu() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.checklist_rounded, color: Colors.white),
                title: const Text('حدد الدردشات', style: TextStyle(color: Colors.white, fontSize: 16)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _isSelectionMode = true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined, color: Colors.white),
                title: const Text('الإعدادات', style: TextStyle(color: Colors.white, fontSize: 16)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchiveSettingsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline_rounded, color: Colors.white),
                title: const Text('كيف يتم الأمر', style: TextStyle(color: Colors.white, fontSize: 16)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showHowItWorks();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHowItWorks() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.archive_outlined, color: titiTeal, size: 48),
              const SizedBox(height: 16),
              const Text('كيف يتم الأمر', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              const Text(
                'ستبقى الدردشات المؤرشفة في الأرشيف حتى عندما تتلقى رسالة جديدة. إدارة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.touch_app_outlined, size: 24, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'اضغط باستمرار على الدردشات لأرشفتها أو إلغاء أرشفتها.',
                      style: TextStyle(fontSize: 15, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.visibility_outlined, size: 24, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'سيظهر أرشيفك في صندوق الوارد بمجرد أرشفة الدردشة.',
                      style: TextStyle(fontSize: 15, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Future<void> _unarchiveSelected() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    for (final roomId in _selectedRoomIds) {
      await chatProvider.archiveChat(roomId, false);
    }
    _cancelSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء أرشفة الدردشات'), backgroundColor: titiTeal),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceCard,
        title: const Text('حذف الدردشات؟', style: TextStyle(color: Colors.white)),
        content: const Text('لا يمكن التراجع عن هذا الإجراء.', style: TextStyle(color: textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء', style: TextStyle(color: iconSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: titiRed))),
        ],
      ),
    );

    if (confirm == true) {
      await chatProvider.hideChatRooms(_selectedRoomIds.toList());
      _cancelSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الدردشات'), backgroundColor: titiTeal),
        );
      }
    }
  }

  // [Tini]: ويدجت الأفاتار الجديد - صورة أو حرف + دائرة ستوري
  Widget _buildAvatarWithStory({
    required String uid,
    required String name,
    required String profileImg,
    required String currentUid,
    double size = 52,
  }) {
    final String initial = name.isNotEmpty? name.trim()[0].toUpperCase() : '?';
    final bool hasImage = profileImg.isNotEmpty && profileImg.startsWith('http');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
       .collection('stories')
       .doc(uid)
       .collection('items')
       .where('expiresAt', isGreaterThan: Timestamp.now())
       .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs?? [];
        final hasStories = docs.isNotEmpty;
        final hasUnviewed = docs.any((d) {
          final viewedBy = List<String>.from(d['viewedBy']?? []);
          return!viewedBy.contains(currentUid);
        });

        if (hasStories) {
          if (hasImage) {
            // عنده صورة + عنده ستوري
            return StoryRing(
              imageUrl: profileImg,
              size: size,
              hasStories: true,
              hasUnviewed: hasUnviewed,
              heroTag: 'archived-tab-$uid',
            );
          } else {
            // أول حرف + دائرة ستوري
            return Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasUnviewed
                 ? const SweepGradient(
                        colors: [
                          Color(0xFF00E5FF),
                          Color(0xFF00BFFF),
                          Color(0xFF1E90FF),
                          Color(0xFF00E5FF),
                        ],
                        stops: [0.0, 0.33, 0.66, 1.0],
                      )
                    : null,
                border: hasUnviewed? null : Border.all(color: Colors.grey.shade700, width: 2.5),
              ),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0F1720),
                ),
                child: CircleAvatar(
                  radius: (size - 18) / 2,
                  backgroundColor: const Color(0xFF1A222C),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.35,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }
        } else {
          // ما عنده ستوري
          return Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0F1720),
            ),
            child: CircleAvatar(
              radius: (size - 18) / 2,
              backgroundColor: const Color(0xFF1A222C),
              backgroundImage: hasImage? CachedNetworkImageProvider(profileImg) : null,
              child:!hasImage
               ? Text(
                      initial,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.35,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
    final String? currentUid = authProvider.uid;

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        leading: _isSelectionMode
        ? TextButton(
                onPressed: _cancelSelection,
                child: const Text('إلغاء', style: TextStyle(color: Colors.white, fontSize: 16)),
              )
            : IconButton(
                icon: const Icon(Icons.more_horiz, color: Colors.white),
                onPressed: _showOptionsMenu,
              ),
        title: Text(
          _isSelectionMode? 'حدد الدردشات' : 'الأرشيف',
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
      body: currentUid == null
      ? const Center(child: Text("يرجى تسجيل الدخول", style: TextStyle(color: Colors.white)))
          : StreamBuilder<QuerySnapshot>(
              stream: Provider.of<ChatProvider>(context).getArchivedConversations(currentUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: titiTeal));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("لا توجد دردشات مؤرشفة", style: TextStyle(color: textSecondary)));
                }

                final chats = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final doc = chats[index];
                    final chatData = doc.data() as Map<String, dynamic>;
                    final participants = List<String>.from(chatData['participants']?? []);
                    final otherUid = participants.firstWhere((id) => id!= currentUid, orElse: () => '');
                    final participantsInfo = Map<String, dynamic>.from(chatData['participantsInfo']?? {});
                    final otherInfo = Map<String, dynamic>.from(participantsInfo[otherUid]?? {});
                    final name = otherInfo['name']?? 'مستخدم';
                    final profileImg = otherInfo['profileImg']?? '';
                    final lastMessageTime = chatData['lastMessageTime'] as Timestamp?;
                    final isSelected = _selectedRoomIds.contains(doc.id);

                    return Container(
                      color: isSelected? titiTeal.withValues(alpha:0.15) : Colors.transparent,
                      child: ListTile(
                        onLongPress: () => _startSelectionMode(doc.id),
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleSelectRoom(doc.id);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  viewedUid: otherUid,
                                  displayFullName: name,
                                  displayProfileImg: profileImg,
                                  isFriend: otherInfo['isFriend']?? false,
                                ),
                              ),
                            );
                          }
                        },
                        leading: _isSelectionMode
                        ? Icon(
                                isSelected? Icons.check_circle : Icons.radio_button_unchecked,
                                color: isSelected? titiTeal : iconSecondary,
                              )
                            : _buildAvatarWithStory(
                                uid: otherUid,
                                name: name,
                                profileImg: profileImg,
                                currentUid: currentUid,
                              ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                        subtitle: Text(
                          _formatTime(lastMessageTime),
                          maxLines: 1,
                          style: const TextStyle(color: textSecondary, fontSize: 13)
                        ),
                        trailing: const Icon(Icons.camera_alt_outlined, color: iconSecondary),
                      ),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: _isSelectionMode
      ? Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF2C3440))),
                color: surfaceCard,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton(
                      onPressed: _markAllAsRead,
                      child: const Text('قراءة الكل', style: TextStyle(color: Colors.white, fontSize: 15))
                    ),
                    TextButton(
                      onPressed: _selectedRoomIds.isEmpty? null : _unarchiveSelected,
                      child: Text('إلغاء الأرشفة', style: TextStyle(color: _selectedRoomIds.isEmpty? iconSecondary : Colors.white, fontSize: 15))
                    ),
                    TextButton(
                      onPressed: _selectedRoomIds.isEmpty? null : _deleteSelected,
                      child: Text('حذف', style: TextStyle(color: _selectedRoomIds.isEmpty? iconSecondary : titiRed, fontSize: 15))
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class ArchiveSettingsScreen extends StatefulWidget {
  const ArchiveSettingsScreen({super.key});

  @override
  State<ArchiveSettingsScreen> createState() => _ArchiveSettingsScreenState();
}

class _ArchiveSettingsScreenState extends State<ArchiveSettingsScreen> {
  bool pinOnTop = false;
  bool keepArchived = true;
  bool autoArchive = false;
  bool _isLoading = true;

  static const Color bgDark = Color(0xFF0F1720);
  static const Color surfaceCard = Color(0xFF1A222C);
  static const Color titiTeal = Colors.teal;
  static const Color textSecondary = Colors.white70;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
    _currentUid = authProvider.uid;
    if (_currentUid == null) {
      setState(() => _isLoading = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    pinOnTop = prefs.getBool('archive_pin_on_top')?? false;

    final doc = await _firestore.collection('users').doc(_currentUid).get();
    final data = doc.data();
    if (data!= null && data['archiveSettings']!= null) {
      final settings = Map<String, dynamic>.from(data['archiveSettings']);
      keepArchived = settings['keepArchived']?? true;
      autoArchive = settings['autoArchive']?? false;
    }

    setState(() => _isLoading = false);
  }

  Future<void> _savePinOnTop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('archive_pin_on_top', value);
    setState(() => pinOnTop = value);
  }

  Future<void> _saveFirestoreSettings() async {
    if (_currentUid == null) return;
    await _firestore.collection('users').doc(_currentUid).set({
      'archiveSettings': {
        'keepArchived': keepArchived,
        'autoArchive': autoArchive,
      }
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgDark,
        body: const Center(child: CircularProgressIndicator(color: titiTeal)),
      );
    }

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('الإعدادات', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTile(
            'التثبيت في الأعلى',
            pinOnTop,
            _savePinOnTop,
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: surfaceCard, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('الاحتفاظ بأرشفة الدردشات', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
                  subtitle: const Text('ستبقى الدردشات مؤرشفة حتى عندما تتلقى رسالة جديدة.', style: TextStyle(fontSize: 13, color: textSecondary)),
                  value: keepArchived,
                  onChanged: (val) {
                    setState(() => keepArchived = val);
                    _saveFirestoreSettings();
                  },
                  activeColor: titiTeal,
                  inactiveThumbColor: Colors.white54,
                  inactiveTrackColor: Colors.white24,
                ),
                const Divider(height: 1, color: Color(0xFF2C3440)),
                SwitchListTile(
                  title: const Text('أرشفة تلقائية للدردشات غير النشطة', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
                  subtitle: const Text('ستتم أرشفة الدردشات التي لا تحتوي على رسائل جديدة خلال 30 يوماً ماضياً تلقائياً.', style: TextStyle(fontSize: 13, color: textSecondary)),
                  value: autoArchive,
                  onChanged: (val) {
                    setState(() => autoArchive = val);
                    _saveFirestoreSettings();
                  },
                  activeColor: titiTeal,
                  inactiveThumbColor: Colors.white54,
                  inactiveTrackColor: Colors.white24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(String title, bool value, Function(bool) onChanged) {
    return Container(
      decoration: BoxDecoration(color: surfaceCard, borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
        value: value,
        onChanged: onChanged,
        activeColor: titiTeal,
        inactiveThumbColor: Colors.white54,
        inactiveTrackColor: Colors.white24,
      ),
    );
  }
}