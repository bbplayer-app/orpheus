import { NativeModule, requireNativeModule } from 'expo';

import { ExpoOrpheusModuleEvents } from './ExpoOrpheus.types';

declare class ExpoOrpheusModule extends NativeModule<ExpoOrpheusModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoOrpheusModule>('ExpoOrpheus');
