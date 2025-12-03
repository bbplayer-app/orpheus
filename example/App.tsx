import React, { useEffect, useState } from 'react';
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
} from 'react-native';
import { Orpheus, PlaybackState, RepeatMode, Track } from 'expo-orpheus';

const { width } = Dimensions.get('window');

// 模拟一些测试数据
const TEST_TRACKS: Track[] = [
  {
    id: 'test_2',
    // 模拟 B 站伪协议 (前提是你已经实现了那个 ResolvingDataSource)
    url: 'orpheus://bilibili?bvid=BV1Ab4y1s7S5',
    title: 'Bilibili Test (Fake)',
    artist: 'Orpheus Repo',
    artwork: 'https://i0.hdslb.com/bfs/archive/c3bc7e8aa16ef98b85c1dd571f38409af3a56765.jpg',
  },
];

export default function OrpheusTestScreen() {
  const [currentTrack, setCurrentTrack] = useState<Track | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [playbackState, setPlaybackState] = useState<PlaybackState>(PlaybackState.IDLE);
  const [progress, setProgress] = useState({ position: 0, duration: 0, buffered: 0 });
  const [repeatMode, setRepeatMode] = useState<RepeatMode>(RepeatMode.OFF);

  useEffect(() => {
    // 1. 初始化状态
    syncState();

    // 2. 注册监听器 (使用 Expo Module 新写法)
    const sub1 = Orpheus.addListener('onPlaybackStateChanged', (event) => {
      console.log('State Changed:', event.state);
      setPlaybackState(event.state);
    });

    const sub2 = Orpheus.addListener('onTrackTransition', (event) => {
      console.log('Track Transition:', event);
      // 切歌了，同步一下最新的 Track 信息
      syncState();
    });

    const sub3 = Orpheus.addListener('onIsPlayingChanged', (event) => {
      setIsPlaying(event.status);
    });

    const sub4 = Orpheus.addListener('onPositionUpdate', (event) => {
      // 高频更新，注意性能
      setProgress({
        position: event.position,
        duration: event.duration,
        buffered: event.buffered,
      });
    });

    const sub5 = Orpheus.addListener('onPlayerError', (event) => {
      Alert.alert('播放器报错', `Code: ${event.code}\nMessage: ${event.message}`);
    });

    return () => {
      sub1.remove();
      sub2.remove();
      sub3.remove();
      sub4.remove();
      sub5.remove();
    };
  }, []);

  // 同步原生属性到 React State
  const syncState = () => {
    setCurrentTrack(Orpheus.currentTrack);
    setIsPlaying(Orpheus.isPlaying);
    // 假设 Orpheus 有同步的 getter state
    // setPlaybackState(Orpheus.state); 
  };

  // 格式化时间 mm:ss
  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  // --- 测试动作 ---

  const handleAddTracks = async () => {
    await Orpheus.add(TEST_TRACKS);
    console.log('Tracks added');
  };

  const handlePlayPause = () => {
    if (isPlaying) {
      Orpheus.pause();
    } else {
      Orpheus.play();
    }
  };

  const handleTestIndexTrack = async () => {
    try {
      // 测试你新加的方法！
      // 假设这是个 AsyncFunction，如果不是 async 去掉 await 即可
      // @ts-ignore
      const track = await Orpheus.getIndexTrack(0); 
      
      if (track) {
        Alert.alert('Get Index 0 Success', `Title: ${track.title}\nID: ${track.id}`);
      } else {
        Alert.alert('Get Index 0', 'Returned null (Queue might be empty)');
      }
    } catch (e: any) {
      Alert.alert('Error', e.message);
    }
  };

  const toggleRepeat = () => {
    const nextMode = (repeatMode + 1) % 3;
    Orpheus.setRepeatMode(nextMode);
    setRepeatMode(nextMode);
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        
        {/* 1. 封面与信息区域 */}
        <View style={styles.artworkContainer}>
          {currentTrack?.artwork ? (
            <Image source={{ uri: currentTrack.artwork }} style={styles.artwork} />
          ) : (
            <View style={[styles.artwork, styles.artworkPlaceholder]}>
              <Text style={{ color: '#fff' }}>No Artwork</Text>
            </View>
          )}
          <Text style={styles.title}>{currentTrack?.title || 'No Track Playing'}</Text>
          <Text style={styles.artist}>{currentTrack?.artist || 'Orpheus Player'}</Text>
          <Text style={styles.stateText}>State: {PlaybackState[playbackState]}</Text>
        </View>

        {/* 2. 进度条区域 */}
        <View style={styles.progressContainer}>
          <View style={styles.progressBarBg}>
            <View 
              style={[
                styles.progressBarFill, 
                { width: `${(progress.duration > 0 ? progress.position / progress.duration : 0) * 100}%` }
              ]} 
            />
          </View>
          <View style={styles.timeRow}>
            <Text style={styles.timeText}>{formatTime(progress.position)}</Text>
            <Text style={styles.timeText}>{formatTime(progress.duration)}</Text>
          </View>
        </View>

        {/* 3. 核心控制按钮 */}
        <View style={styles.controlsRow}>
          <Button title="Prev" onPress={() => Orpheus.skipToPrevious()} />
          <Button 
            title={isPlaying ? "PAUSE" : "PLAY"} 
            onPress={handlePlayPause} 
            primary 
          />
          <Button title="Next" onPress={() => Orpheus.skipToNext()} />
        </View>

        {/* 4. 功能测试区 */}
        <View style={styles.actionsContainer}>
          <Text style={styles.sectionTitle}>Functional Tests</Text>
          
          <View style={styles.grid}>
            <Button title="Add Tracks" onPress={handleAddTracks} />
            <Button title="Clear Queue" onPress={() => Orpheus.clear()} danger />
            <Button 
              title={`Mode: ${RepeatMode[repeatMode]}`} 
              onPress={toggleRepeat} 
            />
            <Button title="Get Index 0" onPress={handleTestIndexTrack} />
            <Button title="Seek +10s" onPress={() => Orpheus.seekTo(progress.position + 10)} />
          </View>
        </View>

      </ScrollView>
    </SafeAreaView>
  );
}

