'use strict';
/*
 * Laheey Warehouse System API
 * A small REST layer in front of the Postgres warehouse, shaped the way a MuleSoft "System API" would be:
 * read-only, paginated with keyset cursors, and protected by an API key header.
 * Salesforce calls it through a Named Credential (callout:Laheey_Warehouse/...).
 */
const express = require('express');
const { Pool } = require('pg');

const PORT = Number(process.env.PORT || 8080);
const API_KEY = process.env.API_KEY || 'dev-only-change-me';
const pool = new Pool({ connectionString: process.env.DATABASE_URL || 'postgres://laheey:laheey@localhost:5432/warehouse', max: 10 });

const app = express();
app.disable('x-powered-by');

// ---------- helpers ----------
const int = (v, def, min, max) => {
  const n = v === undefined ? def : Number.parseInt(v, 10);
  if (!Number.isFinite(n) || n < min || n > max) {
    const e = new Error(`Expected an integer between ${min} and ${max}, got "${v}"`); e.status = 400; throw e;
  }
  return n;
};
const money = (v) => (v === null || v === undefined ? null : Number(v));
const day = (v) => (v ? (v instanceof Date ? v.toISOString().slice(0, 10) : String(v).slice(0, 10)) : null);
const route = (fn) => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);

// Request log line, useful when watching Salesforce callouts arrive through the tunnel
app.use((req, res, next) => {
  const t = Date.now();
  res.on('finish', () => console.log(`${new Date().toISOString()} ${req.method} ${req.originalUrl} ${res.statusCode} ${Date.now() - t}ms`));
  next();
});

app.get('/health', route(async (req, res) => {
  const { rows } = await pool.query('SELECT scale, seed, as_of FROM dataset_meta LIMIT 1');
  res.json({ status: 'ok', dataset: rows[0] ? { scale: rows[0].scale, seed: rows[0].seed, asOf: day(rows[0].as_of) } : null });
}));

// Everything under /v1 needs the API key
app.use('/v1', (req, res, next) => {
  if (req.get('x-api-key') !== API_KEY) return res.status(401).json({ error: 'Missing or invalid x-api-key header' });
  next();
});

// Row counts per table: the "how big is this" slide of the demo
app.get('/v1/stats', route(async (req, res) => {
  const { rows } = await pool.query(`
    SELECT relname AS table, n_live_tup::bigint AS rows FROM pg_stat_user_tables
    WHERE relname IN ('accounts','contacts','customers','products','orders','order_lines','support_cases') ORDER BY 2 DESC`);
  res.json({ tables: rows.map((r) => ({ table: r.table, rows: Number(r.rows) })), total: rows.reduce((s, r) => s + Number(r.rows), 0) });
}));

// ---------- sync endpoints (pulled page by page by Apex Queueable jobs) ----------
// Top-N active accounts by 12-month revenue. cursor = last rank received.
app.get('/v1/sync/accounts', route(async (req, res) => {
  const cursor = int(req.query.cursor, 0, 0, 10_000_000);
  const pageSize = int(req.query.pageSize, 200, 1, 2000);
  const top = int(req.query.top, 2000, 1, 100_000);
  const { rows } = await pool.query(`
    SELECT r.rank, a.warehouse_id, a.name, a.segment, a.tier, a.city, a.state, a.sales_rep, a.payment_terms,
           s.lifetime_revenue, s.revenue_12m, s.orders_90d, s.last_order_date, s.open_cases
    FROM account_rank r
    JOIN accounts a ON a.id = r.account_id
    JOIN account_stats s ON s.account_id = r.account_id
    WHERE r.rank > $1 AND r.rank <= $2
    ORDER BY r.rank
    LIMIT $3`, [cursor, top, pageSize]);
  const last = rows.length ? Number(rows[rows.length - 1].rank) : cursor;
  res.json({
    records: rows.map((r) => ({
      warehouseId: r.warehouse_id, name: r.name, segment: r.segment, tier: r.tier, city: r.city, state: r.state,
      salesRep: r.sales_rep, paymentTerms: r.payment_terms, lifetimeRevenue: money(r.lifetime_revenue),
      revenue12m: money(r.revenue_12m), orders90d: Number(r.orders_90d), lastOrderDate: day(r.last_order_date), openCases: Number(r.open_cases),
    })),
    nextCursor: rows.length === pageSize && last < top ? String(last) : null,
  });
}));

