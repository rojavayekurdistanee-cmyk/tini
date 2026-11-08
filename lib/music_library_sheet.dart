import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'music_provider.dart';
import 'auth_provider.dart' as custom;
import 'package:cached_network_image/cached_network_image.dart';

// دالة مساعدة لتنسيق الوقت من الملي ثانية إلى mm:ss
String formatDuration(int durationMs) {
  int totalSeconds = (durationMs / 1000).toInt();
  int minutes = totalSeconds ~/ 60;
  int seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class MusicWaveformIndicator extends StatefulWidget {
  const MusicWaveformIndicator({Key? key}) : super(key: key);
  @override
  State<MusicWaveformIndicator> createState() => _MusicWaveformIndicatorState();
}

class _MusicWaveformIndicatorState extends State<MusicWaveformIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this)..repeat(reverse: true);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildWaveBar(heightFactor: 0.3 + (_controller.value * 0.7)),
            const SizedBox(width: 2),
            _buildWaveBar(heightFactor: 0.1 + ((1.0 - _controller.value) * 0.9)),
            const SizedBox(width: 2),
            _buildWaveBar(heightFactor: 0.5 + (_controller.value * 0.5)),
            const SizedBox(width: 2),
            _buildWaveBar(heightFactor: 0.2 + ((1.0 - _controller.value) * 0.6)),
          ],
        );
      },
    );
  }
  Widget _buildWaveBar({required double heightFactor}) {
    return Container(width: 3, height: 16 * heightFactor.clamp(0.1, 1.0), decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(1.5)));
  }
}

void showMusicSheet({
  required BuildContext context,
  required Function(Map<String, dynamic> selectedTrack) onTrackSelected,
}) {
  final PlayerController sheetPlayerController = PlayerController();
  final TextEditingController searchController = TextEditingController();
  String? playingUrl;

  final musicProvider = Provider.of<MusicProvider>(context, listen: false);
  final authProvider = Provider.of<custom.AuthProvider>(context, listen: false);
  
  musicProvider.fetchTrending();
  musicProvider.fetchLatest();
  musicProvider.fetchRecommended();
  musicProvider.fetchFavorites(authProvider.uid);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0F1720),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      return Consumer<MusicProvider>(
        builder: (context, provider, child) {
          // [إضافة] التحقق إذا كان هناك نص في البحث
          bool isSearching = searchController.text.isNotEmpty;

          return DefaultTabController(
            length: 4,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
              child: Column(
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 15),
                  const TabBar(
                    indicatorColor: Colors.teal,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    tabs: [Tab(text: 'المشهور'), Tab(text: 'مقترح'), Tab(text: 'المفضلات'), Tab(text: 'الأحدث')],
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: searchController,
                    // [إضافة] الربط مع الـ Provider للبحث لحظياً
                    onChanged: (value) {
                      provider.searchTracks(value);
                    },
                    decoration: InputDecoration(
                      hintText: 'بحث عن أصوات...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    // [تعديل] إذا كان هناك بحث نعرض نتائج البحث، وإلا نعرض التابات الافتراضية
                    child: isSearching 
                    ? _buildTrackList(provider.searchResults, provider.isLoadingSearch, playingUrl, (url) => playingUrl = url, sheetPlayerController, onTrackSelected, context, provider, authProvider)
                    : TabBarView(
                      children: [
                        _buildTrackList(provider.trendingTracks, provider.isLoadingTrending, playingUrl, (url) => playingUrl = url, sheetPlayerController, onTrackSelected, context, provider, authProvider),
                        _buildTrackList(provider.recommendedTracks, provider.isLoadingRecommended, playingUrl, (url) => playingUrl = url, sheetPlayerController, onTrackSelected, context, provider, authProvider),
                        _buildTrackList(provider.favoriteTracks, provider.isLoadingFavorites, playingUrl, (url) => playingUrl = url, sheetPlayerController, onTrackSelected, context, provider, authProvider),
                        _buildTrackList(provider.latestTracks, provider.isLoadingLatest, playingUrl, (url) => playingUrl = url, sheetPlayerController, onTrackSelected, context, provider, authProvider),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() {
    sheetPlayerController.dispose();
    searchController.dispose();
  });
}

// دالة لبناء قائمة الأغاني بشكل موحد
Widget _buildTrackList(
  List<Map<String, dynamic>> tracks, 
  bool isLoading, 
  String? playingUrl, 
  Function(String?) onPlayToggle,
  PlayerController playerController,
  Function(Map<String, dynamic>) onTrackSelected,
  BuildContext context,
  MusicProvider provider,
  custom.AuthProvider authProvider
) {
  if (isLoading) return const Center(child: CircularProgressIndicator(color: Colors.teal));
  if (tracks.isEmpty) return const Center(child: Text("لا توجد أصوات", style: TextStyle(color: Colors.white54)));

  return ListView.builder(
    itemCount: tracks.length,
    itemBuilder: (context, index) {
      final track = tracks[index];
      bool isCurrent = playingUrl == track['url'];
      bool isFavorite = provider.favoriteTracks.any((t) => t['url'] == track['url']);

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isCurrent ? Colors.teal.withValues(alpha:0.1) : const Color(0xFF1A222C),
          borderRadius: BorderRadius.circular(10),
          border: isCurrent ? Border.all(color: Colors.teal.withValues(alpha:0.5)) : null
        ),
        child: ListTile(
          onTap: () async {
            if (playingUrl == track['url']) {
              await playerController.pausePlayer();
              onPlayToggle(null);
            } else {
              await playerController.preparePlayer(path: track['url'], shouldExtractWaveform: false);
              await playerController.startPlayer();
              onPlayToggle(track['url']);
            }
          },
                    leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(imageUrl: track['cover']?? '', width: 50, height: 50, fit: BoxFit.cover, placeholder: (c, u) => Container(width: 50, height: 50, color: Colors.white10), errorWidget: (c, u, e) => Container(width: 50, height: 50, color: Colors.white10, child: const Icon(Icons.music_note, color: Colors.white24))),
          ),
          title: Text(track['title'] ?? 'عنوان غير معروف', style: const TextStyle(color: Colors.white)),
          subtitle: Text("${track['artist'] ?? 'مستخدم'} • ${formatDuration(track['duration'] ?? 0)}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.white54,
                ),
                onPressed: () {
                  provider.toggleFavorite(authProvider.uid, track);
                },
              ),
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.teal, size: 30),
                onPressed: () {
                  onTrackSelected(track);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}