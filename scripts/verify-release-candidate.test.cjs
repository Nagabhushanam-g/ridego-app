'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const verifier = path.join(__dirname, 'verify-release-candidate.cjs');
const files = [
  'rider/build/app/outputs/flutter-apk/app-release.apk',
  'rider/build/app/outputs/bundle/release/app-release.aab',
  'driver/build/app/outputs/flutter-apk/app-release.apk',
  'driver/build/app/outputs/bundle/release/app-release.aab'
];
function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ridego-release-'));
  const lines = [];
  for (const name of files) {
    const target = path.join(root, name);
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.writeFileSync(target, 'fixture:' + name);
    lines.push(crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex') + '  ' + name);
  }
  fs.mkdirSync(path.join(root, 'release-candidate'));
  fs.writeFileSync(path.join(root, 'release-candidate/provenance.txt'),
    'source_commit=' + 'a'.repeat(40) + '\nworkflow_run_id=123\n');
  fs.writeFileSync(path.join(root, 'release-candidate/SHA256SUMS'), lines.join('\n') + '\n');
  return root;
}
function verify(root) {
  return spawnSync(process.execPath, [verifier, root], {encoding: 'utf8'});
}
test('accepts exactly four intact artifacts with provenance', () => {
  const root = fixture();
  try { assert.equal(verify(root).status, 0); }
  finally { fs.rmSync(root, {recursive: true, force: true}); }
});
test('rejects modified APK', () => {
  const root = fixture();
  try {
    fs.appendFileSync(path.join(root, files[0]), 'tampered');
    assert.equal(verify(root).status, 1);
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});
test('rejects missing artifact and malformed provenance', () => {
  const root = fixture();
  try {
    fs.rmSync(path.join(root, files[2]));
    assert.equal(verify(root).status, 1);
    fs.writeFileSync(path.join(root, 'release-candidate/provenance.txt'), 'unknown');
    assert.equal(verify(root).status, 1);
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});
test('rejects duplicate or injected checksum paths', () => {
  const root = fixture();
  try {
    const manifest = path.join(root, 'release-candidate/SHA256SUMS');
    fs.appendFileSync(manifest, fs.readFileSync(manifest, 'utf8').split('\n')[0] + '\n');
    assert.equal(verify(root).status, 1);
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});
