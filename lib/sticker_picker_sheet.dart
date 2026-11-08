import 'package:flutter/material.dart';
import 'sticker_layer.dart';
import 'gif_service.dart';
import 'local_sticker_manager.dart';
import 'dart:io';
import 'emoji_data.dart'; // ✅ استدعاء ملف الايموجيات

class StickerPickerSheet extends StatefulWidget {
  const StickerPickerSheet({super.key});

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<String> _gifResults = [];
  List<String> _userStickers = [];
  List<String> _favorites = [];
  bool _isLoading = false;
  String selectedCategory = 'social'; // ✅ القسم المختار افتراضياً

  // ✅ كاش للستيكرات عشان ما نعيد بناء الليست كل مرة
  final Map<String, List<String>> _categoryStickersCache = {};

  // ✅ صار يستخدم الليست من emoji_data.dart
  final List<Map<String, String>> _emojis = kAllEmojis;

  // ✅ ستكيرات TitiStar للسوشيال - محدثة كاملة
  final List<String> _socialStickers = [
    'assets/stickers/social/titi_like.png', // قلب او لايك
    'assets/stickers/social/titi_follow.png', // تابعني
    'assets/stickers/social/titi_share.png', // شارك
    'assets/stickers/social/titi_comment.png', // علق
    'assets/stickers/social/titi_save.png', // حفظ
    'assets/stickers/social/titi_mention.png', // منشن
    'assets/stickers/social/titi_shop.png', // القديم
    'assets/stickers/social/titi_sale.png', // القديم
    'assets/stickers/social/titi_deal.png', // القديم
    'assets/stickers/social/titi_new.png', // القديم
  ];

