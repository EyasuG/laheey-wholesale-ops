'use strict';
// Runs the generator at "tiny" scale into CSV files and checks counts, determinism and referential integrity.
const { test } = require('node:test');
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const GEN = path.join(__dirname, '..', 'generate.js');
const run = (dir) => execFileSync('node', [GEN, '--scale', 'tiny', '--target', 'csv', '--out', dir, '--as-of', '2026-10-28', '--quiet'], { stdio: 'pipe' });
const read = (dir, t) => fs.readFileSync(path.join(dir, `${t}.csv`), 'utf8').trim().split('\n');
const rows = (dir, t) => read(dir, t).slice(1).map((l) => l.split(','));

const dirA = fs.mkdtempSync(path.join(os.tmpdir(), 'lwo-a-'));
const dirB = fs.mkdtempSync(path.join(os.tmpdir(), 'lwo-b-'));
run(dirA);
run(dirB);

test('produces the expected row counts', () => {
  assert.strictEqual(rows(dirA, 'products').length, 400);
  assert.strictEqual(rows(dirA, 'accounts').length, 300);
  assert.strictEqual(rows(dirA, 'contacts').length, 900);
  assert.strictEqual(rows(dirA, 'customers').length, 3000);
  assert.strictEqual(rows(dirA, 'orders').length, 15000);
  assert.strictEqual(rows(dirA, 'support_cases').length, 2000);
  const lines = rows(dirA, 'order_lines').length;
  assert.ok(lines > 15000 * 2 && lines < 15000 * 3, `order_lines ${lines} should average 2-3 per order`);
});

test('is deterministic for the same seed', () => {
  for (const t of ['accounts', 'orders', 'order_lines', 'support_cases']) {
    assert.strictEqual(fs.readFileSync(path.join(dirA, `${t}.csv`), 'utf8'), fs.readFileSync(path.join(dirB, `${t}.csv`), 'utf8'), t);
  }
});

test('every order has exactly one buyer and valid references', () => {
  const header = read(dirA, 'orders')[0].split(',');
  const ai = header.indexOf('account_id'), ci = header.indexOf('customer_id');
  for (const o of rows(dirA, 'orders')) {
    const hasA = o[ai] !== '', hasC = o[ci] !== '';
    assert.ok(hasA !== hasC, `order ${o[0]} must have account XOR customer`);
    if (hasA) assert.ok(Number(o[ai]) >= 1 && Number(o[ai]) <= 300);
    if (hasC) assert.ok(Number(o[ci]) >= 1 && Number(o[ci]) <= 3000);
  }
});

test('order totals equal the sum of their lines plus shipping minus discount', () => {
  const sums = new Map();
  for (const l of rows(dirA, 'order_lines')) sums.set(l[1], (sums.get(l[1]) || 0) + Number(l[5]));
  const h = read(dirA, 'orders')[0].split(',');
  const [si, di, shi, ti] = ['subtotal', 'discount', 'shipping', 'total'].map((c) => h.indexOf(c));
  for (const o of rows(dirA, 'orders').slice(0, 2000)) {
    assert.ok(Math.abs(sums.get(o[0]) - Number(o[si])) < 0.011, `subtotal of ${o[0]}`);
    assert.ok(Math.abs(Number(o[si]) - Number(o[di]) + Number(o[shi]) - Number(o[ti])) < 0.011, `total of ${o[0]}`);
  }
});

test('no order is dated after the as-of date', () => {
  const h = read(dirA, 'orders')[0].split(',');
  const di = h.indexOf('order_date');
  for (const o of rows(dirA, 'orders')) assert.ok(o[di] <= '2026-10-28', o[di]);
});
