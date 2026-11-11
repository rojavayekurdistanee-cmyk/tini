import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'group_members_screen.dart';
import 'group_create_details_screen.dart';
import 'group_theme_sheet.dart';
import 'r2_service.dart';
import 'group_privacy_safety_screen.dart';
import 'package:video_player/video_player.dart';
import 'group_invite_link_screen.dart';

const Color kBg = Color(0xFF0F1720);
const Color kSurface = Color(0xFF1A222C);
const Color kFieldFill = Color(0xFF1C1C1E);
const Color kErrorRed = Color(0xFFE53935);



class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  const GroupInfoScreen({super.key, required this.groupId});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  bool _isUploading = false;
  final R2Service _r2Service = R2Service();

  Future<List<String>> _getMemberPhotos(List<String> memberIds) async {
    if (memberIds.isEmpty) return [];
    final ids = memberIds.length > 10? memberIds.sublist(memberIds.length - 10) : memberIds;
    final snap = await FirebaseFirestore.instance.collection('public_profiles').where(FieldPath.documentId, whereIn: ids).get();
    List<String> photos = snap.docs.map((d) {
      final data = d.data();
      return (data['profileImg']?? '') as String;
    }).where((u) => u.trim().isNotEmpty).toList();
    if (photos.length > 2) photos = photos.sublist(photos.length - 2);
    return photos;
  }

  Widget _buildAvatar(String? groupImage, List<String> memberPhotos, {required double radius}) {
    final hasGroupImage = groupImage!= null && groupImage.trim().isNotEmpty;
    if (hasGroupImage) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(groupImage), backgroundColor: kFieldFill);
    }
    if (memberPhotos.length >= 2) {
      return SizedBox(
        width: radius * 2.9,
        height: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: 0,
              child: CircleAvatar(radius: radius, backgroundImage: NetworkImage(memberPhotos[0]), backgroundColor: kFieldFill),
            ),
            Positioned(
              right: radius * 0.9,
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kBg, width: 3)),
                child: CircleAvatar(radius: radius, backgroundImage: NetworkImage(memberPhotos[1]), backgroundColor: kFieldFill),
              ),
            ),
          ],
        ),
      );
    }
    if (memberPhotos.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(memberPhotos[0]), backgroundColor: kFieldFill);
    }
    return CircleAvatar(radius: radius, backgroundColor: kFieldFill, child: Icon(Icons.group, size: radius, color: Colors.white54));
  }

  Future<void> _changeGroupName(String currentName, bool isOwner) async {
    if (!isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فقط مالك المجموعة يمكنه تغيير الاسم', style: TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('تغيير اسم المجموعة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
          decoration: InputDecoration(
            hintText: 'اسم المجموعة',
            hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Tajawal'),
            filled: true,
            fillColor: kFieldFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('إلغاء', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal'))),
          TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: Text('حفظ', style: TextStyle(color: Colors.teal, fontFamily: 'Tajawal', fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (newName!= null && newName.isNotEmpty && newName!= currentName) {
      await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({'groupName': newName});
    }
  }

  Future<void> _changeGroupImage(String? oldImageUrl, bool isOwner) async {
    if (!isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فقط مالك المجموعة يمكنه تغيير الصورة', style: TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      if (oldImageUrl!= null) {
        await NetworkImage(oldImageUrl).evict();
      }
      final file = File(picked.path);
      final uniqueName = 'group_images/${widget.groupId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newUrl = await _r2Service.uploadFile(file, uniqueName);
      await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({'groupImage': newUrl});
      if (oldImageUrl!= null && oldImageUrl.isNotEmpty) {
        await _r2Service.deleteByUrl(oldImageUrl);
      }
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل رفع الصورة: $e', style: TextStyle(fontFamily: 'Tajawal'))));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removeGroupImage(String? oldImageUrl, bool isOwner) async {
    if (!isOwner) return;
    if (oldImageUrl == null || oldImageUrl.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('حذف صورة المجموعة؟', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('إلغاء', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('حذف', style: TextStyle(color: kErrorRed, fontFamily: 'Tajawal'))),
        ],
      ),
    );
    if (confirm!= true) return;

    setState(() => _isUploading = true);
    try {
      await NetworkImage(oldImageUrl).evict();
      await _r2Service.deleteByUrl(oldImageUrl);
      await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({'groupImage': ''});
      imageCache.clear();
      imageCache.clearLiveImages();
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _buildInstaRow(String title, String? subtitle, Widget iconWidget, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 16, fontWeight: FontWeight.w500), textAlign: TextAlign.right),
                  if (subtitle!= null) const SizedBox(height: 2),
                  if (subtitle!= null) Text(subtitle, style: const TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 13), textAlign: TextAlign.right),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kSurface, title: Text('معلومات المجموعة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')), iconTheme: IconThemeData(color: Colors.white)),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).snapshots(),
        builder: (c, snap) {
          if (!snap.hasData) return Center(child: CircularProgressIndicator());
          final data = snap.data!.data() as Map<String, dynamic>;
          final members = List<String>.from(data['members']?? []);
          final createdBy = data['createdBy'] as String? ?? '';
          final isOwner = createdBy == uid;
          final groupName = data['groupName']?? '';
          final groupImage = data['groupImage'] as String?;
          return ListView(
            children: [
              SizedBox(height: 20),
              Center(
                child: FutureBuilder<List<String>>(
                  future: _getMemberPhotos(members),
                  builder: (context, photoSnap) {
                    final photos = photoSnap.data?? [];
                    return Stack(
                      children: [
                        _buildAvatar(groupImage, photos, radius: 50),
                        if (_isUploading) Positioned.fill(child: Container(decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: Center(child: CircularProgressIndicator(color: Colors.white)))),
                        if (isOwner) Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _isUploading? null : () => _changeGroupImage(groupImage, isOwner), child: Container(padding: EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.teal, shape: BoxShape.circle, border: Border.all(color: kBg, width: 2)), child: Icon(Icons.camera_alt, size: 18, color: Colors.white)))),
                        if (isOwner && groupImage!= null && groupImage.isNotEmpty)
                          Positioned(top: 0, right: 0, child: GestureDetector(onTap: _isUploading? null : () => _removeGroupImage(groupImage, isOwner), child: Container(padding: EdgeInsets.all(4), decoration: BoxDecoration(color: kErrorRed, shape: BoxShape.circle, border: Border.all(color: kBg, width: 2)), child: Icon(Icons.close, size: 14, color: Colors.white)))),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(height: 12),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(data['groupName']?? '', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold)),
                    if (isOwner) IconButton(icon: Icon(Icons.edit, size: 18, color: Colors.white54), onPressed: () => _changeGroupName(groupName, isOwner)),
                  ],
                ),
              ),
              if (isOwner) SizedBox(height: 4),
              if (isOwner) Center(child: GestureDetector(onTap: () => _changeGroupName(groupName, isOwner), child: Text('تغيير الاسم والصورة', style: TextStyle(color: Color(0xFF6B8AFF), fontFamily: 'Tajawal', fontSize: 13)))),

              SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Builder(
                      builder: (context) {
                        final admins = List<String>.from(data['admins'] ?? []);
                        final moderators = List<String>.from(data['moderators'] ?? []);
                        final bool isAdmin = admins.contains(uid);
                        final bool isModerator = moderators.contains(uid);
                        final bool canAdd = isOwner || isAdmin || isModerator;
                        // اذا بدك تمنع المشرف، خليها: final bool canAdd = isOwner || isAdmin;

                        if (!canAdd) return Expanded(child: SizedBox());

                        return Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kSurface,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: Colors.white12),
                            ),
                            icon: Icon(Icons.person_add_alt_1, size: 20, color: Colors.white),
                            label: Text('إضافة', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GroupCreateDetailsScreen(groupId: widget.groupId),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSurface,
                          foregroundColor: kErrorRed,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: kErrorRed.withOpacity(0.3)),
                        ),
                        icon: Icon(Icons.logout, size: 20, color: kErrorRed),
                        label: Text('مغادرة', style: TextStyle(color: kErrorRed, fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              backgroundColor: kSurface,
                              title: Text('مغادرة المجموعة؟', style: TextStyle(color: Colors.white, fontFamily: 'Tajawal')),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: Text('إلغاء', style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal'))),
                                TextButton(onPressed: () => Navigator.pop(c, true), child: Text('مغادرة', style: TextStyle(color: kErrorRed, fontFamily: 'Tajawal'))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId).update({'members': FieldValue.arrayRemove([uid])});
                            if (context.mounted) Navigator.pop(context);
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20),

              _buildInstaRow('تخصيص', 'السمة والخط',
                  Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFE040FB), Color(0xFF7C4DFF), Color(0xFF448AFF)]))),
                  () {
                    GroupThemeSheet.show(context, widget.groupId);
                  }),
                 _buildInstaRow('رابط الدعوة', (data['inviteEnabled'] == true) ? 'مُفعل' : 'إيقاف تشغيل',
                 Icon(Icons.link, color: Colors.white, size: 28),
                () {
                   Navigator.push(context, MaterialPageRoute(builder: (_) => GroupInviteLinkScreen(groupId: widget.groupId)));
                 }),

              _buildInstaRow('الأشخاص', '${members.length} أعضاء',
                  Icon(Icons.people_outline, color: Colors.white, size: 28),
                  () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => GroupMembersScreen(groupId: widget.groupId)));
              }),

              _buildInstaRow('الخصوصية والسلامة', null,
                 Icon(Icons.lock_outline, color: Colors.white, size: 28),
                () {
                Navigator.push(
               context,
               MaterialPageRoute(
                builder: (_) => GroupPrivacySafetyScreen(groupId: widget.groupId),
              ),
           );
         }),

              _buildInstaRow('إنشاء دردشة جماعية جديدة', null,
                  Icon(Icons.group_add_outlined, color: Colors.white, size: 28),
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupCreateDetailsScreen(),
                  ),
                );
              }),

              SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'الوسائط التي تمت مشاركتها',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Tajawal',
                      fontSize: 16,
                      fontWeight: FontWeight.bold
                    ),
                  ),
                ),
              ),

              SizedBox(height: 12),
              Divider(color: Colors.white12, height: 1),
              // تبدأ كل المعاينات أسفل الخط الفاصل بالمستوى نفسه.
              const SizedBox(height: 8),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('group_chats')
                    .doc(widget.groupId)
                    .collection('messages')
                    .where('type', whereIn: ['image', 'video', 'album'])
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      child: Text('تعذر تحميل الوسائط: ${snap.error}',
                        style: const TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 11),
                        textAlign: TextAlign.center),
                    );
                  }
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator(color: Colors.white54)),
                    );
                  }
                  // كل ألبوم له معاينة واحدة فقط بنفس قياس الوسائط الفردية؛
                  // تبقى جميع عناصر الألبوم متاحة بالسحب داخل العارض.
                  final entries = <_GroupMediaEntry>[];
                  for (final doc in snap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['viewOnce'] == true) continue;
                    final type = (data['type'] ?? '').toString();
                    final caption = (data['text'] ?? data['caption'] ?? '').toString();
                    if (type == 'album' && data['mediaItems'] is List) {
                      final album = <_GroupMediaEntry>[];
                      for (final raw in data['mediaItems'] as List) {
                        if (raw is! Map) continue;
                        final item = Map<String, dynamic>.from(raw);
                        final url = (item['url'] ?? item['mediaUrl'] ?? '').toString();
                        if (url.isEmpty) continue;
                        album.add(_GroupMediaEntry(
                          url: url,
                          isVideo: item['isVideo'] == true || item['type'] == 'video',
                          caption: (item['caption'] ?? '').toString().isNotEmpty
                              ? item['caption'].toString() : caption,
                        ));
                      }
                      if (album.isEmpty) continue;
                      // اعرض غلاف الألبوم فقط في الشبكة، ولا تفرد عناصره.
                      entries.add(album.first.withAlbum(album, 0));
                    } else if (type == 'image' || type == 'video') {
                      final url = (data['mediaUrl'] ?? '').toString();
                      if (url.isNotEmpty) {
                        entries.add(_GroupMediaEntry(url: url,
                          isVideo: type == 'video', caption: caption));
                      }
                    }
                  }
                  if (entries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 40),
                      child: Text('ستظهر هنا الصور ومقاطع الفيديو التي تمت مشاركتها في هذه الدردشة.',
                        style: TextStyle(color: Colors.white54, fontFamily: 'Tajawal', fontSize: 14),
                        textAlign: TextAlign.center),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2,
                      childAspectRatio: 1),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final item = entries[i];
                      Future<void> open({VideoPlayerController? preparedController,
                          Future<bool>? preparedReady}) async {
                        if (item.album != null) {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _GroupAlbumViewer(
                              items: item.album!, initialIndex: item.albumIndex,
                              preparedController: preparedController,
                              preparedReady: preparedReady)));
                        } else if (item.isVideo) {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _VideoViewerScreen(
                              videoUrl: item.url, caption: item.caption)));
                        } else {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _ImageViewerScreen(
                              imageUrl: item.url, caption: item.caption)));
                        }
                      }
                      if (item.isVideo) {
                        return ClipRect(child: Stack(fit: StackFit.expand, children: [
                          _GroupInfoVideoTile(
                            key: ValueKey('${item.url}_${item.albumIndex}'),
                            videoUrl: item.url, caption: item.caption,
                            onOpen: item.album == null ? null : (controller, ready) async {
                              // إذا فشلت تهيئة المعاينة، جرّب مشغلاً جديداً عند الفتح.
                              if (await ready) {
                                await open(preparedController: controller, preparedReady: ready);
                              } else {
                                await open();
                              }
                            },
                          ),
                          if (item.album != null)
                            const Positioned(left: 6, top: 6,
                              child: IgnorePointer(child: Icon(Icons.collections_rounded,
                                color: Colors.white, size: 20))),
                        ]));
                      }
                      return GestureDetector(
                        onTap: open,
                        child: ClipRect(child: Stack(fit: StackFit.expand, children: [
                          Image.network(item.url, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: kFieldFill)),
                          if (item.album != null)
                            const Positioned(left: 6, top: 6,
                              child: Icon(Icons.collections_rounded,
                                color: Colors.white, size: 20)),
                          if (item.caption.trim().isNotEmpty)
                            const Positioned(right: 6, bottom: 6,
                              child: Icon(Icons.notes_rounded, color: Colors.white, size: 19)),
                        ])),
                      );
                    },
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
// معاينة الفيديو تُجهّز المشغّل مرة واحدة، ويُعاد استخدامه عند فتح الفيديو.
// يبقى مالك المشغّل هو عنصر الشبكة، فلا يحدث تحميل ثانٍ عند الانتقال.
class _GroupInfoVideoTile extends StatefulWidget {
  final String videoUrl;
  final String caption;
  final Future<void> Function(VideoPlayerController, Future<bool>)? onOpen;
  const _GroupInfoVideoTile({super.key, required this.videoUrl, required this.caption, this.onOpen});

