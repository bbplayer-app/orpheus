import React, { useEffect, useState, useCallback } from 'react';
import {
  StyleSheet,
  Text,
  View,
  Image,
  TouchableOpacity,
  ScrollView,
  SafeAreaView,
  Alert,
} from 'react-native';
// 假设这些类型都是从你的包里导出的
import { Orpheus, PlaybackState, RepeatMode, Track, TransitionReason, useCurrentTrack } from '@roitium/expo-orpheus';

const TEST_TRACKS: Track[] = [
  {
    id: 'bilibili--BV1DL4y1V7xH--584235509',
    url: 'orpheus://bilibili?bvid=BV1DL4y1V7xH&cid=584235509',
    title: 'Superstar (Desktop Lyrics Demo)',
    artist: 'えびかれー伯爵',
    artwork: 'https://i0.hdslb.com/bfs/archive/8f2c8d87a9f7e8e8e8e8e8e8e8e8e8e8e8e8e8e8.jpg',
  },
  {
    id: 'test_bili_fake',
    url: 'orpheus://bilibili?bvid=BV1WPS4BuEEb',
    title: 'Bilibili Test (Fake)',
    artist: 'Orpheus Repo',
    artwork: 'https://i1.hdslb.com/bfs/archive/77894b93c447724ff2d52a8171771c72681cb986.jpg',
  },
  {
    id: 'test_bili_new1',
    url: 'orpheus://bilibili?bvid=BV1DzCABvEAV',
    title: 'lty',
    artist: 'Orpheus Repo',
    artwork: 'https://i2.hdslb.com/bfs/archive/1dc8b91a28f425835178bc5a399dbdbb6788d3ff.jpg',
  },
  {
    id: 'test_bili_new2',
    url: 'orpheus://bilibili?bvid=BV1NSC5BtEem',
    title: '111',
    artist: 'Orpheus Repo',
    artwork: 'https://i1.hdslb.com/bfs/archive/e115f949947eabc57f626a5f4f81eeb3d468c63c.jpg',
  },
  {
    id: 'test_bili_new3',
    url: 'orpheus://bilibili?bvid=BV1mV411X7DZ&dolby=1&hires=1',
    title: '草东《大风吹》【Hi-Res】',
    artist: 'Orpheus Repo',
    artwork: 'https://i1.hdslb.com/bfs/archive/554224b5870aad1353306f2fb8e788e3c22c4bae.jpg',
  },
];

