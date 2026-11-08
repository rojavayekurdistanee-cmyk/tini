import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'search_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_provider.dart' as custom;
import 'profile_screen.dart';
import 'post_view_screen.dart'; // [جديد]
import 'story.dart';
import 'story_ring.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'audience_access.dart';
import 'audience_gate.dart';

class SearchResultsScreen extends StatefulWidget {
  final String initialQuery;
  const SearchResultsScreen({super.key, required this.initialQuery});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;

  final Color bg = const Color(0xFF0F1720);
  final Color surface = const Color(0xFF1A222C);
  final Color fieldFill = const Color(0xFF1C1C1E);
  final Color highlight = const Color(0xFFFF3B30);

  String _activeFilter = 'الكل'; // [جديد]

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _searchController = TextEditingController(text: widget.initialQuery);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SearchProvider>();
      provider.search(widget.initialQuery);
      provider.addRecentSearch(widget.initialQuery);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // [جديد] فتح فيديو من نتائج البحث
  Future<void> _openSearchFeed(String selectedPostId, SearchProvider provider) async {
    final candidates = provider.posts;
    if (candidates.isEmpty) return;
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;

    // إظهار loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: Colors.teal)),
    );

    try {
      // 1. جيب كل postId
      final postIds = candidates.map((p) => p['postId'] as String).toList();

      // 2. جيب DocumentSnapshots بالتوازي
      final docs = await Future.wait(
        postIds.map((id) => FirebaseFirestore.instance.collection('posts').doc(id).get())
      );

      // 3. فلترة الموجود فقط
      final validDocs = docs.where((d) => d.exists && d.data() != null &&
          AudienceAccess.instance.canViewPost(d.data()!, postId: d.id)).toList();
      if (!mounted || viewerUid != FirebaseAuth.instance.currentUser?.uid) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final selectedIndex = validDocs.indexWhere((doc) => doc.id == selectedPostId);

      // 4. إغلاق loading
      if (mounted) Navigator.pop(context);

      if (validDocs.isEmpty || selectedIndex < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لا يمكن فتح الفيديو'), backgroundColor: Colors.red),
        );
        return;
      }

