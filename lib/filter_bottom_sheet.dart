import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'dart:typed_data';
import 'filter_model.dart';
import 'filters_repository.dart';
import 'filter_grid_item.dart';
import 'filter_tabs.dart';
import 'filter_preview_video.dart';

// موديل للفلاتر المضافة على التايملاين
class FilterClip {
  final String id;
  final FilterModel filter;
  final Duration startTime;
  final Duration endTime;
  final Color color;

  FilterClip({
    required this.id,
    required this.filter,
    required this.startTime,
    required this.endTime,
    required this.color,
  });

  FilterClip copyWith({
    String? id,
    FilterModel? filter,
    Duration? startTime,
    Duration? endTime,
    Color? color,
  }) {
    return FilterClip(
      id: id?? this.id,
      filter: filter?? this.filter,
      startTime: startTime?? this.startTime,
      endTime: endTime?? this.endTime,
      color: color?? this.color,
    );
  }
}

class FilterBottomSheet extends StatefulWidget {
  final FilterModel initialFilter;
  final Function(FilterModel) onFilterSelected;
  final VoidCallback onClose;
  final VideoPlayerController? videoController;
  final Duration videoDuration;
  final List<FilterClip> filterClips;
  final List<Uint8List> videoThumbnails;
  final Function(FilterClip) onClipAdded;
  final Function(FilterClip) onClipUpdated;
  final Function(String?) onClipSelected;
  final Function(String) onClipDeleted; // ← جديد: للحذف

