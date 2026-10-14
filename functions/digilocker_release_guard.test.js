'use strict';

// Fail closed if a production Firebase entrypoint gains DigiLocker exports.
// Preparation modules remain deliberately inactive until explicit approval.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const functionsDir = __dirname;
const config = JSON.parse(fs.readFileSync(path.join(functionsDir, '..', 'firebase.json'), 'utf8'));
const packageMetadata = JSON.parse(fs.readFileSync(path.join(functionsDir, 'package.json'), 'utf8'));

function productionEntrypoints() {
  const sources = new Set(['index.js', packageMetadata.main || 'index.js']);
  const configured = Array.isArray(config.functions) ? config.functions : [config.functions];
  for (const item of configured) {
    // Fail if the Firebase configuration changes to a new source directory.
    assert.equal(item.source, 'functions', 'Review any changed Firebase Functions source directory');
  }
  return [...sources];
}

test('every configured production Firebase entrypoint excludes DigiLocker', () => {
  for (const filename of productionEntrypoints()) {
    assert.match(filename, /^[A-Za-z0-9_.-]+\.js$/, 'Review unusual entrypoint paths');
    const source = fs.readFileSync(path.join(functionsDir, filename), 'utf8');
    // Conservative: even a commented reference requires review, to avoid
    // simple bypasses using alias imports or computed export names.
    assert.doesNotMatch(source, /digilocker/i,
      'DigiLocker must not appear in production entrypoint ' + filename);
  }
});

test('DigiLocker preparation modules do not import the production entrypoint', () => {
  for (const moduleName of [
    'digilocker_audited_flow.js',
    'digilocker_callable_adapter.js',
    'digilocker_resolved_callback.js',
  ]) {
    const source = fs.readFileSync(path.join(functionsDir, moduleName), 'utf8');
    assert.doesNotMatch(source, /require\(['"]\.\/index['"]\)/,
      moduleName + ' must not import the production entrypoint');
  }
});