  @override
  State<_GroupInfoVideoTile> createState() => _GroupInfoVideoTileState();
}

class _GroupInfoVideoTileState extends State<_GroupInfoVideoTile>
    with AutomaticKeepAliveClientMixin {
  late final VideoPlayerController _controller;
  late final Future<bool> _ready;
  bool _initialized = false;
  bool _viewerOpen = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _ready = _controller.initialize().then((_) {
      if (mounted) setState(() => _initialized = true);
      return true;
    }).catchError((Object error) {
      debugPrint('Group media thumbnail init failed: $error');
      return false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: () async {
        // لا نعرض نفس VideoPlayer في الشبكة والعارض بنفس اللحظة.
        // هذا يمنع تنازع سطح الفيديو أثناء فتح عناصر الألبوم.
        if (_viewerOpen) return;
        setState(() => _viewerOpen = true);
        try {
          if (widget.onOpen != null) {
            await widget.onOpen!(_controller, _ready);
          } else {
            final thumbnailReady = await _ready;
            if (!mounted) return;
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => _VideoViewerScreen(
                videoUrl: widget.videoUrl,
                caption: widget.caption,
                preparedController: thumbnailReady ? _controller : null,
                preparedReady: thumbnailReady ? _ready : null,
              ),
            ));
          }
        } finally {
          if (mounted) {
            if (_controller.value.isInitialized) {
              await _controller.pause();
              await _controller.seekTo(Duration.zero);
            }
            if (mounted) setState(() => _viewerOpen = false);
          }
        }
      },
      child: Stack(fit: StackFit.expand, children: [
        Container(color: kFieldFill),
        if (_initialized && !_viewerOpen)
          FittedBox(fit: BoxFit.cover, child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ))
        else
          const Center(child: Icon(Icons.videocam_outlined, color: Colors.white38)),
        Container(color: Colors.black26,
          child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32))),
        if (widget.caption.trim().isNotEmpty)
          const Positioned(right: 6, bottom: 6,
            child: Icon(Icons.notes_rounded, color: Colors.white, size: 19)),
      ]),
    );
  }
}

