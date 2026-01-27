import { AppRegistry } from "react-native";
export * from "./ExpoOrpheusModule";
export * from "./hooks";

const ORPHEUS_HEADLESS_TASK = "OrpheusHeadlessTask";

export type OrpheusHeadlessTrackStartedEvent = {
  eventName: "onTrackStarted";
  trackId: string;
  reason: number;
};

export type OrpheusHeadlessEvent = OrpheusHeadlessTrackStartedEvent;

export function registerOrpheusHeadlessTask(
  task: (event: OrpheusHeadlessEvent) => Promise<void>
) {
  AppRegistry.registerHeadlessTask(ORPHEUS_HEADLESS_TASK, () => task);
}
