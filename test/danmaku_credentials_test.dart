import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/utils/dandan_credentials.dart';

void main() {
  // The missing-credentials warning is logged, and the log sink needs bindings.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DanDanPlay credential gating', () {
    test(
      'isAvailable mirrors whether build-time credentials were injected',
      () {
        expect(DanmakuApi.isAvailable, hasDandanCredentials);
        expect(
          hasDandanCredentials,
          dandanCredentials['id']!.isNotEmpty &&
              dandanCredentials['value']!.isNotEmpty,
        );
      },
    );

    test(
      'requests are skipped instead of issued without credentials',
      () async {
        // Release/PR CI injects real credentials; only the local debug build is
        // missing them, and that is the case under test.
        if (hasDandanCredentials) return;

        expect(await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(123), 0);
        expect(await DanmakuApi.getDanDanmaku(456, 1), isEmpty);
        expect(await DanmakuApi.getDanDanmakuByEpisodeID(789), isEmpty);
        expect((await DanmakuApi.searchAnimes('test')).animes, isEmpty);
        final episodes = await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(1);
        expect(episodes.episodes, isEmpty);
        expect(episodes.bangumiId, 0);
      },
    );
  });
}
