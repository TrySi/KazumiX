import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazumi/bean/widget/compact_source_selector.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';

Road _road(String name, int episodes) => Road(
  name: name,
  data: List.generate(
    episodes,
    (index) => 'https://example.com/$name/${index + 1}',
  ),
  identifier: List.generate(episodes, (index) => '第${index + 1}话'),
);

Widget _host({
  required List<Road> roads,
  required int selectedRoad,
  bool isPlaying = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EpisodeSelectionPanel(
        title: '测试番剧',
        roads: roads,
        selectedRoad: selectedRoad,
        selectedEpisode: 1,
        downloads: const {},
        isOffline: true,
        isPlaying: isPlaying,
        onEpisodeSelected: (_, _) {},
      ),
    ),
  );
}

void main() {
  final roads = <Road>[_road('爱丽丝线路', 3), _road('贝拉线路', 2), _road('卡罗尔线路', 4)];

  testWidgets('follows the playback line when something else switches it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(roads: roads, selectedRoad: 0));
    expect(find.text('爱丽丝线路'), findsOneWidget);

    // Playback moved to another line without a tap on the selector.
    await tester.pumpWidget(_host(roads: roads, selectedRoad: 2));
    expect(find.text('卡罗尔线路'), findsOneWidget);
    expect(find.text('爱丽丝线路'), findsNothing);
  });

  testWidgets('keeps the browsed line across rebuilds of the same line', (
    tester,
  ) async {
    await tester.pumpWidget(_host(roads: roads, selectedRoad: 0));

    await tester.tap(find.byType(CompactSourceSelector<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('卡罗尔线路'));
    await tester.pumpAndSettle();
    expect(find.text('卡罗尔线路'), findsOneWidget);

    // A playback update rebuilds the panel without switching the line.
    await tester.pumpWidget(
      _host(roads: roads, selectedRoad: 0, isPlaying: true),
    );
    expect(find.text('卡罗尔线路'), findsOneWidget);
  });
}