  const FilterBottomSheet({
    super.key,
    required this.initialFilter,
    required this.onFilterSelected,
    required this.onClose,
    this.videoController,
    required this.videoDuration,
    this.filterClips = const [],
    required this.videoThumbnails,
    required this.onClipAdded,
    required this.onClipUpdated,
    required this.onClipSelected,
    required this.onClipDeleted, // ← جديد
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late FilterModel _selectedFilter;
  int _selectedTabIndex = 0;
  late List<String> _categories;
  String? _selectedClipId;

  // متغيرات مؤقتة للسحب السلس
  String? _draggingClipId;
  Duration? _draggingStartTime;
  Duration? _draggingEndTime;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _categories = FiltersRepository.categories;
  }

  @override
  Widget build(BuildContext context) {
    final currentFilters = FiltersRepository.getByCategory(_categories[_selectedTabIndex]);

    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: const BoxDecoration(
        color: Color(0xFF0E161B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildTimelineBar(),
          ),

          const SizedBox(height: 12),

          // شريط أدوات الكليب المحدد
          if (_selectedClipId!= null) _buildSelectedClipToolbar(),

          const SizedBox(height: 8),
          FilterTabs(
            categories: _categories,
            selectedIndex: _selectedTabIndex,
            onTap: (index) => setState(() => _selectedTabIndex = index),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 0.7,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: currentFilters.length,
              itemBuilder: (context, index) {
                final filter = currentFilters[index];
                return FilterGridItem(
                  filter: filter,
                  isSelected: _selectedFilter.id == filter.id,
                  onTap: () {
                    setState(() => _selectedFilter = filter);
                    widget.onFilterSelected(filter);

                    final videoDuration = widget.videoDuration;

                    Duration startTime = Duration.zero;
                    Duration endTime = const Duration(seconds: 5);

                    if (_selectedClipId!= null) {
                      // إذا في كليب محدد، ضيف الكليب الجديد بعده
                      final selectedClip = widget.filterClips.where((c) => c.id == _selectedClipId).firstOrNull;
                      if (selectedClip == null) return; // ← تعديل: حماية
                      startTime = selectedClip.endTime;
                      endTime = startTime + const Duration(seconds: 5);
                      if (endTime > videoDuration) endTime = videoDuration;
                      if (startTime >= videoDuration) return;
                    } else if (widget.videoController!= null) {
                      // إذا ما في كليب محدد، ضيفه عند المؤشر الحالي
                      startTime = widget.videoController!.value.position;
                      endTime = startTime + const Duration(seconds: 5);
                      if (endTime > videoDuration) endTime = videoDuration;
                      if (startTime >= videoDuration) return;
                    }

                    final clip = FilterClip(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      filter: filter,
                      startTime: startTime,
                      endTime: endTime,
                      color: _getRandomColor(),
                    );
                    widget.onClipAdded(clip);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSelectedClipToolbar() {
    final selectedClip = widget.filterClips.where((c) => c.id == _selectedClipId).firstOrNull;

    // ← تعديل: لو الكليب انحذف ما تكرش، ارجع فاضي
    if (selectedClip == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedClipId = null);
      });
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selectedClip.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selectedClip.color, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.layers, color: selectedClip.color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              selectedClip.filter.name,
              style: TextStyle(color: selectedClip.color, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${_formatDuration(selectedClip.startTime)} - ${_formatDuration(selectedClip.endTime)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              final clipIdToDelete = selectedClip.id;
              setState(() => _selectedClipId = null); // ← تعديل: صفّر قبل الحذف
              widget.onClipSelected(null); // ← تعديل: بلّغ الأب انه ما في selection
              widget.onClipDeleted(clipIdToDelete); // ← تعديل: احذف آخر شي
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.delete, color: Colors.red, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final seconds = (d.inMilliseconds / 1000).toStringAsFixed(1);
    return '${seconds}s';
  }

  Widget _buildTimelineBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 40,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0E161B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: widget.videoController?? ValueNotifier(VideoPlayerValue(duration: Duration.zero)),
            builder: (context, value, child) {
              final totalDuration = widget.videoDuration.inMilliseconds.toDouble();
              final currentPosition = value.position.inMilliseconds.toDouble();

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedClipId = null);
                  widget.onClipSelected(null);
                },
                child: Stack(
                  children: [
                    // 1. الفريمات بالخلفية
                    if (widget.videoThumbnails.isNotEmpty && totalDuration > 0)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            children: widget.videoThumbnails.map((thumb) {
                              return Expanded(
                                child: Image.memory(
                                  thumb,
                                  fit: BoxFit.cover,
                                  height: 40,
                                  color: Colors.black.withValues(alpha: 0.4),
                                  colorBlendMode: BlendMode.darken,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),

                    // 2. البلوكات فوق الفريمات
                    if (totalDuration > 0)
                    ...widget.filterClips.map((clip) => _buildDraggableClip(clip, constraints.maxWidth, totalDuration)).toList(),

                    // 3. الخط الأبيض للمؤشر
                    if (widget.videoController!= null && totalDuration > 0)
                      Positioned(
                        right: (currentPosition / totalDuration) * constraints.maxWidth - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDraggableClip(FilterClip clip, double maxWidth, double totalDuration) {
    final isDragging = _draggingClipId == clip.id;
    final displayStartTime = isDragging? _draggingStartTime! : clip.startTime;
    final displayEndTime = isDragging? _draggingEndTime! : clip.endTime;

    final startPercent = displayStartTime.inMilliseconds / totalDuration;
    final endPercent = displayEndTime.inMilliseconds / totalDuration;
    final width = (endPercent - startPercent) * maxWidth;
    final right = startPercent * maxWidth;
    final isSelected = _selectedClipId == clip.id;

    return Positioned(
      right: right,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedClipId = clip.id);
          widget.onClipSelected(clip.id);
          HapticFeedback.selectionClick();
        },
        onPanStart: (_) {
          HapticFeedback.lightImpact();
          setState(() {
            _selectedClipId = clip.id;
            _draggingClipId = clip.id;
            _draggingStartTime = clip.startTime;
            _draggingEndTime = clip.endTime;
          });
        },
        onPanUpdate: (details) {
          if (_draggingClipId!= clip.id) return;
          final deltaMs = (details.delta.dx / maxWidth) * totalDuration;
          final newStart = _draggingStartTime!.inMilliseconds - deltaMs;
          final newEnd = _draggingEndTime!.inMilliseconds - deltaMs;

          if (newStart >= 0 && newEnd <= totalDuration && newEnd - newStart >= 500) {
            setState(() {
              _draggingStartTime = Duration(milliseconds: newStart.toInt());
              _draggingEndTime = Duration(milliseconds: newEnd.toInt());
            });
          }
        },
        onPanEnd: (_) {
          if (_draggingClipId == clip.id) {
            final newClip = clip.copyWith(
              startTime: _draggingStartTime,
              endTime: _draggingEndTime,
            );
            widget.onClipUpdated(newClip);
            setState(() {
              _draggingClipId = null;
              _draggingStartTime = null;
              _draggingEndTime = null;
            });
          }
        },
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: clip.color.withValues(alpha: isSelected? 1.0 : 0.8),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected? Colors.white : clip.color,
              width: isSelected? 3 : 2,
            ),
            boxShadow: isSelected? [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ] : null,
          ),
          child: Stack(
            children: [
              // سحب من اليسار = تغيير البداية
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  onPanStart: (_) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedClipId = clip.id;
                      _draggingClipId = clip.id;
                      _draggingStartTime = clip.startTime;
                      _draggingEndTime = clip.endTime;
                    });
                  },
                  onPanUpdate: (details) {
                    if (_draggingClipId!= clip.id) return;
                    final deltaMs = (details.delta.dx / maxWidth) * totalDuration;
                    final newStart = _draggingStartTime!.inMilliseconds - deltaMs;
                    final minDuration = 500;

                    if (newStart >= 0 && _draggingEndTime!.inMilliseconds - newStart >= minDuration) {
                      setState(() {
                        _draggingStartTime = Duration(milliseconds: newStart.toInt());
                      });
                    }
                  },
                  onPanEnd: (_) {
                    if (_draggingClipId == clip.id) {
                      final newClip = clip.copyWith(startTime: _draggingStartTime);
                      widget.onClipUpdated(newClip);
                      setState(() {
                        _draggingClipId = null;
                        _draggingStartTime = null;
                        _draggingEndTime = null;
                      });
                    }
                  },
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.3),
                    child: const Center(
                      child: Icon(Icons.drag_indicator, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),

              // اسم الفلتر بالنص
              if (width > 40)
                Center(
                  child: Text(
                    clip.filter.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              // سحب من اليمين = تغيير النهاية
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 20,
                child: GestureDetector(
                  onPanStart: (_) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedClipId = clip.id;
                      _draggingClipId = clip.id;
                      _draggingStartTime = clip.startTime;
                      _draggingEndTime = clip.endTime;
                    });
                  },
                  onPanUpdate: (details) {
                    if (_draggingClipId!= clip.id) return;
                    final deltaMs = (details.delta.dx / maxWidth) * totalDuration;
                    final newEnd = _draggingEndTime!.inMilliseconds - deltaMs;
                    final minDuration = 500;

                    if (newEnd <= totalDuration && newEnd - _draggingStartTime!.inMilliseconds >= minDuration) {
                      setState(() {
                        _draggingEndTime = Duration(milliseconds: newEnd.toInt());
                      });
                    }
                  },
                  onPanEnd: (_) {
                    if (_draggingClipId == clip.id) {
                      final newClip = clip.copyWith(endTime: _draggingEndTime);
                      widget.onClipUpdated(newClip);
                      setState(() {
                        _draggingClipId = null;
                        _draggingStartTime = null;
                        _draggingEndTime = null;
                      });
                    }
                  },
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.3),
                    child: const Center(
                      child: Icon(Icons.drag_indicator, size: 12, color: Colors.white),
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

  Color _getRandomColor() {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.pink,
      Colors.teal,
      Colors.amber,
    ];
    return colors[DateTime.now().millisecond % colors.length];
  }
}