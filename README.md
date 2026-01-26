# Orpheus

**Audio Module for BBPlayer**

This is a high-performance custom audio playback library built for the BBPlayer project. It is designed to replace `react-native-track-player`, providing tighter integration with Android Media3 (ExoPlayer) and native support for Bilibili audio streaming logic.

## Integration with Bilibili

You can set the Bilibili cookie using `Orpheus.setBilibiliCookie()`, which will be automatically used for audio stream requests. If not set, high-bitrate audio may not be available.

Orpheus identifies resources from Bilibili via a special URI format: `orpheus://bilibili?bvid=xxx&cid=111&quality=30280&dolby=0&hires=0`. If `cid` is not provided, it defaults to the first part of the video. `quality` corresponds to the Bilibili API standard.

## Caching

Orpheus implements a two-layer caching mechanism:

1. **Manual Download Cache**: Content explicitly downloaded by the user.
2. **Streaming Cache**: An LRU cache (256MB) for "play while downloading".

## Download System

Orpheus integrates Media3's DownloadManager, replacing the previous implementation in BBPlayer.

## Loudness Normalization

Enabled by default. Only applies to uncached Bilibili audio.

## API Documentation

### Methods

#### Playback Control

- `play(): Promise<void>`
  Resumes playback.

- `pause(): Promise<void>`
  Pauses playback.

- `skipToNext(): Promise<void>`
  Skips to the next track in the queue.

- `skipToPrevious(): Promise<void>`
  Skips to the previous track in the queue.

- `skipTo(index: number): Promise<void>`
  Skips to a specific track index in the queue.

- `seekTo(seconds: number): Promise<void>`
  Seeks to a specific position (in seconds) in the current track.

- `clear(): Promise<void>`
  Clears the playback queue.

- `removeTrack(index: number): Promise<void>`
  Removes a track at the specified index from the queue.

- `setPlaybackSpeed(speed: number): Promise<void>`
  Sets the playback speed (e.g., 1.0, 1.5).

- `getPlaybackSpeed(): Promise<number>`
  Gets the current playback speed.

#### Queue Management

- `addToEnd(tracks: Track[], startFromId?: string, clearQueue?: boolean): Promise<void>`
  Adds tracks to the end of the queue.
  - `tracks`: Array of tracks to add.
  - `startFromId` (optional): ID of the track to play immediately after adding.
  - `clearQueue` (optional): Whether to clear the existing queue before adding.

- `playNext(track: Track): Promise<void>`
  Inserts a track to be played next.

- `getQueue(): Promise<Track[]>`
  Retrieves the current playback queue.

- `getCurrentIndex(): Promise<number>`
  Gets the index of the currently playing track.

- `getCurrentTrack(): Promise<Track | null>`
  Gets the currently playing track object.

- `getIndexTrack(index: number): Promise<Track | null>`
  Gets the track at a specific index.

#### State & Configuration

- `getIsPlaying(): Promise<boolean>`
  Returns `true` if audio is currently playing.

- `getPosition(): Promise<number>`
  Gets the current playback position in seconds.

- `getDuration(): Promise<number>`
  Gets the duration of the current track in seconds.

- `getBuffered(): Promise<number>`
  Gets the buffered position in seconds.

- `setRepeatMode(mode: RepeatMode): Promise<void>`
  Sets the repeat mode (`OFF`, `TRACK`, `QUEUE`).

- `getRepeatMode(): Promise<RepeatMode>`
  Gets the current repeat mode.

- `setShuffleMode(enabled: boolean): Promise<void>`
  Enables or disables shuffle mode.

- `getShuffleMode(): Promise<boolean>`
  Gets the current shuffle state.

- `setBilibiliCookie(cookie: string): void`
  Sets the Bilibili cookie for authentication.

#### Sleep Timer

- `setSleepTimer(durationMs: number): Promise<void>`
  Sets a sleep timer.
  - `durationMs`: Duration in milliseconds.

- `getSleepTimerEndTime(): Promise<number | null>`
  Gets the timestamp (ms) when the sleep timer will trigger, or `null` if not set.

- `cancelSleepTimer(): Promise<void>`
  Cancels the active sleep timer.

#### Downloads

- `downloadTrack(track: Track): Promise<void>`
  Starts downloading a single track.

- `multiDownload(tracks: Track[]): Promise<void>`
  Starts downloading multiple tracks.

- `removeDownload(id: string): Promise<void>`
  Removes a download task by ID.

- `removeAllDownloads(): Promise<void>`
  Removes all downloaded content.

- `getDownloads(): Promise<DownloadTask[]>`
  Gets a list of all download tasks.

- `getDownloadStatusByIds(ids: string[]): Promise<Record<string, DownloadState>>`
  Gets the download status for a list of track IDs.

- `getUncompletedDownloadTasks(): Promise<DownloadTask[]>`
  Gets all tasks that are not yet completed.

- `clearUncompletedDownloadTasks(): Promise<void>`
  Clears tasks that are in an incomplete state.

#### Desktop Lyrics

- `showDesktopLyrics(): Promise<void>`
  Shows the desktop lyrics overlay.

- `hideDesktopLyrics(): Promise<void>`
  Hides the desktop lyrics overlay.

- `checkOverlayPermission(): Promise<boolean>`
  Checks if the app has permission to display overlays.

- `requestOverlayPermission(): Promise<void>`
  Requests the overlay permission from the system.

- `setDesktopLyrics(lyricsJson: string): Promise<void>`
  Updates the content of the desktop lyrics.

### Events

Use `Orpheus.addListener(eventName, callback)` to listen for events.

- `onPlaybackStateChanged`
  - `state`: `PlaybackState`
- `onTrackStarted` (Deprecated in v0.9.0, use Headless Task)
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
  - `DownloadTask` object
- `onPlaybackSpeedChanged`
  - `speed`: `number`

### Headless Task

To handle background events (like `onTrackStarted` which might occur when the UI is not active), register a headless task:

```typescript
import { registerOrpheusHeadlessTask } from "@roitium/expo-orpheus";

registerOrpheusHeadlessTask(async (event) => {
  if (event.eventName === "onTrackStarted") {
    console.log("Track started:", event.trackId);
  }
});
```

## Properties

- `Orpheus.restorePlaybackPositionEnabled`: `boolean`
- `Orpheus.loudnessNormalizationEnabled`: `boolean`
- `Orpheus.autoplayOnStartEnabled`: `boolean`
- `Orpheus.isDesktopLyricsShown`: `boolean`
- `Orpheus.isDesktopLyricsLocked`: `boolean`

## Disclaimer

This library is primarily maintained for internal use within BBPlayer. Documentation may not cover every edge case.