      // 5. افتح PostViewScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostViewScreen(
            posts: validDocs,
            initialIndex: selectedIndex,
            thumbnailUrl: validDocs[selectedIndex].data()?['thumbnailUrl'],
            showSearchBar: true, // [جديد]
            searchQuery: provider.currentQuery, // [جديد]
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // [جديد] فتح فيديوهات صوت معين
  Future<void> _openSoundFeed(Map<String, dynamic> sound) async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    final String soundTitle = sound['title']?? '';
    if (soundTitle.isEmpty) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => Center(child: CircularProgressIndicator(color: Colors.teal)));

    try {
      final query = await FirebaseFirestore.instance
         .collection('posts')
         .where('songTitle', isEqualTo: soundTitle)
         .where('isMysteryBox', isEqualTo: false) // [تعديل] اخفاء الصناديق النادرة
         .orderBy('createdAt', descending: true)
         .limit(50)
         .get();
      await Future.wait(query.docs.map((doc) async {
        final audience = AudienceAccess.instance;
        if (audience.isPostPending(doc.data(), postId: doc.id)) {
          await audience.verifyPost(doc.id);
        }
      }));
      if (!mounted || viewerUid != FirebaseAuth.instance.currentUser?.uid) {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (mounted) Navigator.pop(context);
      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا توجد فيديوهات لهذا الصوت'), backgroundColor: Colors.orange));
        return;
      }
      // [إضافة - فلتر الخصوصية] للجميع يطلع، اصدقاء فقط للأصدقاء المتبادلين، انا فقط ما يطلع
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final filtered = query.docs.where((d) {
        final data = d.data();
        if (!AudienceAccess.instance.canViewPost(data, postId: d.id)) return false;
        final pr = (data['privacy'] ?? 'public').toString().toLowerCase();
        final privacy = pr == 'everyone' ? 'public' : pr == 'only_me' ? 'private' : pr;
        if (privacy == 'private') return false;
        if (privacy == 'friends') {
          final ownerId = data['uid']?.toString() ?? '';
          if (ownerId == myUid) return true;
          // هنا لازم تفحص متابعة متبادلة، اذا ما عندك لستة جاهزة احجب احتياطياً
          // الحل الصحيح هو نفسه يلي في search_provider
          return false; // منع مؤقت حتى تجيب following/followers
        }
        return true;
      }).toList();
      if (filtered.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا توجد فيديوهات لهذا الصوت'), backgroundColor: Colors.orange));
        return;
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => PostViewScreen(posts: filtered, initialIndex: 0, showSearchBar: true, searchQuery: soundTitle)));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  // [جديد] فتح فيديوهات هاشتاق معين
  Future<void> _openHashtagFeed(Map<String, dynamic> hashtag) async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    final String tagName = hashtag['name']?? '';
    if (tagName.isEmpty) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => Center(child: CircularProgressIndicator(color: Colors.teal)));

    try {
      final query = await FirebaseFirestore.instance
         .collection('posts')
         .where('hashtags', arrayContains: tagName)
         .where('isMysteryBox', isEqualTo: false) // [تعديل] اخفاء الصناديق النادرة
         .orderBy('createdAt', descending: true)
         .limit(50)
         .get();
      await Future.wait(query.docs.map((doc) async {
        final audience = AudienceAccess.instance;
        if (audience.isPostPending(doc.data(), postId: doc.id)) {
          await audience.verifyPost(doc.id);
        }
      }));
      if (!mounted || viewerUid != FirebaseAuth.instance.currentUser?.uid) {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (mounted) Navigator.pop(context);
      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا توجد فيديوهات لهذا الهاشتاق'), backgroundColor: Colors.orange));
        return;
      }
      // [إضافة - فلتر الخصوصية] للجميع يطلع، اصدقاء فقط للأصدقاء المتبادلين، انا فقط ما يطلع
      final myUid2 = FirebaseAuth.instance.currentUser?.uid ?? '';
      final filtered = query.docs.where((d) {
        final data = d.data();
        if (!AudienceAccess.instance.canViewPost(data, postId: d.id)) return false;
        final pr = (data['privacy'] ?? 'public').toString().toLowerCase();
        final privacy = pr == 'everyone' ? 'public' : pr == 'only_me' ? 'private' : pr;
        if (privacy == 'private') return false;
        if (privacy == 'friends') {
          final ownerId = data['uid']?.toString() ?? '';
          if (ownerId == myUid2) return true;
          return false;
        }
        return true;
      }).toList();
      if (filtered.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا توجد فيديوهات لهذا الهاشتاق'), backgroundColor: Colors.orange));
        return;
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => PostViewScreen(posts: filtered, initialIndex: 0, showSearchBar: true, searchQuery: '#$tagName')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Container(
            height: 40,
            decoration: BoxDecoration(
              color: fieldFill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'بحث',
                hintStyle: TextStyle(color: Colors.white54),
                prefixIcon: Icon(Icons.search, color: Colors.white54, size: 22),
                suffixIcon: IconButton(
                  icon: Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  context.read<SearchProvider>().search(val);
                }
              },
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.arrow_forward, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            SizedBox(width: 8),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: Colors.teal,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 15),
            tabs: const [
              Tab(text: 'الأفضل'),
              Tab(text: 'الفيديوهات'),
              Tab(text: 'الأشخاص'),
              Tab(text: 'الأصوات'),
              Tab(text: 'الهاشتاقات'),
            ],
          ),
        ),
        body: Consumer<SearchProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return Center(child: CircularProgressIndicator(color: Colors.teal));
            }
            return TabBarView(
              controller: _tabController,
              children: [
                _buildBestTab(provider),
                _buildVideosTab(provider),
                _buildUsersTab(provider),
                _buildSoundsTab(provider),
                _buildHashtagsTab(provider),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBestTab(SearchProvider provider) {
    final filteredPosts = _getFilteredPosts(provider.posts); // [جديد]
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('الكل'),
                _filterChip('لم تتم مشاهدته'),
                _filterChip('شاهدته'),
                _filterChip('تم التحميل مؤخرًا'),
              ],
            ),
          ),
          _buildVideoGrid(filteredPosts, provider), // [معدل]
        ],
      ),
    );
  }

  Widget _filterChip(String text) {
    final bool active = _activeFilter == text; // [جديد]
    return GestureDetector( // [جديد]
      onTap: () => setState(() => _activeFilter = text), // [جديد]
      child: Container(
        margin: EdgeInsets.only(left: 8),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active? Colors.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(text, style: TextStyle(color: active? Colors.white : Colors.white70, fontSize: 13)),
      ),
    );
  }

  // [جديد] خوارزمية الفلترة
  List<Map<String, dynamic>> _getFilteredPosts(List<Map<String, dynamic>> posts) {
    final String uid = FirebaseAuth.instance.currentUser?.uid?? '';
    final now = DateTime.now();

    switch (_activeFilter) {
      case 'شاهدته':
        return posts.where((p) {
          final viewedBy = List<String>.from(p['viewedBy']?? []);
          return viewedBy.contains(uid);
        }).toList();
      case 'لم تتم مشاهدته':
        return posts.where((p) {
          final viewedBy = List<String>.from(p['viewedBy']?? []);
          return!viewedBy.contains(uid);
        }).toList();
      case 'تم التحميل مؤخرًا':
        return posts.where((p) {
          final createdAt = p['createdAt'];
          if (createdAt is Timestamp) {
            return now.difference(createdAt.toDate()).inDays <= 7;
          }
          return false;
        }).toList();
      default:
        return posts;
    }
  }

  Widget _buildVideosTab(SearchProvider provider) {
    return _buildVideoGrid(provider.posts, provider); // [معدل]
  }

  // [معدل] أضفنا provider parameter و GestureDetector
  Widget _buildVideoGrid(List<Map<String, dynamic>> posts, SearchProvider provider) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.68,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: posts.length,
      itemBuilder: (context, i) {
        final p = posts[i];
        return AudiencePostGate(
          post: p,
          postId: p['postId']?.toString(),
          child: GestureDetector( // [جديد]
          onTap: () => _openSearchFeed(p['postId'].toString(), provider), // [جديد]
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                        child: CachedNetworkImage(
  imageUrl: p['thumbnailUrl']?? '',
  fit: BoxFit.cover,
  errorWidget: (_, __, ___) => Container(color: Colors.black26),
),
                      ),
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Icon(Icons.volume_up, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['description']?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                            .collection('stories')
                            .doc(p['uid']?? p['userId']?? '')
                            .collection('items')
                            .where('expiresAt', isGreaterThan: Timestamp.now())
                            .snapshots(),
                            builder: (context, snap) {
                              final docs = snap.data?.docs?? [];
                              final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
                              final hasStories = docs.isNotEmpty;
                              final hasUnviewed = docs.any((d) {
                                final viewedBy = List<String>.from(d['viewedBy']?? []);
                                return!viewedBy.contains(currentUid);
                              });

                              // [مُصحح] رجعنا منطق الحرف
                              final String profileImg = p['profileImg']?? '';
                              final String username = p['username']?? '';
                              final bool hasImage = profileImg.isNotEmpty;
                              final String initial = username.isNotEmpty? username[0].toUpperCase() : '?';

                              if (hasStories) {
                                return StoryRing(
                                  imageUrl: profileImg,
                                  size: 20,
                                  hasStories: true,
                                  hasUnviewed: hasUnviewed,
                                  heroTag: 'search-video-${p['postId']?? i}',
                                );
                              } else if (hasImage) {
                                return CircleAvatar(
                                radius: 10,
                                backgroundImage: CachedNetworkImageProvider(profileImg),
                              );
                              } else {
                                return CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.grey[800],
                                  child: Text(initial, style: TextStyle(color: Colors.white, fontSize: 10)),
                                );
                              }
                            },
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              p['username']?? '',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${_formatNumber(p['views']?? 0)}',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildUsersTab(SearchProvider provider) {
    final String currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
    final users = provider.users;
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: 8),
      itemCount: users.length,
      separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 1),
      itemBuilder: (context, i) {
        final u = users[i];
        final String targetUid = u['uid']?? '';
        final String profileImg = u['profileImg']?? '';
        final String username = u['username']?? '';
        final String fullName = u['fullName']?? '';
        final bool hasImage = profileImg.isNotEmpty;
        final String initial = (fullName.isNotEmpty? fullName : username).isNotEmpty
     ? (fullName.isNotEmpty? fullName : username)[0].toUpperCase()
            : '?';

        return AudienceProfileGate(
          uid: targetUid,
          child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          onTap: () {
            if (targetUid.isNotEmpty && targetUid!= currentUid) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: targetUid)));
            }
          },
          leading: GestureDetector(
            onTap: () {
              if (targetUid.isNotEmpty && targetUid!= currentUid) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: targetUid)));
              }
            },
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
              .collection('stories')
              .doc(targetUid)
              .collection('items')
              .where('expiresAt', isGreaterThan: Timestamp.now())
              .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs?? [];
                final currentUid = FirebaseAuth.instance.currentUser?.uid?? '';
                final hasStories = docs.isNotEmpty;
                final hasUnviewed = docs.any((d) {
                  final viewedBy = List<String>.from(d['viewedBy']?? []);
                  return!viewedBy.contains(currentUid);
                });

                // [مُصحح] رجعنا منطق الحرف
                if (hasStories) {
                  return StoryRing(
                    imageUrl: profileImg,
                    size: 56,
                    hasStories: true,
                    hasUnviewed: hasUnviewed,
                    heroTag: 'search-user-$targetUid',
                  );
                } else if (hasImage) {
                  return CircleAvatar(
                  radius: 28,
                  backgroundImage: CachedNetworkImageProvider(profileImg),
                );
                } else {
                  return CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey[800],
                    child: Text(initial, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  );
                }
              },
            ),
          ),
          title: Text(username, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(
            '$fullName • ${_formatNumber(u['followers']?? 0)} متابع',
            style: TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: targetUid == currentUid
    ? const SizedBox.shrink()
              : StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(currentUid).collection('following').doc(targetUid).snapshots(),
                  builder: (context, snapshot) {
                    final bool isFollowing = snapshot.hasData && snapshot.data!.exists;
                    return ElevatedButton(
                      onPressed: () {
                        context.read<custom.AuthProvider>().toggleFollow(targetUid);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFollowing? Colors.white12 : Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: Size(80, 32),
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text(isFollowing? 'إلغاء' : 'متابعة', style: TextStyle(fontSize: 13)),
                    );
                  },
                ),
        ),
        );
      },
    );
  }

  Widget _buildSoundsTab(SearchProvider provider) {
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: 8),
      itemCount: provider.songs.length,
      separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 1),
      itemBuilder: (context, i) {
        final s = provider.songs[i];
        return ListTile(
          onTap: () => _openSoundFeed(s),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.videocam, color: Colors.white),
          ),
          title: Text(s['title']?? '', style: TextStyle(color: Colors.white, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'يحتوي على موسيقى من: ${s['artist']?? ''} • ${s['uses']?? 0} فيديو',
            style: TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(imageUrl: s['cover']?? '', width: 56, height: 56, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 56, height: 56, color: Colors.black26)),
          ),
        );
      },
    );
  }

  Widget _buildHashtagsTab(SearchProvider provider) {
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: 8),
      itemCount: provider.hashtags.length,
      separatorBuilder: (_, __) => Divider(color: Colors.white10, height: 1),
      itemBuilder: (context, i) {
        final h = provider.hashtags[i];
        return ListTile(
          onTap: () => _openHashtagFeed(h),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.videocam, color: Colors.white),
          ),
          title: Text('#${h['name']?? ''}', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          subtitle: Text('${_formatNumber(h['count']?? 0)} منشور', style: TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.right),
          trailing: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
            child: Center(child: Text('#', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
          ),
        );
      },
    );
  }

  String _formatNumber(dynamic n) {
    final num = (n is int)? n : int.tryParse(n.toString())?? 0;
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}م';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)} ألف';
    return num.toString();
  }
}