// 简易按钮组件
const Button = ({ title, onPress, primary, danger }: any) => (
  <TouchableOpacity 
    style={[
      styles.btn, 
      primary && styles.btnPrimary,
      danger && styles.btnDanger
    ]} 
    onPress={onPress}
  >
    <Text style={[styles.btnText, (primary || danger) && { color: '#fff' }]}>{title}</Text>
  </TouchableOpacity>
);

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#121212' },
  scrollContent: { padding: 20 },
  artworkContainer: { alignItems: 'center', marginBottom: 30, marginTop: 20 },
  artwork: { width: 200, height: 200, borderRadius: 12, marginBottom: 20 },
  artworkPlaceholder: { backgroundColor: '#333', justifyContent: 'center', alignItems: 'center' },
  title: { color: '#fff', fontSize: 20, fontWeight: 'bold', textAlign: 'center', marginBottom: 5 },
  artist: { color: '#ccc', fontSize: 16, marginBottom: 10 },
  stateText: { color: '#666', fontSize: 12, marginTop: 5 },
  
  progressContainer: { marginBottom: 30 },
  progressBarBg: { height: 6, backgroundColor: '#333', borderRadius: 3, overflow: 'hidden' },
  progressBarFill: { height: '100%', backgroundColor: '#1DB954' },
  timeRow: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 8 },
  timeText: { color: '#888', fontSize: 12, fontVariant: ['tabular-nums'] },

  controlsRow: { flexDirection: 'row', justifyContent: 'space-evenly', alignItems: 'center', marginBottom: 40 },
  
  actionsContainer: { backgroundColor: '#1E1E1E', padding: 15, borderRadius: 12 },
  sectionTitle: { color: '#888', marginBottom: 15, fontSize: 12, textTransform: 'uppercase' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },

  btn: { backgroundColor: '#333', paddingVertical: 12, paddingHorizontal: 16, borderRadius: 8, minWidth: 80, alignItems: 'center', marginBottom: 8 },
  btnPrimary: { backgroundColor: '#1DB954' },
  btnDanger: { backgroundColor: '#E53935' },
  btnText: { color: '#ddd', fontWeight: '600' },
});