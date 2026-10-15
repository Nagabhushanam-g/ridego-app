'use strict';
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const failures = [];
const warnings = [];
const check = (condition, message) => { if (!condition) failures.push(message); };

for (const [app, expectedId] of [
  ['rider', 'com.ridego.rider'],
  ['driver', 'com.example.ridego_driver']
]) {
  const gradle = read(`${app}/android/app/build.gradle.kts`);
  const pubspec = read(`${app}/pubspec.yaml`);
  check(gradle.includes(`applicationId = "${expectedId}"`),
    `${app}: application ID unexpectedly changed; verify Firebase and Play Console registration`);
  check(/^version:\s*\d+\.\d+\.\d+\+\d+/m.test(pubspec),
    `${app}: pubspec.yaml must specify semantic version and Android build number`);
  if (gradle.includes('signingConfig = signingConfigs.getByName("debug")')) {
    warnings.push(`${app}: checked-in release build uses debug signing; CI must inject verified release signing`);
  }
  if (expectedId.startsWith('com.example.')) {
    warnings.push(`${app}: placeholder-style application ID requires explicit Play Console identity confirmation`);
  }
}

const workflow = read('.github/workflows/build-payment-test-apks.yml');
for (const name of [
  'RIDER_KEYSTORE_BASE64', 'DRIVER_KEYSTORE_BASE64',
  'RIDER_KEY_ALIAS', 'DRIVER_KEY_ALIAS',
  'FIREBASE_RIDER_GOOGLE_SERVICES_JSON', 'FIREBASE_DRIVER_GOOGLE_SERVICES_JSON'
]) {
  check(workflow.includes('secrets.' + name), `APK workflow missing ${name} secret reference`);
}
check((workflow.match(/flutter build apk --release/g) || []).length >= 2,
  'APK workflow must build both Rider and Partner in release mode');
check((workflow.match(/flutter build appbundle --release/g) || []).length >= 2,
  'Release workflow must build Rider and Partner Android App Bundles');
check(workflow.includes('ridego-rider-play-candidate-aab') &&
  workflow.includes('ridego-partner-play-candidate-aab'),
  'Release workflow must upload both Play Store candidate AAB artifacts');
check(workflow.includes('signingConfigs.getByName("release")'),
  'APK workflow must inject release signing into Gradle configuration');

console.log('RideGo release preflight (static configuration only)');
for (const message of warnings) console.log('WARNING: ' + message);
for (const message of failures) console.error('FAIL: ' + message);
console.log(`${failures.length} failure(s), ${warnings.length} warning(s)`);
if (failures.length) process.exitCode = 1;
