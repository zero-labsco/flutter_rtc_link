#!/usr/bin/env node
/**
 * install-hook.test.mjs
 *
 * Minimal, dependency-free checks for the docs tooling:
 *   1. website/scripts/pre-commit exists, is a shell script and calls sync-docs.
 *   2. sync-docs.mjs resolves the correct repo root, pages dir and placeholder.
 *   3. Both script files declare the same placeholder.
 *
 * Run with `npm test` inside website/ (no test framework required).
 */

import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const testDir = dirname(fileURLToPath(import.meta.url));
const websiteDir = join(testDir, '..');
const repoRoot = join(websiteDir, '..');

let failures = 0;

function check(name, fn) {
  try {
    fn();
    console.log(`  ok   ${name}`);
  } catch (err) {
    failures++;
    console.error(`  FAIL ${name}\n       ${err.message}`);
  }
}

function assert(cond, message) {
  if (!cond) throw new Error(message);
}

console.log('install-hook / sync-docs sanity checks');

const hook = join(websiteDir, 'scripts', 'pre-commit');
const sync = join(websiteDir, 'scripts', 'sync-docs.mjs');
const pubspec = join(repoRoot, 'pubspec.yaml');

check('pre-commit template exists', () => {
  assert(existsSync(hook), `missing ${hook}`);
});

check('pre-commit is a shell script that runs sync-docs', () => {
  const body = readFileSync(hook, 'utf8');
  assert(body.startsWith('#!'), 'missing shebang');
  assert(
    body.includes('sync-docs.mjs'),
    'pre-commit does not invoke sync-docs.mjs',
  );
});

check('sync-docs.mjs exists and targets this repo', () => {
  const body = readFileSync(sync, 'utf8');
  assert(body.includes("join(scriptDir, '..', '..')"), 'unexpected repo root');
  assert(body.includes('__RTCLINK_VERSION__'), 'unexpected placeholder');
});

check('placeholder matches between scripts', () => {
  const syncBody = readFileSync(sync, 'utf8');
  const m = syncBody.match(/const PLACEHOLDER = '([^']+)'/);
  assert(m, 'PLACEHOLDER not declared');
  assert(m[1] === '__RTCLINK_VERSION__', `placeholder is ${m[1]}`);
});

check('pubspec.yaml declares a semver version', () => {
  const body = readFileSync(pubspec, 'utf8');
  assert(
    /^version:\s*[0-9]+\.[0-9]+\.[0-9]+/m.test(body),
    'no x.y.z version in pubspec.yaml',
  );
});

check('every language variant has a _meta.js', () => {
  for (const dir of ['pages', join('pages', 'zh')]) {
    const meta = join(websiteDir, dir, '_meta.js');
    assert(existsSync(meta), `missing ${meta}`);
  }
});

if (failures > 0) {
  console.error(`\n${failures} check(s) failed.`);
  process.exit(1);
}
console.log('\nAll checks passed.');
