const fs = require('fs');
const path = require('path');

const packageJsonPath = path.resolve(__dirname, '../package.json');
const buildGradlePath = path.resolve(__dirname, '../android/build.gradle');

const packageJson = require(packageJsonPath);
const version = packageJson.version;

console.log(`Syncing Android version to ${version}...`);

let buildGradleContent = fs.readFileSync(buildGradlePath, 'utf8');

// Update version = '...'
buildGradleContent = buildGradleContent.replace(
  /version = '[\d\.]+'/,
  `version = '${version}'`
);

// Update versionName "..."
buildGradleContent = buildGradleContent.replace(
  /versionName "[\d\.]+"/,
  `versionName "${version}"`
);

fs.writeFileSync(buildGradlePath, buildGradleContent);

console.log('Android build.gradle updated.');