export default function OrpheusTestScreen() {
  // --- State ---
  const [isPlaying, setIsPlaying] = useState(false);
  const [playbackState, setPlaybackState] = useState<PlaybackState>(PlaybackState.IDLE);
  const [progress, setProgress] = useState({ position: 0, duration: 0, buffered: 0 });
  
  const [repeatMode, setRepeatMode] = useState<RepeatMode>(RepeatMode.OFF);
  const [shuffleMode, setShuffleMode] = useState(false);
  const [playbackSpeed, setPlaybackSpeed] = useState(1.0);
  const {track: currentTrack} = useCurrentTrack()
  const [restorePlaybackPositionEnabled, setRestorePlaybackPositionEnabled] = useState(false);
  const [downloadTasks, setDownloadTasks] = useState<any[]>([]);
  const [autoplay, setAutoplay] = useState(false);
  const [desktopLyricsShown, setDesktopLyricsShown] = useState(false);
  const [desktopLyricsLocked, setDesktopLyricsLocked] = useState(false);
  
  // 调试信息
  const [lastEventLog, setLastEventLog] = useState<string>('就绪');

  useEffect(() => {
    setRestorePlaybackPositionEnabled(Orpheus.restorePlaybackPositionEnabled)
    setAutoplay(Orpheus.autoplayOnStartEnabled)
  }, [restorePlaybackPositionEnabled, autoplay]);

  // --- 初始化与监听 ---
  useEffect(() => {
    // 1. 挂载时同步一次完整状态
    syncFullState();

    // 2. 注册监听器
    // 注意：事件名称必须严格对应 OrpheusEvents 类型中的定义

    const subState = Orpheus.addListener('onPlaybackStateChanged', (event) => {
      console.log('状态改变:', event.state);
      setPlaybackState(event.state);
    });

    // 对应新定义的 onTrackStarted
    const subTrackStart = Orpheus.addListener('onTrackStarted', async (event) => {
      console.log('歌曲开始:', event);
      console.log(`歌曲开始: ${event.trackId} (原因: ${TransitionReason[event.reason]})`);
    });

    // 对应新定义的 onTrackFinished (调试用)
    const subTrackFinish = Orpheus.addListener('onTrackFinished', (event) => {
      console.log('歌曲结束:', event);
      setLastEventLog(`歌曲结束: ${event.trackId}`);
    });

    const subPlaying = Orpheus.addListener('onIsPlayingChanged', (event) => {
      setIsPlaying(event.status);
    });

    const subProgress = Orpheus.addListener('onPositionUpdate', (event) => {
      setProgress({
        position: event.position,
        duration: event.duration,
        buffered: event.buffered,
      });
    });

    const subError = Orpheus.addListener('onPlayerError', (event) => {
      Alert.alert('播放器报错', `代码: ${event.code}\n信息: ${event.message}`);
      setLastEventLog(`错误: ${event.code}`);
    });

    // 监听下载进度
    const subDownload = Orpheus.addListener('onDownloadUpdated', (task) => {
      console.log(`下载更新 [${task.id}]: ${task.percentDownloaded.toFixed(1)}% (状态: ${task.state})`);
      // 简单更新一下日志，或者你可以把 task 存到 state 里展示
      // setLastEventLog(`DL [${task.id}]: ${task.percentDownloaded.toFixed(1)}%`);
    });

    const subSpeed = Orpheus.addListener('onPlaybackSpeedChanged', (event) => {
        console.log('播放速度改变:', event.speed);
        setPlaybackSpeed(event.speed);
    });

    return () => {
      subState.remove();
      // subTrackStart.remove();
      subTrackFinish.remove();
      subPlaying.remove();
      subProgress.remove();
      subError.remove();
      subDownload.remove();
      subSpeed.remove();
    };
  }, []);

  // --- 异步同步状态的辅助函数 ---

  const syncFullState = async () => {
    try {
      // await syncCurrentTrack();
      
      const playing = await Orpheus.getIsPlaying();
      setIsPlaying(playing);

      const shuffle = await Orpheus.getShuffleMode();
      setShuffleMode(shuffle);

      const speed = await Orpheus.getPlaybackSpeed();
      setPlaybackSpeed(speed);
      
      const repeat = await Orpheus.getRepeatMode();
      setRepeatMode(repeat);

      await syncDesktopLyricsStatus();

    } catch (e: any) {
      console.error("同步状态错误:", e);
      setLastEventLog(`同步错误: ${e.message}`);
    }
  };

  const syncDesktopLyricsStatus = async () => {
    try {
      // 使用属性直接获取状态
      const shown = Orpheus.isDesktopLyricsShown;
      setDesktopLyricsShown(shown);
      const locked = Orpheus.isDesktopLyricsLocked;
      setDesktopLyricsLocked(locked);
    } catch (e: any) {
      console.error("同步歌词状态错误:", e);
    }
  }

  // --- 交互处理 ---

  const handlePlayPause = async () => {
    try {
      if (isPlaying) {
        await Orpheus.pause();
      } else {
        await Orpheus.play();
      }
    } catch (e: any) {
      Alert.alert("操作失败", e.message);
    }
  };

  const handleAddTracks = async () => {
    try {
      // API 变更：add -> addToEnd
      // 第二个参数 startFromId，这里传 undefined 表示不立即切歌，或者传 TEST_TRACKS[0].id 立即播放
      await Orpheus.addToEnd(TEST_TRACKS, undefined, false);
      setLastEventLog('歌曲已添加到队列末尾');
      Alert.alert('成功', '歌曲已添加到队列');
    } catch (e: any) {
      Alert.alert("添加失败", e.message);
    }
  };

  const handleClearAndPlay = async () => {
    try {
      // 测试 addToEnd 的 clearQueue 参数
      await Orpheus.addToEnd(TEST_TRACKS, TEST_TRACKS[0].id, true);
      setLastEventLog('队列已清空并播放新歌曲');
    } catch (e: any) {
      Alert.alert("操作失败", e.message);
    }
  };

  const handleTestIndexTrack = async () => {
    try {
      const track = await Orpheus.getIndexTrack(0);
      if (track) {
        Alert.alert('获取索引 0 成功', `标题: ${track.title}\nID: ${track.id}`);
      } else {
        Alert.alert('获取索引 0', '返回空 (队列可能为空)');
      }
    } catch (e: any) {
      Alert.alert('错误', e.message);
    }
  };

  const toggleRepeat = async () => {
    const nextMode = (repeatMode + 1) % 3; // 0, 1, 2 循环
    await Orpheus.setRepeatMode(nextMode);
    // 虽然可以等 UI 自动更新，但为了反应快，这里先 set 一下
    setRepeatMode(nextMode);
  };

  const toggleShuffle = async () => {
    const nextState = !shuffleMode;
    await Orpheus.setShuffleMode(nextState);
    setShuffleMode(nextState);
  };

  const toggleSpeed = async () => {
    // 0.5 -> 1.0 -> 1.25 -> 1.5 -> 2.0 -> 0.5
    // simple approximate matching to handle potential precision issues if needed, but strict is fine for now
    const speeds = [0.5, 1.0, 1.25, 1.5, 2.0];
    let nextSpeed = 1.0;
    
    // Find next speed
    for (let i = 0; i < speeds.length; i++) {
        if (playbackSpeed < speeds[i] - 0.01) { // Current speed is less than this slot (floating point tol)
            nextSpeed = speeds[i];
            break;
        }
    }
    // If not found (current is max or unknown), wrap to first
    if (playbackSpeed >= speeds[speeds.length - 1] - 0.01) {
        nextSpeed = speeds[0];
    }
    
    await Orpheus.setPlaybackSpeed(nextSpeed);
    // Optimistic
    setPlaybackSpeed(nextSpeed);
  };

  const handleRemoveCurrent = async () => {
    try {
      const idx = await Orpheus.getCurrentIndex();
      if (idx !== -1) {
        await Orpheus.removeTrack(idx);
        setLastEventLog(`移除索引 ${idx} 的歌曲`);
      } else {
        Alert.alert("无法移除", "当前没有播放索引");
      }
    } catch (e: any) {
      Alert.alert("错误", e.message);
    }
  }

  // 格式化时间 mm:ss
  const formatTime = (seconds: number) => {
    if (!seconds || isNaN(seconds) || seconds < 0) return "0:00";
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  // 进度条百分比
  const progressPercent = progress.duration > 0 
    ? (progress.position / progress.duration) * 100 
    : 0;

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        
        {/* 1. 顶部状态栏 */}
        <View style={styles.header}>
          <Text style={styles.headerTitle}>Orpheus 调试器</Text>
          <Text style={styles.stateTag}>{PlaybackState[playbackState]}</Text>
        </View>

        {/* 2. 封面与信息 */}
        <View style={styles.artworkContainer}>
          {currentTrack?.artwork ? (
            <Image source={{ uri: currentTrack.artwork }} style={styles.artwork} />
          ) : (
            <View style={[styles.artwork, styles.artworkPlaceholder]}>
              <Text style={{ color: '#666' }}>暂无封面</Text>
            </View>
          )}
          
          <Text style={styles.title} numberOfLines={1}>
            {currentTrack?.title || '未播放'}
          </Text>
          <Text style={styles.artist} numberOfLines={1}>
            {currentTrack?.artist || 'Orpheus 播放器'}
          </Text>
          <Text style={styles.trackId}>ID: {currentTrack?.id || '-'}</Text>
          <Text style={styles.debugText}>{lastEventLog}</Text>
        </View>

        {/* 3. 进度条 */}
        <View style={styles.progressContainer}>
          <View style={styles.progressBarBg}>
            {/* 缓冲进度 (灰色) */}
            <View 
              style={[
                styles.progressBarBuffered, 
                { width: `${progress.duration > 0 ? Math.min((progress.buffered / progress.duration) * 100, 100) : 0}%` }
              ]} 
            />
            {/* 播放进度 (绿色) */}
            <View 
              style={[
                styles.progressBarFill, 
                { width: `${Math.min(progressPercent, 100)}%` }
              ]} 
            />
          </View>
          <View style={styles.timeRow}>
            <Text style={styles.timeText}>{formatTime(progress.position)}</Text>
            <Text style={styles.timeText}>{formatTime(progress.duration)}</Text>
          </View>
        </View>

        {/* 4. 播放控制 */}
        <View style={styles.controlsRow}>
          <ControlButton label="⏮" onPress={() => Orpheus.skipToPrevious()} />
          
          <TouchableOpacity 
            style={styles.playBtn} 
            onPress={handlePlayPause}
          >
            <Text style={styles.playBtnText}>{isPlaying ? "⏸" : "▶️"}</Text>
          </TouchableOpacity>
          
          <ControlButton label="⏭" onPress={() => Orpheus.skipToNext()} />
        </View>

        {/* 5. 模式控制 */}
        <View style={styles.modeRow}>
          <Button 
            title={`重复: ${RepeatMode[repeatMode]}`} 
            onPress={toggleRepeat} 
            small 
          />
          <Button 
            title={`随机: ${shuffleMode ? '开' : '关'}`} 
            onPress={toggleShuffle} 
            small 
            active={shuffleMode}
          />
          <Button 
            title={`倍速: ${playbackSpeed.toFixed(1)}x`} 
            onPress={toggleSpeed} 
            small 
            active={playbackSpeed !== 1.0}
          />
        </View>

        {/* 6. 功能测试区 */}
        <View style={styles.actionsContainer}>
          <Text style={styles.sectionTitle}>队列 API</Text>
          <View style={styles.grid}>
            <Button title="添加到末尾" onPress={handleAddTracks} />
            <Button title="清空并播放" onPress={handleClearAndPlay} primary />
            <Button title="清空队列" onPress={() => Orpheus.clear()} danger />
            <Button title="移除当前" onPress={handleRemoveCurrent} danger />
          </View>

          <Text style={[styles.sectionTitle, { marginTop: 15 }]}>信息 & 跳转</Text>
          <View style={styles.grid}>
            <Button title="打印队列" onPress={async () => {
               const q = await Orpheus.getQueue();
               console.log('当前队列:', q);
               setLastEventLog(`队列长度: ${q.length}`);
            }} />
            <Button title="获取歌曲 [0]" onPress={handleTestIndexTrack} />
            
            <Button title="快进 +15s" onPress={() => {
              Orpheus.seekTo(progress.position + 15);
            }} />
            <Button title="跳转到 0s" onPress={() => {
              Orpheus.seekTo(0);
            }} />

            <Button title={(restorePlaybackPositionEnabled ? '禁用' : '启用') + " 记忆播放"} onPress={() => {
              Orpheus.restorePlaybackPositionEnabled = true;
              setRestorePlaybackPositionEnabled(Orpheus.restorePlaybackPositionEnabled)
            }} />

            <Button title={(autoplay ? '禁用' : '启用') + " 启动自动播放"} onPress={() => {
              Orpheus.autoplayOnStartEnabled = true;
              setRestorePlaybackPositionEnabled(Orpheus.restorePlaybackPositionEnabled)
            }} />

            <Button title="设置睡眠定时 (10s)" onPress={() => {
              Orpheus.setSleepTimer(10000);
            }} />
            <Button title="获取睡眠剩余时间" onPress={async () => {
              try{
              const endTime = await Orpheus.getSleepTimerEndTime();
              if (endTime) {
                Alert.alert('睡眠结束时间', `${endTime / 1000}s`);
              } else {
                Alert.alert('睡眠结束时间', '未设置');
              }
            }catch(e){
              Alert.alert('睡眠结束时间', e.message);
              console.log(e)
            }
            }} />
            <Button title="取消睡眠定时" onPress={() => {
              Orpheus.cancelSleepTimer();
            }} />
          </View>

          <Text style={[styles.sectionTitle, { marginTop: 15 }]}>下载 API</Text>
          <View style={styles.grid}>
             <Button title="下载 [0]" onPress={() => {
               Orpheus.downloadTrack(TEST_TRACKS[0]);
             }} />
             <Button title="批量下载" onPress={() => {
                Orpheus.multiDownload(TEST_TRACKS.slice(1));
             }} />
             <Button title="获取所有下载" onPress={async () => {
               const downloads = await Orpheus.getDownloads();
               console.log('所有下载:', downloads);
               setLastEventLog(`下载数量: ${downloads.length}`);
             }} />
             <Button title="获取 ID 状态" onPress={async () => {
               const ids = TEST_TRACKS.map(t => t.id);
               try{
               const statusMap = await Orpheus.getDownloadStatusByIds(ids);
                              console.log('状态映射:', statusMap);
               Alert.alert('状态映射', JSON.stringify(statusMap, null, 2));
               }catch(e){
                 Alert.alert('获取 ID 状态失败', e.message);
                 console.log(e)
                 return
               }
             }} />
             <Button title="删除所有下载" onPress={() => {
               Orpheus.removeAllDownloads();
             }} danger />
          </View>

          <Text style={[styles.sectionTitle, { marginTop: 15 }]}>桌面歌词 API</Text>
          <View style={{marginBottom: 10}}>
             <Text style={{color: '#aaa', fontSize: 12}}>状态: {desktopLyricsShown ? '显示' : '隐藏'} / {desktopLyricsLocked ? '锁定' : '未锁定'}</Text>
          </View>
          <View style={styles.grid}>
             <Button title="请求悬浮窗权限" onPress={async () => {
                await Orpheus.requestOverlayPermission();
             }} />
             <Button title="检查悬浮窗权限" onPress={async () => {
                const has = await Orpheus.checkOverlayPermission();
                Alert.alert('悬浮窗权限', has ? '已授权' : '未授权');
             }} />
             <Button title="显示桌面歌词" onPress={async () => {
                await Orpheus.showDesktopLyrics();
                await syncDesktopLyricsStatus();
             }} primary />
             <Button title="隐藏桌面歌词" onPress={async () => {
                await Orpheus.hideDesktopLyrics();
                await syncDesktopLyricsStatus();
             }} danger />
             <Button title="锁定桌面歌词" onPress={async () => {
                Orpheus.isDesktopLyricsLocked = true;
                await syncDesktopLyricsStatus();
             }} />
             <Button title="解锁桌面歌词" onPress={async () => {
                Orpheus.isDesktopLyricsLocked = false;
                await syncDesktopLyricsStatus();
             }} />
             <Button title="刷新状态" onPress={async () => {
                await syncDesktopLyricsStatus();
             }} />
          </View>
        </View>

      </ScrollView>
    </SafeAreaView>
  );
}

