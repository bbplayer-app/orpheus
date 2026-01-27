import { AppRegistry, Platform } from "react-native";
import { Orpheus } from "./ExpoOrpheusModule";
import type { OrpheusHeadlessEvent } from "./ExpoOrpheusModule";

export * from "./ExpoOrpheusModule";
export * from "./hooks";

const ORPHEUS_HEADLESS_TASK = "OrpheusHeadlessTask";

export function registerOrpheusHeadlessTask(
  task: (event: OrpheusHeadlessEvent) => Promise<void>
) {
  if (Platform.OS === "android") {
    AppRegistry.registerHeadlessTask(ORPHEUS_HEADLESS_TASK, () => task);
  } else {
    // iOS: Bridge headless events from NativeModule events
    Orpheus.addListener("onHeadlessEvent", (event: OrpheusHeadlessEvent) => {
      task(event).catch((e) =>
        console.error("[Orpheus] Headless task error:", e)
      );
    });
  }
}
