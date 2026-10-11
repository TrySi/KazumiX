part of 'source_sheet.dart';

class _SourceSearchGroup {
  const _SourceSearchGroup({
    required this.name,
    required this.keyword,
    required this.status,
    required this.results,
  });

  final String name;
  final String keyword;
  final PluginSearchStatus status;
  final List<SearchItem> results;

  bool get isSearching => status == PluginSearchStatus.pending;
  bool get hasResults =>
      status == PluginSearchStatus.success && results.isNotEmpty;

  String get statusLabel => switch (status) {
    PluginSearchStatus.pending => '检索中…',
    PluginSearchStatus.success =>
      results.isEmpty ? '无结果' : '${results.length} 个结果',
    PluginSearchStatus.noResult => '无结果',
    PluginSearchStatus.error => '检索失败',
    PluginSearchStatus.captcha => '需要验证',
  };
}

enum _SourceDisplay { preview, expanded, collapsed }

class _SourceSheetView extends StatefulWidget {
  const _SourceSheetView({
    required this.keyword,
    required this.downloadMode,
    required this.groups,
    required this.firstResultSource,
    required this.onSourceSearch,
    required this.onSourceAliasSearch,
    required this.onRetry,
    required this.onVerify,
    required this.onOpenBrowser,
    required this.onPlay,
    required this.onClose,
  });

  final String keyword;
  final bool downloadMode;
  final List<_SourceSearchGroup> groups;
  final String? firstResultSource;
  final ValueChanged<String> onSourceSearch;
  final ValueChanged<String> onSourceAliasSearch;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onVerify;
  final ValueChanged<String> onOpenBrowser;
  final void Function(String sourceName, SearchItem result) onPlay;
  final VoidCallback onClose;

  @override
  State<_SourceSheetView> createState() => _SourceSheetViewState();
}

class _SourceSheetViewState extends State<_SourceSheetView> {
  final _scrollController = ScrollController();
  final _display = <String, _SourceDisplay>{};
  final _headerKeys = <String, GlobalKey>{};
  bool _autoExpansionHandled = false;

  @override
  void initState() {
    super.initState();
    _autoExpandFirstResult();
  }

  @override
  void didUpdateWidget(covariant _SourceSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = widget.groups.map((group) => group.name).toSet();
    _display.removeWhere((name, _) => !names.contains(name));
    _headerKeys.removeWhere((name, _) => !names.contains(name));
    _autoExpandFirstResult();
  }

