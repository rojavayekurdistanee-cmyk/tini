import 'package:flutter/material.dart';
import 'audience_access.dart';
import 'package:provider/provider.dart';
import 'post_provider.dart';
import 'package:flutter/rendering.dart';
import 'profile_screen.dart'; 
import 'create_post_screen.dart';
import 'video_processor.dart'; 
import 'titi_following_tab.dart';
import 'titi_friends_tab.dart';
import 'titi_trending_tab.dart';
import 'titi_recommendations_tab.dart';
import 'post_view_screen.dart';
import 'titi_single_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'messages_tab.dart';
import 'chat_provider.dart';
import 'search_screen.dart';
import 'stories_bar.dart';
import 'secret_vault_screen.dart';
import 'titi_profile_engine.dart';
import 'auth_provider.dart' as custom;

class HomeScreen extends StatefulWidget {
  final String? openPostId;
  final String? openCommentId;
  const HomeScreen({super.key, this.openPostId, this.openCommentId});
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _currentTab = 0;
  bool isCommentsPanelOpen = false;
  bool get _isHomeFeedVisible => _currentTab == 0 &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  final Color titiTeal = const Color(0xFF009688); // تيال - نجمة
  final Color titiRed = const Color(0xFFFF1744); // احمر - ارضية الدائرة
  final Color titiYellow = const Color(0xFFFFEB3B); // اصفر - خط التقدم
  String _lastHomeUrl = ""; // FIX: نحفظ رابط فيديو الهوم
  String _pendingNewVideoUrl = ""; // FIX: فيديو جديد ناطر لترجع عالهوم
  // Fix تذكر مكان كل تبويب: ذاكرة لكل تبويب لحالو
  final Map<int, String> _innerTabLastUrl = {0: "", 1: "", 2: "", 3: ""};
  int _currentInnerTab = 3; // 3 = توصيات الافتراضي
  bool _tabListenerAdded = false;
  TabController? _homeTabController; // [Fix]: للعودة إلى التوصيات بعد رفع فيديو من شاشة أخرى.

  // [AUDIENCE CONTROL - ADDITION]
  final _audience = AudienceAccess.instance;

