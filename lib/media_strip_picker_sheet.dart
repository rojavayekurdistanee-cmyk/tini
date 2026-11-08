import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'preview_media_item.dart';

/// شريط اختيار الصور/الفيديوهات من المعرض (يظهر عند الضغط على زر "+" في شاشة المعاينة).
/// يرجع قائمة عناصر مختارة (بالترتيب) عند الضغط على علامة الصح، أو null عند الإغلاق.
Future<List<PreviewMediaItem>?> showMediaStripPicker(
  BuildContext context, {
  required int maxSelect,
}) {
  return showModalBottomSheet<List<PreviewMediaItem>>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    isScrollControlled: true,
    builder: (_) => MediaStripPickerSheet(maxSelect: maxSelect),
  );
}

class MediaStripPickerSheet extends StatefulWidget {
  final int maxSelect;
  const MediaStripPickerSheet({super.key, required this.maxSelect});

  @override
  State<MediaStripPickerSheet> createState() => _MediaStripPickerSheetState();
}

class _MediaStripPickerSheetState extends State<MediaStripPickerSheet> {
  static const Color _green = Color(0xFF21C063);
  static const Color _bg = Color(0xFF111B21);
  static const int _pageSize = 60;

  final List<AssetEntity> _assets = [];
  final List<AssetEntity> _selected = [];
  AssetPathEntity? _path;
  bool _loading = true;
  bool _loadingMore = false;
  bool _done = false;
  bool _denied = false;
  bool _busy = false;
  bool _limitHit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!(ps.isAuth || ps == PermissionState.limited)) {
        if (mounted) {
          setState(() {
            _denied = true;
            _loading = false;
          });
        }
        return;
      }
      final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
      if (paths.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _path = paths[0];
      final List<AssetEntity> first = await paths[0].getAssetListRange(start: 0, end: _pageSize);
      _done = first.length < _pageSize;
      if (!mounted) return;
      setState(() {
        _assets.addAll(first);
        _loading = false;
      });
    } catch (e) {
      debugPrint('MediaStripPicker load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final AssetPathEntity? path = _path;
    if (path == null || _loadingMore || _done) return;
    _loadingMore = true;
    try {
      final int start = _assets.length;
      final List<AssetEntity> more = await path.getAssetListRange(start: start, end: start + _pageSize);
      if (more.length < _pageSize) _done = true;
      if (more.isNotEmpty && mounted) setState(() => _assets.addAll(more));
    } catch (e) {
      debugPrint('MediaStripPicker more error: $e');
    } finally {
      _loadingMore = false;
    }
  }

  void _toggle(AssetEntity a) {
    if (_busy) return;
    final int idx = _selected.indexWhere((e) => e.id == a.id);
    if (idx != -1) {
      HapticFeedback.selectionClick();
      setState(() {
        _selected.removeAt(idx);
        _limitHit = false;
      });
      return;
    }
    if (_selected.length >= widget.maxSelect) {
      HapticFeedback.heavyImpact();
      setState(() => _limitHit = true);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _selected.add(a));
  }

  Future<void> _confirm() async {
    if (_busy || _selected.isEmpty) return;
    setState(() => _busy = true);
    final List<PreviewMediaItem> out = [];
    for (final AssetEntity a in _selected) {
      try {
        final File? f = await a.originFile ?? await a.file;
        if (f == null) continue;
        final bool isVideo = a.type == AssetType.video;
        out.add(PreviewMediaItem(
          file: f,
          isVideo: isVideo,
          duration: isVideo ? a.videoDuration : Duration.zero,
        ));
      } catch (e) {
        debugPrint('MediaStripPicker file error: $e');
      }
    }
    if (!mounted) return;
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'إضافة صور أو فيديوهات',
                    style: TextStyle(
                      color: _limitHit ? const Color(0xFFE5384D) : Colors.white,
                      fontFamily: 'Tajawal',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_selected.length}/${widget.maxSelect}',
                  style: TextStyle(
                    color: _limitHit ? const Color(0xFFE5384D) : Colors.white70,
                    fontFamily: 'Tajawal',
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 104,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))
                  : _denied
                      ? const Center(
                          child: Text(
                            'لا يوجد إذن للوصول إلى المعرض',
                            style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 14),
                          ),
                        )
                      : _assets.isEmpty
                          ? const Center(
                              child: Text(
                                'لا توجد وسائط في المعرض',
                                style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 14),
                              ),
                            )
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _assets.length,
                              itemBuilder: (context, i) {
                                if (i >= _assets.length - 12) _loadMore();
                                return _tile(_assets[i]);
                              },
                            ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: _selected.isEmpty ? null : _confirm,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _selected.isEmpty ? const Color(0xFF2A3942) : _green,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.4),
                            )
                          : Icon(
                              Icons.check_rounded,
                              color: _selected.isEmpty ? Colors.white38 : Colors.black,
                              size: 28,
                            ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(AssetEntity a) {
    final int idx = _selected.indexWhere((e) => e.id == a.id);
    final bool sel = idx != -1;
    final bool isVid = a.type == AssetType.video;
    return GestureDetector(
      onTap: () => _toggle(a),
      child: Container(
        width: 98,
        margin: const EdgeInsetsDirectional.only(end: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AssetEntityImage(
                a,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(240),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1B1B1B)),
              ),
              if (isVid)
                const Positioned(
                  left: 6,
                  bottom: 5,
                  child: Icon(Icons.videocam_rounded, color: Colors.white, size: 17, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                ),
              if (sel) Container(color: const Color(0x66000000)),
              if (sel)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      '${idx + 1}',
                      style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w800, height: 1.1),
                    ),
                  ),
                ),
              if (sel)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: _green, width: 2.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}