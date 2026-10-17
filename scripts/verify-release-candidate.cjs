#!/usr/bin/env node
'use strict';
// Verify downloaded RideGo CI release artifacts against the provenance manifest.
// Usage: node scripts/verify-release-candidate.cjs <extracted-artifact-root>
// Expected files: release-candidate/{SHA256SUMS,provenance.txt} and original
// rider/driver build output paths (see docs/PLAY_STORE_RELEASE_GATE.md).
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = process.argv[2] ? path.resolve(process.argv[2]) : '';
if (!root || !fs.existsSync(root)) {
  console.error('Usage: node scripts/verify-release-candidate.cjs <extracted-artifact-root>');
  process.exit(2);
}
function read(rel) { return fs.readFileSync(path.join(root, rel), 'utf8'); }
try {
  const provenance = read('release-candidate/provenance.txt');
  const commit = /^source_commit=([a-f0-9]{40})$/m.exec(provenance)?.[1];
  const run = /^workflow_run_id=([1-9][0-9]*)$/m.exec(provenance)?.[1];
  if (!commit || !run ||
      (provenance.match(/^source_commit=/gm) || []).length !== 1 ||
      (provenance.match(/^workflow_run_id=/gm) || []).length !== 1) {
    throw Error('Invalid or duplicate source commit / workflow run provenance');
  }
  const expected = new Set([
    'rider/build/app/outputs/flutter-apk/app-release.apk',
    'rider/build/app/outputs/bundle/release/app-release.aab',
    'driver/build/app/outputs/flutter-apk/app-release.apk',
    'driver/build/app/outputs/bundle/release/app-release.aab'
  ]);
  const lines = read('release-candidate/SHA256SUMS').trim().split(/\r?\n/);
  const seen = new Set();
  for (const line of lines) {
    const match = /^([a-f0-9]{64})  (.+)$/.exec(line);
    if (!match || !expected.has(match[2]) || seen.has(match[2])) {
      throw Error('Unexpected, duplicate, or malformed checksum entry');
    }
    seen.add(match[2]);
    const file = path.resolve(root, match[2]);
    if (!file.startsWith(root + path.sep)) throw Error('Unsafe artifact path');
    // Reject symlinks, including symlinked parent directories, to ensure the
    // checked bytes belong to the extracted artifact tree.
    let segment = root;
    for (const part of match[2].split('/')) {
      segment = path.join(segment, part);
      if (fs.lstatSync(segment).isSymbolicLink()) {
        throw Error('Symlinked release artifact path: ' + match[2]);
      }
    }
    if (!fs.statSync(file).isFile()) throw Error('Not a regular artifact file');
    const actual = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    if (actual !== match[1]) throw Error('SHA-256 mismatch: ' + match[2]);
    console.log('Verified: ' + match[2]);
  }
  if (seen.size !== expected.size) throw Error('Missing Rider or Partner APK/AAB checksum');
  console.log('All four artifacts match source commit ' + commit + ', workflow run ' + run);
  console.log('Note: hashes establish consistency with this manifest, not publisher identity or Play approval.');
} catch (error) {
  console.error('Release candidate verification FAILED: ' + error.message);
  process.exitCode = 1;
}
