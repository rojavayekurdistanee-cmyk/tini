import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// قائمة مرفقات موحّدة للدردشات. لا تغيّر أي مسار إرسال قائم.
/// تعتمد على callbacks حتى تستخدم كل دردشة منطق الإرسال الخاص بها.
class TiniAttachmentSheet extends StatefulWidget {
  const TiniAttachmentSheet({
    super.key,
    required this.onGallery,
    required this.onCamera,
    required this.onLocation,
    required this.onDocument,
  });

  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback onLocation;
  final VoidCallback onDocument;

  @override
  State<TiniAttachmentSheet> createState() => _TiniAttachmentSheetState();
}

class _TiniAttachmentSheetState extends State<TiniAttachmentSheet> {
  final List<AssetEntity> _assets = [];
  bool _loading = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth && !permission.hasAccess) return;
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
      if (paths.isEmpty) return;
      final media = await paths.first.getAssetListPaged(page: 0, size: 120);
      if (mounted) setState(() => _assets.addAll(media));
    } catch (error) {
      debugPrint('Tini attachment gallery error: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _choose(VoidCallback callback) {
    Navigator.of(context).pop();
    // ينتظر انتهاء إغلاق النافذة قبل فتح الواجهة المطلوبة.
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }

  Widget _option(IconData icon, String title, VoidCallback callback) {
    return Expanded(
      child: InkWell(
        onTap: () => _choose(callback),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.teal, size: 28),
              const SizedBox(height: 7),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -180 && !_expanded) setState(() => _expanded = true);
        if (velocity > 180 && _expanded) setState(() => _expanded = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: height * (_expanded ? 0.88 : 0.65),
        decoration: const BoxDecoration(
          color: Color(0xFF0F1720),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(8))),
              if (!_expanded) ...[
                const SizedBox(height: 12),
                Row(children: [
                  _option(Icons.photo_library_outlined, 'المعرض', widget.onGallery),
                  _option(Icons.camera_alt_outlined, 'الكاميرا', widget.onCamera),
                  _option(Icons.location_on_outlined, 'الموقع', widget.onLocation),
                  _option(Icons.description_outlined, 'المستند', widget.onDocument),
                ]),
                const Divider(color: Colors.white12),
              ],
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                    : _assets.isEmpty
                        ? const Center(child: Text('لا توجد وسائط متاحة', style: TextStyle(color: Colors.white70)))
                        : GridView.builder(
                            padding: const EdgeInsets.all(3),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3,
                            ),
                            itemCount: _assets.length,
                            itemBuilder: (context, index) {
                              final asset = _assets[index];
                              return InkWell(
                                onTap: () => _choose(widget.onGallery),
                                child: Stack(fit: StackFit.expand, children: [
                                  AssetEntityImage(asset, isOriginal: false, thumbnailSize: const ThumbnailSize.square(240), fit: BoxFit.cover),
                                  if (asset.type == AssetType.video)
                                    const Align(alignment: Alignment.bottomRight, child: Padding(
                                      padding: EdgeInsets.all(5), child: Icon(Icons.videocam, color: Colors.white, size: 19),
                                    )),
                                ]),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
