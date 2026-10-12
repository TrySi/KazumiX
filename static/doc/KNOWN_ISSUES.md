# 已知问题

## 本地 tab 离线选集 SP/OP/ED 匹配局限

本地 tab（`/tab/download/`）的选集 sheet 会展示番剧的全部正片与 SP/OP/ED。

- **正片**按集号（`episodeNumber`）匹配「已下载」状态，跨来源/线路可靠。
- **SP/OP/ED**：Bangumi 的非正片 `sort` 字段通常为 0，且 `DownloadEpisode`
  未持久化 Bangumi 分集 `id`，目前只能按 `nameCn`/`name` 匹配「已下载」状态。
  若下载时的名字与离线缓存元数据的名字不一致，可能被误显示为「未下载」。

彻底修复需要在 `DownloadEpisode` 增加 Bangumi 分集 `id` 字段，并在下载入口写入，
后续可改用 `id` 精确匹配。

## 本地 tab「编辑观看状态」无法把「观看中」退回「未看过」

`_WatchStateEditorSheet`（`lib/pages/offline/offline_page.dart`）是**二元勾选**：
只有「已看完」的集数会被勾上，「观看中」与「未看过」在界面上都表现为未勾选。

因此在编辑器里对某一集取消勾选时：

- 「已看完」→ 取消勾选：生效（`setEpisodeWatched(watched: false)` 会连同
  `prog.progress` 一起清零）。
- 「观看中」→ 取消勾选：**无操作**。`_editWatchStates` 里
  `wasWatched == shouldWatch`（同为 false）被跳过，不会把该集降级为「未看过」。

即：编辑器只能在「把该集观看记录整体重置」时顺带覆盖「观看中」，无法单独把一集
从「观看中」退回「未看过」。底层 `HistoryRepository.setEpisodeWatched` 是具备该
能力的（`watched: false` 会 `prog.progress = Duration.zero`），只是 UI 没有入口。

如需支持，需要把编辑器改成三态（未看过 / 观看中 / 已看完），或为「观看中」的
集数单独提供「重置进度」动作。
