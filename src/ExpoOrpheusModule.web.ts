import { registerWebModule, NativeModule } from 'expo';

import { ExpoOrpheusModuleEvents } from './ExpoOrpheus.types';

class ExpoOrpheusModule extends NativeModule<ExpoOrpheusModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ExpoOrpheusModule, 'ExpoOrpheusModule');