// النص الطويل قابل للفتح بكلمة «المزيد» والتمرير داخل مساحة محددة.
class _GroupMediaCaption extends StatefulWidget {
  final String caption;
  const _GroupMediaCaption({required this.caption});
  @override
  State<_GroupMediaCaption> createState() => _GroupMediaCaptionState();
}

class _GroupMediaCaptionState extends State<_GroupMediaCaption> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    if (widget.caption.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Colors.black87),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _expanded ? 190 : 48),
          child: SingleChildScrollView(
            child: Text(widget.caption, textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)),
          ),
        ),
        if (widget.caption.length > 65 || widget.caption.contains('\n'))
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(padding: const EdgeInsets.only(top: 5),
              child: Text(_expanded ? 'أقل' : 'المزيد',
                style: const TextStyle(color: Color(0xFF21C063), fontSize: 14))),
          ),
      ]),
    );
  }
}

class _ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String caption;
  const _ImageViewerScreen({required this.imageUrl, this.caption = ''});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Stack(children: [
        Positioned.fill(child: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: Image.network(imageUrl)))),
        if (caption.trim().isNotEmpty)
          Positioned(left: 0, right: 0, bottom: 0,
            child: SafeArea(top: false, child: _GroupMediaCaption(caption: caption))),
      ]),
    );
  }
}

