import { requireNativeModule, NativeModule } from 'expo-modules-core';

export enum PlaybackState {
  IDLE = 1,
  BUFFERING = 2,
  READY = 3,
  ENDED = 4
}

export enum RepeatMode {
  OFF = 0,
  TRACK = 1,
  QUEUE = 2
}

export enum TransitionReason {
  REPEAT = 0,
  AUTO = 1,
  SEEK = 2,
  PLAYLIST_CHANGED = 3
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
  onTrackTransition(event: { currentTrackId: string; previousTrackId?: string; reason: TransitionReason }): void;
  onPlayerError(event: { code: string; message: string }): void;
  onPositionUpdate(event: { position: number; duration: number; buffered: number }): void;
  onIsPlayingChanged(event: { status: boolean }): void;
};

declare class OrpheusModule extends NativeModule<OrpheusEvents> {
  readonly position: number;
  readonly duration: number;
  readonly isPlaying: boolean;
  readonly currentIndex: number;
  readonly currentTrack: Track | null;
  readonly shuffleMode: boolean;

  getIndexTrack(index: number): Track | null;
  setBilibiliCookie(cookie: string): void;
  play(): void;
  pause(): void;
  clear(): void;
  skipTo(index: number): void;
  skipToNext(): void;
  skipToPrevious(): void;
  seekTo(seconds: number): void;
  setRepeatMode(mode: RepeatMode): void;
  setShuffleMode(enabled: boolean): void;

  getQueue(): Promise<Track[]>;
  add(tracks: Track[]): Promise<void>;
}

export const Orpheus = requireNativeModule<OrpheusModule>('Orpheus');