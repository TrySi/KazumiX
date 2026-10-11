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
import 'package:kazumi/request/apis/bangumi_api.dart';
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
  final CollectController _collectController = inject<CollectController>();
  final DownloadController _downloadController = inject<DownloadController>();
  final PluginsController _pluginsController = inject<PluginsController>();
  final Map<String, String> _sourceKeywords = {};
  final Map<String, _SourceRoadCache> _roadCache = {};
  final Set<String> _emptySourceKeys = {};
  final Set<RuleCancelToken> _sourcePreflightTokens = {};

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
    _searchService.queryAllSource(_keyword);
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
          final roads = await option.plugin.queryChapterRoads(
            option.item.src,
            cancelToken: token,
          );
          if (!mounted) return;
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
        final roads = await option.plugin.queryChapterRoads(
          option.item.src,
          cancelToken: cancelToken,
        );
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

  void _playEpisode(
    _SourceSearchOption source,
    _SourceRoadOption road,
    RoadEpisodeMatch match,
  ) {
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
      final availableOptions = options
          .where((option) => _roadCache.containsKey(option.key))
          .toList();
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

      return _EpisodeSourceSheetView(
        downloadMode: widget.downloadMode,
        sourceOptions: availableOptions,
        selectedSourceKey: selectedSource?.key,
        roadOptions: _roadOptions,
        selectedRoadIndex: selectedRoad?.index,
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
        onSourceSelected: (key) {
          final option = options.firstWhereOrNull((item) => item.key == key);
          if (option != null) unawaited(_selectSource(option));
        },
        onRoadSelected: (index) => setState(() => _selectedRoadIndex = index),
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
