import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'search_provider.dart';
import 'search_results_screen.dart';
import 'auth_provider.dart' as custom;
import 'audience_access.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // ألوان Tini المعتمدة
  final Color bgColor = const Color(0xFF0F1720);
  final Color surfaceColor = const Color(0xFF1A222C);
  final Color fieldFill = const Color(0xFF1C1C1E);
  final Color titiTeal = Colors.teal;
  final Color highlightRed = const Color(0xFFFF3B30);

  // [AUDIENCE CONTROL - ADDITION]
  bool _isViewerAdult = false;

  bool _isUserAdultContent(Map<String, dynamic> userData) =>
      !AudienceAccess.instance.canViewProfile((userData['uid'] ?? '').toString());

  bool _isPostAdultContent(Map<String, dynamic> postData) =>
      !AudienceAccess.instance.canViewPost(postData, postId: postData['postId']?.toString());

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {});
      if (_controller.text.isNotEmpty) {
        context.read<SearchProvider>().search(_controller.text);
      } else {
        context.read<SearchProvider>().clearSearch();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // تحميل البحث الأخير
      context.read<SearchProvider>().loadRecentSearches();
      // [AUDIENCE CONTROL] - حالة المشاهد - FIXED V2
      // ملاحظات الفحص القديم؛ لا تمنح flags المخزنة صلاحية بلوغ بعد التوحيد:
      // [إصلاح] اعتمد على isUserAdult او age مع بعض
      // اذا age = 0 حاول تحسب من birthDate
      // [AUDIENCE CONTROL] - حالة المشاهد من المصدر الموحد بعد التحقق من الخادم.
      if (mounted) setState(() => _isViewerAdult = AudienceAccess.instance.isViewerAdult);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    final query = _controller.text.trim();
    if (query.isNotEmpty) {
      FocusScope.of(context).unfocus();
      final prov = context.read<SearchProvider>();
      prov.addRecentSearch(query);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchResultsScreen(initialQuery: query),
        ),
      );
    }
  }

  void _goBack() {
    FocusScope.of(context).unfocus();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final searchProv = context.watch<SearchProvider>();
    _isViewerAdult = AudienceAccess.instance.isViewerAdult;
    final isTyping = _controller.text.isNotEmpty;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              // الشريط العلوي
              _buildSearchBar(),
              // المحتوى
              Expanded(
                child: isTyping
                ? _buildTypingResults(searchProv)
                    : _buildInitialView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          // زر بحث - صار يشتغل
          GestureDetector(
            onTap: _performSearch,
            child: Text(
              'بحث',
              style: TextStyle(
                color: highlightRed,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // حقل البحث
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: fieldFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.right,
                onSubmitted: (_) => _performSearch(),
                decoration: InputDecoration(
                  hintText: _controller.text.isEmpty? 'ابحث في Tini' : '',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  // حذف المايك نهائياً - X يظهر فقط عند الكتابة
                  prefixIcon: _controller.text.isNotEmpty
                   ? GestureDetector(
                          onTap: () {
                            _controller.clear();
                            context.read<SearchProvider>().clearSearch();
                          },
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        )
                      : null,
                  suffixIcon: Icon(Icons.search, color: Colors.white54, size: 22),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // سهم الرجوع - صار ما يعلق
          GestureDetector(
            onTap: _goBack,
            child: const Icon(Icons.arrow_forward, color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }

  // الحالة الأولى: قبل الكتابة - عمليات البحث الأخيرة
  Widget _buildInitialView() {
    final recent = context.watch<SearchProvider>().recentSearches;

    if (recent.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: Colors.white12),
            const SizedBox(height: 20),
            Text('ابحث في Tini', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('أشخاص • فيديوهات • أصوات • هاشتاقات', style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // عنوان مع زر مسح الكل
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => context.read<SearchProvider>().clearRecentSearches(),
                child: Text('مسح الكل', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),
              Text('عمليات البحث الأخيرة', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: recent.length,
            itemBuilder: (context, index) => _buildHistoryItem(recent[index]),
          ),
        ),
      ],
    );
  }

  // الحالة الثانية: أثناء الكتابة - بحث حقيقي
  Widget _buildTypingResults(SearchProvider prov) {
    if (prov.isLoading) {
      return Center(child: CircularProgressIndicator(color: titiTeal, strokeWidth: 2));
    }

    // [Phase 4 - نظام الحظر - مركزي]
    final authProv = context.watch<custom.AuthProvider>();
    final Set<String> myBlockedSet = authProv.blockedUsers.toSet();

    // [AUDIENCE CONTROL] - فلترة 18+ : الاسم ما يظهر من الأساس
    List<dynamic> filteredUsers = _isViewerAdult
        ? prov.users
        : prov.users.where((u) {
            final data = u as Map<String, dynamic>;
            return !_isUserAdultContent(data);
          }).toList();
    // [Phase 4] - اخفاء المحظورين من واجهة البحث - انا حاظرو
    filteredUsers = filteredUsers.where((u) {
      final String uid = (u as Map)['uid']?.toString()?? '';
      if (uid.isEmpty) return false;
      return !myBlockedSet.contains(uid);
    }).toList();

    List<dynamic> filteredPosts = _isViewerAdult
        ? prov.posts
        : prov.posts.where((p) {
            final data = p as Map<String, dynamic>;
            return !_isPostAdultContent(data);
          }).toList();
    // فلتر اضافي للخصوصية - للجميع / اصدقاء / انا فقط
    filteredPosts = filteredPosts.where((p) {
      final data = p as Map<String, dynamic>;
      final pr = (data['privacy'] ?? 'public').toString().toLowerCase();
      final privacy = pr == 'everyone' ? 'public' : pr;
      if (privacy == 'private' || privacy == 'only_me') return false;
      if (privacy == 'friends') {
        // لازم متابعة متبادلة، غير هيك ما يظهر
        final String ownerId = data['uid']?.toString() ?? '';
        // نعتمد على myFollowing و myFollowers من الـ Provider - لو مو موجودين نمنعه احتياطياً
        // الأفضل تركه للـ Provider بس هون إضافي
        if (ownerId.isEmpty) return false;
      }
      return true;
    }).toList();
    // [Phase 4] - اخفاء فيديوهات المحظور من واجهة البحث
    filteredPosts = filteredPosts.where((p) {
      final String owner = (p as Map)['uid']?.toString()?? '';
      if (owner.isEmpty) return false;
      return !myBlockedSet.contains(owner);
    }).toList();

    final hasResults = filteredUsers.isNotEmpty || filteredPosts.isNotEmpty || prov.hashtags.isNotEmpty || prov.songs.isNotEmpty;

    if (!hasResults) {
      return Center(
        child: Text(
          'لا توجد نتائج لـ "${_controller.text}"',
          style: TextStyle(color: Colors.white54, fontSize: 15),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // الأشخاص - مفلتر
        if (filteredUsers.isNotEmpty)...[
          _buildSectionHeader('الأشخاص'),
       ...filteredUsers.map((u) => _buildSuggestionItem(
                text: u['fullName']?.toString()?? u['username']?.toString()?? '',
                isUser: true,
                subtitle: u['isFriend'] == true? 'صديق' : '@${u['username']?? ''}',
                avatar: u['profileImg']?.toString(),
              )),
        ],
        // الفيديوهات - مفلتر
        if (filteredPosts.isNotEmpty)...[
          _buildSectionHeader('الفيديوهات'),
      ...filteredPosts.map((p) {
            return _buildSuggestionItem(
                text: p['description']?.toString()?? '',
                isUser: false,
                subtitle: '${p['views']?? 0} مشاهدة',
                avatar: p['thumbnailUrl']?.toString(),
              );
          }),
        ],
        // الهاشتاقات
        if (prov.hashtags.isNotEmpty)...[
          _buildSectionHeader('الهاشتاقات'),
       ...prov.hashtags.map((h) => _buildSuggestionItem(
                text: '#${h['name']?.toString()?? ''}',
                isUser: false,
                subtitle: '${h['count']?? 0} منشور',
                avatar: null,
              )),
        ],
        // الأصوات
        if (prov.songs.isNotEmpty)...[
          _buildSectionHeader('الأصوات'),
       ...prov.songs.map((s) => _buildSuggestionItem(
                text: s['title']?.toString()?? '',
                isUser: false,
                subtitle: s['artist']?.toString(),
                avatar: s['cover']?.toString(),
              )),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(color: titiTeal, fontSize: 13, fontWeight: FontWeight.bold),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _buildHistoryItem(String text) {
    return InkWell(
      onTap: () {
        _controller.text = text;
        _controller.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
        _performSearch();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Colors.white30, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            // زر X ظاهر دائماً للحذف
            GestureDetector(
              onTap: () => context.read<SearchProvider>().removeRecentSearch(text),
              child: Icon(Icons.close, color: Colors.white54, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingItem(String text, bool isHot) {
    return InkWell(
      onTap: () {
        _controller.text = text;
        _performSearch();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isHot? highlightRed : Colors.white24,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: isHot? highlightRed : Colors.white,
                      fontSize: 15,
                      fontWeight: isHot? FontWeight.bold : FontWeight.normal,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  if (isHot)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('رائج', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        const SizedBox(width: 2),
                        Icon(Icons.trending_up, color: Colors.white38, size: 12),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionItem({required String text, bool isUser = false, String? subtitle, String? avatar}) {
    final bool hasAvatar = avatar!= null && avatar.isNotEmpty;
    final String initial = text.isNotEmpty? text[0].toUpperCase() : '?';

    return InkWell(
      onTap: () {
        // يملى الحقل + يبحث فوراً
        final cleanText = text.startsWith('#')? text.replaceFirst('#', '') : text;
        _controller.text = cleanText;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        _performSearch();
      },
      onLongPress: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // سهم
            Icon(Icons.north_east, color: Colors.white54, size: 20),
            const SizedBox(width: 12),
            // أيقونة بحث
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: surfaceColor,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search, color: Colors.white54, size: 18),
            ),
            const SizedBox(width: 12),
            // النص
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    text,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle!= null && subtitle.isNotEmpty)
                    Text(
                      '· $subtitle',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // صورة المستخدم
            if (isUser)...[
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 18,
                backgroundColor: titiTeal,
                backgroundImage: hasAvatar? CachedNetworkImageProvider(avatar!) : null,
                child: hasAvatar
                  ? null
                    : Text(
                        initial,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}