  // ✅ كل الأقسام من البار السفلي بدون TikTok Shop
  final List<Map<String, dynamic>> _categories = [
    {'icon': '👥', 'name': 'سوشيال', 'key': 'social'},
    {'icon': '💀', 'name': 'يوم الموتى', 'key': 'dayofdead'},
    {'icon': '🎃', 'name': 'هالوين', 'key': 'halloween'},
    {'icon': '🎅', 'name': 'كريسماس', 'key': 'christmas'},
    {'icon': '2026', 'name': '2026', 'key': 'newyear'},
    {'icon': '🌹', 'name': 'رومانسي', 'key': 'love'},
    {'icon': '⚽', 'name': 'رياضة', 'key': 'sports'},
    {'icon': '🔥', 'name': 'ترند', 'key': 'trending'},
    {'icon': '🍕', 'name': 'طعام', 'key': 'food'},
    {'icon': '❤', 'name': 'حب', 'key': 'hearts'},
    {'icon': '🅣', 'name': 'نصوص', 'key': 'text'},
    {'icon': '↩', 'name': 'اسهم', 'key': 'arrows'},
    {'icon': '✨', 'name': 'لمعة', 'key': 'sparkles'},
    {'icon': '♀', 'name': 'يوم المرأة', 'key': 'womensday'},
    {'icon': '📨', 'name': 'عيد الأب', 'key': 'fathersday'},
    {'icon': '📚', 'name': 'العودة للمدرسة', 'key': 'school'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadUserData();
    // ✅ نعمل precache للقسم الافتراضي + اللي جنبه أول ما يفتح
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheCategoryImages(selectedCategory);
    });
  }

  // ✅ فنكشن تسوي precache للقسم الحالي + اللي قبله + اللي بعده
  void _precacheCategoryImages(String key) {
    final currentIndex = _categories.indexWhere((cat) => cat['key'] == key);
    if (currentIndex == -1) return;

    final indicesToPrecache = [
      currentIndex - 1,
      currentIndex,
      currentIndex + 1,
    ].where((i) => i >= 0 && i < _categories.length);

    for (final i in indicesToPrecache) {
      final categoryKey = _categories[i]['key'];
      final stickers = _getStickersByCategory(categoryKey);
      for (final path in stickers) {
        if (!path.startsWith('http')) {
          precacheImage(AssetImage(path), context);
        }
      }
    }
  }

  Future<void> _loadUserData() async {
    _userStickers = await LocalStickerManager.getUserStickers();
    _favorites = await LocalStickerManager.getFavorites();
    setState(() {});
  }

  Future<void> _searchGif(String query) async {
    setState(() => _isLoading = true);
    _gifResults = await GifService.searchStickers(query);
    setState(() => _isLoading = false);
  }

  void _selectSticker(String path, {bool isEmoji = false, bool isGif = false, bool isFromGallery = false}) {
    final sticker = StickerLayer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      path: path,
      isEmoji: isEmoji,
      isGif: isGif,
      isFromGallery: isFromGallery,
    );
    Navigator.pop(context, sticker);
  }

  // ✅ فنكشن بتجيب الستيكرات حسب القسم - صارت تستخدم الكاش
  List<String> _getStickersByCategory(String key) {
    // لو موجود بالكاش رجعه مباشرة
    if (_categoryStickersCache.containsKey(key)) {
      return _categoryStickersCache[key]!;
    }

    List<String> result;
    switch(key) {
      case 'dayofdead':
        result = [
          'assets/stickers/dayofdead/skull_colored.png',
          'assets/stickers/dayofdead/flowers.png',
          'assets/stickers/dayofdead/candle.png',
        ];
        break;
      case 'halloween':
        result = [
          'assets/stickers/halloween/pumpkin.png',
          'assets/stickers/halloween/ghost.png',
          'assets/stickers/halloween/bat.png',
          'assets/stickers/halloween/witch.png',
          'assets/stickers/halloween/coffin.png',
        ];
        break;
      case 'christmas':
        result = [
          'assets/stickers/christmas/santa.png',
          'assets/stickers/christmas/tree.png',
          'assets/stickers/christmas/gift.png',
          'assets/stickers/christmas/snowman.png',
        ];
        break;
      case 'newyear':
        result = [
          'assets/stickers/newyear/2026.png',
          'assets/stickers/newyear/2027.png',
          'assets/stickers/newyear/fireworks.png',
          'assets/stickers/newyear/celebrate.png',
          'assets/stickers/newyear/sunny_bunnies.png',
        ];
        break;
      case 'love':
        result = [
          'assets/stickers/love/heart.png',
          'assets/stickers/love/rose.png',
          'assets/stickers/love/kiss.png',
          'assets/stickers/love/love_text.png',
        ];
        break;
      case 'sports':
        result = [
          'assets/stickers/sports/football.png',
          'assets/stickers/sports/basketball.png',
          'assets/stickers/sports/trophy.png',
        ];
        break;
      case 'trending':
        result = [
          'assets/stickers/trending/fire.png',
          'assets/stickers/trending/star.png',
          'assets/stickers/trending/crown.png',
        ];
        break;
      case 'food':
        result = [
          'assets/stickers/food/pizza.png',
          'assets/stickers/food/burger.png',
          'assets/stickers/food/donut.png',
        ];
        break;
      case 'hearts':
        result = [
          'assets/stickers/hearts/red_heart.png',
          'assets/stickers/hearts/pink_heart.png',
          'assets/stickers/hearts/sparkle_heart.png',
        ];
        break;
      case 'text':
        result = [
          'assets/stickers/text/wicked.png',
          'assets/stickers/text/lock.png',
          'assets/stickers/text/omg.png',
        ];
        break;
      case 'arrows':
        result = [
          'assets/stickers/arrows/arrow_right.png',
          'assets/stickers/arrows/arrow_left.png',
          'assets/stickers/arrows/curved_arrow.png',
        ];
        break;
      case 'sparkles':
        result = [
          'assets/stickers/sparkles/stars.png',
          'assets/stickers/sparkles/glitter.png',
          'assets/stickers/sparkles/shine.png',
        ];
        break;
      case 'womensday':
        result = [
          'assets/stickers/womensday/woman_symbol.png',
          'assets/stickers/womensday/flowers.png',
          'assets/stickers/womensday/power.png',
        ];
        break;
      case 'fathersday':
        result = [
          'assets/stickers/fathersday/best_dad.png',
          'assets/stickers/fathersday/tie.png',
          'assets/stickers/fathersday/mustache.png',
          'assets/stickers/fathersday/super_dad.png',
        ];
        break;
      case 'school':
        result = [
          'assets/stickers/school/bag.png',
          'assets/stickers/school/bus.png',
          'assets/stickers/school/books.png',
          'assets/stickers/school/first_day.png',
        ];
        break;
      default: // social
        result = _socialStickers;
        break;
    }

    // خزنها بالكاش قبل ما ترجعها
    _categoryStickersCache[key] = result;
    return result;
  }

  // ✅ فنكشن بتجيب اسم القسم
  String _getCategoryName(String key) {
    return _categories.firstWhere((cat) => cat['key'] == key)['name'];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xF7161823), // فوق: شفاف 97%
            Color(0xFF161823), // تحت: معتم 100%
          ],
          stops: [0.2, 1.0], // ← اخر 10% من الأسفل معتم
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)), // ✅ الحواف 12 زي تيك توك
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'البحث عن صور GIF',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search, color: Colors.white),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: _searchGif,
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(Icons.people_alt_outlined)), // ✅ غيرت الايقونة للسوشيال
              Tab(icon: Icon(Icons.emoji_emotions_outlined)),
              Tab(icon: Icon(Icons.sticky_note_2_outlined)),
              Tab(icon: Icon(Icons.star_border)),
            ],
          ),
          Expanded(
            child: _isLoading
        ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSocialTab(), // ✅ غيرت اسم الفنكشن
                      _buildEmojiTab(),
                      _buildUserStickersTab(),
                      _buildFavoritesTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialTab() { // ✅ غيرت من Ecommerce لـ Social
    // ✅ صار يجيب الستيكرات حسب القسم المختار
    final stickers = _searchController.text.isEmpty? _getStickersByCategory(selectedCategory) : _gifResults;
    return Column(
      children: [
        if (_searchController.text.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(_getCategoryName(selectedCategory), style: TextStyle(color: Colors.grey[400], fontSize: 16)), // ✅ العنوان ديناميكي
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: stickers.length,
            itemBuilder: (context, index) {
              final path = stickers[index];
              return GestureDetector(
                onTap: () => _selectSticker(path, isGif: path.startsWith('http')),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: path.startsWith('http')
              ? Image.network(path, fit: BoxFit.contain)
                      : Image.asset(path, fit: BoxFit.contain),
                ),
              );
            },
          ),
        ),
        if (_searchController.text.isEmpty) _buildCategoriesRow(),
      ],
    );
  }

  Widget _buildCategoriesRow() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final bool isSelected = selectedCategory == category['key']; // ✅ يشيك اذا القسم مختار

          return GestureDetector(
            onTap: () {
              setState(() {
                selectedCategory = category['key']; // ✅ الربط صار هون
              });
              // ✅ نعمل precache للقسم الجديد + اللي جنبه
              _precacheCategoryImages(category['key']);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  CircleAvatar(
                    backgroundColor: isSelected? Colors.blue : Colors.grey[850], // ✅ لون ازرق للمختار
                    child: Text(category['icon'], style: const TextStyle(fontSize: 20)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmojiTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _emojis.length,
      itemBuilder: (context, index) {
        final item = _emojis[index]; // ✅ صار Map
        return GestureDetector(
          onTap: () => _selectSticker(item['emoji']!, isEmoji: true), // ✅ بيرجع الايموجي
          child: Center(child: Text(item['emoji']!, style: const TextStyle(fontSize: 40))),
        );
      },
    );
  }

  Widget _buildUserStickersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('ملصقاتك', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _userStickers.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return GestureDetector(
                  onTap: () async {
                    final path = await LocalStickerManager.pickAndSaveImage();
                    if (path!= null) {
                      await _loadUserData();
                      _selectSticker(path, isFromGallery: true);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[700]!, width: 2, style: BorderStyle.solid),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 40),
                  ),
                );
              }
              final path = _userStickers[index - 1];
              return GestureDetector(
                onTap: () => _selectSticker(path, isFromGallery: true),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('تم استخدامه مؤخراً', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _favorites.length,
            itemBuilder: (context, index) {
              final path = _favorites[index];
              return GestureDetector(
                onTap: () => _selectSticker(path),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: path.startsWith('http')
              ? Image.network(path, fit: BoxFit.contain)
                      : Image.asset(path, fit: BoxFit.contain),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}