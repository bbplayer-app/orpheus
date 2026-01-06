# Orpheus

**BBPlayer 内部音频模块**

这是一个为 BBPlayer 项目构建的高性能定制音频播放库。旨在替代 `react-native-track-player`，以提供与 Android Media3 (ExoPlayer) 更紧密的集成，并针对 Bilibili 音频流逻辑提供了原生层支持。

## 与 B 站集成

通过 `Orpheus.setBilibiliCookie()` 设置 cookie，稍后会自动用于音频流请求。（不设置也行，只是无法获取高码率的音频）

Orpheus 通过特殊的 uri 识别来自 bilibili 的资源，格式为 `orpheus://bilibili?bvid=xxx&cid=111&quality=30280&dolby=0&hires=0`，若不提供 cid 则默认请求第一个分 p。quality 参考 b 站 api。

## 缓存

Orpheus 内部有两层缓存：

1. 用户手动下载的缓存
2. 边下边播：LRU 缓存，256mb

## 下载系统

Orpheus 集成了 Media3 的 DownloadManager，抛弃了原先 BBPlayer 中繁琐的下载实现。

## 响度均衡

默认启用，只对未缓存的 b 站音频生效

## 桌面歌词

相信聪明的你去看一下公开方法名就知道怎么使用了！
（需要注意的是，在切歌时，会自动清空当前的歌词）

## 使用

虽然该包是公开的，但仍然主要供 BBPlayer 内部使用。可能不会有完整的文档覆盖。我们欢迎你 fork 后自行修改使用。
