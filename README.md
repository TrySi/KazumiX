<div align=center>

<h1>KazumiX</h1>

<img src="assets/images/logo/logo_rounded.png" width=200></img>

<img src="https://img.shields.io/badge/Flutter-03A9F4?style=for-the-badge&logo=flutter&logoColor=white"></img>
<img src="https://img.shields.io/badge/Dart-00B4AB?style=for-the-badge&logo=Dart&logoColor=white"></img>

<p>基于 <a href="https://github.com/Predidit/Kazumi">Kazumi</a> 的个人分支。使用最多五行基于 <code>Xpath</code> 语法的选择器构建自己的采集规则，支持 <code>Anime4K</code> 实时超分辨率。</p>
</div>

## 这是什么

本仓库是 [Kazumi](https://github.com/Predidit/Kazumi) 的**个人自用分支**，不对外发布，也不追求与上游保持同步。

改动主要围绕**离线下载**这条线：把已下载的番剧做成一个可管理的本地媒体库，补齐了跨来源合并播放、逐集观看状态、离线元数据缓存与下载管理界面，顺带处理了一些上游尚未覆盖的边界情况（弹幕凭据缺失、镜像凭据缺失、下载目录迁移等）。

包名 `com.trysi.kazumix`，可与官方版本共存。代码仍为 GPL-3.0，上游署名见文末。

## 支持平台

- **Android 10 及以上**
- **Windows 10 及以上**

只保留这两个平台。上游的 `linux/`、`ios/`、`macos/` 目录与对应 CI 任务已从本仓库移除；Dart 代码里的 `Platform.isIOS` 等分支仍然保留（否则无法通过分析），只是不会再被构建。

## 相对上游的改动

### 本地与离线

- 新增**「本地」tab**：把已下载番剧做成媒体库，支持按观看状态（未看过 / 观看中 / 已看完）与追番状态筛选、四种排序、搜索、卡片与列表两种布局、多选批量删除。
- **逐集观看状态**：每集可标记未看过 / 观看中 / 已看完，既可从本地 tab 批量编辑，也由播放历史自动推导，两者按最新时间合并。
- **跨来源合并播放**：同一集从多个来源下载后会在播放器里合成一条「本地」线路，逐集定位到各自来源的文件与弹幕。一集有多个来源时由「下载时间较早者」胜出，结果稳定，不随容器迭代顺序漂移。
- **离线元数据与封面缓存**：番剧详情与时间表会缓存到本地，断网仍可浏览；封面单独落盘，有体积上限与淘汰策略。
- 下载路径扁平化为 `<番剧>/<集号>`（原为 `<番剧>/<来源插件>/<集号>`），同时保留对旧布局的识别与删除。
- 数据容器迁移后会重写已记录的下载路径，避免下载「消失」。

### 下载

- 下载管理**按番剧分组**，新增「下载中 / 已下载」分段筛选，卡片显示来源、总大小与整体进度。
- **已下载集数的跨来源、跨线路标记与拦截**，避免重复下载导致同一集的多份文件互相覆盖。
- 「我的」页面显示下载状态分布（完成 / 下载中 / 暂停 / 失败），与下载页口径一致（按集去重）。

### 播放

- **来源与线路合并为单一选择器**，每个选项附带集数、封装格式、画质与解析延迟。
- **画质探测**：优先读取 faststart 的 `moov`，回退到文件尾部 `moov`，再回退到解析 H.264 SPS；按轨道 handler 选择视频轨，避免读到音轨的零尺寸。
- 分集标题在各页面统一（正片 `第X话`，特典 `SPx` / `OPx` / `EDx`）。

### 数据与同步

- **追番列表备份的导出与导入**（本地文件）。导入保留更新时间较新的记录，重复导入不会产生副本。
- 离线同步按「已下载 > 已追番 > 当季 > 旧季」排序，先补齐最可能需要的内容。

### 其他

- 构建时**未注入 DanDanPlay 凭据**则直接关闭弹幕入口，而不是让每次请求都拿到 403。
- 构建时**未注入镜像凭据**则 Bangumi 加速默认走直连；用户显式选择仍被尊重。
- 界面与包名品牌化为 KazumiX。

> 逐条依据见 `git log`。每个提交的正文都写了改动原因，而不只是改了什么。

## 构建

本分支不发布到任何应用商店，自行构建即可：

```bash
flutter pub get

flutter build apk --split-per-abi   # Android
flutter build windows               # Windows
```

### 凭据注入

四个可选凭据通过 `--dart-define` 注入：

| 变量 | 缺少时的行为 |
| --- | --- |
| `DANDANAPI_APPID` / `DANDANAPI_KEY` | 弹幕功能整体关闭（入口置灰） |
| `KAZUMI_APPID` / `KAZUMI_KEY` | Bangumi 加速默认直连，镜像模式需自行选 |

本地开发可以写进 `.kazumi_build_defines.env`（已在 `.gitignore` 中，不要提交），再用 `.vscode/launch.json` 里带 **local defines** 的配置启动，它会自动加上 `--dart-define-from-file`。

### 图标

`assets/images/logo/` 当前是白底占位图（原因见「美术资源」）。换入自己的图片后：

```bash
dart run flutter_launcher_icons
```

这会重新生成 Android 与 Windows 的图标。

## 测试

```bash
flutter test
flutter analyze --no-fatal-infos --fatal-warnings
```

两项都必须通过。当前 `analyze` 没有任何输出，因此**任何一条新信息都意味着改动引入了问题**。

## 开发

欢迎提交 PR。开始之前请阅读[贡献指引](static/doc/CONTRIBUTING.md)。自定义规则可在上游的[规则仓库](https://github.com/Predidit/KazumiRules)分享，教程见[规则开发文档](https://kazumi.app/docs/rules/develop-rules)。

## Q&A

<details>
<summary>使用者 Q&A</summary>

#### Q: 为什么少数番剧中有广告？

A: 本项目未插入任何广告。广告来自视频源，请不要相信广告中的任何内容，并尽量选择没有广告的视频源观看。

#### Q: 为什么我启用超分辨率功能后播放卡顿？

A: 超分辨率功能对 GPU 性能要求较高。如果没有在高性能独立显卡上运行，尽量选择效率档而非质量档；对低分辨率视频源使用超分也可以降低性能消耗。

#### Q: 为什么播放视频时内存占用较高？

A: 播放时会尽可能多地缓存视频到内存，以提供较好的观看体验。如果内存较为紧张，可以在播放设置中启用低内存模式，这会限制缓存。

#### Q: 为什么少数番剧无法通过外部播放器观看？

A: 部分视频源使用了反盗链措施。这可以由 KazumiX 处理，但外部播放器无法处理。

#### Q: 为什么本地 tab 里某集显示「未下载」，但文件明明在？

A: 本地 tab 依据下载记录（Hive）统计，而不是扫描磁盘。如果文件是手动拷进去的，需要重新下载一次；或在下载管理里删除该集后再下载，让记录与文件对上。

#### Q: 为什么同一集在两处都下载了，播放只用其中一个？

A: 跨来源合并时优先使用「下载时间较早」的那份，以保证同一集在不同时间打开时播放的是同一个文件。想换来源，可以先删除较早的那份。

</details>

<details>
<summary>规则编写者 Q&A</summary>

#### Q: 为什么我的自定义规则无法实现检索？

A: 目前对 `Xpath` 语法的支持并不完整，只支持以 `//` 开头的选择器。建议参照示例规则构建。

#### Q: 为什么我的自定义规则可以实现检索，但不能实现观看？

A: 尝试关闭自定义规则的「使用内置播放器」选项，这会退化为 `webview` 播放，兼容性更好。但在内置播放器可用时，建议启用内置播放器，以获得更流畅并带弹幕的体验。

</details>

<details>
<summary>开发者 Q&A</summary>

#### Q: 我在尝试自行编译该项目，但编译没有成功。

A: 编译需要良好的网络环境。除 Google 托管的 Flutter 依赖外，本项目还依赖 MavenCentral / GitHub / SourceForge 上的资源。如果位于中国大陆，可能需要设置恰当的镜像地址。

</details>

## 美术资源

原项目图标来自 [Yuquanaaa](https://www.pixiv.net/users/66219277) 发表在 [Pixiv](https://www.pixiv.net/artworks/116666979) 上的作品。

原作者拥有该图标的版权，并且明确声明该图标**不是自由使用的、不随本项目的 GPL 授权**，因此本仓库不包含这一图标：`assets/images/logo/` 下是一张写着 `KazumiX PLACEHOLDER` 的白底占位图。

本项目内嵌字体为 [Mi Sans](https://hyperos.mi.com/font/zh/details/sc/)，由 [Xiaomi](https://www.mi.com/index.html) 开发和拥有版权。

## 免责声明

本项目基于 GNU 通用公共许可证第 3 版（GPL-3.0）授权。我们不对其适用性、可靠性或准确性作出任何明示或暗示的保证。在法律允许的最大范围内，作者和贡献者不承担任何因使用本软件而产生的直接、间接、偶然、特殊或后果性的损害赔偿责任。

使用本项目需遵守所在地法律法规，不得进行任何侵犯第三方知识产权的行为。因使用本项目而产生的数据和缓存应在 24 小时内清除，超出 24 小时的使用需获得相关权利人的授权。

## 隐私政策

不收集任何用户数据，不使用任何遥测组件。

## 致谢

- [Kazumi](https://github.com/Predidit/Kazumi) 及其作者 [Predidit](https://github.com/Predidit)——本分支的全部基础。
- [XpathSelector](https://github.com/simonkimi/xpath_selector)——本项目的基石。
- [弹弹play](https://www.dandanplay.com/)——使用了弹弹play 开放平台以提供弹幕交互。
- [Bangumi](https://bangumi.tv/)——使用了 Bangumi 开放 API 以提供番剧元数据。
- [Anime4K](https://github.com/bloc97/Anime4K)——使用 Anime4K 进行实时超分。
- [SyncPlay](https://github.com/Syncplay/syncplay)——使用 SyncPlay 协议并通过其公共服务器实现一起看。
- [trace.moe](https://trace.moe)——使用 trace.moe 提供的图片识别番剧功能。
- [media-kit](https://github.com/media-kit/media-kit)——跨平台媒体播放能力来自 media-kit。
- [avbuild](https://github.com/wang-bin/avbuild)——使用了来自 avbuild 的树外补丁实现非标准视频流播放。
- [hive](https://github.com/isar/hive)——持久化储存能力来自 hive。
- [所有上游贡献者](https://github.com/Predidit/Kazumi/graphs/contributors)——本项目因为你们变得更好。