  void _onAudienceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _audience.removeListener(_onAudienceChanged);
    super.dispose();
  }

  // [TIKTOK FLIP - ADDITION]
  bool _wasUploading = false;
  bool _hasHandledUpload = false;

   bool _isPostDeleted(Map<String, dynamic> data) {
    return data['isDeleted'] == true;
  }

  void toggleCommentsPanel(bool isOpen) {
    setState(() {
      isCommentsPanelOpen = isOpen;
    });
  }

  @override
  void initState() {
    super.initState();
    _audience.addListener(_onAudienceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // فك قفل مباشر بعد النشر - ما بيلغي ميزة كتم الصوت
      try {
        await TitiSingleEngine().emergencyUnlock();
        if (mounted && _isHomeFeedVisible) {
          await TitiProfileEngine().unlock();
          // A cold-start notification may cover Home while unlock awaits.
          if (mounted && _isHomeFeedVisible) {
            final String cur = TitiSingleEngine().currentUrl;
            if (cur.isNotEmpty) {
              await TitiSingleEngine().playUrl(cur);
            } else {
              await TitiSingleEngine().forceResumeForTab();
            }
          }
        }
      } catch (_) {}
      context.read<ChatProvider>().startFollowRequestsListener();
      context.read<ChatProvider>().startActivitiesListener();
      // [Two-Way Block] - مزامنة الحظر مع post_provider - هاد اللي بيخلي الفيد ما يطلع عند المحظور
      try {
        final auth = context.read<custom.AuthProvider>();
        context.read<PostProvider>().syncHardBlockedFromCenter(auth.blockedUsersSet, blockedBySet: auth.blockedBySet);
      } catch (_) {}
      // [AUDIENCE CONTROL] - حالة المشاهد - FIXED V2
      // القرار العمري يُقرأ من الحساب الحالي وصاحب الفيديو عند العرض.
      if (widget.openPostId != null && widget.openPostId!.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) {
              final postFuture = FirebaseFirestore.instance.collection('posts').doc(widget.openPostId!).get();
              return ListenableBuilder(
                listenable: _audience,
                builder: (context, _) => FutureBuilder(
                future: postFuture,
                builder: (context, snap) {
                  if (!snap.hasData || !snap.data!.exists) {
                    return const Scaffold(backgroundColor: Color(0xFF000000), body: Center(child: CircularProgressIndicator()));
                  }
                  final data = snap.data!.data() as Map<String, dynamic>?;
                  if (data != null && _isPostDeleted(data)) {
                    return const Scaffold(
                      backgroundColor: Color(0xFF000000),
                      body: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline, color: Colors.white24, size: 50),
                            SizedBox(height: 16),
                            Text("هذا الفيديو في المحذوفات", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text("تم نقل هذا الفيديو إلى المحذوفات", style: TextStyle(color: Colors.white54, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  }

                  if (data != null && !_audience.canViewPost(data, postId: snap.data!.id)) {
                    return const Scaffold(
                      backgroundColor: Color(0xFF000000),
                      body: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.no_adult_content, color: Colors.white, size: 50),
                            SizedBox(height: 16),
                            Text("هذا المحتوى للبالغين فقط 18+", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text("هذا الفيديو محجوب للمستخدمين تحت 18 سنة", style: TextStyle(color: Colors.white54, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  }
                                    // [Phase 5 + 6 - HARD BLOCK Two-Way - مركزي]
                  try {
                    final authBlock = context.read<custom.AuthProvider>();
                    final String ownerUid = data?['uid']?.toString()?? '';
                    if (ownerUid.isNotEmpty && (authBlock.blockedUsersSet.contains(ownerUid) || authBlock.blockedBySet.contains(ownerUid))) {
                      return const Scaffold(
                        backgroundColor: Color(0xFF000000),
                        body: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.block, color: Colors.white, size: 50),
                              SizedBox(height: 16),
                              Text("هذا الحساب محظور", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      );
                    }
                  } catch (_) {}
                  return PostViewScreen(
                    posts: [snap.data!], 
                    initialIndex: 0,
                    openComments: widget.openCommentId != null && widget.openCommentId!.isNotEmpty,
                    highlightCommentId: widget.openCommentId,
                  );
                },
                ),
              );
            },
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: 3,
      child: Builder(
        builder: (context) {
          // Fix تذكر مكان كل تبويب: نحفظ وين كان قبل ما نطلع، ونرجعو لنفس المكان
          final TabController tabController = DefaultTabController.of(context);
          _homeTabController = tabController;
          if (!_tabListenerAdded) {
            _tabListenerAdded = true;
tabController.addListener(() {
  if (!tabController.indexIsChanging && mounted) {
    final int newInner = tabController.index;
    if (newInner!= _currentInnerTab) {
      final String curUrl = TitiSingleEngine().currentUrl;
      if (curUrl.isNotEmpty) {
        _innerTabLastUrl[_currentInnerTab] = curUrl;
      }
      _currentInnerTab = newInner;
    }
  }
});
          }
          return Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: const Color(0xFF000000),
            body: Stack(
              children: [
                IndexedStack(
                  index: _currentTab,
                  children: [
                    _buildMainInterface(),
                    const MessagesTab(),
                    ProfileScreen(
onBackToHome: () {
  setState(() => _currentTab = 0);
  Future.delayed(const Duration(milliseconds: 150), () async {
    await TitiSingleEngine().unlockForHome();
    await TitiProfileEngine().unlock();
    if (_lastHomeUrl.isNotEmpty) {
      TitiSingleEngine().playUrl(_lastHomeUrl);
    }
  });
},
                    ),
                    const SecretVaultScreen(),
                  ],
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 5,
                  left: 20,
                  child: _buildTitiUploadStar(),
                ),
              ],
            ),
            bottomNavigationBar: isCommentsPanelOpen ? null : _buildTitiBottomBar(),
          );
        },
      ),
    );
  }

  Widget _buildTitiUploadStar() {
    return Consumer<PostProvider>(
      builder: (context, postProv, child) {
        // [TIKTOK FLIP - ADDITION] - كشف انتهاء الرفع - FIXED V3 يحفظ للرجوع
        if (postProv.isPublishingInBackground) {
          _wasUploading = true;
          _hasHandledUpload = false;
        } else if (_wasUploading && !_hasHandledUpload && !postProv.isPublishingInBackground) {
          _wasUploading = false;
          _hasHandledUpload = true;
          if (postProv.lastUploadedPost != null) {
            final data = (postProv.lastUploadedPost!.data() as Map<String, dynamic>?);
            final url = data?['videoUrl'] ?? "";
            if (url.isNotEmpty) {
              final bool isHomeVisible = _currentTab == 0 && (ModalRoute.of(context)?.isCurrent ?? true);
              if (!isHomeVisible) {
                _pendingNewVideoUrl = url; // احفظو لبين ما ترجع
              } else {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  if (_currentTab != 0) return;
                  if ((ModalRoute.of(context)?.isCurrent ?? true) == false) return;
                  try {
                    final tabCtrl = DefaultTabController.of(context);
                    tabCtrl.animateTo(3);
                    _currentInnerTab = 3;
                    await TitiSingleEngine().unlockForNewUpload();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _currentTab == 0 && (ModalRoute.of(context)?.isCurrent ?? true)) {
                        TitiSingleEngine().playUrl(url);
                      }
                    });
                  } catch (e) {}
                });
              }
            }
          }
        }

        if (!postProv.isPublishingInBackground && postProv.publicationError == null) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(postProv.publicationStatus.isEmpty
                    ? "جاري رفع تألقك.. ${ (postProv.uploadProgress * 100).toInt() }%"
                    : postProv.publicationStatus),
                duration: Duration(seconds: postProv.publicationError == null ? 1 : 5),
                backgroundColor: postProv.publicationError == null
                    ? titiTeal : const Color(0xFFE53935),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 35,
                  height: 35,
                  child: CircularProgressIndicator(
                    value: postProv.publicationProgress,
                    strokeWidth: 2.5,
                    color: titiYellow, // التقدم اصفر
                    backgroundColor: titiRed, // الارضية حمراء
                  ),
                ),
                Icon(postProv.publicationError == null ? Icons.star_rounded
                    : Icons.error_outline,
                    color: postProv.publicationError == null ? titiTeal : Colors.red,
                    size: 22), // النجمة تيال
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainInterface() {
    const double tabsHeight = 50.0;
    return Stack(
      children: [
        Positioned.fill(
          // [Home Video Scroll] - حجم كل صفحة يساوي المساحة المتاحة فعلياً فوق شريط التنقل.
          child: TabBarView(
            children: [
              _TabWithStories(child: TitiFollowingTab(isHomeActive: _isHomeFeedVisible), bgColor: Color(0xFF000000)),
              _TabWithStories(child: TitiFriendsTab(isHomeActive: _isHomeFeedVisible), bgColor: Color(0xFF000000)),
              TitiTrendingTab(isHomeActive: _isHomeFeedVisible),
              TitiRecommendationsTab(isHomeActive: _isHomeFeedVisible),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0, 
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTopTabBar(),
              _buildIndependentTabs(tabsHeight),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopTabBar() {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double topBarHeight = screenHeight * 0.034;
    return Container(
      height: topBarHeight,
      decoration: BoxDecoration(color: Colors.black),
    );
  }

  Widget _buildIndependentTabs(double height) {
    return Container(
      height: height,
      color: Colors.transparent,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  GestureDetector(
onTap: () async {
  _lastHomeUrl = TitiSingleEngine().currentUrl;
  await TitiSingleEngine().lock();
  await TitiProfileEngine().lock();
  Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchScreen())).then((_) async {
    if (_currentTab == 0) {
      await TitiProfileEngine().lock();
      await TitiSingleEngine().unlockForHome();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_pendingNewVideoUrl.isNotEmpty) {
          TitiSingleEngine().playUrl(_pendingNewVideoUrl);
          _pendingNewVideoUrl = "";
        } else if (_lastHomeUrl.isNotEmpty) {
          TitiSingleEngine().playUrl(_lastHomeUrl);
        }
      });
    }
  });
},
                    child: const Icon(Icons.search, color: Colors.white, size: 28),
                  ),
                  const Expanded(
                    child: TabBar(
                      isScrollable: true,
                      padding: EdgeInsets.only(right: 65, left: 5),
                      indicatorColor: Colors.white,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white60,
                      labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(text: "أتابعه"),
                        Tab(text: "الأصدقاء"),
                        Tab(text: "رائج"),
                        Tab(text: "توصيات"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 15,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF0F1720), borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text("LIVE", style: TextStyle(color: Color(0xFFFF3B30), fontSize: 13, fontWeight: FontWeight.bold))],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitiBottomBar() {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double bottomBarHeight = screenHeight * 0.0775;
    return Container(
      height: bottomBarHeight,
      decoration: BoxDecoration(color: Colors.black, border: const Border(top: BorderSide(color: Colors.white12, width: 0.5))),
      child: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bottomNavItem(Icons.home_filled, "الواجهة", 0),
            _bottomNavItem(Icons.message_outlined, "الرسائل", 1),
            GestureDetector(
              onTap: () async {
                _lastHomeUrl = TitiSingleEngine().currentUrl;
                await TitiSingleEngine().lock();
                await TitiProfileEngine().lock();
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CreatePostScreen(selectedLayout: DuetLayout.sideBySide))).then((_) async {
                  if (_currentTab == 0) {
                    final bool hasNewUpload = _pendingNewVideoUrl.isNotEmpty;
                    if (hasNewUpload) {
                      await TitiSingleEngine().unlockForNewUpload();
                      _currentInnerTab = 3;
                      _homeTabController?.animateTo(3);
                    } else {
                      await TitiSingleEngine().unlockForHome();
                    }
                    await TitiProfileEngine().lock();
                    Future.delayed(const Duration(milliseconds: 150), () {
                      if (_pendingNewVideoUrl.isNotEmpty) {
                        TitiSingleEngine().playUrl(_pendingNewVideoUrl);
                        _pendingNewVideoUrl = "";
                      } else if (!hasNewUpload && _lastHomeUrl.isNotEmpty) {
                        TitiSingleEngine().playUrl(_lastHomeUrl);
                      }
                    });
                  }
                });
              },
              child: Container(width: 45, height: 28, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.cyan, width: 2)), child: const Icon(Icons.add, color: Colors.black, size: 20)),
            ),
            _bottomNavItem(Icons.inventory_2, "السر", 3), 
            _bottomNavItem(Icons.person_outline, "ملفي", 2),
          ],
        ),
      ),
    );
  }