// Contacts of the top-N accounts. cursor = last contact id.
app.get('/v1/sync/contacts', route(async (req, res) => {
  const cursor = int(req.query.cursor, 0, 0, 2_000_000_000);
  const pageSize = int(req.query.pageSize, 500, 1, 2000);
  const top = int(req.query.top, 2000, 1, 100_000);
  const { rows } = await pool.query(`
    SELECT c.id, c.warehouse_id, a.warehouse_id AS account_wid, c.first_name, c.last_name, c.title, c.email, c.phone, c.is_primary
    FROM contacts c
    JOIN account_rank r ON r.account_id = c.account_id AND r.rank <= $2
    JOIN accounts a ON a.id = c.account_id
    WHERE c.id > $1
    ORDER BY c.id
    LIMIT $3`, [cursor, top, pageSize]);
  res.json({
    records: rows.map((r) => ({ warehouseId: r.warehouse_id, accountWarehouseId: r.account_wid, firstName: r.first_name, lastName: r.last_name,
      title: r.title, email: r.email, phone: r.phone, isPrimary: r.is_primary })),
    nextCursor: rows.length === pageSize ? String(rows[rows.length - 1].id) : null,
  });
}));

// Recent orders of the top-N accounts. cursor = last order id.
app.get('/v1/sync/orders', route(async (req, res) => {
  const cursor = int(req.query.cursor, 0, 0, Number.MAX_SAFE_INTEGER);
  const pageSize = int(req.query.pageSize, 1000, 1, 2000);
  const top = int(req.query.top, 2000, 1, 100_000);
  const days = int(req.query.days, 60, 1, 1500);
  const { rows } = await pool.query(`
    SELECT o.id, o.order_number, a.warehouse_id AS account_wid, o.order_date, o.ship_date, o.status, o.payment_status, o.channel,
           o.subtotal, o.discount, o.shipping, o.total, o.line_count
    FROM orders o
    JOIN account_rank r ON r.account_id = o.account_id AND r.rank <= $2
    JOIN accounts a ON a.id = o.account_id
    CROSS JOIN dataset_meta m
    WHERE o.id > $1 AND o.order_date > m.as_of - $3::int
    ORDER BY o.id
    LIMIT $4`, [cursor, top, days, pageSize]);
  res.json({
    records: rows.map(orderDto),
    nextCursor: rows.length === pageSize ? String(rows[rows.length - 1].id) : null,
  });
}));

// Monthly metrics for the top-N accounts. cursor = last account rank; one page = up to pageSize accounts x months.
app.get('/v1/sync/metrics', route(async (req, res) => {
  const cursor = int(req.query.cursor, 0, 0, 10_000_000);
  const pageSize = int(req.query.pageSize, 100, 1, 500);
  const top = int(req.query.top, 2000, 1, 100_000);
  const months = int(req.query.months, 12, 1, 24);
  const { rows } = await pool.query(`
    WITH page AS (
      SELECT account_id, rank FROM account_rank WHERE rank > $1 AND rank <= $2 ORDER BY rank LIMIT $3)
    SELECT p.rank, a.warehouse_id AS account_wid, mm.month, mm.revenue, mm.order_count, mm.avg_order_value
    FROM page p
    JOIN accounts a ON a.id = p.account_id
    JOIN account_monthly_metrics mm ON mm.account_id = p.account_id
    CROSS JOIN dataset_meta m
    WHERE mm.month >= date_trunc('month', m.as_of) - make_interval(months => $4 - 1)
    ORDER BY p.rank, mm.month`, [cursor, top, pageSize, months]);
  const ranks = [...new Set(rows.map((r) => Number(r.rank)))];
  const last = ranks.length ? ranks[ranks.length - 1] : cursor;
  res.json({
    records: rows.map((r) => ({ warehouseId: `${r.account_wid}-${day(r.month).slice(0, 7)}`, accountWarehouseId: r.account_wid,
      month: day(r.month), revenue: money(r.revenue), orderCount: Number(r.order_count), avgOrderValue: money(r.avg_order_value) })),
    nextCursor: ranks.length === pageSize && last < top ? String(last) : null,
  });
}));

