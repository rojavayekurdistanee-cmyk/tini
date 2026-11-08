// [Tini] ملف media_picker_screen.dart - النسخة المحدثة لدعم الديو + المحادثة
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'media_preview_screen.dart';
// [Tini]: استيراد شاشة الكاميرا لإتمام عملية الربط برمجياً
import 'create_post_screen.dart';
import 'video_processor.dart';

class MediaPickerScreen extends StatefulWidget {
  final bool isAddingMore;
  // [Tini Duet]: إضافة مستقبلات الديو لربط الشاشات
  final String? duetVideoUrl;
  final bool isDuet;
  // [Titi Chat]: وضع المحادثة المرن
  final bool isForChat;

  const MediaPickerScreen({
    super.key,
    this.isAddingMore = false,
    this.duetVideoUrl, // استقبال رابط الفيديو الأصلي
    this.isDuet = false, // الوضع الافتراضي ليس ديو
    this.isForChat = false, // الوضع الافتراضي ليس محادثة
  });

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> with WidgetsBindingObserver {
  List<AssetEntity> _mediaList = [];
  final List<AssetEntity> _selectedMedia = [];
  bool _isLoading = true;
  int _selectedTab = 0; // 0: الكل، 1: الفيديوهات، 2: الصور

  bool _isProcessing = false;
  DuetLayout _selectedLayout = DuetLayout.sideBySide;
  int _currentPage = 0;
  late final void Function(dynamic) _changeCallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changeCallback = (_) => _loadDeviceMedia(isRefresh: true);
    PhotoManager.addChangeCallback(_changeCallback);
    PhotoManager.startChangeNotify();
    _loadDeviceMedia(isRefresh: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PhotoManager.removeChangeCallback(_changeCallback);
    PhotoManager.stopChangeNotify();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDeviceMedia(isRefresh: true);
    }
  }

