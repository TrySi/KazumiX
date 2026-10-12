import 'package:flutter/material.dart';

import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/utils/format.dart';
import 'package:kazumi/utils/media.dart';

const Duration _kExpandDuration = Duration(milliseconds: 250);
const Curve _kExpandCurve = Curves.easeInOutCubic;

class DownloadRecordCard extends StatelessWidget {
  const DownloadRecordCard({
    super.key,
    required this.bangumiName,
    required this.coverSource,
    required this.completedCount,
    required this.totalCount,
    required this.activeCount,
    required this.aggregateProgress,
    required this.expanded,
    required this.onToggle,
    required this.onResumeAll,
    required this.onPauseAll,
    required this.onDeleteAll,
    required this.totalSpeed,
    required this.episodeTileBuilder,
  });

  final String bangumiName;
  final String coverSource;
  final int completedCount;
  final int totalCount;
  final int activeCount;
  final double aggregateProgress;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onResumeAll;
  final VoidCallback? onPauseAll;
  final VoidCallback onDeleteAll;
  final double totalSpeed;

  final List<Widget> Function() episodeTileBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final allCompleted = completedCount >= totalCount;

    var meta = '$completedCount/$totalCount 已完成';
    if (activeCount > 0) {
      meta += ' · $activeCount 项进行中';
      if (totalSpeed > 0) {
        meta += ' · ${formatSpeed(totalSpeed)}';
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NetworkImgLayer(src: coverSource, width: 56, height: 75),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bangumiName,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          meta,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  KazumiMenuButton(
                    animated: false,
                    builder: (context, toggle) => IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: '更多操作',
                      onPressed: toggle,
                    ),
                    menuChildren: [
                      if (onResumeAll != null)
                        KazumiMenuItem(label: '全部开始', onPressed: onResumeAll!),
                      if (onPauseAll != null)
                        KazumiMenuItem(label: '全部暂停', onPressed: onPauseAll!),
                      KazumiMenuItem(
                        label: '全部删除',
                        destructive: true,
                        onPressed: onDeleteAll,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: _kExpandDuration,
                      curve: _kExpandCurve,
                      child: Icon(
                        Icons.expand_more,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!allCompleted)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, expanded ? 4 : 16),
              child: LinearProgressIndicator(value: aggregateProgress),
            ),
          AnimatedSize(
            duration: _kExpandDuration,
            curve: _kExpandCurve,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(children: episodeTileBuilder()),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class DownloadEpisodeTile extends StatelessWidget {
  const DownloadEpisodeTile({
    super.key,
    required this.episode,
    required this.statusText,
    this.title,
    this.sourceLabel,
    this.actions = const [],
    this.onPlay,
  });

  final DownloadEpisode episode;
  final String statusText;

  /// Pre-computed display title; falls back to the stored episode name.
  final String? title;
  final String? sourceLabel;
  final List<Widget> actions;

  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isError = episode.status == DownloadStatus.failed;
    final showProgress =
        episode.status == DownloadStatus.downloading ||
        (episode.status == DownloadStatus.paused &&
            episode.progressPercent > 0);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            _EpisodeStatusBadge(episode: episode),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ??
                        (episode.episodeName.isNotEmpty
                            ? formatEpisodeLabel(episode.episodeName)
                            : '第${episode.episodeNumber}话'),
                    style: textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: textTheme.bodySmall?.copyWith(
                      color: isError
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: episode.progressPercent),
                  ],
                ],
              ),
            ),
            if (sourceLabel != null) ...[
              const SizedBox(width: 8),
              RuleTag(
                label: sourceLabel!,
                background: colorScheme.surfaceContainerHighest,
                foreground: colorScheme.onSurfaceVariant,
              ),
            ],
            const SizedBox(width: 8),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _EpisodeStatusBadge extends StatelessWidget {
  const _EpisodeStatusBadge({required this.episode});

  final DownloadEpisode episode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color background;
    Widget child;
    switch (episode.status) {
      case DownloadStatus.completed:
        background = colorScheme.secondaryContainer;
        child = Icon(
          Icons.check_rounded,
          size: 18,
          color: colorScheme.onSecondaryContainer,
        );
        break;
      case DownloadStatus.downloading:
        background = Colors.transparent;
        child = SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            value: episode.progressPercent,
            strokeWidth: 2.5,
          ),
        );
        break;
      case DownloadStatus.resolving:
        background = Colors.transparent;
        child = const SizedBox(
          width: 22,
          height: 22,
          child: LoadingIndicator(),
        );
        break;
      case DownloadStatus.failed:
        background = colorScheme.errorContainer;
        child = Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: colorScheme.onErrorContainer,
        );
        break;
      case DownloadStatus.paused:
        background = colorScheme.surfaceContainerHighest;
        child = Icon(
          Icons.pause_rounded,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        );
        break;
      case DownloadStatus.pending:
      default:
        background = colorScheme.surfaceContainerHighest;
        child = Icon(
          Icons.schedule_rounded,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        );
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Center(child: child),
    );
  }
}