Widget _bottomNavItem(IconData icon, String label, int index, {Color? specialColor}) {
    bool isSelected = _currentTab == index;
    Color itemColor = specialColor?? (isSelected? Colors.cyanAccent : Colors.white);
    return GestureDetector(
      onTap: () async {
        final wasHome = _currentTab == 0;
        if (index != 0 && wasHome) {
          _lastHomeUrl = TitiSingleEngine().currentUrl;
          await TitiSingleEngine().lock();
          if (index == 2) {
            await TitiProfileEngine().unlock();
          } else {
            await TitiProfileEngine().lock();
          }
        } else if (index == 0 && !wasHome) {
          await TitiProfileEngine().lock();
          await TitiSingleEngine().unlockForHome();
          Future.delayed(const Duration(milliseconds: 150), () {
            if (_pendingNewVideoUrl.isNotEmpty) {
              TitiSingleEngine().playUrl(_pendingNewVideoUrl);
              _pendingNewVideoUrl = "";
            } else if (_lastHomeUrl.isNotEmpty) {
              TitiSingleEngine().playUrl(_lastHomeUrl);
            }
          });
        }
        setState(() => _currentTab = index);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: itemColor, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: itemColor, fontSize: 10, fontWeight: specialColor != null ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}

class _TabWithStories extends StatefulWidget {
  final Widget child;
  final Color? bgColor;
  const _TabWithStories({required this.child, this.bgColor});
  @override
  State<_TabWithStories> createState() => _TabWithStoriesState();
}

class _TabWithStoriesState extends State<_TabWithStories> {
  bool _showStories = true;
  // [Tini - Single Video Stories] - التقاط السحب عند عدم وجود صفحة ثانية قابلة للتمرير.
  Offset? _swipeStart;
  int? _swipePointer;

  @override
  Widget build(BuildContext context) {
    // [Tini - Responsive Stories] - موقع الفيديو والشريط يتشاركان نفس الارتفاع المحسوب.
    final storiesHeight = StoriesBar.responsiveHeight(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification && n.metrics.axis == Axis.vertical && n.direction == ScrollDirection.reverse && _showStories) {
          setState(() => _showStories = false);
        }
        return false;
      },
      // Listener لا ينافس PageView على حركة السحب ولا يغيّر تمرير الفيديوهات المتعددة.
      child: Listener(
        onPointerDown: (event) {
          if (!_showStories || _swipePointer != null ||
              event.localPosition.dy <= 50.0 + storiesHeight) return;
          _swipePointer = event.pointer;
          _swipeStart = event.localPosition;
        },
        onPointerMove: (event) {
          if (!_showStories || _swipePointer != event.pointer || _swipeStart == null) return;
          final delta = event.localPosition - _swipeStart!;
          // سحبة مقصودة للأعلى داخل الفيديو، وليست حركة أفقية للقصص أو التبويبات.
          if (delta.dy < -30.0 && -delta.dy > delta.dx.abs() * 1.25) {
            _swipeStart = null;
            _swipePointer = null;
            setState(() => _showStories = false);
          }
        },
        onPointerUp: (event) {
          if (_swipePointer == event.pointer) {
            _swipeStart = null;
            _swipePointer = null;
          }
        },
        onPointerCancel: (event) {
          if (_swipePointer == event.pointer) {
            _swipeStart = null;
            _swipePointer = null;
          }
        },
        child: Stack(
          children: [
            AnimatedPadding(duration: const Duration(milliseconds: 250), padding: EdgeInsets.only(top: _showStories ? 50.0 + storiesHeight : 0), child: widget.child),
            AnimatedPositioned(duration: const Duration(milliseconds: 250), top: _showStories ? 50 : -storiesHeight, left: 0, right: 0, height: storiesHeight, child: StoriesBar(backgroundColor: widget.bgColor)),
          ],
        ),
      ),
    );
  }
}