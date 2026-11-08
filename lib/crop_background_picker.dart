import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:path_provider/path_provider.dart';

/// Native gallery-style picker with three columns and album selection.
/// Only images are supported as replacement backgrounds in this release.
class CropBackgroundPicker extends StatefulWidget {
  const CropBackgroundPicker({super.key});

  @override
  State<CropBackgroundPicker> createState() => _CropBackgroundPickerState();
}

class _CropBackgroundPickerState extends State<CropBackgroundPicker> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  final List<AssetEntity> _images = [];
  final ScrollController _scroll = ScrollController();
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  bool _selecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 440 && !_loading && _hasMore) {
        _nextPage();
      }
    });
    _initialize();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _loading = true);
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth && !permission.hasAccess) {
        throw StateError('يجب السماح بالوصول إلى الصور لاختيار الخلفية');
      }
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image,
        filterOption: FilterOptionGroup(orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ]));
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _album = albums.isEmpty ? null : albums.first;
        _loading = false;
      });
      await _nextPage();
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _loading = false; });
    }
  }

  Future<void> _nextPage() async {
    final album = _album;
    if (album == null || _loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await album.getAssetListPaged(page: _page, size: 72);
      if (!mounted || _album != album) return;
      setState(() {
        _images.addAll(page);
        _page++;
        _hasMore = page.length == 72;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setAlbum(AssetPathEntity album) {
    setState(() {
      _album = album;
      _images.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    _nextPage();
  }

  Future<void> _select(AssetEntity asset) async {
    if (_selecting) return;
    setState(() => _selecting = true);
    try {
      final File? file = await asset.originFile;
      if (file == null || !await file.exists()) throw StateError('الصورة غير متاحة');
      // Persist a local copy. The gallery package may return a temporary path.
      final support = await getApplicationSupportDirectory();
      final stable = await file.copy('${support.path}/tini_bg_${DateTime.now().microsecondsSinceEpoch}.${file.path.split('.').last}');
      if (mounted) Navigator.of(context).pop(stable.path);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اختيار الصورة: $error')));
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      title: PopupMenuButton<AssetPathEntity>(
        initialValue: _album,
        onSelected: _setAlbum,
        itemBuilder: (_) => _albums.map((a) => PopupMenuItem(
          value: a, child: Text(a.name))).toList(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_album?.name ?? 'الكل', style: const TextStyle(color: Colors.black, fontSize: 17)),
          const Icon(Icons.keyboard_arrow_down, color: Colors.black),
        ]),
      ),
      actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))],
    ),
    body: Column(children: [
      if (_error != null) Padding(padding: const EdgeInsets.all(12),
        child: Text(_error!, style: const TextStyle(color: Colors.red))),
      Expanded(child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2,
          childAspectRatio: 0.85),
        itemCount: _images.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return InkWell(
            onTap: () => Navigator.pop(context, '__tini_remove_background__'),
            child: const ColoredBox(color: Color(0xFFF0F0F0),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.block, color: Colors.black54),
                Text('بلا خلفية', style: TextStyle(color: Colors.black54)),
              ])));
          return InkWell(
            onTap: _selecting ? null : () => _select(_images[i - 1]),
            child: AssetEntityImage(_images[i - 1], fit: BoxFit.cover,
              thumbnailSize: const ThumbnailSize(240, 320), isOriginal: false));
        },
      )),
      if (_loading) const LinearProgressIndicator(color: Colors.teal),
    ]),
  );
}
