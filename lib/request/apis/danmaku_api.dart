import 'package:kazumi/modules/danmaku/danmaku_ch_convert.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/dandan_credentials.dart';

class DanmakuApi {
  static final DanmakuClient _client = DanmakuClient.instance;

  static bool _warnedUnavailable = false;

  /// Whether DanDanPlay requests can be signed in this build.
  static bool get isAvailable => hasDandanCredentials;

  /// Returns true when the caller must skip the request. Warns once so the
  /// missing build-time credentials are obvious in the logs.
  static bool _skipUnavailable() {
    if (hasDandanCredentials) return false;
    if (!_warnedUnavailable) {
      _warnedUnavailable = true;
      KazumiLogger().w(
        'Danmaku: DANDANAPI_APPID/DANDANAPI_KEY missing at build time, '
        'danmaku requests are disabled',
      );
    }
    return true;
  }

  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    if (_skipUnavailable()) return 0;
    final path = ApiEndpoints.formatUrl(
      ApiEndpoints.dandanAPIInfoByBgmBangumiId,
      [bgmBangumiID],
    );
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData).bangumiId;
  }

  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
    int bangumiID,
  ) async {
    if (_skipUnavailable()) return DanmakuEpisodeResponse.fromTemplate();
    final path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData);
  }

  // v2 episode search avoids the anime search's 25-result cap.
  // Fetch full episode lists separately; search results can truncate them.
  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    if (_skipUnavailable()) {
      return const DanmakuSearchResponse(animes: [], hasMore: false);
    }
    final endPoint =
        ApiEndpoints.dandanAPIDomain + ApiEndpoints.dandanAPISearchEpisodes;
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {'anime': title, 'v2': 'true'},
    );
    return DanmakuSearchResponse.fromJson(jsonData);
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
    int bangumiID,
    int episode,
  ) async {
    if (bangumiID == 0 || _skipUnavailable()) {
      return [];
    }
    // Automatic matching relies on an undocumented episode ID convention.
    return _getComments('$bangumiID${episode.toString().padLeft(4, '0')}');
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(int episodeID) =>
      _getComments(episodeID.toString());

  static Future<List<DanmakuEntry>> _getComments(String episodeID) async {
    if (_skipUnavailable()) return [];
    final endPoint =
        '${ApiEndpoints.dandanAPIDomain}${ApiEndpoints.dandanAPIComment}$episodeID';
    final conversion = DanmakuChConvert.fromValue(
      GStorage.getSetting(SettingsKeys.danmakuChConvert),
    );
    KazumiLogger().i('Danmaku: final request URL $endPoint');
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {
        'withRelated': 'true',
        'chConvert': conversion.value.toString(),
      },
    );
    final List<dynamic> comments = jsonData['comments'];
    return [for (final comment in comments) DanmakuEntry.fromJson(comment)];
  }
}
