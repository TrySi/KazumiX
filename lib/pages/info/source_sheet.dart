import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/compact_source_selector.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/repositories/bangumi_offline_cache_repository.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/roads/road_episode_availability.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/captcha_verification_service.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/utils/m3u8_parser.dart';
import 'package:url_launcher/url_launcher.dart';

part 'source_alias_dialog.dart';
part 'source_captcha_flow.dart';
part 'source_sheet_view.dart';

class SourceSheet extends StatefulWidget {
  const SourceSheet({
    super.key,
    required this.infoController,
    this.downloadMode = false,
  });

  final InfoController infoController;
  final bool downloadMode;

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<SourceSheet> {
  /// Process-wide cache of search / roads / latency / format per show, so
  /// reopening the play or download sheet reuses the last discovery instead of
  /// re-running every source query. Limited to the most recent few shows.
  static final Map<int, _SourceDiscovery> _discoveryCache = {};
  static const int _maxCachedShows = 12;

  final CollectController _collectController = inject<CollectController>();
  final DownloadController _downloadController = inject<DownloadController>();
  final PluginsController _pluginsController = inject<PluginsController>();
  final Map<String, String> _sourceKeywords = {};
  final Map<String, _SourceRoadCache> _roadCache = {};
  final Set<String> _emptySourceKeys = {};
  final Set<RuleCancelToken> _sourcePreflightTokens = {};
  final Map<String, Duration> _sourceLatency = {};
  final Map<String, String?> _roadFormats = {};
  final Map<String, String?> _roadQuality = {};
  final Set<String> _sourceHasMp4 = {};
  WebViewVideoSourceService? _videoSourceService;

  late final String _keyword;
  late final PluginSearchService _searchService;
  late final _SourceCaptchaFlow _captchaFlow;
  late final Future<void> _episodeLoad;
  List<EpisodeInfo> _releasedEpisodes = [];
  String? _selectedSourceKey;
  _SourceSearchOption? _selectedSourceOption;
  List<Road> _selectedSourceRoads = [];
  List<_SourceRoadOption> _roadOptions = [];
  int? _selectedRoadIndex;
  bool _episodesLoading = true;
  bool _roadsLoading = false;
  bool _sourceOptionsLoading = false;
  bool _sourcePreflightScheduled = false;
  int _roadRequestGeneration = 0;
  RuleCancelToken? _roadCancelToken;

  @override
  void initState() {
    super.initState();
    final item = widget.infoController.bangumiItem;
    _keyword = item.nameCn.isEmpty ? item.name : item.nameCn;
    _searchService = PluginSearchService(
      infoController: widget.infoController,
      pluginsController: _pluginsController,
    );
    _captchaFlow = _SourceCaptchaFlow(
      onVerified: _showVerifiedResult,
      onCancelled: (plugin) => _retry(plugin.name),
    );
    _episodeLoad = _loadReleasedEpisodes();
    if (!_restoreDiscoveryCache(item.id)) {
      _searchService.queryAllSource(_keyword);
    }
  }

  bool _restoreDiscoveryCache(int bangumiId) {
    final cached = _discoveryCache[bangumiId];
    if (cached == null || cached.keyword != _keyword) return false;
    final controller = widget.infoController;
    controller.pluginSearchResponseList
      ..clear()
      ..addAll(cached.searchResponses);
    controller.pluginSearchStatus
      ..clear()
      ..addAll(cached.searchStatus);
    _roadCache.addAll(cached.roadCache);
    _sourceLatency.addAll(cached.sourceLatency);
    _roadFormats.addAll(cached.roadFormats);
    _roadQuality.addAll(cached.roadQuality);
    _sourceHasMp4.addAll(cached.sourceHasMp4);
    _emptySourceKeys.addAll(cached.emptySourceKeys);
    return true;
  }

  @override
  void dispose() {
    _roadRequestGeneration++;
    _roadCancelToken?.cancel();
    for (final token in _sourcePreflightTokens) {
      token.cancel();
    }
    _searchService.cancel();
    _captchaFlow.dispose();
    unawaited(_videoSourceService?.dispose());

    final bangumiId = widget.infoController.bangumiItem.id;
    final controller = widget.infoController;
    if (controller.pluginSearchResponseList.isNotEmpty) {
      _discoveryCache.remove(bangumiId);
      _discoveryCache[bangumiId] = _SourceDiscovery(
        keyword: _keyword,
        searchResponses: List.of(controller.pluginSearchResponseList),
        searchStatus: Map.of(controller.pluginSearchStatus),
        roadCache: Map.of(_roadCache),
        sourceLatency: Map.of(_sourceLatency),
        roadFormats: Map.of(_roadFormats),
        roadQuality: Map.of(_roadQuality),
        sourceHasMp4: Set.of(_sourceHasMp4),
        emptySourceKeys: Set.of(_emptySourceKeys),
      );
      if (_discoveryCache.length > _maxCachedShows) {
        _discoveryCache.remove(_discoveryCache.keys.first);
      }
    }
    super.dispose();
  }

  String _keywordFor(String name) => _sourceKeywords[name] ?? _keyword;

  Plugin _pluginFor(String name) =>
      _pluginsController.pluginList.firstWhere((plugin) => plugin.name == name);

  void _querySource(String keyword, String pluginName) {
    final trimmed = keyword.trim();
    if (!mounted || trimmed.isEmpty) return;
    setState(() => _sourceKeywords[pluginName] = trimmed);
    _searchService.querySource(trimmed, pluginName);
  }

  void _retry(String name) => _querySource(_keywordFor(name), name);

  Future<void> _loadReleasedEpisodes() async {
    final cache = BangumiOfflineCacheRepository();
    final bangumiId = widget.infoController.bangumiItem.id;
    final cachedEpisodes = cache.readEpisodes(bangumiId);
    if (cachedEpisodes != null) {
      setState(() {
        _releasedEpisodes = releasedMainEpisodes(cachedEpisodes);
        _episodesLoading = false;
      });
      if (!cache.isFresh('episodes:$bangumiId', const Duration(hours: 12))) {
        unawaited(_refreshReleasedEpisodes(cache, bangumiId));
      }
      return;
    }

    await _refreshReleasedEpisodes(cache, bangumiId);
  }

  Future<void> _refreshReleasedEpisodes(
    BangumiOfflineCacheRepository cache,
    int bangumiId,
  ) async {
    try {
      final episodes = await BangumiApi.getBangumiEpisodesByID(bangumiId);
      if (!mounted) return;
      if (episodes.isNotEmpty) {
        await cache.writeEpisodes(bangumiId, episodes);
      }
      final releasedEpisodes = releasedMainEpisodes(episodes);
      setState(() {
        if (releasedEpisodes.isNotEmpty || _releasedEpisodes.isEmpty) {
          _releasedEpisodes = releasedEpisodes;
        }
        _episodesLoading = false;
      });
      if (releasedEpisodes.isNotEmpty) _refreshCachedRoadMatches();
    } catch (error) {
      KazumiLogger().w(
        'SourceSheet: failed to load released episodes',
        error: error,
      );
      if (mounted) setState(() => _episodesLoading = false);
    }
  }

  void _refreshCachedRoadMatches() {
    for (final key in _roadCache.keys.toList()) {
      final cached = _roadCache[key]!;
      final refreshed = _buildRoadCache(cached.roads);
      if (refreshed == null) {
        _roadCache.remove(key);
        continue;
      }
      _roadCache[key] = refreshed;
    }
    final selectedKey = _selectedSourceKey;
    final refreshed = selectedKey == null ? null : _roadCache[selectedKey];
    setState(() {
      if (refreshed == null) return;
      _selectedSourceRoads = refreshed.roads;
      _roadOptions = refreshed.options;
      if (!_roadOptions.any((option) => option.index == _selectedRoadIndex)) {
        _selectedRoadIndex = _roadOptions.first.index;
      }
    });
  }

  _SourceRoadCache? _buildRoadCache(List<Road> roads) {
    final roadOptions = [
      for (var index = 0; index < roads.length; index++)
        if (roads[index].data.isNotEmpty)
          _SourceRoadOption(
            index: index,
            road: roads[index],
            matches: matchRoadEpisodes(
              _releasedEpisodes,
              road: roads[index],
              roadIndex: index,
            ),
          ),
    ].where((roadOption) => roadOption.matches.isNotEmpty).toList();
    if (roadOptions.isEmpty) return null;
    return _SourceRoadCache(roads: roads, options: roadOptions);
  }

  void _scheduleSourcePreflight(List<_SourceSearchOption> options) {
    final pendingOptions = options
        .where(
          (option) =>
              !_roadCache.containsKey(option.key) &&
              !_emptySourceKeys.contains(option.key),
        )
        .toList();
    if (_sourcePreflightScheduled || pendingOptions.isEmpty) return;
    _sourcePreflightScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_preflightSources(pendingOptions));
    });
  }

  Future<void> _preflightSources(List<_SourceSearchOption> options) async {
    if (!mounted) return;
    setState(() => _sourceOptionsLoading = true);
    var nextIndex = 0;

    Future<void> loadNext() async {
      while (nextIndex < options.length && mounted) {
        final option = options[nextIndex++];
        if (_roadCache.containsKey(option.key) ||
            _emptySourceKeys.contains(option.key)) {
          continue;
        }
        final token = RuleCancelToken();
        _sourcePreflightTokens.add(token);
        try {
          await _episodeLoad;
          if (!mounted) return;
          final stopwatch = Stopwatch()..start();
          final roads = await option.plugin.queryChapterRoads(
            option.item.src,
            cancelToken: token,
          );
          stopwatch.stop();
          if (!mounted) return;
          _sourceLatency[option.key] = stopwatch.elapsed;
          final cache = _buildRoadCache(roads);
          if (cache == null) {
            _emptySourceKeys.add(option.key);
          } else {
            _roadCache[option.key] = cache;
          }
        } catch (error) {
          _emptySourceKeys.add(option.key);
          KazumiLogger().w(
            'SourceSheet: failed to preflight source ${option.plugin.name}',
            error: error,
          );
        } finally {
          _sourcePreflightTokens.remove(token);
          if (mounted) setState(() {});
        }
      }
    }

    final workerCount = options.length < 3 ? options.length : 3;
    await Future.wait(List.generate(workerCount, (_) => loadNext()));
    if (!mounted) return;
    setState(() {
      _sourceOptionsLoading = false;
      _sourcePreflightScheduled = false;
    });
  }

  Future<bool> _selectSource(
    _SourceSearchOption option, {
    bool showFailureToast = true,
  }) async {
    final generation = ++_roadRequestGeneration;
    _roadCancelToken?.cancel();
    setState(() {
      _selectedSourceKey = option.key;
      _selectedSourceOption = option;
      _selectedSourceRoads = [];
      _roadOptions = [];
      _selectedRoadIndex = null;
      _roadsLoading = true;
    });

    try {
      await _episodeLoad;
      if (!mounted || generation != _roadRequestGeneration) return false;

      var cached = _roadCache[option.key];
      if (cached == null) {
        final cancelToken = RuleCancelToken();
        _roadCancelToken = cancelToken;
        final stopwatch = Stopwatch()..start();
        final roads = await option.plugin.queryChapterRoads(
          option.item.src,
          cancelToken: cancelToken,
        );
        stopwatch.stop();
        _sourceLatency[option.key] = stopwatch.elapsed;
        if (!mounted || generation != _roadRequestGeneration) return false;
        cached = _buildRoadCache(roads);
        if (cached == null) {
          _emptySourceKeys.add(option.key);
          throw ChapterErrorException(option.plugin.name);
        }
        _roadCache[option.key] = cached;
      }

      if (generation != _roadRequestGeneration) return false;
      setState(() {
        _selectedSourceRoads = cached!.roads;
        _roadOptions = cached.options;
        _selectedRoadIndex = cached.options.first.index;
        _roadsLoading = false;
      });
      unawaited(_detectRoadFormat(cached.options.first.index));
      return true;
    } catch (error) {
      if (generation == _roadRequestGeneration && mounted) {
        setState(() => _roadsLoading = false);
        KazumiLogger().w(
          'SourceSheet: failed to query episode roads',
          error: error,
        );
        if (showFailureToast) {
          KazumiDialog.showToast(message: '未能获取有效播放列表，请选择其他来源');
        }
      }
      return false;
    }
  }

  Future<void> _openSearchManager(
    BuildContext context,
    List<_SourceSearchGroup> groups,
    List<_SourceSearchOption> options,
  ) async {
    final firstResultSource = groups
        .firstWhereOrNull((group) => group.hasResults)
        ?.name;
    await showAdaptiveBottomSheet<void>(
      context: context,
      maxHeightFactor: 0.88,
      builder: (managerContext) => _SourceSheetView(
        keyword: _keyword,
        downloadMode: widget.downloadMode,
        groups: groups,
        firstResultSource: firstResultSource,
        onSourceSearch: _showCustomKeyword,
        onSourceAliasSearch: _showAliasPicker,
        onRetry: _retry,
        onVerify: (name) =>
            _captchaFlow.start(_pluginFor(name), _keywordFor(name)),
        onOpenBrowser: _openInBrowser,
        onPlay: (name, item) {
          final option = options.firstWhereOrNull(
            (candidate) =>
                candidate.plugin.name == name && candidate.item.src == item.src,
          );
          if (option == null) return;
          unawaited(
            _selectSource(option, showFailureToast: false).then((loaded) {
              if (loaded && managerContext.mounted) {
                Navigator.of(managerContext).pop();
              }
            }),
          );
        },
        onClose: () => Navigator.of(managerContext).pop(),
      ),
    );
  }

  Future<void> _startDownloads(
    Set<int> selectedEpisodeNumbers,
    Map<int, RoadEpisodeMatch> matches,
  ) async {
    final source = _selectedSourceOption;
    if (source == null) return;

    final alreadyDownloaded = _downloadController
        .activeOrCompletedEpisodeNumbers(widget.infoController.bangumiItem.id);
    final episodesByNumber = {
      for (final episode in _releasedEpisodes) episode.episode.toInt(): episode,
    };
    var addedCount = 0;
    for (final episodeNumber in selectedEpisodeNumbers.toList()..sort()) {
      final match = matches[episodeNumber];
      final episode = episodesByNumber[episodeNumber];
      if (match == null || episode == null) continue;
      if (alreadyDownloaded.contains(episodeNumber)) continue;
      await _downloadController.startDownload(
        bangumiId: widget.infoController.bangumiItem.id,
        bangumiName: widget.infoController.bangumiItem.nameCn.isNotEmpty
            ? widget.infoController.bangumiItem.nameCn
            : widget.infoController.bangumiItem.name,
        bangumiCover: widget.infoController.bangumiItem.images['large'] ?? '',
        pluginName: source.plugin.name,
        episodeNumber: episodeNumber,
        episodeName: episode.nameCn.isNotEmpty ? episode.nameCn : match.title,
        road: match.roadIndex,
        episodePageUrl: match.pageUrl,
      );
      addedCount++;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    KazumiDialog.showToast(
      message: addedCount > 0
          ? '已添加 $addedCount 集到下载队列，可在下载管理中查看'
          : '所选集数均已下载或已在队列中',
    );
  }

  void _showVerifiedResult(Plugin plugin, String pageHtml) {
    if (!mounted) return;
    if (_searchService.applyHarvestedSearchResult(plugin.name, pageHtml)) {
      KazumiDialog.showToast(message: '验证成功');
      return;
    }
    _captchaFlow.showSuccess(
      plugin.name,
      onComplete: () => _retry(plugin.name),
    );
  }

  Future<void> _openInBrowser(String name) async {
    final plugin = _pluginFor(name);
    final targetUrl = plugin.usesApiSearch
        ? plugin.baseUrl
        : plugin.searchURL.replaceAll(
            '@keyword',
            Uri.encodeQueryComponent(_keywordFor(name)),
          );
    try {
      if (await launchUrl(
        Uri.parse(targetUrl),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (error) {
      KazumiLogger().w('SourceSheet: failed to open browser', error: error);
    }
    if (mounted) KazumiDialog.showToast(message: '无法打开浏览器，请稍后重试');
  }

  /// Detects the media format (MP4 / HLS) of a road's first available episode
  /// so the road list can label it. Detection is cached per road and runs only
  /// when the road is selected, keeping the cost off the source preflight.
  Future<void> _detectRoadFormat(int roadIndex) async {
    final sourceKey = _selectedSourceKey;
    if (sourceKey == null) return;
    final formatKey = '$sourceKey#$roadIndex';
    if (_roadFormats.containsKey(formatKey)) return;
    final source = _selectedSourceOption;
    if (source == null) return;
    final road = _roadOptions.firstWhereOrNull(
      (option) => option.index == roadIndex,
    );
    if (road == null) return;
    final firstUrl = road.road.data.firstWhere(
      (url) => url.isNotEmpty,
      orElse: () => '',
    );
    if (firstUrl.isEmpty) return;

    final fullUrl = source.plugin.buildFullUrl(firstUrl);
    try {
      final service = _videoSourceService ??= WebViewVideoSourceService();
      final resolved = await service.resolve(
        fullUrl,
        useLegacyParser: source.plugin.useLegacyParser,
      );
      final url = resolved.url.toLowerCase();
      String? format;
      String? quality;
      if (url.contains('.mp4')) {
        format = 'MP4';
        quality = await _detectMp4Quality(resolved.url);
      } else if (url.contains('.m3u8')) {
        format = 'HLS';
        quality = await _detectM3u8Quality(resolved.url);
      }
      if (mounted) {
        setState(() {
          _roadFormats[formatKey] = format;
          _roadQuality[formatKey] = quality;
          if (format == 'MP4') {
            _sourceHasMp4.add(sourceKey);
          }
        });
      }
    } catch (error) {
      KazumiLogger().w(
        'SourceSheet: failed to detect road format',
        error: error,
      );
    }
  }

  /// Fetches an m3u8 and, when it is a master playlist, returns a short
  /// quality label like `1080p · 5.0Mbps`. Returns null when the playlist is
  /// media-only or the fetch fails.
  Future<String?> _detectM3u8Quality(String url) async {
    try {
      final content = await DownloadHttpClient.instance.getPlain(url);
      if (M3u8Parser.detectType(content) != M3u8Type.master) return null;
      final master = M3u8Parser.parseMasterPlaylist(content, url);
      if (master.variants.isEmpty) return null;
      final best = master.bestVariant;
      final parts = <String>[];
      final resolution = best.resolution;
      if (resolution != null && resolution.isNotEmpty) {
        parts.add(_shortResolution(resolution));
      }
      if (best.bandwidth > 0) {
        parts.add(_shortBandwidth(best.bandwidth));
      }
      return parts.isEmpty ? null : parts.join(' · ');
    } catch (error) {
      KazumiLogger().w(
        'SourceSheet: failed to read m3u8 quality',
        error: error,
      );
      return null;
    }
  }

  /// Probes the first megabytes of an MP4, parsing the `moov` box to read
  /// resolution (`tkhd`) and, when the total size is known, the bitrate
  /// (`mvhd` duration + `Content-Range` total). Returns null when the `moov`
  /// box is not at the front (non-faststart) or parsing fails.
  Future<String?> _detectMp4Quality(String url) async {
    try {
      final range = await DownloadHttpClient.instance.getRangeBytes(url);
      if (range == null) return null;
      final moov = _findBox(range.bytes, 'moov', maxDepth: 0);
      if (moov == null) return null;

      final parts = <String>[];
      final tkhd = _findBox(moov, 'tkhd');
      if (tkhd != null) {
        final dimensions = _parseTkhdDimensions(tkhd);
        if (dimensions != null) {
          parts.add('${dimensions.$1}x${dimensions.$2}');
          parts.add(_shortResolution('${dimensions.$1}x${dimensions.$2}'));
        }
      }

      final mvhd = _findBox(moov, 'mvhd');
      final totalSize = range.totalSize;
      if (mvhd != null && totalSize != null) {
        final duration = _parseMvhdDurationSeconds(mvhd);
        if (duration != null && duration > 0) {
          final bitrate = (totalSize * 8 / duration).round();
          parts.add(_shortBandwidth(bitrate));
        }
      }
      return parts.isEmpty ? null : parts.join(' · ');
    } catch (error) {
      KazumiLogger().w('SourceSheet: failed to read mp4 quality', error: error);
      return null;
    }
  }

  /// Walks MP4 boxes looking for [type]; [maxDepth] limits container recursion.
  Uint8List? _findBox(Uint8List bytes, String type, {int maxDepth = 3}) {
    var offset = 0;
    while (offset + 8 <= bytes.length) {
      final size = _readUint32(bytes, offset);
      final boxType = _readType(bytes, offset + 4);
      var headerSize = 8;
      if (size == 1) headerSize = 16;
      final boxSize = size == 0 ? bytes.length - offset : size;
      if (boxSize < headerSize) break;
      final payloadStart = offset + headerSize;
      final payloadEnd = (offset + boxSize).clamp(0, bytes.length);
      if (payloadEnd <= payloadStart) break;

      if (boxType == type) {
        return bytes.sublist(payloadStart, payloadEnd);
      }
      if (maxDepth > 0) {
        final found = _findBox(
          bytes.sublist(payloadStart, payloadEnd),
          type,
          maxDepth: maxDepth - 1,
        );
        if (found != null) return found;
      }
      offset += boxSize;
    }
    return null;
  }

  (int, int)? _parseTkhdDimensions(Uint8List tkhd) {
    if (tkhd.length < 4) return null;
    final version = tkhd[0];
    final widthOffset = version == 1 ? 88 : 76;
    if (tkhd.length < widthOffset + 8) return null;
    final width = _readUint32(tkhd, widthOffset) / 65536.0;
    final height = _readUint32(tkhd, widthOffset + 4) / 65536.0;
    if (width <= 0 || height <= 0) return null;
    return (width.round(), height.round());
  }

  double? _parseMvhdDurationSeconds(Uint8List mvhd) {
    if (mvhd.length < 4) return null;
    final version = mvhd[0];
    if (version == 1) {
      if (mvhd.length < 32) return null;
      final timescale = _readUint32(mvhd, 20);
      final duration = _readUint64(mvhd, 24);
      if (timescale == 0) return null;
      return duration / timescale;
    }
    if (mvhd.length < 24) return null;
    final timescale = _readUint32(mvhd, 12);
    final duration = _readUint32(mvhd, 16);
    if (timescale == 0) return null;
    return duration / timescale;
  }

  int _readUint32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint32(offset);

  int _readUint64(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint64(offset);

  String _readType(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(offset, offset + 4));
  }

  String _shortResolution(String resolution) {
    final match = RegExp(
      r'x(\d+)',
      caseSensitive: false,
    ).firstMatch(resolution);
    if (match == null) return resolution;
    final height = int.tryParse(match.group(1)!);
    if (height == null) return resolution;
    if (height >= 2160) return '4K';
    if (height >= 1440) return '2K';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 480) return '480p';
    return '${height}p';
  }

  String _shortBandwidth(int bandwidth) {
    if (bandwidth >= 1000000) {
      return '${(bandwidth / 1000000).toStringAsFixed(1)}Mbps';
    }
    return '${(bandwidth / 1000).round()}Kbps';
  }

  Future<void> _selectCombined(String combinedKey) async {
    final separator = combinedKey.indexOf('#');
    if (separator <= 0) return;
    final sourceKey = combinedKey.substring(0, separator);
    final roadIndex = int.tryParse(combinedKey.substring(separator + 1));
    if (roadIndex == null) return;
    final cache = _roadCache[sourceKey];
    if (cache == null) return;
    final option = _selectedSourceOption;
    if (option == null || option.key != sourceKey) {
      final source = _sourceOptionsByKey(sourceKey);
      if (source == null) return;
      _selectedSourceOption = source;
    }
    setState(() {
      _selectedSourceKey = sourceKey;
      _selectedSourceRoads = cache.roads;
      _roadOptions = cache.options;
      _selectedRoadIndex = roadIndex;
    });
    unawaited(_detectRoadFormat(roadIndex));
  }

  _SourceSearchOption? _sourceOptionsByKey(String key) {
    // Rebuild from the plugin search responses (same data used in build()).
    for (final response in widget.infoController.pluginSearchResponseList) {
      for (final item in response.data) {
        final plugin = _pluginFor(response.pluginName);
        final option = _SourceSearchOption(plugin: plugin, item: item);
        if (option.key == key) return option;
      }
    }
    return null;
  }

  void _playEpisode(
    _SourceSearchOption source,
    _SourceRoadOption road,
    RoadEpisodeMatch match,
  ) {
    final formats = <int, String?>{};
    final qualities = <int, String?>{};
    for (final option in _roadOptions) {
      final key = '${source.key}#${option.index}';
      formats[option.index] = _roadFormats[key];
      qualities[option.index] = _roadQuality[key];
    }

    context.pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: widget.infoController.bangumiItem,
        plugin: source.plugin,
        title: source.item.name,
        src: source.item.src,
        roads: _selectedSourceRoads,
        initialEpisode: match.episodeIndex,
        initialRoad: road.index,
        resumeHistory: false,
        roadFormats: formats,
        roadQuality: qualities,
        sourceLatency: _sourceLatency[source.key],
      ),
    );
  }

  void _showAliasPicker(String pluginName) {
    if (widget.infoController.bangumiItem.alias.isEmpty) {
      KazumiDialog.showToast(message: '无可用别名，试试修改检索关键词');
      return;
    }
    _showAliasPickerDialog(
      sourceName: pluginName,
      aliases: widget.infoController.bangumiItem.alias,
      onAliasSelected: (alias) => _querySource(alias, pluginName),
      onAliasesChanged: () => _collectController.updateLocalCollect(
        widget.infoController.bangumiItem,
      ),
    );
  }

  void _showCustomKeyword(String pluginName) => _showCustomKeywordDialog(
    initialKeyword: _keywordFor(pluginName),
    sourceName: pluginName,
    onSubmit: (keyword) {
      final item = widget.infoController.bangumiItem;
      if (!item.alias.contains(keyword)) {
        item.alias.add(keyword);
        _collectController.updateLocalCollect(item);
      }
      _querySource(keyword, pluginName);
    },
  );

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) {
      // Snapshot observable values here; lazy list builders are not tracked.
      final groupsByName = {
        for (final plugin in _pluginsController.pluginList)
          plugin.name: _SourceSearchGroup(
            name: plugin.name,
            keyword: _keywordFor(plugin.name),
            status:
                widget.infoController.pluginSearchStatus[plugin.name] ??
                PluginSearchStatus.pending,
            results: <SearchItem>[],
          ),
      };
      final seenBySource = <String, Set<String>>{};
      // Responses follow completion order; groups keep configured order.
      for (final response in widget.infoController.pluginSearchResponseList) {
        final group = groupsByName[response.pluginName];
        if (group == null) continue;
        final seen = seenBySource.putIfAbsent(group.name, () => <String>{});
        for (final result in response.data) {
          if (seen.add(result.src)) group.results.add(result);
        }
      }
      final optionsByKey = <String, _SourceSearchOption>{};
      for (final response in widget.infoController.pluginSearchResponseList) {
        if (!_pluginsController.pluginList.any(
          (plugin) => plugin.name == response.pluginName,
        )) {
          continue;
        }
        for (final item in response.data) {
          if (item.src.isEmpty) continue;
          final option = _SourceSearchOption(
            plugin: _pluginFor(response.pluginName),
            item: item,
          );
          optionsByKey.putIfAbsent(option.key, () => option);
        }
      }
      final options = optionsByKey.values
          .where((option) => !_emptySourceKeys.contains(option.key))
          .toList();
      final searchPending = groupsByName.values.any(
        (group) => group.isSearching,
      );
      if (!searchPending && !_episodesLoading) {
        _scheduleSourcePreflight(options);
      }
      final availableOptions =
          options.where((option) => _roadCache.containsKey(option.key)).toList()
            ..sort((a, b) {
              final aLatency = _sourceLatency[a.key];
              final bLatency = _sourceLatency[b.key];
              if (aLatency == null && bLatency == null) return 0;
              if (aLatency == null) return 1;
              if (bLatency == null) return -1;
              return aLatency.compareTo(bLatency);
            });
      final selectedSource = availableOptions.firstWhereOrNull(
        (option) => option.key == _selectedSourceKey,
      );
      if (availableOptions.isNotEmpty &&
          selectedSource == null &&
          !_roadsLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_roadsLoading) {
            unawaited(
              _selectSource(availableOptions.first, showFailureToast: false),
            );
          }
        });
      }
      final groups = groupsByName.values.toList();
      final selectedRoad = _roadOptions.firstWhereOrNull(
        (option) => option.index == _selectedRoadIndex,
      );

      final combinedOptions = <_CombinedOption>[];
      for (final sourceOption in availableOptions) {
        final cache = _roadCache[sourceOption.key];
        if (cache == null) continue;
        for (final roadOption in cache.options) {
          final combinedKey = '${sourceOption.key}#${roadOption.index}';
          combinedOptions.add(
            _CombinedOption(
              key: combinedKey,
              sourceName: sourceOption.item.name,
              pluginName: sourceOption.plugin.name,
              roadName: roadOption.road.name,
              episodeCount: roadOption.matches.length,
              latency: _sourceLatency[sourceOption.key],
              format: _roadFormats[combinedKey],
              quality: _roadQuality[combinedKey],
            ),
          );
        }
      }
      final selectedCombinedKey =
          _selectedSourceKey != null && _selectedRoadIndex != null
          ? '$_selectedSourceKey#$_selectedRoadIndex'
          : null;

      return _EpisodeSourceSheetView(
        downloadMode: widget.downloadMode,
        combinedOptions: combinedOptions,
        selectedCombinedKey: selectedCombinedKey,
        episodes: _releasedEpisodes,
        matches: selectedRoad?.matches ?? const {},
        downloadedEpisodes: _downloadController.activeOrCompletedEpisodeNumbers(
          widget.infoController.bangumiItem.id,
        ),
        episodesLoading: _episodesLoading,
        roadsLoading: _roadsLoading,
        searchPending: searchPending,
        sourceOptionsLoading:
            searchPending ||
            _episodesLoading ||
            _sourceOptionsLoading ||
            _sourcePreflightScheduled,
        onCombinedSelected: (key) => unawaited(_selectCombined(key)),
        onEpisodeSelected: (episode, match) {
          final road = selectedRoad;
          if (selectedSource != null && road != null) {
            _playEpisode(selectedSource, road, match);
          }
        },
        onDownloadSelected: (numbers) =>
            _startDownloads(numbers, selectedRoad?.matches ?? const {}),
        onManageSources: () => _openSearchManager(context, groups, options),
        onClose: () => Navigator.of(context).pop(),
      );
    },
  );
}