class _VideoViewerScreen extends StatefulWidget {
  final String videoUrl;
  final String caption;
  final VideoPlayerController? preparedController;
  final Future<bool>? preparedReady;
  const _VideoViewerScreen({required this.videoUrl, this.caption = '',
    this.preparedController, this.preparedReady});

  @override
  State<_VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<_VideoViewerScreen> {
  late VideoPlayerController _controller;
  bool _isInit = false;
  bool _isMuted = false;
  bool _failed = false;

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.preparedController ??
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    final ready = widget.preparedReady ??
        _controller.initialize().then((_) => true).catchError((Object _) => false);
    ready.then((ok) async {
      if (!mounted) return;
      if (!ok) {
        setState(() => _failed = true);
        return;
      }
      _controller.addListener(_onVideoChanged);
      setState(() => _isInit = true);
      await _controller.setLooping(true);
      if (mounted) await _controller.play();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoChanged);
    if (widget.preparedController == null) {
      _controller.dispose();
    } else {
      _controller.pause();
      _controller.setLooping(false);
      _controller.setVolume(1);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: _failed
              ? const Text('تعذر تحميل الفيديو', style: TextStyle(color: Colors.white70))
              : _isInit
                  ? InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: GestureDetector(
                      onTap: () => _controller.value.isPlaying
                          ? _controller.pause() : _controller.play(),
                      child: Stack(alignment: Alignment.center, children: [
                        AspectRatio(aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller)),
                        if (!_controller.value.isPlaying)
                          Container(padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 48)),
                      ]),
                    ),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
        ),
        SafeArea(child: Padding(padding: const EdgeInsets.all(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(onTap: () => Navigator.pop(context),
              child: Container(padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 22))),
            GestureDetector(onTap: _isInit ? () {
              setState(() => _isMuted = !_isMuted);
              _controller.setVolume(_isMuted ? 0 : 1);
            } : null,
              child: Container(padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: Icon(_isMuted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white, size: 22))),
          ]))),
        if (_isInit)
          Positioned(bottom: 0, left: 0, right: 0,
            child: SafeArea(top: false, child: VideoProgressIndicator(
              _controller, allowScrubbing: true,
              colors: const VideoProgressColors(playedColor: Colors.white,
                bufferedColor: Colors.white24, backgroundColor: Colors.transparent),
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10)))),
        if (widget.caption.trim().isNotEmpty)
          Positioned(left: 0, right: 0, bottom: 35,
            child: SafeArea(top: false, child: _GroupMediaCaption(caption: widget.caption))),
      ]),
    );
  }
}

