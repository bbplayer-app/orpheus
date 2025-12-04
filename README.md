# Orpheus

**BBPlayer 内部音频模块**

这是一个为 BBPlayer 项目构建的高性能定制音频播放库。旨在替代 `react-native-track-player`，以提供与 Android Media3 (ExoPlayer) 更紧密的集成，并针对 Bilibili 音频流逻辑提供了原生层支持。

## 与 B 站集成

通过 `Orpheus.setBilibiliCookie()` 设置 cookie，稍后会自动用于音频流请求。（不设置也行，只是无法获取高码率的音频）

Orpheus 通过特殊的 uri 识别来自 bilibili 的资源，格式为 `orpheus://bilibili?bvid=xxx&cid=111&quality=30280`，若不提供 cid 则默认请求第一个分 p。quality 参考 b 站 api。
