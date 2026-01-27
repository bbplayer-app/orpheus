import { AppRegistry, Platform } from "react-native";
import { Orpheus, OrpheusHeadlessEvent } from "./ExpoOrpheusModule";

const ORPHEUS_HEADLESS_TASK = "OrpheusHeadlessTask";

type HeadlessListener = (event: OrpheusHeadlessEvent) => void;
const listeners = new Set<HeadlessListener>();

export function registerOrpheusHeadlessTask(
  task: (event: OrpheusHeadlessEvent) => Promise<void>
) {
  const compositeTask = async (event: OrpheusHeadlessEvent) => {
    // Notify UI listeners
    listeners.forEach((listener) => {
      try {
        listener(event);
      } catch (e) {
        console.error("[Orpheus] Error in internal headless listener:", e);
      }
    });
    
    // Run user task
    await task(event);
  };

  if (Platform.OS === "android") {
    AppRegistry.registerHeadlessTask(ORPHEUS_HEADLESS_TASK, () => compositeTask);
  } else {
    // iOS: Bridge headless events from NativeModule events
    Orpheus.addListener("onHeadlessEvent", (event: OrpheusHeadlessEvent) => {
      compositeTask(event).catch((e) =>
        console.error("[Orpheus] Headless task error:", e)
      );
    });
  }
}

export function addOrpheusHeadlessListener(
  listener: HeadlessListener
): { remove: () => void } {
  listeners.add(listener);
  return {
    remove: () => {
      listeners.delete(listener);
    },
  };
}