// --- 组件封装 ---

const ControlButton = ({ label, onPress }: any) => (
  <TouchableOpacity style={styles.controlBtn} onPress={onPress}>
    <Text style={styles.controlBtnText}>{label}</Text>
  </TouchableOpacity>
);

const Button = ({ title, onPress, primary, danger, small, active }: any) => (
  <TouchableOpacity 
    style={[
      styles.btn, 
      primary && styles.btnPrimary,
      danger && styles.btnDanger,
      active && styles.btnActive,
      small && styles.btnSmall
    ]} 
    onPress={onPress}
  >
    <Text style={[
      styles.btnText, 
      small && { fontSize: 12 },
      (primary || danger || active) && { color: '#fff' }
    ]}>{title}</Text>
  </TouchableOpacity>
);

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#121212' },
  scrollContent: { padding: 20, paddingBottom: 50 },
  
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 },
  headerTitle: { color: '#fff', fontSize: 18, fontWeight: 'bold' },
  stateTag: { color: '#1DB954', fontSize: 12, borderWidth: 1, borderColor: '#1DB954', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 4 },

  artworkContainer: { alignItems: 'center', marginBottom: 25 },
  artwork: { width: 240, height: 240, borderRadius: 12, marginBottom: 15, backgroundColor: '#000' },
  artworkPlaceholder: { backgroundColor: '#222', justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: '#333' },
  title: { color: '#fff', fontSize: 22, fontWeight: 'bold', textAlign: 'center', marginBottom: 5 },
  artist: { color: '#bbb', fontSize: 16, marginBottom: 5 },
  trackId: { color: '#444', fontSize: 10, fontFamily: 'monospace', marginBottom: 5 },
  debugText: { color: '#e5e5e5', fontSize: 10, fontFamily: 'monospace', backgroundColor: '#333', padding: 4, borderRadius: 4, marginTop: 5},

  progressContainer: { marginBottom: 30 },
  progressBarBg: { height: 6, backgroundColor: '#333', borderRadius: 3, overflow: 'hidden', position: 'relative' },
  progressBarBuffered: { height: '100%', backgroundColor: '#555', position: 'absolute', left: 0, top: 0 },
  progressBarFill: { height: '100%', backgroundColor: '#1DB954', position: 'absolute', left: 0, top: 0 },
  timeRow: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 8 },
  timeText: { color: '#888', fontSize: 12, fontVariant: ['tabular-nums'] },

  controlsRow: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', marginBottom: 30, gap: 40 },
  controlBtn: { padding: 10 },
  controlBtnText: { fontSize: 32, color: '#fff' },
  playBtn: { width: 70, height: 70, borderRadius: 35, backgroundColor: '#fff', justifyContent: 'center', alignItems: 'center' },
  playBtnText: { fontSize: 32, color: '#000', marginLeft: 4 },

  modeRow: { flexDirection: 'row', justifyContent: 'center', gap: 10, marginBottom: 30 },

  actionsContainer: { backgroundColor: '#1E1E1E', padding: 15, borderRadius: 12 },
  sectionTitle: { color: '#666', marginBottom: 15, fontSize: 12, fontWeight: 'bold', textTransform: 'uppercase' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },

  btn: { backgroundColor: '#333', paddingVertical: 12, paddingHorizontal: 16, borderRadius: 8, minWidth: 80, alignItems: 'center', marginBottom: 0 },
  btnSmall: { paddingVertical: 8, paddingHorizontal: 12, minWidth: 60 },
  btnPrimary: { backgroundColor: '#1DB954' },
  btnDanger: { backgroundColor: '#E53935' },
  btnActive: { backgroundColor: '#1DB954' },
  btnText: { color: '#ddd', fontWeight: '600' },
});