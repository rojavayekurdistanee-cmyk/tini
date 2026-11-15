import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:titi_star/banner_video_navigation.dart';
import 'package:titi_star/video_playback_handoff.dart';

class PlaybackDriver implements BannerVideoPlaybackDriver {
  @override
  final operations = VideoPlaybackQueue();
  final opened = <VideoPlaybackSnapshot>[];
  Future<void>? pendingVideoOpen;
  @override
  String? viewer = 'viewer';
  @override
  bool canPlay(String url) => true;
  @override
  VideoPlaybackBookmarks captureBookmarks() =>
      const VideoPlaybackBookmarks(homeUrl: 'home');
  @override
  VideoPlaybackSnapshot capture(VideoPlaybackOrigin origin) =>
      VideoPlaybackSnapshot(
        engine: origin.engine,
        url: origin.url,
        playing: false,
      );
  @override
  Future<void> restoreBookmarks(
    VideoPlaybackBookmarks bookmarks, {
    required bool sameViewer,
  }) async {}
  @override
  Future<void> silence() async {}
  @override
  Future<void> silenceHome() async {}
  @override
  Future<void> open(
    VideoPlaybackSnapshot snapshot,
    bool Function() valid,
  ) async {
    if (snapshot.url == 'notification') await pendingVideoOpen;
    if (valid()) opened.add(snapshot);
  }
}

void main() {
  for (final lateHome in [false, true]) {
    testWidgets(
      'cold launch restores autoplay with ${lateHome ? 'late' : 'ready'} Home',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        final driver = PlaybackDriver();
        final owner = Object();
        var homeVisible = true;
        void registerHome() => VideoPlaybackRegistry.watch(
          owner,
          () => VideoPlaybackOrigin(
            engine: VideoPlaybackEngine.home,
            url: 'home',
            postId: 'home-post',
            isVisible: () => homeVisible,
          ),
        );
        addTearDown(() => VideoPlaybackRegistry.unwatch(owner));
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Home')),
          ),
        );
        var reserved = false;
        final navigation = BannerVideoNavigation.open(
          navigator: navigator.currentState!,
          url: 'notification',
          playback: driver,
          prepareColdStart: () async {
            reserved =
                !VideoPlaybackRegistry.allowsHome('home') &&
                VideoPlaybackRegistry.allowsHome('notification');
            if (!lateHome) registerHome();
          },
          onPushed: () {
            homeVisible = false;
            if (lateHome) registerHome();
          },
          child: const Scaffold(body: Text('Notification video')),
        );
        await tester.pumpAndSettle();
        expect(reserved, isTrue);
        expect(find.text('Notification video'), findsOneWidget);
        expect(driver.opened.map((s) => s.url), ['notification']);
        // Counter/rebuild frames must neither restart nor pause the owned video.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(seconds: 2));
        }
        expect(driver.opened.length, 1);
        homeVisible = true;
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await navigation;
        expect(driver.opened.last.url, 'home');
        expect(driver.opened.last.playing, isTrue);
        expect(VideoPlaybackRegistry.foregroundBanner, isNull);
      },
    );
  }

  testWidgets('Back during slow cold video open restores only Home', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final pending = Completer<void>();
    final driver = PlaybackDriver()..pendingVideoOpen = pending.future;
    final owner = Object();
    var homeVisible = true;
    VideoPlaybackRegistry.watch(
      owner,
      () => VideoPlaybackOrigin(
        engine: VideoPlaybackEngine.home,
        url: 'home',
        postId: 'home-post',
        isVisible: () => homeVisible,
      ),
    );
    addTearDown(() => VideoPlaybackRegistry.unwatch(owner));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    final navigation = BannerVideoNavigation.open(
      navigator: navigator.currentState!,
      url: 'notification',
      playback: driver,
      prepareColdStart: () async {},
      onPushed: () => homeVisible = false,
      child: const Scaffold(body: Text('Notification video')),
    );
    await tester.pumpAndSettle();
    homeVisible = true;
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    await navigation;
    expect(driver.opened.map((s) => s.url), ['home']);
    expect(driver.opened.single.playing, isTrue);
    expect(VideoPlaybackRegistry.foregroundBanner, isNull);
  });

  testWidgets('account change cancels cold video activation and restoration', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final driver = PlaybackDriver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    final navigation = BannerVideoNavigation.open(
      navigator: navigator.currentState!,
      url: 'notification',
      playback: driver,
      prepareColdStart: () async {
        driver.viewer = 'another-viewer';
      },
      onPushed: () => fail('must not push for the previous viewer'),
      child: const Scaffold(body: Text('Notification video')),
    );
    await tester.pumpAndSettle();
    await navigation;
    expect(driver.opened, isEmpty);
    expect(VideoPlaybackRegistry.foregroundBanner, isNull);
  });
}
