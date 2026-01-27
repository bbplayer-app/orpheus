import { registerRootComponent } from 'expo';
import { Orpheus, registerOrpheusHeadlessTask } from '@roitium/expo-orpheus';
import LYRICS_DATA from '../bilibili--BV1DL4y1V7xH--584235509.json';

import App from './App';

registerOrpheusHeadlessTask(async (event) => {
  if (event.eventName === 'onTrackStarted') {
    // TypeScript now knows event has trackId and reason
    console.log('[OrpheusHeadlessTask] Track Started:', event.trackId, event.reason);
          if (event.trackId === 'bilibili--BV1DL4y1V7xH--584235509') {
        await Orpheus.setDesktopLyrics(JSON.stringify(LYRICS_DATA));
      }
  } else if (event.eventName === 'onTrackFinished') {
    console.log('[OrpheusHeadlessTask] Track Finished:', event.trackId, 'Position:', event.finalPosition, 'Duration:', event.duration);
  }
});

registerRootComponent(App);
