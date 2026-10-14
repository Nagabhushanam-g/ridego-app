'use strict';

// Static fail-closed guard for the current RC-only Storage policy.
// Complements future Firebase Storage Emulator authorization tests.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const rules = fs.readFileSync(path.join(__dirname, '..', 'storage.rules'), 'utf8');

test('only registration certificate path is explicitly writable', () => {
  const paths = [...rules.matchAll(/match\s+\/([^\s{]+(?:\{[^}]+\}[^\s{]*)*)\s*\{/g)]
    .map(match => match[1]);
  assert.ok(paths.includes('partnerDocuments/{uid}/registrationCertificate'));
  assert.ok(paths.includes('{allPaths=**}'));
  assert.equal(paths.filter(p => p.startsWith('partnerDocuments/')).length, 1);
});

test('RC writes require owner, image MIME, nonempty data and 5 MB limit', () => {
  assert.match(rules, /request\.auth\s*!=\s*null\s*&&\s*request\.auth\.uid\s*==\s*uid/);
  assert.match(rules, /request\.resource\.size\s*>\s*0/);
  assert.match(rules, /request\.resource\.size\s*<=\s*5\s*\*\s*1024\s*\*\s*1024/);
  assert.match(rules, /request\.resource\.contentType\s+in\s+\['image\/jpeg',\s*'image\/png'\]/);
  assert.match(rules, /allow\s+create,\s*update:\s*if\s+owner\(\)\s*&&\s*validRcImage\(\)/);
  assert.match(rules, /allow\s+delete,\s*list:\s*if\s+false/);
  assert.match(rules, /match\s+\/\{allPaths=\*\*\}\s*\{\s*allow\s+read,\s*write:\s*if\s+false/);
});
