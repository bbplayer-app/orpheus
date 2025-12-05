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
  Dimensions,
  ActivityIndicator,
} from 'react-native';
import { Orpheus, PlaybackState, RepeatMode, Track, TransitionReason } from 'expo-orpheus';

// 屏幕宽度，用于计算进度条
const { width } = Dimensions.get('window');

const TEST_TRACKS: Track[] = [
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
    title: '"叫你妈妈带你去买玩具吧" 草东《大风吹》【Hi-Res 24bit/192kHz】',
    artist: 'Orpheus Repo',
    artwork: 'https://i1.hdslb.com/bfs/archive/554224b5870aad1353306f2fb8e788e3c22c4bae.jpg',
  },
];

export default function OrpheusTestScreen() {
  // --- State ---
  const [currentTrack, setCurrentTrack] = useState<Track | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [playbackState, setPlaybackState] = useState<PlaybackState>(PlaybackState.IDLE);
  const [progress, setProgress] = useState({ position: 0, duration: 0, buffered: 0 });
  
  // 以前能直接读属性，现在这些状态得自己维护或者异步获取
  const [repeatMode, setRepeatMode] = useState<RepeatMode>(RepeatMode.OFF);
  const [shuffleMode, setShuffleMode] = useState(false);
  const [transitionCount, setTransitionCount] = useState(0); // 仅用于测试切歌次数

  // --- 初始化与监听 ---
  useEffect(() => {
    // 1. 挂载时同步一次完整状态
    syncFullState();

    // 2. 注册监听器 (Expo Modules 写法)
    const subState = Orpheus.addListener('onPlaybackStateChanged', (event) => {
      console.log('State Changed:', event.state);
      setPlaybackState(event.state);
    });

    const subTrack = Orpheus.addListener('onTrackTransition', async (event) => {
      console.log('Track Transition:', event);
      setTransitionCount((c) => c + 1);
      // 切歌了，重新拉取当前歌曲信息
      await syncCurrentTrack();
    });

    const subPlaying = Orpheus.addListener('onIsPlayingChanged', (event) => {
      setIsPlaying(event.status);
    });

    const subProgress = Orpheus.addListener('onPositionUpdate', (event) => {
      // 进度更新频率较高，直接 set state
      setProgress({
        position: event.position,
        duration: event.duration,
        buffered: event.buffered,
      });
    });

    const subError = Orpheus.addListener('onPlayerError', (event) => {
      Alert.alert('播放器报错', `Code: ${event.code}\nMessage: ${event.message}`);
    });

    return () => {
      subState.remove();
      subTrack.remove();
      subPlaying.remove();
      subProgress.remove();
      subError.remove();
    };
  }, []);

  // --- 异步同步状态的辅助函数 ---

  const syncFullState = async () => {
    try {
      await syncCurrentTrack();
      
      const playing = await Orpheus.getIsPlaying();
      setIsPlaying(playing);

      const shuffle = await Orpheus.getShuffleMode();
      setShuffleMode(shuffle);
      
      // 注意：你的接口定义里好像漏了 getRepeatMode，如果原生没给 getter，JS 这边只能默认 OFF 或自己记录
      // 这里暂时只同步其他状态
    } catch (e) {
      console.error("Sync State Error:", e);
    }
  };

  const syncCurrentTrack = async () => {
    try {
      const track = await Orpheus.getCurrentTrack();
      setCurrentTrack(track);
    } catch (e) {
      console.error("Sync Track Error:", e);
    }
  };

  // --- 交互处理 ---

  const handlePlayPause = async () => {
    try {
      // 因为 getIsPlaying 是异步的，这里依赖本地 state 可能会更快，
      // 但为了准确，也可以再 await 一次，或者直接 toggle
      if (isPlaying) {
        await Orpheus.pause();
      } else {
        await Orpheus.play();
      }
      // 状态更新会通过 onIsPlayingChanged 回调回来，这里不需要手动 setIsPlaying
    } catch (e: any) {
      Alert.alert("操作失败", e.message);
    }
  };

  const handleAddTracks = async () => {
    try {
      await Orpheus.add(TEST_TRACKS);
      console.log('Tracks added');
      // 加完歌可能想自动同步一下队列状态（如果 UI 有列表展示的话）
    } catch (e: any) {
      Alert.alert("添加失败", e.message);
    }
  };

  const handleTestIndexTrack = async () => {
    try {
      // 测试 getIndexTrack (异步)
      const track = await Orpheus.getIndexTrack(0);
      if (track) {
        Alert.alert('Get Index 0 Success', `Title: ${track.title}\nID: ${track.id}`);
      } else {
        Alert.alert('Get Index 0', 'Returned null (Queue might be empty)');
      }
    } catch (e: any) {
      console.log(e.message)
      Alert.alert('Error', e.message);
    }
  };

  const toggleRepeat = async () => {
    const nextMode = (repeatMode + 1) % 3;
    await Orpheus.setRepeatMode(nextMode);
    setRepeatMode(nextMode); // 本地乐观更新
  };

  const toggleShuffle = async () => {
    const nextState = !shuffleMode;
    await Orpheus.setShuffleMode(nextState);
    setShuffleMode(nextState); // 本地乐观更新
  };

  // 格式化时间 mm:ss
  const formatTime = (seconds: number) => {
    if (!seconds || isNaN(seconds)) return "0:00";
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
          <Text style={styles.headerTitle}>Orpheus Debugger</Text>
          <Text style={styles.stateTag}>{PlaybackState[playbackState]}</Text>
        </View>

        {/* 2. 封面与信息 */}
        <View style={styles.artworkContainer}>
          {currentTrack?.artwork ? (
            <Image source={{ uri: currentTrack.artwork }} style={styles.artwork} />
          ) : (
            <View style={[styles.artwork, styles.artworkPlaceholder]}>
              <Text style={{ color: '#666' }}>No Artwork</Text>
            </View>
          )}
          
          <Text style={styles.title} numberOfLines={1}>
            {currentTrack?.title || 'No Track Playing'}
          </Text>
          <Text style={styles.artist} numberOfLines={1}>
            {currentTrack?.artist || 'Orpheus Player'}
          </Text>
          <Text style={styles.trackId}>ID: {currentTrack?.id || '-'}</Text>
        </View>

        {/* 3. 进度条 */}
        <View style={styles.progressContainer}>
          <View style={styles.progressBarBg}>
            {/* 缓冲进度 (灰色) */}
            <View 
              style={[
                styles.progressBarBuffered, 
                { width: `${progress.duration > 0 ? (progress.buffered / progress.duration) * 100 : 0}%` }
              ]} 
            />
            {/* 播放进度 (绿色) */}
            <View 
              style={[
                styles.progressBarFill, 
                { width: `${progressPercent}%` }
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
            title={`Repeat: ${RepeatMode[repeatMode]}`} 
            onPress={toggleRepeat} 
            small 
          />
          <Button 
            title={`Shuffle: ${shuffleMode ? 'ON' : 'OFF'}`} 
            onPress={toggleShuffle} 
            small 
            active={shuffleMode}
          />
        </View>

        {/* 6. 功能测试区 */}
        <View style={styles.actionsContainer}>
          <Text style={styles.sectionTitle}>API Tests</Text>
          
          <View style={styles.grid}>
            <Button title="Add Test Tracks" onPress={handleAddTracks} />
            <Button title="Clear Queue" onPress={() => Orpheus.clear()} danger />
            <Button title="Get Track [0]" onPress={handleTestIndexTrack} />
            
            <Button title="Seek +15s" onPress={() => {
              Orpheus.seekTo(progress.position + 15);
            }} />
             <Button title="Get Queue Info" onPress={async () => {
               // 简单测试一下获取队列
               const q = await Orpheus.getQueue();
               console.log('Queue:', q);
               Alert.alert("Queue Info", `Count: ${q.length}`);
            }} />
            <Text style={{ color: '#888', marginTop: 10 }}>
              Track Transitions: {transitionCount}
            </Text>
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
  artwork: { width: 240, height: 240, borderRadius: 12, marginBottom: 20, backgroundColor: '#000' },
  artworkPlaceholder: { backgroundColor: '#222', justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: '#333' },
  title: { color: '#fff', fontSize: 22, fontWeight: 'bold', textAlign: 'center', marginBottom: 5 },
  artist: { color: '#bbb', fontSize: 16, marginBottom: 5 },
  trackId: { color: '#444', fontSize: 10, fontFamily: 'monospace' },

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