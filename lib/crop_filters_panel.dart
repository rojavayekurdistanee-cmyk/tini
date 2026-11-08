import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'crop_color_filters.dart';

class CropFiltersPanel extends StatefulWidget {
  final CropFilterSelection initial;
  final List<Uint8List> thumbnails;
  final ValueChanged<CropFilterSelection> onPreview, onConfirm;
  final VoidCallback onCancel;
  const CropFiltersPanel({
    super.key,
    required this.initial,
    required this.thumbnails,
    required this.onPreview,
    required this.onConfirm,
    required this.onCancel,
  });
  @override
  State<CropFiltersPanel> createState() => _CropFiltersPanelState();
}

class _CropFiltersPanelState extends State<CropFiltersPanel> {
  late CropFilterSelection _selection;
  late String _category;
  final _list = ScrollController();
  @override
  void initState() {
    super.initState();
    _selection = widget.initial;
    _category =
        _selection.filter?.category ?? CropColorFilters.categories.first;
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  void _preview(CropFilterSelection value) {
    setState(() => _selection = value);
    widget.onPreview(value);
  }

  @override
  Widget build(BuildContext context) {
    final filters = CropColorFilters.all
        .where((f) => f.category == _category)
        .toList();
    final frame = widget.thumbnails.isEmpty
        ? null
        : widget.thumbnails[widget.thumbnails.length ~/ 2];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: const Color(0xFF1C1C1E),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 50,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'الأصل',
                      onPressed: () => _preview(const CropFilterSelection()),
                      icon: Icon(
                        Icons.block,
                        color: _selection.id == null
                            ? const Color(0xFF25F4EE)
                            : Colors.white,
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final category in CropColorFilters.categories)
                              InkWell(
                                onTap: () {
                                  setState(() => _category = category);
                                  if (_list.hasClients) _list.jumpTo(0);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: _category == category
                                            ? Colors.white
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    category,
                                    style: TextStyle(
                                      color: _category == category
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: _category == category
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'تأكيد الفلتر',
                      onPressed: () => widget.onConfirm(_selection),
                      icon: const Icon(Icons.check, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              SizedBox(
                height: 133,
                child: ListView.separated(
                  controller: _list,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  itemCount: filters.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final filter = filters[index];
                    final selected = _selection.id == filter.id;
                    return Semantics(
                      selected: selected,
                      button: true,
                      label: filter.name,
                      child: InkWell(
                        onTap: () => _preview(
                          CropFilterSelection(
                            id: filter.id,
                            intensity: _selection.id == null
                                ? .8
                                : _selection.intensity,
                          ),
                        ),
                        child: SizedBox(
                          width: 76,
                          child: Column(
                            children: [
                              Container(
                                width: 76,
                                height: 76,
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    width: 2,
                                    color: selected
                                        ? const Color(0xFF25F4EE)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CropFilterSelection(id: filter.id)
                                      .apply(
                                        frame == null
                                            ? const DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Color(0xFF80CED7),
                                                      Color(0xFFF4CF9A),
                                                      Color(0xFF704D43),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            : Image.memory(
                                                frame,
                                                fit: BoxFit.cover,
                                                gaplessPlayback: true,
                                                excludeFromSemantics: true,
                                              ),
                                      ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                filter.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: selected
                                      ? Colors.white
                                      : Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'إلغاء تغييرات الفلتر',
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _selection.intensity.clamp(0, 1).toDouble(),
                        label: '${(_selection.intensity * 100).round()}%',
                        onChanged: _selection.id == null
                            ? null
                            : (value) => _preview(
                                CropFilterSelection(
                                  id: _selection.id,
                                  intensity: value,
                                ),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      _selection.id == null
                          ? '0'
                          : '${(_selection.intensity * 100).round()}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
