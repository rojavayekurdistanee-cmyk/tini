import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'video_reactions_service.dart';

// [Tini - Owner Reactions Overlay] - حركة محلية على يسار فيديو صاحب الحساب فقط.
class VideoReactionsOverlay extends StatefulWidget {
  final String postId;
  final bool isActive;
  // [Tini - Owner Reactions Overlay] - انتقال مباشر للبروفايل الكامل أو التعليق المحدد.
  final ValueChanged<String> onProfileTap;
  final ValueChanged<String> onCommentTap;

  const VideoReactionsOverlay({
    super.key,
    required this.postId,
    required this.isActive,
    required this.onProfileTap,
    required this.onCommentTap,
  });

  @override
  State<VideoReactionsOverlay> createState() => _VideoReactionsOverlayState();
}

class _ActiveReaction {
  final int id;
  final VideoReaction reaction;
  final Duration duration;

  const _ActiveReaction(this.id, this.reaction, this.duration);
}

class _VideoReactionsOverlayState extends State<VideoReactionsOverlay> {
  final VideoReactionsService _service = VideoReactionsService();
  final math.Random _random = math.Random();
  final List<_ActiveReaction> _visible = [];
  final Map<int, Timer> _removalTimers = {};
  List<VideoReaction> _reactions = [];
  Timer? _timer;
  int _cursor = 0;
  int _serial = 0;
  int _loadGeneration = 0;
  int _displayGeneration = 0;
  bool _hasLoaded = false;
  bool _isLoading = false;

  // نفس مسافة الحركة لجميع الفقاعات؛ تتغير المدة فتتغير السرعة بشكل طبيعي.
  static const double _travelDistance = 249.0;
  // حد أدنى محافظ للمسافة العمودية بين فقاعتين أثناء حركتهما.
  static const double _safeSeparation = 50.0;

  // إيقاف المؤقتات القديمة ومنعها من إظهار فقاعات بعد تغيير الفيديو أو إيقاف العرض.
  void _stopAndClear() {
    _timer?.cancel();
    _timer = null;
    for (final timer in _removalTimers.values) {
      timer.cancel();
    }
    _removalTimers.clear();
    _displayGeneration++;
    _visible.clear();
  }

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(covariant VideoReactionsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      _loadGeneration++;
      _stopAndClear();
      _cursor = 0;
      _hasLoaded = false;
      _isLoading = false;
      _reactions = [];
      if (widget.isActive) _load();
    } else if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        if (_hasLoaded) {
          _cursor = 0;
          _start();
        } else if (!_isLoading) {
          _load();
        }
      } else {
        _stopAndClear();
        _cursor = 0;
      }
    }
  }

  Future<void> _load() async {
    if (_isLoading) return;
    _isLoading = true;
    final generation = ++_loadGeneration;
    _stopAndClear();
    _cursor = 0;
    try {
      // تُقرأ بيانات Firebase مرة واحدة؛ كل الدورات اللاحقة تستخدم نفس القائمة.
      final data = await _service.getReactions(widget.postId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _reactions = data;
        _hasLoaded = true;
      });
      if (widget.isActive) _start();
    } catch (error) {
      // فشل جلب التفاعلات لا يعطّل تشغيل الفيديو أو بقية واجهته.
      debugPrint('[Tini Overlay] Failed to load reactions: $error');
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _reactions = [];
          _hasLoaded = true;
        });
      }
    } finally {
      if (generation == _loadGeneration) _isLoading = false;
    }
  }

  // زمن متغير لكل فقاعة، بدون أي استعلام جديد أو مؤقت دوري سريع.
  Duration _randomDuration() =>
      Duration(milliseconds: 4800 + _random.nextInt(1401));

  // حساب فاصل آمن حسب سرعتي الفقاعتين: حتى الأسرع لا تلحق الأبطأ.
  Duration _safeNextDelay(Duration current, Duration next) {
    final currentMs = current.inMilliseconds.toDouble();
    final nextMs = next.inMilliseconds.toDouble();
    final currentSpeed = _travelDistance / currentMs;
    final nextSpeed = _travelDistance / nextMs;

    var requiredMs = _safeSeparation / currentSpeed;
    if (nextSpeed > currentSpeed) {
      requiredMs = math.max(
        requiredMs,
        (_safeSeparation + (nextSpeed - currentSpeed) * currentMs) /
            nextSpeed,
      );
    }

    // اختلاف صغير بالفواصل يجعل العرض طبيعياً، مع الحفاظ على مسافة الأمان.
    final variedMs = requiredMs.ceil() + 80 + _random.nextInt(451);
    return Duration(milliseconds: math.min(variedMs, current.inMilliseconds + 100));
  }

  void _start() {
    _timer?.cancel();
    _timer = null;
    if (!widget.isActive || _reactions.isEmpty || _cursor >= _reactions.length) {
      return;
    }
    _showNext(_randomDuration());
  }

  void _showNext(Duration duration) {
    if (!mounted || !widget.isActive || _reactions.isEmpty) return;
    if (_cursor >= _reactions.length) return;

    final item = _ActiveReaction(++_serial, _reactions[_cursor], duration);
    _cursor++;
    final displayGeneration = _displayGeneration;
    setState(() {
      _visible.add(item);
    });

    // إزالة العنصر بعد انتهاء حركته، وليس بعد وقت ثابت يخالف سرعته.
    _removalTimers[item.id] = Timer(
      duration + const Duration(milliseconds: 80),
      () {
        _removalTimers.remove(item.id);
        if (!mounted || displayGeneration != _displayGeneration) return;
        setState(() => _visible.removeWhere((element) => element.id == item.id));

        // الدورة التالية تبدأ بعد اختفاء آخر فقاعة، بلا تكرار متداخل لنفس الشخص.
        if (widget.isActive && _cursor >= _reactions.length && _visible.isEmpty) {
          _timer?.cancel();
          _timer = Timer(
            Duration(milliseconds: 650 + _random.nextInt(701)),
            () {
              if (!mounted || !widget.isActive ||
                  displayGeneration != _displayGeneration) return;
              _cursor = 0;
              _start();
            },
          );
        }
      },
    );

    if (_cursor < _reactions.length) {
      final nextDuration = _randomDuration();
      _timer?.cancel();
      _timer = Timer(_safeNextDelay(duration, nextDuration), () {
        if (!mounted || !widget.isActive ||
            displayGeneration != _displayGeneration) return;
        _showNext(nextDuration);
      });
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _stopAndClear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // الـ Stack شفّاف للمس خارج الفقاعات: يبقى التحكم بالفيديو كما كان.
    return Stack(
      children: [
        for (final item in _visible)
          Positioned.fill(
            // المفتاح لازم يكون على عنصر Stack المباشر حتى لا يُعاد تشغيل
            // أنيميشن الفقاعة عند حذف فقاعة سابقة من القائمة.
            key: ValueKey(item.id),
            child: _FloatingReactionBubble(
              reaction: item.reaction,
              duration: item.duration,
              baseBottom: MediaQuery.sizeOf(context).height * 0.32,
              onProfileTap: widget.onProfileTap,
              onCommentTap: widget.onCommentTap,
            ),
          ),
      ],
    );
  }
}

