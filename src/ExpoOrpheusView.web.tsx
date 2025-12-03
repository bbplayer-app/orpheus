import * as React from 'react';

import { ExpoOrpheusViewProps } from './ExpoOrpheus.types';

export default function ExpoOrpheusView(props: ExpoOrpheusViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