  Future<void> _loadDeviceMedia({bool isRefresh = false}) async {
    if (isRefresh) {
      _currentPage = 0;
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        PhotoManager.openSetting();
        if (mounted) {
          setState(() {
            if (isRefresh) _mediaList = [];
            _isLoading = false;
          });
        }
        return;
      }

      // هذا السطر هو اللي يخلي الجديد يظهر أولاً سواء صورة أو فيديو
      final filter = FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      );

      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: _getAssetType(),
        filterOption: filter,
      );

      debugPrint("Tini MediaPicker: tab=$_selectedTab type=${_getAssetType()} albums=${albums.length}");

      if (albums.isEmpty) {
        if (mounted) {
          setState(() {
            if (isRefresh) _mediaList = [];
            _isLoading = false;
          });
        }
        return;
      }

      final List<AssetEntity> media = await albums[0].getAssetListPaged(
        page: _currentPage,
        size: 100,
      );

      debugPrint("Tini MediaPicker: page=$_currentPage got ${media.length} items");

      if (mounted) {
        setState(() {
          _mediaList = isRefresh ? media : [..._mediaList, ...media];
          _isLoading = false;
          // نزيد الصفحة فقط إذا رجع عناصر (عشان ما نضل نطلب صفحات فاضية)
          if (media.isNotEmpty) {
            _currentPage++;
          }
        });
      }
    } catch (e, st) {
      debugPrint("Tini MediaPicker load error: $e");
      debugPrint("$st");
      if (mounted) {
        setState(() {
          if (isRefresh) _mediaList = [];
          _isLoading = false;
        });
      }
    }
  }

  RequestType _getAssetType() {
    if (_selectedTab == 1) return RequestType.video;
    if (_selectedTab == 2) return RequestType.image;
    return RequestType.common;
  }

  void _toggleSelection(AssetEntity entity) {
    if (_isProcessing) return;
    setState(() {
      if (_selectedMedia.contains(entity)) {
        _selectedMedia.remove(entity);
      } else {
        // في وضع الديو، نسمح باختيار فيديو واحد فقط من الاستوديو لدمجه
        if (widget.isDuet) {
          _selectedMedia.clear();
          _selectedMedia.add(entity);
        } else {
          _selectedMedia.add(entity);
        }
      }
    });
  }

  // [Tini]: تعديل منطق الانتقال ليدعم الديو والمسار العادي مع التنسيقات
  Future<void> _navigateToPreview(List<AssetEntity> media) async {
    if (media.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // تم حذف clearFileCache لأنه كان يمسح الفيديو الجديد

      // تجهيز الملفات المختارة
      List<String> paths = [];
      String? localVideoPath;

      for (var asset in media) {
        final File? file = await asset.originFile;
        if (file!= null) {
          paths.add(file.path);
          if (asset.type == AssetType.video) {
            localVideoPath = file.path;
          }
        }
        if (file == null) debugPrint("Tini: Failed to load origin file for ${asset.id}");
      }

      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 400));

      // [Titi Chat]: مسار المحادثة المرن - إرجاع المسارات مباشرة
      if (widget.isForChat) {
        Navigator.pop(context, paths);
        return;
      }

      if (widget.isDuet) {
        // [Titi Mechanical]: الانتقال إلى شاشة الكاميرا مع بيانات الديو
        debugPrint("Tini: الانتقال لتسجيل الديو باستخدام فيديو من الاستوديو: $localVideoPath");

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreatePostScreen(
              duetVideoUrl: widget.duetVideoUrl, // الفيديو الأصلي من السيرفر
              isDuet: true,
              videoPath: localVideoPath, // الفيديو المختار من الاستوديو ليظهر بجانب الأصلي
              selectedLayout: _selectedLayout, // تمرير التنسيق المختار للكاميرا
            ),
          ),
        );
      } else {
        if (widget.isAddingMore) {
          Navigator.pop(context, media);
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MediaPreviewScreen(
                selectedMedia: media,
                selectedLayout: _selectedLayout, // [إضافة حرفية]: تمرير التنسيق لشاشة المعاينة
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("خطأ في معالجة ميديا Tini: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _onImageTap(AssetEntity entity) {
    if (_isProcessing) return;

    // في وضع الديو، الضغط المباشر يفتح المعاينة (بدء الديو) فوراً
    if (widget.isDuet && entity.type == AssetType.video) {
      _navigateToPreview([entity]);
      return;
    }

    // [Titi Chat]: في وضع المحادثة، الضغط يضيف للتحديد فقط
    if (widget.isForChat) {
      _toggleSelection(entity);
      return;
    }

    if (_selectedMedia.isNotEmpty) {
      _toggleSelection(entity);
    } else {
      _navigateToPreview([entity]);
    }
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = widget.isDuet
       ? "اختيار فيديو للديو"
        : widget.isForChat
           ? "إرسال وسائط"
            : "الأحدث";

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            if (_isProcessing) return;
            Navigator.pop(context);
          },
        ),
        title: GestureDetector(
          onTap: () => debugPrint("فتح قائمة الألبومات"),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(appBarTitle, style: const TextStyle(color: Colors.white, fontSize: 17)),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          if (!widget.isDuet &&!widget.isForChat)
            TextButton(
              onPressed: () {},
              child: const Text("نص", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.isDuet)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTab("الكل", 0),
                  _buildTab("الفيديوهات", 1),
                  _buildTab("الصور", 2),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
               ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : GridView.builder(
                    padding: const EdgeInsets.all(2),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: _mediaList.isEmpty
                        ? 0
                        : _mediaList.length + 1,
                    itemBuilder: (context, index) {
                      if (index >= _mediaList.length) {
                        // وصل لنهاية القائمة → حمّل الصفحة الجاية فقط إذا في عناصر
                        if (!_isLoading && _mediaList.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _loadDeviceMedia();
                          });
                        }
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final entity = _mediaList[index];
                      final isSelected = _selectedMedia.contains(entity);
                      final selectionIndex = _selectedMedia.indexOf(entity) + 1;

                      // في وضع الديو، نظهر فقط الفيديوهات أو نجعل الصور باهتة
                      bool isDisabled = widget.isDuet && entity.type!= AssetType.video;

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: isDisabled? null : () => _onImageTap(entity),
                              child: Opacity(
                                opacity: isDisabled? 0.3 : 1.0,
                                child: AssetEntityImage(
                                  entity,
                                  isOriginal: false,
                                  thumbnailSize: const ThumbnailSize.square(250),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),

                          if (!widget.isDuet)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: GestureDetector(
                                onTap: () => _toggleSelection(entity),
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                    color: isSelected? const Color(0xFFFF3B30) : Colors.black26,
                                  ),
                                  child: isSelected
                                     ? Center(
                                          child: Text(
                                            "$selectionIndex",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),

                          if (entity.type == AssetType.video)
                            Positioned(
                              bottom: 5,
                              right: 5,
                              child: Row(
                                children: [
                                  Text(
                                    _formatDuration(entity.duration),
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.play_circle_outline, color: Colors.white, size: 16),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),

          if (_selectedMedia.isNotEmpty &&!widget.isDuet)
            Container(
              height: 100,
              width: double.infinity,
              color: const Color(0xFF0F1720),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                itemCount: _selectedMedia.length,
                itemBuilder: (context, index) {
                  final selectedEntity = _selectedMedia[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 70,
                            height: 70,
                            child: AssetEntityImage(
                              selectedEntity,
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(150),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _toggleSelection(selectedEntity),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            decoration: const BoxDecoration(
              color: Color(0xFF1A222C),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: const Text("Smart Edit", style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
                ElevatedButton(
                  onPressed: (_selectedMedia.isEmpty || _isProcessing)
                     ? null
                      : () => _navigateToPreview(_selectedMedia),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 10),
                  ),
                  child: _isProcessing
                   ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        widget.isDuet
                           ? "بدء الديو"
                            : widget.isForChat
                               ? "إرسال (${_selectedMedia.length})"
                                : "التالي (${_selectedMedia.length})",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildTab(String label, int index) {
    bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        if (_isProcessing) return;
        setState(() {
          _selectedTab = index;
          _isLoading = true;
        });
        _loadDeviceMedia(isRefresh: true);
      },
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSelected? Colors.white : Colors.white54,
              fontWeight: isSelected? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 4),
          if (isSelected)
            Container(height: 2, width: 25, color: Colors.teal),
        ],
      ),
    );
  }
}