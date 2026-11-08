// [Tini] ملف grid_layout_sheet.dart - نسخة التلاحم التام (Zero Spacing)
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_manager/photo_manager.dart'; 
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart'; 

class GridTileDim {
  final int cross;
  final int main;
  GridTileDim(this.cross, this.main);
}

class GridConfig {
  final String name;
  final List<GridTileDim> dims;
  GridConfig({required this.name, required this.dims});
}

class TileState {
  AssetEntity asset;
  final TransformationController controller; 

  TileState({required this.asset, TransformationController? controller}) 
      : controller = controller ?? TransformationController();
}

class GridLayoutScreen extends StatefulWidget {
  final List<AssetEntity> initialSelectedMedia;
  const GridLayoutScreen({super.key, required this.initialSelectedMedia});

  @override
  State<GridLayoutScreen> createState() => _GridLayoutScreenState();
}

class _GridLayoutScreenState extends State<GridLayoutScreen> {
  final GlobalKey _gridKey = GlobalKey();

  final List<GridConfig> layouts = [
    GridConfig(name: "كلاسيك", dims: [GridTileDim(2, 3), GridTileDim(2, 3), GridTileDim(2, 3), GridTileDim(2, 3)]),
    GridConfig(name: "عمودي", dims: [GridTileDim(4, 2), GridTileDim(4, 2), GridTileDim(4, 2), GridTileDim(4, 2)]),
    GridConfig(name: "تركيز علوي", dims: [GridTileDim(4, 4), GridTileDim(2, 2), GridTileDim(2, 2)]),
    GridConfig(name: "شبكة مربعة", dims: [GridTileDim(2, 2), GridTileDim(2, 2), GridTileDim(2, 2), GridTileDim(2, 2)]),
    GridConfig(name: "نمط مختلط", dims: [GridTileDim(2, 4), GridTileDim(2, 2), GridTileDim(2, 2)]),
    GridConfig(name: "ثلاثي طول", dims: [GridTileDim(2, 6), GridTileDim(2, 3), GridTileDim(2, 3)]),
    GridConfig(name: "عريض", dims: [GridTileDim(4, 3), GridTileDim(4, 3)]),
    GridConfig(name: "سينمائي", dims: [GridTileDim(4, 2), GridTileDim(2, 2), GridTileDim(2, 2), GridTileDim(4, 2)]),
    GridConfig(name: "بانوراما", dims: [GridTileDim(4, 5)]),
    GridConfig(name: "مجلة", dims: [GridTileDim(3, 4), GridTileDim(1, 2), GridTileDim(1, 2)]),
    GridConfig(name: "توازن", dims: [GridTileDim(2, 3), GridTileDim(2, 3), GridTileDim(4, 2)]),
    GridConfig(name: "تيكتوك برو", dims: [GridTileDim(2, 5), GridTileDim(2, 5)]),
  ];

  late GridConfig selectedLayout;
  List<TileState> _tiles = []; 
  bool _isEditMode = false; 
  bool _isExporting = false; 

  @override
  void initState() {
    super.initState();
    selectedLayout = layouts[0];
    _tiles = widget.initialSelectedMedia.map((asset) => TileState(asset: asset)).toList();
  }

  @override
  void dispose() {
    for (var tile in _tiles) {
      tile.controller.dispose();
    }
    super.dispose();
  }

  Future<Uint8List?> _captureGrid() async {
    try {
      RenderRepaintBoundary boundary = _gridKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("TITI_DEBUG: خطأ أثناء التقاط الصورة: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720), 
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "تخطيط الشبكة",
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _isEditMode ? Icons.photo_size_select_large : Icons.edit_note_rounded,
              color: _isEditMode ? const Color(0xFFFF3B30) : Colors.white,
              size: 30,
            ),
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                child: RepaintBoundary(
                  key: _gridKey,
                  child: Container(
                    color: const Color(0xFF0F1720),
                    child: StaggeredGrid.count(
                      crossAxisCount: 4,
                      // تم تصفير المسافات هنا لتحقيق التلاحم التام
                      mainAxisSpacing: 0, 
                      crossAxisSpacing: 0,
                      children: List.generate(
                        _tiles.length < selectedLayout.dims.length 
                            ? _tiles.length 
                            : selectedLayout.dims.length, 
                        (index) {
                          final tile = _tiles[index];
                          final dim = selectedLayout.dims[index];
                          return StaggeredGridTile.count(
                            crossAxisCellCount: dim.cross,
                            mainAxisCellCount: dim.main, 
                            child: _buildTile(tile, index),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildLayoutPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(TileState tile, int index) {
    if (_isEditMode) {
      return Container(
        // في وضع التعديل نترك حدوداً بسيطة جداً فقط لتمييز المربعات أثناء التحريك
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFFFF3B30).withValues(alpha:0.3), 
            width: 0.5,
          ),
        ),
        child: InteractiveViewer(
          transformationController: tile.controller,
          panEnabled: true, 
          scaleEnabled: true, 
          clipBehavior: Clip.hardEdge,
          minScale: 0.5, 
          maxScale: 5.0,
          child: AssetEntityImage(
            tile.asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(400),
            fit: BoxFit.cover, 
            alignment: Alignment.center,
          ),
        ),
      );
    }

    return DragTarget<int>(
      onAccept: (fromIndex) {
        setState(() {
          final temp = _tiles[index];
          _tiles[index] = _tiles[fromIndex];
          _tiles[fromIndex] = temp;
        });
      },
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 100, height: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AssetEntityImage(
                  tile.asset, 
                  isOriginal: false, 
                  thumbnailSize: const ThumbnailSize.square(200),
                  fit: BoxFit.cover
                ),
              ),
            ),
          ),
          childWhenDragging: Container(color: Colors.white10), 
          child: Container(
            // إزالة أي حدود هنا لضمان التلاحم
            child: AssetEntityImage(
              tile.asset,
              isOriginal: false, 
              thumbnailSize: const ThumbnailSize.square(400),
              fit: BoxFit.cover, 
              alignment: Alignment.center,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayoutPicker() {
    return Container(
      height: 160,
      decoration: const BoxDecoration(
        color: Color(0xFF1A222C),
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Text(
            _isEditMode ? "وضع تحريك الصور داخل المربعات" : selectedLayout.name,
            style: TextStyle(
              color: _isEditMode ? const Color(0xFFFF3B30) : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold
            )
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: layouts.length,
              itemBuilder: (context, index) {
                bool isSelected = selectedLayout == layouts[index];
                return GestureDetector(
                  onTap: () => setState(() {
                    selectedLayout = layouts[index];
                    _isEditMode = false; 
                  }),
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: isSelected ? const Color(0xFFFF3B30) : Colors.transparent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white12,
                    ),
                    child: Center(
                      child: Icon(Icons.grid_view_rounded, color: isSelected ? Colors.white : Colors.white54, size: 30),
                    ),
                  ),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20, bottom: 10),
              child: _isExporting 
                ? const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 3),
                    ),
                  )
                : IconButton(
                    onPressed: () async {
                      if (_isExporting) return;

                      setState(() => _isExporting = true);
                      
                      try {
                        Uint8List? gridImage = await _captureGrid();

                        if (gridImage == null) {
                           throw Exception("فشل التقاط صورة الشبكة");
                        }

                        await PhotoManager.clearFileCache();
                        
                        if (!mounted) return;

                        Navigator.pop(context, {
                          'isGrid': true,
                          'gridImage': gridImage, 
                        });
                        
                      } catch (e) {
                        setState(() => _isExporting = false);
                      }
                    },
                    icon: const Icon(Icons.check_circle, color: Colors.teal, size: 45),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}