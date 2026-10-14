'use strict';

// Deployment safety gate: DigiLocker preparation must not be reachable from
// the production Firebase Functions entrypoint without explicit approval.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const entry = fs.readFileSync(path.join(__dirname, 'index.js'), 'utf8');

test('production Firebase entrypoint has no DigiLocker imports or exports', () => {
  const active = entry.split(/\r?\n/).filter(line => !/^\s*(?:\/\/|\*)/.test(line));
  for (const line of active) {
    assert.doesNotMatch(line, /digilocker/i,
      'DigiLocker must not be activated in functions/index.js without approval');
  }
});

test('DigiLocker preparation modules do not modify production exports', () => {
  const modules = [
    'digilocker_audited_flow.js',
    'digilocker_callable_adapter.js',
    'digilocker_resolved_callback.js',
  ];
  for (const moduleName of modules) {
    const source = fs.readFileSync(path.join(__dirname, moduleName), 'utf8');
    assert.doesNotMatch(source, /require\(['"]\.\/index['"]\)/,
      moduleName + ' must not import the production entrypoint');
  }
});
