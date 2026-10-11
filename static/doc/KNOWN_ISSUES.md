# 已知问题

## 本地 tab 离线选集 SP/OP/ED 匹配局限

本地 tab（`/tab/download/`）的选集 sheet 会展示番剧的全部正片与 SP/OP/ED。

- **正片**按集号（`episodeNumber`）匹配「已下载」状态，跨来源/线路可靠。
- **SP/OP/ED**：Bangumi 的非正片 `sort` 字段通常为 0，且 `DownloadEpisode`
  未持久化 Bangumi 分集 `id`，目前只能按 `nameCn`/`name` 匹配「已下载」状态。
  若下载时的名字与离线缓存元数据的名字不一致，可能被误显示为「未下载」。

彻底修复需要在 `DownloadEpisode` 增加 Bangumi 分集 `id` 字段，并在下载入口写入，
后续可改用 `id` 精确匹配。
