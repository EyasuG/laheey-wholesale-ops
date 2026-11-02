'use strict';
// Integration tests: need a generated warehouse. Skipped automatically when the database is unreachable.
const { test, after } = require('node:test');
const assert = require('node:assert');

process.env.API_KEY = 'test-key';
const { app, pool } = require('../server');

let base, server, dbUp = true;
const ready = (async () => {
  try { await pool.query('SELECT 1 FROM dataset_meta'); } catch { dbUp = false; }
  server = app.listen(0);
  base = `http://localhost:${server.address().port}`;
})();
after(async () => { server.close(); await pool.end(); });

const get = async (path, key = 'test-key') => {
  const res = await fetch(base + path, { headers: key ? { 'x-api-key': key } : {} });
  return { status: res.status, body: await res.json() };
};

test('rejects calls without the API key', async (t) => {
  await ready; if (!dbUp) return t.skip('warehouse not reachable');
  assert.strictEqual((await get('/v1/stats', null)).status, 401);
});

test('validates query parameters', async (t) => {
  await ready; if (!dbUp) return t.skip('warehouse not reachable');
  assert.strictEqual((await get('/v1/sync/accounts?pageSize=999999')).status, 400);
});

test('pages through top accounts without gaps or repeats', async (t) => {
  await ready; if (!dbUp) return t.skip('warehouse not reachable');
  const seen = new Set();
  let cursor = '0', pages = 0;
  while (cursor !== null) {
    const { status, body } = await get(`/v1/sync/accounts?top=250&pageSize=100&cursor=${cursor}`);
    assert.strictEqual(status, 200);
    body.records.forEach((r) => { assert.ok(!seen.has(r.warehouseId)); seen.add(r.warehouseId); });
    cursor = body.nextCursor; pages++;
  }
  assert.strictEqual(seen.size, 250);
  assert.strictEqual(pages, 3);
});

test('returns an order with its lines', async (t) => {
  await ready; if (!dbUp) return t.skip('warehouse not reachable');
  const { status, body } = await get('/v1/orders/LWO-00000001');
  assert.strictEqual(status, 200);
  assert.strictEqual(body.lines.length, body.lineCount);
  const sum = body.lines.reduce((s, l) => s + l.lineTotal, 0);
  assert.ok(Math.abs(sum - body.subtotal) < 0.011);
});

test('keyset pagination of an account order history is newest first', async (t) => {
  await ready; if (!dbUp) return t.skip('warehouse not reachable');
  const top = (await get('/v1/sync/accounts?top=1&pageSize=1')).body.records[0];
  const p1 = (await get(`/v1/accounts/${top.warehouseId}/orders?pageSize=20`)).body;
  const p2 = (await get(`/v1/accounts/${top.warehouseId}/orders?pageSize=20&beforeDate=${p1.next.beforeDate}&beforeId=${p1.next.beforeId}`)).body;
  const dates = [...p1.records, ...p2.records].map((r) => r.orderDate);
  assert.deepStrictEqual(dates, [...dates].sort().reverse());
  assert.strictEqual(new Set([...p1.records, ...p2.records].map((r) => r.orderNumber)).size, 40);
});