// عناصر الألبوم في معرض معلومات المجموعة، دون تغيير بيانات الرسائل الأصلية.
class _GroupMediaEntry {
  final String url;
  final bool isVideo;
  final String caption;
  final List<_GroupMediaEntry>? album;
  final int albumIndex;

  const _GroupMediaEntry({required this.url, required this.isVideo,
    required this.caption, this.album, this.albumIndex = 0});

  _GroupMediaEntry withAlbum(List<_GroupMediaEntry> items, int index) =>
      _GroupMediaEntry(url: url, isVideo: isVideo, caption: caption,
        album: items, albumIndex: index);
}

// سحب أفقي بين كل صور وفيديوهات الرسالة المجمعة، مع وصف كل عنصر.
class _GroupAlbumViewer extends StatefulWidget {
  final List<_GroupMediaEntry> items;
  final int initialIndex;
  final VideoPlayerController? preparedController;
  final Future<bool>? preparedReady;
  const _GroupAlbumViewer({required this.items, required this.initialIndex,
    this.preparedController, this.preparedReady});

  @override
  State<_GroupAlbumViewer> createState() => _GroupAlbumViewerState();
}

class _GroupAlbumViewerState extends State<_GroupAlbumViewer> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final item = widget.items[i];
              return Stack(children: [
                Positioned.fill(child: Center(
                  child: item.isVideo
                    ? (i == _index ? _GroupAlbumVideoPage(key: ValueKey(item.url), url: item.url,
                        preparedController: i == widget.initialIndex ? widget.preparedController : null,
                        preparedReady: i == widget.initialIndex ? widget.preparedReady : null)
                        : const SizedBox.shrink())
                    : InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: Image.network(item.url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text('تعذر تحميل الصورة',
                          style: TextStyle(color: Colors.white70)))),
                )),
                if (item.caption.trim().isNotEmpty)
                  Positioned(left: 0, right: 0, bottom: 0,
                    child: _GroupMediaCaption(caption: item.caption)),
              ]);
            },
          ),
          Positioned(top: 4, left: 12, right: 12,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white)),
              Text('${_index + 1} / ${widget.items.length}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            ])),
        ]),
      ),
    );
  }
}

