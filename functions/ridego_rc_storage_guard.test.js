'use strict';

// Static fail-closed guard for the current RC-only Storage policy.
// Complements future Firebase Storage Emulator authorization tests.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const rules = fs.readFileSync(path.join(__dirname, '..', 'storage.rules'), 'utf8');

test('only registration certificate path is explicitly writable', () => {
  assert.match(rules, /match\s+\/partnerDocuments\/\{uid\}\/registrationCertificate\s*\{/);
  assert.match(rules, /match\s+\/\{allPaths=\*\*\}\s*\{/);
  const explicitPaths = [...rules.matchAll(/match\s+\/partnerDocuments\//g)];
  assert.equal(explicitPaths.length, 1, 'Review any additional Partner document paths');
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