class _SourceSearchOption {
  const _SourceSearchOption({required this.plugin, required this.item});

  final Plugin plugin;
  final SearchItem item;

  String get key => '${plugin.name}\u0000${item.src}';
  String get label => '${plugin.name} · ${item.name}';
}

class _SourceRoadOption {
  const _SourceRoadOption({
    required this.index,
    required this.road,
    required this.matches,
  });

  final int index;
  final Road road;
  final Map<int, RoadEpisodeMatch> matches;
}

class _SourceRoadCache {
  const _SourceRoadCache({required this.roads, required this.options});

  final List<Road> roads;
  final List<_SourceRoadOption> options;
}

class _CombinedOption {
  const _CombinedOption({
    required this.key,
    required this.sourceName,
    required this.pluginName,
    required this.roadName,
    required this.episodeCount,
    this.latency,
    this.format,
    this.quality,
  });

  final String key;
  final String sourceName;
  final String pluginName;
  final String roadName;
  final int episodeCount;
  final Duration? latency;
  final String? format;
  final String? quality;
}

class _SourceDiscovery {
  const _SourceDiscovery({
    required this.keyword,
    required this.searchResponses,
    required this.searchStatus,
    required this.roadCache,
    required this.sourceLatency,
    required this.roadFormats,
    required this.roadQuality,
    required this.sourceHasMp4,
    required this.emptySourceKeys,
  });

  final String keyword;
  final List<PluginSearchResponse> searchResponses;
  final Map<String, PluginSearchStatus> searchStatus;
  final Map<String, _SourceRoadCache> roadCache;
  final Map<String, Duration> sourceLatency;
  final Map<String, String?> roadFormats;
  final Map<String, String?> roadQuality;
  final Set<String> sourceHasMp4;
  final Set<String> emptySourceKeys;
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}
