import { requireNativeModule, NativeModule } from "expo-modules-core";

export enum PlaybackState {
  IDLE = 1,
  BUFFERING = 2,
  READY = 3,
  ENDED = 4,
}

export enum RepeatMode {
  OFF = 0,
  TRACK = 1,
  QUEUE = 2,
}

export enum TransitionReason {
  REPEAT = 0,
  AUTO = 1,
  SEEK = 2,
  PLAYLIST_CHANGED = 3,
}

export interface Track {
  id: string;
  url: string;
  title?: string;
  artist?: string;
  artwork?: string;
  duration?: number;
  [key: string]: any;
}

export type OrpheusEvents = {
  onPlaybackStateChanged(event: { state: PlaybackState }): void;
  onTrackTransition(event: {
    currentTrackId: string;
    previousTrackId?: string;
    reason: TransitionReason;
  }): void;
  onPlayerError(event: { code: string; message: string }): void;
  onPositionUpdate(event: {
    position: number;
    duration: number;
    buffered: number;
  }): void;
  onIsPlayingChanged(event: { status: boolean }): void;
};

declare class OrpheusModule extends NativeModule<OrpheusEvents> {
  /**
   * 获取当前进度（秒）
   */
  getPosition(): Promise<number>;

  /**
   * 获取总时长（秒）
   */
  getDuration(): Promise<number>;

  /**
   * 获取缓冲进度（秒）
   */
  getBuffered(): Promise<number>;

  /**
   * 获取是否正在播放
   */
  getIsPlaying(): Promise<boolean>;

  /**
   * 获取当前播放索引
   */
  getCurrentIndex(): Promise<number>;

  /**
   * 获取当前播放的 Track 对象
   */
  getCurrentTrack(): Promise<Track | null>;

  /**
   * 获取随机模式状态
   */
  getShuffleMode(): Promise<boolean>;

  /**
   * 获取指定索引的 Track
   */
  getIndexTrack(index: number): Promise<Track | null>;

  getRepeatMode(): Promise<RepeatMode>;

  setBilibiliCookie(cookie: string): void;

  play(): Promise<void>;

  pause(): Promise<void>;

  clear(): Promise<void>;

  skipTo(index: number): Promise<void>;

  skipToNext(): Promise<void>;

  skipToPrevious(): Promise<void>;

  /**
   * 跳转进度
   * @param seconds 秒数
   */
  seekTo(seconds: number): Promise<void>;

  setRepeatMode(mode: RepeatMode): Promise<void>;

  setShuffleMode(enabled: boolean): Promise<void>;

  getQueue(): Promise<Track[]>;

  /**
   * 添加到队列末尾，且不去重。
   * @param tracks
   * @param startFromId 可选，添加后立即播放该 ID 的曲目
   * @param clearQueue 可选，是否清空当前队列
   */
  addToEnd(tracks: Track[], startFromId?: string, clearQueue?: boolean): Promise<void>;

  /**
   * 播放下一首
   * @param track
   */
  playNext(track: Track): Promise<void>;

  removeTrack(index: number): Promise<void>;
}

export const Orpheus = requireNativeModule<OrpheusModule>("Orpheus");