  void _autoExpandFirstResult() {
    final name = widget.firstResultSource;
    if (_autoExpansionHandled || name == null) return;
    _autoExpansionHandled = true;
    _display[name] = _SourceDisplay.preview;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setDisplay(String name, _SourceDisplay display) {
    setState(() {
      _autoExpansionHandled = true;
      _display[name] = display;
    });
  }

  void _collapseFromFooter(String name) {
    final headerContext = _headerKeys[name]?.currentContext;
    if (headerContext != null) {
      // Anchor before shrinking, while the header is still laid out.
      Scrollable.ensureVisible(headerContext, alignment: 0);
    }
    _setDisplay(name, _SourceDisplay.collapsed);
  }

  Widget _animateSize(Widget child) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: splitListMotionDuration,
          curve: splitListMotionCurve,
          alignment: Alignment.topCenter,
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    final pending = widget.groups.where((group) => group.isSearching).length;
    final resultCount = widget.groups
        .where((group) => group.hasResults)
        .fold(0, (sum, group) => sum + group.results.length);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          MaterialBottomSheetHeader(
            title: widget.downloadMode ? '下载来源' : '播放来源',
            description: pending > 0
                ? '检索中 ${widget.groups.length - pending}/${widget.groups.length} · $resultCount 个结果'
                : '${widget.groups.length} 个来源 · $resultCount 个结果',
            compact: true,
            onClose: widget.onClose,
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  if (widget.groups.isEmpty)
                    const SliverToBoxAdapter(
                      child: GeneralEmptyState(
                        icon: Icons.extension_rounded,
                        title: '请先在规则管理中添加来源',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverList.builder(
                        itemCount: widget.groups.length,
                        findChildIndexCallback: (key) {
                          final index = widget.groups.indexWhere(
                            (group) => ValueKey(group.name) == key,
                          );
                          return index < 0 ? null : index;
                        },
                        itemBuilder: (context, index) {
                          final group = widget.groups[index];
                          return Padding(
                            key: ValueKey(group.name),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildSourceGroup(group),
                          );
                        },
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: SafeArea(top: false, child: SizedBox(height: 24)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceGroup(_SourceSearchGroup group) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final display = _display[group.name] ?? _SourceDisplay.collapsed;
    final collapsed = display == _SourceDisplay.collapsed;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : splitListMotionDuration;

    void toggle() => _setDisplay(
      group.name,
      collapsed ? _SourceDisplay.preview : _SourceDisplay.collapsed,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: _headerKeys.putIfAbsent(group.name, GlobalKey.new),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  button: true,
                  expanded: !collapsed,
                  label: '来源规则：${group.name}，${group.statusLabel}',
                  onTap: toggle,
                  excludeSemantics: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: toggle,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  group.name,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                group.statusLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedRotation(
                                turns: collapsed ? 0 : 0.5,
                                duration: duration,
                                curve: splitListMotionCurve,
                                child: Icon(
                                  Icons.expand_more_rounded,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildSourceMenu(group),
            ],
          ),
        ),
        if (!collapsed && group.keyword != widget.keyword)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              '检索词：${group.keyword}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        _animateSize(
          collapsed
              ? const SizedBox.shrink()
              : _buildSourceBody(
                  group,
                  showAll: display == _SourceDisplay.expanded,
                ),
        ),
      ],
    );
  }

  Widget _buildSourceBody(_SourceSearchGroup group, {required bool showAll}) {
    if (!group.hasResults) {
      return SplitListRow(
        topRadius: splitListOuterRadius,
        bottomRadius: splitListOuterRadius,
        child: switch (group.status) {
          PluginSearchStatus.pending => _buildSearching(),
          PluginSearchStatus.success ||
          PluginSearchStatus.noResult => GeneralEmptyState(
            icon: Icons.search_off_rounded,
            title: '没有找到匹配结果',
            compact: true,
            actions: [
              StateActionButton.tonal(
                onPressed: () => widget.onSourceSearch(group.name),
                text: '修改检索词',
              ),
              TextButton(
                onPressed: () => widget.onSourceAliasSearch(group.name),
                child: const Text('使用别名'),
              ),
            ],
          ),
          PluginSearchStatus.captcha => _buildSourceIssue(
            group.name,
            requiresVerification: true,
          ),
          PluginSearchStatus.error => _buildSourceIssue(
            group.name,
            requiresVerification: false,
          ),
        },
      );
    }

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final visibleCount = showAll ? group.results.length : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visibleCount; index++) ...[
          if (index > 0) const SizedBox(height: splitListRowGap),
          _buildResult(group, index),
        ],
        if (group.results.length > 1) ...[
          const SizedBox(height: splitListRowGap),
          SplitListRow(
            bottomRadius: splitListOuterRadius,
            onTap: () => showAll
                ? _collapseFromFooter(group.name)
                : _setDisplay(group.name, _SourceDisplay.expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        showAll ? '收起全部条目' : '展开全部 ${group.results.length} 个结果',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      showAll
                          ? Icons.unfold_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSourceMenu(_SourceSearchGroup group) => TooltipVisibility(
    visible: false,
    child: KazumiMenuButton(
      animated: true,
      builder: (context, toggle) => IconButton(
        tooltip: '${group.name} 的更多操作',
        icon: const Icon(Icons.more_horiz_rounded, size: 20),
        onPressed: toggle,
      ),
      menuChildren: [
        KazumiMenuItem(
          label: '修改此来源的检索词',
          onPressed: () => widget.onSourceSearch(group.name),
        ),
        KazumiMenuItem(
          label: '使用别名检索此来源',
          onPressed: () => widget.onSourceAliasSearch(group.name),
        ),
        KazumiMenuItem(
          label: '重新检索此来源',
          onPressed: () => widget.onRetry(group.name),
        ),
        KazumiMenuItem(
          label: '在浏览器中打开',
          onPressed: () => widget.onOpenBrowser(group.name),
        ),
      ],
    ),
  );

  Widget _buildResult(_SourceSearchGroup group, int index) {
    final theme = Theme.of(context);
    final result = group.results[index];
    return SplitListRow(
      topRadius: index == 0 ? splitListOuterRadius : splitListInnerRadius,
      bottomRadius: group.results.length == 1
          ? splitListOuterRadius
          : splitListInnerRadius,
      onTap: () => widget.onPlay(group.name, result),
      child: Semantics(
        button: true,
        label:
            '${widget.downloadMode ? '下载' : '播放'} ${result.name}，来源 ${group.name}',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    result.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  widget.downloadMode
                      ? Icons.download_rounded
                      : Icons.play_arrow_rounded,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearching() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 64),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const LoadingIndicator(size: 20, semanticsLabel: '正在检索'),
          const SizedBox(width: 12),
          Expanded(
            child: Text('正在检索…', style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    ),
  );

  Widget _buildSourceIssue(
    String sourceName, {
    required bool requiresVerification,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, title, hint, action, onAction) = requiresVerification
        ? (
            Icons.verified_user_outlined,
            '需要验证',
            '完成网站验证后继续检索。',
            '进行验证',
            () => widget.onVerify(sourceName),
          )
        : (
            Icons.error_outline_rounded,
            '检索失败',
            '可以重试，或打开网站检查是否可用。',
            '重试',
            () => widget.onRetry(sourceName),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  icon,
                  size: 20,
                  color: requiresVerification
                      ? colors.onSurfaceVariant
                      : colors.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonal(onPressed: onAction, child: Text(action)),
              TextButton(
                onPressed: () => widget.onOpenBrowser(sourceName),
                child: const Text('打开网站'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EpisodeSourceSheetView extends StatefulWidget {
  const _EpisodeSourceSheetView({
    required this.downloadMode,
    required this.sourceOptions,
    required this.selectedSourceKey,
    required this.roadOptions,
    required this.selectedRoadIndex,
    required this.episodes,
    required this.matches,
    required this.downloadedEpisodes,
    required this.episodesLoading,
    required this.roadsLoading,
    required this.sourceOptionsLoading,
    required this.searchPending,
    required this.onSourceSelected,
    required this.onRoadSelected,
    required this.onEpisodeSelected,
    required this.onDownloadSelected,
    required this.onManageSources,
    required this.onClose,
  });

  final bool downloadMode;
  final List<_SourceSearchOption> sourceOptions;
  final String? selectedSourceKey;
  final List<_SourceRoadOption> roadOptions;
  final int? selectedRoadIndex;
  final List<EpisodeInfo> episodes;
  final Map<int, RoadEpisodeMatch> matches;
  final Set<int> downloadedEpisodes;
  final bool episodesLoading;
  final bool roadsLoading;
  final bool sourceOptionsLoading;
  final bool searchPending;
  final ValueChanged<String> onSourceSelected;
  final ValueChanged<int> onRoadSelected;
  final void Function(EpisodeInfo episode, RoadEpisodeMatch match)
  onEpisodeSelected;
  final ValueChanged<Set<int>> onDownloadSelected;
  final VoidCallback onManageSources;
  final VoidCallback onClose;

  @override
  State<_EpisodeSourceSheetView> createState() =>
      _EpisodeSourceSheetViewState();
}

class _EpisodeSourceSheetViewState extends State<_EpisodeSourceSheetView> {
  final Set<int> _selectedEpisodes = {};

  @override
  void didUpdateWidget(covariant _EpisodeSourceSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSourceKey != widget.selectedSourceKey ||
        oldWidget.selectedRoadIndex != widget.selectedRoadIndex) {
      _selectedEpisodes.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRoad = widget.roadOptions.firstWhereOrNull(
      (option) => option.index == widget.selectedRoadIndex,
    );
    final selectedSource = widget.sourceOptions.firstWhereOrNull(
      (option) => option.key == widget.selectedSourceKey,
    );
    final availableNumbers = widget.matches.keys
        .where((number) => !widget.downloadedEpisodes.contains(number))
        .toSet();
    final allAvailableSelected =
        availableNumbers.isNotEmpty &&
        _selectedEpisodes.length == availableNumbers.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          MaterialBottomSheetHeader(
            title: widget.downloadMode ? '下载来源' : '播放来源',
            description: widget.episodesLoading
                ? '正在获取已放出集数'
                : widget.sourceOptionsLoading
                ? '正在筛选可用来源'
                : '${widget.episodes.length} 集 · ${widget.sourceOptions.length} 个来源',
            onClose: widget.onClose,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _CompactSourceSelector<String>(
                        label: '来源',
                        valueLabel:
                            selectedSource?.item.name ??
                            (widget.sourceOptionsLoading
                                ? '正在筛选可用来源…'
                                : '暂无可用来源'),
                        selectedValue: widget.selectedSourceKey,
                        enabled:
                            widget.sourceOptions.isNotEmpty &&
                            !widget.sourceOptionsLoading,
                        options: [
                          for (final option in widget.sourceOptions)
                            _CompactSelectorOption(
                              value: option.key,
                              title: option.item.name,
                              subtitle: option.plugin.name,
                            ),
                        ],
                        onSelected: widget.onSourceSelected,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '来源检索管理',
                      onPressed: widget.onManageSources,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CompactSourceSelector<int>(
                  label: '线路',
                  valueLabel: selectedRoad == null
                      ? (widget.roadsLoading ? '正在获取线路…' : '暂无可用线路')
                      : selectedRoad.road.name,
                  selectedValue: widget.selectedRoadIndex,
                  enabled: widget.roadOptions.isNotEmpty,
                  options: [
                    for (final option in widget.roadOptions)
                      _CompactSelectorOption(
                        value: option.index,
                        title: option.road.name,
                        subtitle: '${option.matches.length} 集',
                      ),
                  ],
                  onSelected: widget.onRoadSelected,
                ),
              ],
            ),
          ),
          Expanded(
            child:
                widget.episodesLoading ||
                    widget.roadsLoading ||
                    (widget.sourceOptionsLoading && selectedRoad == null)
                ? const Center(child: CircularProgressIndicator())
                : widget.episodes.isEmpty
                ? const GeneralEmptyState(
                    icon: Icons.video_library_outlined,
                    title: '暂无已放出的正片集数',
                    compact: true,
                  )
                : selectedRoad == null
                ? Center(
                    child: GeneralEmptyState(
                      icon: Icons.playlist_remove_rounded,
                      title: widget.sourceOptions.isEmpty
                          ? '没有可用来源'
                          : '当前来源没有可用线路',
                      compact: true,
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 96,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          mainAxisExtent: 44,
                        ),
                    itemCount: widget.episodes.length,
                    itemBuilder: (context, index) {
                      final episode = widget.episodes[index];
                      final episodeNumber = episode.episode.toInt();
                      final match = widget.matches[episodeNumber];
                      final downloaded = widget.downloadedEpisodes.contains(
                        episodeNumber,
                      );
                      final enabled = match != null && !downloaded;
                      final selected = _selectedEpisodes.contains(
                        episodeNumber,
                      );
                      final colors = theme.colorScheme;
                      final backgroundColor = downloaded
                          ? colors.surfaceContainerLow
                          : !enabled
                          ? colors.surfaceContainerLowest
                          : selected
                          ? colors.secondaryContainer
                          : colors.surfaceContainerLow;
                      final foregroundColor = downloaded
                          ? colors.outline
                          : !enabled
                          ? colors.onSurface.withValues(alpha: 0.35)
                          : selected
                          ? colors.onSecondaryContainer
                          : colors.onSurface;
                      return Tooltip(
                        message: downloaded
                            ? '第$episodeNumber集 已下载'
                            : episode.nameCn.isNotEmpty
                            ? episode.nameCn
                            : episode.name,
                        child: Material(
                          color: backgroundColor,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: selected
                                  ? colors.secondary
                                  : colors.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: !enabled
                                ? null
                                : widget.downloadMode
                                ? () => setState(() {
                                    if (selected) {
                                      _selectedEpisodes.remove(episodeNumber);
                                    } else {
                                      _selectedEpisodes.add(episodeNumber);
                                    }
                                  })
                                : () =>
                                      widget.onEpisodeSelected(episode, match),
                            child: Stack(
                              children: [
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      '第$episodeNumber集',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(color: foregroundColor),
                                    ),
                                  ),
                                ),
                                if (downloaded)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(
                                      Icons.download_done_rounded,
                                      size: 14,
                                      color: colors.outline,
                                    ),
                                  )
                                else if (selected)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      size: 14,
                                      color: colors.onSecondaryContainer,
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
          if (widget.downloadMode)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: availableNumbers.isEmpty
                          ? null
                          : () => setState(() {
                              _selectedEpisodes
                                ..clear()
                                ..addAll(
                                  allAvailableSelected
                                      ? const <int>{}
                                      : availableNumbers,
                                );
                            }),
                      child: Text(allAvailableSelected ? '取消全选' : '全选'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _selectedEpisodes.isEmpty
                            ? null
                            : () => widget.onDownloadSelected(
                                Set<int>.of(_selectedEpisodes),
                              ),
                        icon: const Icon(Icons.download_rounded),
                        label: Text(
                          _selectedEpisodes.isEmpty
                              ? '选择集数'
                              : '下载 ${_selectedEpisodes.length} 集',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactSelectorOption<T> {
  const _CompactSelectorOption({
    required this.value,
    required this.title,
    required this.subtitle,
  });

  final T value;
  final String title;
  final String subtitle;
}

class _CompactSourceSelector<T> extends StatelessWidget {
  const _CompactSourceSelector({
    required this.label,
    required this.valueLabel,
    required this.selectedValue,
    required this.enabled,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String valueLabel;
  final T? selectedValue;
  final bool enabled;
  final List<_CompactSelectorOption<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MenuAnchor(
          crossAxisUnconstrained: false,
          consumeOutsideTap: true,
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            alignment: AlignmentDirectional.topStart,
            backgroundColor: WidgetStatePropertyAll(colors.surfaceContainer),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(3),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(width, MediaQuery.sizeOf(context).height * 0.65),
            ),
          ),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Text(
                '选择$label',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            for (final option in options)
              MenuItemButton(
                onPressed: () => onSelected(option.value),
                style: ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(width - 12, 48)),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: WidgetStatePropertyAll(
                    option.value == selectedValue
                        ? colors.secondaryContainer
                        : colors.surfaceContainerLow,
                  ),
                  foregroundColor: WidgetStatePropertyAll(
                    option.value == selectedValue
                        ? colors.onSecondaryContainer
                        : colors.onSurface,
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            option.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: option.value == selectedValue
                                  ? colors.onSecondaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (option.value == selectedValue)
                      Icon(
                        Icons.check_rounded,
                        color: colors.primary,
                        size: 18,
                      ),
                  ],
                ),
              ),
          ],
          builder: (context, controller, child) {
            final open = controller.isOpen;
            final foreground = enabled
                ? open
                      ? colors.onSecondaryContainer
                      : colors.onSurface
                : colors.onSurfaceVariant;
            return Semantics(
              button: enabled,
              expanded: enabled ? open : null,
              label: enabled ? '切换$label' : valueLabel,
              child: Material(
                color: open
                    ? colors.secondaryContainer
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(open ? 14 : 16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled
                      ? () => controller.isOpen
                            ? controller.close()
                            : controller.open()
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: foreground,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                valueLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: foreground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
