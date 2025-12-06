import { useState, useEffect } from "react";
import { Orpheus } from "../ExpoOrpheusModule";

export function useShuffleMode() {
  const [shuffleMode, setShuffleMode] = useState(false);

  const refresh = async () => {
    const val = await Orpheus.getShuffleMode();
    setShuffleMode(val);
  };

  useEffect(() => {
    refresh();
    const sub = Orpheus.addListener("onTrackStarted", refresh);
    return () => sub.remove();
  }, []);

  const toggleShuffle = async () => {
    const newVal = !shuffleMode;
    setShuffleMode(newVal);
    await Orpheus.setShuffleMode(newVal);
    refresh();
  };

  return [shuffleMode, toggleShuffle] as const;
}
