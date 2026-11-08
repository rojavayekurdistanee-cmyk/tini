import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'text_layer.dart';

class TextEditorOverlay extends StatefulWidget {
  final File? videoFile;
  final AssetEntity? videoAsset;
  final File? imageFile; // جديد
  final AssetEntity? imageAsset; // جديد
  final bool isVideo; // جديد
  final List<TextLayer>? initialLayers;

  const TextEditorOverlay({
    super.key,
    this.videoFile,
    this.videoAsset,
    this.imageFile,
    this.imageAsset,
    required this.isVideo,
    this.initialLayers,
  });

  @override
  State<TextEditorOverlay> createState() => _TextEditorOverlayState();
}

class _TextEditorOverlayState extends State<TextEditorOverlay> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<TextLayer> _layers = [];
  int? _selectedIndex;
  int? _editingIndex;

  VideoPlayerController? _videoController;
  File? _imageFile; // جديد

  static const Color _surface = Color(0xFF1A222C);
  static const Color _titiTeal = Colors.teal;

  Color _selectedColor = Colors.white;
  String _selectedFont = 'Roboto';
  TextAlign _selectedAlign = TextAlign.center;
  bool _showFonts = false;
  bool _showColors = false;
  bool _showBgColors = false;

  Color? _selectedBgColor;
  double _selectedBgOpacity = 0.7;

  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  Offset _baseOffset = Offset.zero;

  final List<Color> _colors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    _titiTeal,
  ];

  final List<Color> _bgColors = [
    Colors.transparent,
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.pink,
  ];

  final List<String> _fonts = [
    'Roboto',
    'Serif',
    'Comic Sans',
    'Typewriter',
    'Classic',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialLayers!= null) {
      _layers.addAll(widget.initialLayers!);
    }

    // تهيئة الفيديو
    if (widget.isVideo) {
      if (widget.videoFile!= null) {
        _videoController = VideoPlayerController.file(widget.videoFile!)
         ..initialize().then((_) {
            setState(() {});
            _videoController?.setLooping(true);
            _videoController?.play();
          });
      } else if (widget.videoAsset!= null) {
        widget.videoAsset!.file.then((file) {
          if (file!= null && mounted) {
            _videoController = VideoPlayerController.file(file)
             ..initialize().then((_) {
                setState(() {});
                _videoController?.setLooping(true);
                _videoController?.play();
              });
          }
        });
      }
    }
    // تهيئة الصورة
    else {
      if (widget.imageFile!= null) {
        _imageFile = widget.imageFile;
      } else if (widget.imageAsset!= null) {
        widget.imageAsset!.file.then((file) {
          if (file!= null && mounted) {
            setState(() => _imageFile = file);
          }
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_layers.isEmpty) {
        _addNewLayer();
      } else {
        setState(() {
          _selectedIndex = 0;
          _startEditing(0);
        });
      }
    });
  }

  void _addNewLayer() {
    final size = MediaQuery.of(context).size;
    setState(() {
      _layers.add(TextLayer(
        text: '',
        color: _selectedColor,
        fontFamily: _selectedFont,
        align: _selectedAlign,
        x: size.width / 2,
        y: size.height / 2 - 100,
        backgroundColor: null,
        backgroundOpacity: 0.7,
      ));
      _selectedIndex = _layers.length - 1;
      _startEditing(_layers.length - 1);
    });
  }

  void _startEditing(int index) {
    setState(() {
      _editingIndex = index;
      _selectedIndex = index;
      _textController.text = _layers[index].text;
      _selectedColor = _layers[index].color;
      _selectedFont = _layers[index].fontFamily;
      _selectedAlign = _layers[index].align;
      _selectedBgColor = _layers[index].backgroundColor;
      _selectedBgOpacity = _layers[index].backgroundOpacity;
    });
    _focusNode.requestFocus();
  }

  void _stopEditing() {
    if (_editingIndex!= null) {
      _updateCurrentLayer();
      if (_textController.text.trim().isEmpty) {
        _textController.text = 'اكتب هنا';
        _updateCurrentLayer();
      }
    }
    setState(() {
      _editingIndex = null;
    });
    _focusNode.unfocus();
  }

  void _updateCurrentLayer() {
    if (_editingIndex == null) return;
    setState(() {
      _layers[_editingIndex!] = _layers[_editingIndex!].copyWith(
        text: _textController.text,
        color: _selectedColor,
        fontFamily: _selectedFont,
        align: _selectedAlign,
        backgroundColor: _selectedBgColor,
        setBackgroundColorToNull: _selectedBgColor == null,
        backgroundOpacity: _selectedBgOpacity,
      );
    });
  }

  void _deleteSelected() {
    if (_selectedIndex == null) return;
    setState(() {
      _layers.removeAt(_selectedIndex!);
      _editingIndex = null;
      _selectedIndex = _layers.isEmpty? null : 0;
      if (_selectedIndex!= null) {
        _textController.text = _layers[_selectedIndex!].text;
        _selectedAlign = _layers[_selectedIndex!].align;
        _selectedBgColor = _layers[_selectedIndex!].backgroundColor;
        _selectedBgOpacity = _layers[_selectedIndex!].backgroundOpacity;
      } else {
        _textController.clear();
      }
    });
  }

  void _toggleBackground() {
    if (_selectedIndex == null) return;
    setState(() {
      _showBgColors =!_showBgColors;
      _showFonts = false;
      _showColors = false;
    });
  }

  void _cycleBackgroundOpacity() {
    if (_selectedIndex == null || _selectedBgColor == null) return;
    setState(() {
      if (_selectedBgOpacity == 0.7) {
        _selectedBgOpacity = 1.0;
      } else if (_selectedBgOpacity == 1.0) {
        _selectedBgOpacity = 0.4;
      } else {
        _selectedBgOpacity = 0.7;
      }
      _updateCurrentLayer();
    });
  }

  double _getTextWidth(String text, String fontFamily, double fontSize, double scale) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text.isEmpty? ' ' : text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.width * scale;
  }

  void _cycleTextAlign() {
    if (_selectedIndex == null) return;
    final size = MediaQuery.of(context).size;
    const double margin = 24.0;
    final layer = _layers[_selectedIndex!];

    final textWidth = _getTextWidth(layer.text, layer.fontFamily, 32, layer.scale);
    final halfTextWidth = textWidth / 2;

    setState(() {
      _showFonts = false;
      _showColors = false;
      _showBgColors = false;

      if (_selectedAlign == TextAlign.left) {
        _selectedAlign = TextAlign.center;
        _layers[_selectedIndex!] = layer.copyWith(
          align: _selectedAlign,
          x: size.width / 2,
        );
      } else if (_selectedAlign == TextAlign.center) {
        _selectedAlign = TextAlign.right;
        final newX = (size.width - margin - halfTextWidth).clamp(halfTextWidth + margin, size.width - margin - halfTextWidth);
        _layers[_selectedIndex!] = layer.copyWith(
          align: _selectedAlign,
          x: newX,
        );
      } else {
        _selectedAlign = TextAlign.left;
        final newX = (margin + halfTextWidth).clamp(margin + halfTextWidth, size.width - margin - halfTextWidth);
        _layers[_selectedIndex!] = layer.copyWith(
          align: _selectedAlign,
          x: newX,
        );
      }
    });
  }

  IconData _getAlignIcon() {
    switch (_selectedAlign) {
      case TextAlign.left:
        return Icons.format_align_left;
      case TextAlign.right:
        return Icons.format_align_right;
      case TextAlign.center:
      default:
        return Icons.format_align_center;
    }
  }

  IconData _getBgIcon() {
    if (_selectedBgColor == null || _selectedBgColor == Colors.transparent) {
      return Icons.format_color_reset;
    } else if (_selectedBgOpacity == 1.0) {
      return Icons.format_color_fill;
    } else {
      return Icons.opacity;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: () {
          _stopEditing();
          setState(() => _selectedIndex = null);
        },
        child: Stack(
          children: [
            // الخلفية: فيديو أو صورة
            if (widget.isVideo)
              _videoController!= null && _videoController!.value.isInitialized
                 ? Positioned.fill(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoController!.value.size.width,
                          height: _videoController!.value.size.height,
                          child: VideoPlayer(_videoController!),
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator())
            else if (_imageFile!= null)
              Positioned.fill(
                child: Image.file(
                  _imageFile!,
                  fit: BoxFit.cover,
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),

           ..._layers.asMap().entries.map((entry) {
              final index = entry.key;
              final layer = entry.value;
              final isSelected = _selectedIndex == index;
              final isEditing = _editingIndex == index;
              final hasBg = layer.backgroundColor!= null && layer.backgroundColor!= Colors.transparent;

              return Positioned(
                left: layer.x,
                top: layer.y,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      _startEditing(index);
                    },
                    onDoubleTap: () {
                      setState(() {
                        _layers[index] = layer.copyWith(scale: 1.0, rotation: 0.0);
                      });
                    },
                    onScaleStart:!isEditing
                       ? (details) {
                            _baseScale = layer.scale;
                            _baseRotation = layer.rotation;
                            _baseOffset = Offset(layer.x, layer.y);
                            setState(() => _selectedIndex = index);
                          }
                        : null,
                    onScaleUpdate:!isEditing
                       ? (details) {
                            setState(() {
                              final newScale = (_baseScale * details.scale).clamp(0.3, 5.0);
                              final newRotation = _baseRotation + details.rotation;
                              final delta = details.focalPointDelta;

                              _layers[index] = layer.copyWith(
                                x: _baseOffset.dx + delta.dx,
                                y: _baseOffset.dy + delta.dy,
                                scale: newScale,
                                rotation: newRotation,
                              );
                              _baseOffset = Offset(_layers[index].x, _layers[index].y);
                            });
                          }
                        : null,
                    onScaleEnd:!isEditing
                       ? (details) {
                            _baseScale = _layers[index].scale;
                            _baseRotation = _layers[index].rotation;
                            _baseOffset = Offset(_layers[index].x, _layers[index].y);
                          }
                        : null,
                    child: Transform.scale(
                      scale: layer.scale,
                      child: Transform.rotate(
                        angle: layer.rotation,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isEditing? 12 : 40,
                            vertical: isEditing? 8 : 40
                          ),
                          decoration: BoxDecoration(
                            border: isSelected? Border.all(color: _titiTeal, width: 1.5) : null,
                            color: hasBg
                           ? layer.backgroundColor!.withValues(alpha:layer.backgroundOpacity)
                              : Colors.transparent,
                            borderRadius: hasBg? BorderRadius.circular(12) : null,
                          ),
                          child: isEditing
                          ? IntrinsicWidth(
                                  child: TextField(
                                    controller: _textController,
                                    focusNode: _focusNode,
                                    autofocus: true,
                                    maxLines: null,
                                    onChanged: (_) => _updateCurrentLayer(),
                                    onSubmitted: (_) => _stopEditing(),
                                    textAlign: layer.align,
                                    style: TextStyle(
                                      color: layer.color,
                                      fontFamily: layer.fontFamily,
                                      fontSize: 32,
                                      shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                      contentPadding: EdgeInsets.zero,
                                      filled: true,
                                      fillColor: Colors.transparent,
                                    ),
                                  ),
                                )
                              : Text(
                                  layer.text.isEmpty? 'اكتب هنا' : layer.text,
                                  textAlign: layer.align,
                                  style: TextStyle(
                                    color: layer.text.isEmpty? Colors.white54 : layer.color,
                                    fontFamily: layer.fontFamily,
                                    fontSize: 32,
                                    shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(102),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        _stopEditing();
                        final finalLayers = _layers.where((l) => l.text.trim().isNotEmpty && l.text!= 'اكتب هنا').toList();
                        Navigator.pop(context, finalLayers);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _surface.withAlpha(153),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'تم',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _topIcon(Icons.delete, _deleteSelected),
                        _topIcon(_getAlignIcon(), _cycleTextAlign),
                        _topIcon(_getBgIcon(), _toggleBackground),
                        _topIcon(Icons.format_size, () {
                          setState(() {
                            _showFonts =!_showFonts;
                            _showColors = false;
                            _showBgColors = false;
                          });
                        }),
                        _topIcon(Icons.palette, () {
                          setState(() {
                            _showColors =!_showColors;
                            _showFonts = false;
                            _showBgColors = false;
                          });
                        }),
                        _topIcon(Icons.text_fields, _addNewLayer),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (_showFonts)
              Positioned(
                bottom: bottomInset,
                left: 0,
                right: 0,
                child: Container(
                  height: 44,
                  color: Colors.black.withAlpha(204),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _fonts.length,
                    itemBuilder: (context, index) {
                      final font = _fonts[index];
                      final isSelected = _selectedFont == font;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedFont = font);
                          _updateCurrentLayer();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _surface.withAlpha(153),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected? Colors.white : Colors.white24,
                              width: isSelected? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              font,
                              style: TextStyle(
                                color: isSelected? Colors.white : Colors.white70,
                                fontFamily: font,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            if (_showColors)
              Positioned(
                bottom: bottomInset,
                left: 0,
                right: 0,
                child: Container(
                  height: 50,
                  color: Colors.black.withAlpha(204),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    itemCount: _colors.length,
                    itemBuilder: (context, index) {
                      final color = _colors[index];
                      final isSelected = _selectedColor == color;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedColor = color);
                          _updateCurrentLayer();
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected? _titiTeal : Colors.white,
                              width: isSelected? 3 : 1.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            if (_showBgColors)
              Positioned(
                bottom: bottomInset,
                left: 0,
                right: 0,
                child: Container(
                  height: 90,
                  color: Colors.black.withAlpha(204),
                  child: Column(
                    children: [
                      Container(
                        height: 40,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: _cycleBackgroundOpacity,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _surface.withAlpha(153),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.opacity, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'الشفافية: ${(_selectedBgOpacity * 100).toInt()}%',
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          itemCount: _bgColors.length,
                          itemBuilder: (context, index) {
                            final color = _bgColors[index];
                            final isSelected = _selectedBgColor == color;
                            final isTransparent = color == Colors.transparent;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedBgColor = color == Colors.transparent? null : color;
                                  _updateCurrentLayer();
                                });
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected? _titiTeal : Colors.white,
                                    width: isSelected? 3 : 1.5,
                                  ),
                                ),
                                child: isTransparent
                                 ? const Icon(Icons.block, color: Colors.white54, size: 20)
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _surface.withAlpha(153),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}