class _FloatingReactionBubble extends StatefulWidget {
  final VideoReaction reaction;
  final Duration duration;
  final double baseBottom;
  final ValueChanged<String> onProfileTap;
  final ValueChanged<String> onCommentTap;
  const _FloatingReactionBubble({
    super.key,
    required this.reaction,
    required this.duration,
    required this.baseBottom,
    required this.onProfileTap,
    required this.onCommentTap,
  });

  @override
  State<_FloatingReactionBubble> createState() => _FloatingReactionBubbleState();
}

class _FloatingReactionBubbleState extends State<_FloatingReactionBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _moveY;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 58),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
    // المسار ثابت، لكن مدة الحركة تتغير، فيتغير الإحساس بالسرعة بين الفقاعات.
    _moveY = Tween<double>(begin: 24.0, end: -225.0)
        .animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reaction = widget.reaction;
    final hasComment = reaction.comment != null && reaction.comment!.isNotEmpty;
    final imageUrl = reaction.userImage;
    // نحرك موقع الفقاعة الحقيقي، مو الرسم فقط، حتى منطقة الضغط تتبعها طوال الحركة.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Stack(
        children: [
          Positioned(
            left: 12,
            bottom: widget.baseBottom - _moveY.value,
            child: Opacity(
              opacity: _opacity.value.clamp(0.0, 1.0).toDouble(),
              child: child,
            ),
          ),
        ],
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          constraints: BoxConstraints(maxWidth: hasComment ? 246 : 48),
          padding: EdgeInsets.symmetric(horizontal: hasComment ? 8 : 2, vertical: hasComment ? 6 : 2),
          decoration: BoxDecoration(
            color: hasComment ? Colors.black.withValues(alpha: 0.57) : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // الضغط على الصورة يفتح ProfileScreen الكامل، وليس UserProfileSheet.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: reaction.uid.isNotEmpty
                    ? () => widget.onProfileTap(reaction.uid)
                    : null,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: const Color(0xFF29343F),
                      backgroundImage: imageUrl.startsWith('http')
                          ? CachedNetworkImageProvider(imageUrl)
                          : null,
                      child: imageUrl.startsWith('http')
                          ? null
                          : const Icon(Icons.person, color: Colors.white70, size: 22),
                    ),
                    if (reaction.isLiked)
                      const Positioned(
                        right: -3,
                        bottom: -3,
                        child: Icon(Icons.favorite, color: Color(0xFFE53935), size: 18,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 4)]),
                      ),
                  ],
                ),
              ),
              if (hasComment) ...[
                const SizedBox(width: 9),
                Flexible(
                  // الضغط على النص والاسم يفتح الشيت على معرّف التعليق نفسه.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: reaction.commentId != null && reaction.commentId!.isNotEmpty
                        ? () => widget.onCommentTap(reaction.commentId!)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(reaction.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        Text(reaction.comment!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
