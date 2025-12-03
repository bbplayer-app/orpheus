import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoOrpheusViewProps } from './ExpoOrpheus.types';

const NativeView: React.ComponentType<ExpoOrpheusViewProps> =
  requireNativeView('ExpoOrpheus');

export default function ExpoOrpheusView(props: ExpoOrpheusViewProps) {
  return <NativeView {...props} />;
}