class _GroupAlbumVideoPage extends StatefulWidget {
  final String url;
  final VideoPlayerController? preparedController;
  final Future<bool>? preparedReady;
  const _GroupAlbumVideoPage({super.key, required this.url,
    this.preparedController, this.preparedReady});
  @override
  State<_GroupAlbumVideoPage> createState() => _GroupAlbumVideoPageState();
}

class _GroupAlbumVideoPageState extends State<_GroupAlbumVideoPage> {
  late final VideoPlayerController _video;
  bool _ready = false;
  bool _failed = false;

  void _changed() { if (mounted) setState(() {}); }

  @override
  void initState() {
    super.initState();
    _video = widget.preparedController ??
        VideoPlayerController.networkUrl(Uri.parse(widget.url));
    final ready = widget.preparedReady ??
        _video.initialize().then<bool>((_) => true).catchError((Object error) {
          debugPrint('Group album video initialization failed: $error');
          return false;
        });
    ready.then((ok) {
      if (!ok) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      if (!mounted) return;
      _video.addListener(_changed);
      setState(() => _ready = true);
      _video.play();
    });
  }

  @override
  void dispose() {
    _video.removeListener(_changed);
    if (widget.preparedController == null) {
      _video.dispose();
    } else {
      _video.pause();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('تعذر تحميل الفيديو', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 12),
      const Text('تحقق من الاتصال أو جرّب فتح الفيديو من الدردشة',
        style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
    if (!_ready) return const CircularProgressIndicator(color: Colors.white);
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: GestureDetector(
      onTap: () => _video.value.isPlaying ? _video.pause() : _video.play(),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: _video.value.aspectRatio, child: VideoPlayer(_video)),
        if (!_video.value.isPlaying)
          const Icon(Icons.play_circle_fill, color: Colors.white, size: 54),
        Positioned(left: 0, right: 0, bottom: 0,
          child: VideoProgressIndicator(_video, allowScrubbing: true,
            colors: const VideoProgressColors(playedColor: Colors.white))),
      ]),
      ),
    );
  }
}