// ---------- live lookups (used by the LWC refresh button and Agentforce actions) ----------
app.get('/v1/accounts/:warehouseId/summary', route(async (req, res) => {
  const { rows } = await pool.query(`
    SELECT a.warehouse_id, a.name, a.tier, a.segment, s.lifetime_revenue, s.revenue_12m, s.order_count, s.orders_90d,
           s.last_order_date, s.open_cases,
           (SELECT COUNT(*) FROM orders o WHERE o.account_id = a.id AND o.payment_status = 'Overdue') AS overdue_orders
    FROM accounts a JOIN account_stats s ON s.account_id = a.id
    WHERE a.warehouse_id = $1`, [req.params.warehouseId]);
  if (!rows.length) return res.status(404).json({ error: `No account ${req.params.warehouseId}` });
  const r = rows[0];
  res.json({ warehouseId: r.warehouse_id, name: r.name, tier: r.tier, segment: r.segment, lifetimeRevenue: money(r.lifetime_revenue),
    revenue12m: money(r.revenue_12m), orderCount: Number(r.order_count), orders90d: Number(r.orders_90d),
    lastOrderDate: day(r.last_order_date), openCases: Number(r.open_cases), overdueOrders: Number(r.overdue_orders) });
}));

// Order history for one account, newest first, keyset-paginated on (order_date, id)
app.get('/v1/accounts/:warehouseId/orders', route(async (req, res) => {
  const pageSize = int(req.query.pageSize, 50, 1, 500);
  const beforeDate = req.query.beforeDate || '9999-12-31';
  const beforeId = int(req.query.beforeId, Number.MAX_SAFE_INTEGER, 0, Number.MAX_SAFE_INTEGER);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(beforeDate)) return res.status(400).json({ error: 'beforeDate must be YYYY-MM-DD' });
  const { rows } = await pool.query(`
    SELECT o.id, o.order_number, a.warehouse_id AS account_wid, o.order_date, o.ship_date, o.status, o.payment_status, o.channel,
           o.subtotal, o.discount, o.shipping, o.total, o.line_count
    FROM orders o JOIN accounts a ON a.id = o.account_id
    WHERE a.warehouse_id = $1 AND (o.order_date, o.id) < ($2::date, $3::bigint)
    ORDER BY o.order_date DESC, o.id DESC
    LIMIT $4`, [req.params.warehouseId, beforeDate, beforeId, pageSize]);
  const last = rows[rows.length - 1];
  res.json({ records: rows.map(orderDto), next: rows.length === pageSize ? { beforeDate: day(last.order_date), beforeId: String(last.id) } : null });
}));

// One order with its lines: what the Agentforce "order status" action needs
app.get('/v1/orders/:orderNumber', route(async (req, res) => {
  const { rows } = await pool.query(`
    SELECT o.id, o.order_number, a.warehouse_id AS account_wid, o.order_date, o.ship_date, o.status, o.payment_status, o.channel,
           o.subtotal, o.discount, o.shipping, o.total, o.line_count
    FROM orders o LEFT JOIN accounts a ON a.id = o.account_id
    WHERE o.order_number = $1`, [req.params.orderNumber.toUpperCase()]);
  if (!rows.length) return res.status(404).json({ error: `No order ${req.params.orderNumber}` });
  const lines = await pool.query(`
    SELECT p.name AS product, l.quantity, l.unit_price, l.line_total
    FROM order_lines l JOIN products p ON p.id = l.product_id WHERE l.order_id = $1 ORDER BY l.id`, [rows[0].id]);
  res.json({ ...orderDto(rows[0]), lines: lines.rows.map((l) => ({ product: l.product, quantity: l.quantity, unitPrice: money(l.unit_price), lineTotal: money(l.line_total) })) });
}));

function orderDto(r) {
  return { warehouseId: r.order_number, orderNumber: r.order_number, accountWarehouseId: r.account_wid || null,
    orderDate: day(r.order_date), shipDate: day(r.ship_date), status: r.status, paymentStatus: r.payment_status, channel: r.channel,
    subtotal: money(r.subtotal), discount: money(r.discount), shipping: money(r.shipping), total: money(r.total), lineCount: Number(r.line_count) };
}

// ---------- errors ----------
app.use((req, res) => res.status(404).json({ error: `No route ${req.method} ${req.path}` }));
app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
  if (!err.status) console.error(err);
  res.status(err.status || 500).json({ error: err.status ? err.message : 'Internal error; see the API log' });
});

if (require.main === module) {
  app.listen(PORT, () => console.log(`Laheey Warehouse API listening on http://localhost:${PORT}  (API key from $API_KEY)`));
}
module.exports = { app, pool };
