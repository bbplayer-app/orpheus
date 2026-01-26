# API 文档

## 方法

### 播放控制

- `play(): Promise<void>`
  恢复播放。

- `pause(): Promise<void>`
  暂停播放。

- `skipToNext(): Promise<void>`
  跳至队列中的下一首歌曲。

- `skipToPrevious(): Promise<void>`
  跳至队列中的上一首歌曲。

- `skipTo(index: number): Promise<void>`
  跳至队列中指定索引的歌曲。

- `seekTo(seconds: number): Promise<void>`
  跳转到当前歌曲的指定位置（秒）。

- `clear(): Promise<void>`
  清空播放队列。

- `removeTrack(index: number): Promise<void>`
  移除队列中指定索引的歌曲。

- `setPlaybackSpeed(speed: number): Promise<void>`
  设置播放速度（如 1.0, 1.5）。

- `getPlaybackSpeed(): Promise<number>`
  获取当前播放速度。

### 队列管理

- `addToEnd(tracks: Track[], startFromId?: string, clearQueue?: boolean): Promise<void>`
  将歌曲添加到队列末尾。
  - `tracks`: 要添加的歌曲数组。
  - `startFromId` (可选): 添加后立即播放的歌曲 ID。
  - `clearQueue` (可选): 添加前是否清空现有队列。

- `playNext(track: Track): Promise<void>`
  插入一首歌曲作为下一首播放。

- `getQueue(): Promise<Track[]>`
  获取当前播放队列。

- `getCurrentIndex(): Promise<number>`
  获取当前播放歌曲的索引。

- `getCurrentTrack(): Promise<Track | null>`
  获取当前播放的 Track 对象。

- `getIndexTrack(index: number): Promise<Track | null>`
  获取指定索引的 Track 对象。

### 状态与配置

- `getIsPlaying(): Promise<boolean>`
  返回当前是否正在播放 (`true` 为播放中)。

- `getPosition(): Promise<number>`
  获取当前播放进度（秒）。

- `getDuration(): Promise<number>`
  获取当前歌曲总时长（秒）。

- `getBuffered(): Promise<number>`
  获取缓冲进度（秒）。

- `setRepeatMode(mode: RepeatMode): Promise<void>`
  设置重复模式 (`OFF`, `TRACK`, `QUEUE`).

- `getRepeatMode(): Promise<RepeatMode>`
  获取当前重复模式。

- `setShuffleMode(enabled: boolean): Promise<void>`
  启用或禁用随机播放。

- `getShuffleMode(): Promise<boolean>`
  获取当前随机播放状态。

- `setBilibiliCookie(cookie: string): void`
  设置 Bilibili cookie 用于身份验证。

### 睡眠定时器

- `setSleepTimer(durationMs: number): Promise<void>`
  设置睡眠定时器。
  - `durationMs`: 持续时间（毫秒）。

- `getSleepTimerEndTime(): Promise<number | null>`
  获取睡眠定时器结束的时间戳（毫秒），未设置则返回 `null`。

- `cancelSleepTimer(): Promise<void>`
  取消当前的睡眠定时器。

### 下载

- `downloadTrack(track: Track): Promise<void>`
  开始下载单首歌曲。

- `multiDownload(tracks: Track[]): Promise<void>`
  开始下载多首歌曲。

- `removeDownload(id: string): Promise<void>`
  通过 ID 移除下载任务。

- `removeAllDownloads(): Promise<void>`
  移除所有已下载内容。

- `getDownloads(): Promise<DownloadTask[]>`
  获取所有下载任务的列表。

- `getDownloadStatusByIds(ids: string[]): Promise<Record<string, DownloadState>>`
  批量获取指定歌曲 ID 的下载状态。

- `getUncompletedDownloadTasks(): Promise<DownloadTask[]>`
  获取所有未完成的下载任务。

- `clearUncompletedDownloadTasks(): Promise<void>`
  清除处于未完成状态的任务。

### 桌面歌词

- `showDesktopLyrics(): Promise<void>`
  显示桌面歌词悬浮窗。

- `hideDesktopLyrics(): Promise<void>`
  隐藏桌面歌词悬浮窗。

- `checkOverlayPermission(): Promise<boolean>`
  检查应用是否有显示悬浮窗的权限。

- `requestOverlayPermission(): Promise<void>`
  向系统请求悬浮窗权限。

- `setDesktopLyrics(lyricsJson: string): Promise<void>`
  更新桌面歌词的内容。

## 事件

使用 `Orpheus.addListener(eventName, callback)` 监听事件。

- `onPlaybackStateChanged`
  - `state`: `PlaybackState`
- `onTrackStarted` (已在 v0.9.0 废弃, 请使用 Headless Task)
  - `trackId`: `string`
  - `reason`: `TransitionReason`
- `onTrackFinished`
  - `trackId`: `string`
  - `finalPosition`: `number`
  - `duration`: `number`
- `onIsPlayingChanged`
  - `status`: `boolean`
- `onPositionUpdate`
  - `position`: `number`
  - `duration`: `number`
  - `buffered`: `number`
- `onPlayerError`
  - `code`: `string`
  - `message`: `string`
- `onDownloadUpdated`
  - `DownloadTask` 对象
- `onPlaybackSpeedChanged`
  - `speed`: `number`

## Headless Task

要处理后台事件（如 `onTrackStarted`，可能在 UI 不活跃时触发），请注册 headless task：

```typescript
import { registerOrpheusHeadlessTask } from "@roitium/expo-orpheus";

registerOrpheusHeadlessTask(async (event) => {
  if (event.eventName === "onTrackStarted") {
    console.log("Track started:", event.trackId);
  }
});
```

## 属性

- `Orpheus.restorePlaybackPositionEnabled`: `boolean`
- `Orpheus.loudnessNormalizationEnabled`: `boolean`
- `Orpheus.autoplayOnStartEnabled`: `boolean`
- `Orpheus.isDesktopLyricsShown`: `boolean`
- `Orpheus.isDesktopLyricsLocked`: `boolean`
