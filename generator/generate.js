#!/usr/bin/env node
'use strict';
/*
 * Laheey Wholesale Ops: synthetic dataset generator
 *
 *   node generate.js --scale s            1.0M rows into Postgres  (~1-2 min)
 *   node generate.js --scale m            3.0M rows                (~4-6 min)
 *   node generate.js --scale l           10.0M rows                (~12-20 min)
 *   node generate.js --scale tiny --target csv --out ./out    small CSV set, no database
 *
 * Same --seed + --scale always produces the same rows.
 */
const fs = require('fs');
const path = require('path');
const D = require('./lib/data');

// ---------- options ----------
const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, arr) => {
  if (a.startsWith('--')) acc.push([a.slice(2), arr[i + 1] && !arr[i + 1].startsWith('--') ? arr[i + 1] : 'true']);
  return acc;
}, []));

const SCALES = {
  //        accounts  customers  orders     cases     (contacts = 3 per account, order lines ~2.4 per order)
  tiny: { accounts: 300,   customers: 3000,   orders: 15000,   cases: 2000 },
  s:    { accounts: 5000,  customers: 60000,  orders: 260000,  cases: 40000 },
  m:    { accounts: 15000, customers: 180000, orders: 780000,  cases: 120000 },
  l:    { accounts: 50000, customers: 600000, orders: 2600000, cases: 400000 },
};

const opts = {
  scale: (args.scale || 's').toLowerCase(),
  target: args.target || 'pg',
  out: args.out || path.join(__dirname, '..', 'data'),
  seed: Number(args.seed || 42),
  asOf: args['as-of'] || new Date().toISOString().slice(0, 10),   // data ends "today" so recency-based health scores make sense
  dbUrl: args['database-url'] || process.env.DATABASE_URL || 'postgres://laheey:laheey@localhost:5432/warehouse',
  quiet: args.quiet === 'true',
};
if (!SCALES[opts.scale]) { console.error(`Unknown --scale "${opts.scale}". Use tiny, s, m or l.`); process.exit(1); }
const N = SCALES[opts.scale];
const log = (...m) => { if (!opts.quiet) console.log(...m); };

// ---------- sinks: Postgres COPY (TSV) or CSV files ----------
const tsv = (v) => v === null || v === undefined ? '\\N' : String(v).replace(/\\/g, '\\\\').replace(/\t/g, '\\t').replace(/\n/g, '\\n');
const csv = (v) => { if (v === null || v === undefined) return ''; const s = String(v); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };

class Sink {
  constructor(table, columns, stream, mode) {
    Object.assign(this, { table, columns, stream, mode, rows: 0 });
    if (mode === 'csv') stream.write(columns.join(',') + '\n');
  }
  // Returns a promise only when the stream asks us to slow down (backpressure)
  write(values) {
    this.rows++;
    const line = (this.mode === 'csv' ? values.map(csv).join(',') : values.map(tsv).join('\t')) + '\n';
    if (!this.stream.write(line)) return new Promise((res) => this.stream.once('drain', res));
    return null;
  }
  end() {
    return new Promise((res, rej) => {
      this.stream.on('error', rej);
      this.stream.on(this.mode === 'csv' ? 'close' : 'finish', res);
      this.stream.end();
    });
  }
}

let pg, copyFrom;
async function openSink(table, columns, client) {
  if (opts.target === 'csv') {
    fs.mkdirSync(opts.out, { recursive: true });
    return new Sink(table, columns, fs.createWriteStream(path.join(opts.out, `${table}.csv`)), 'csv');
  }
  const stream = client.query(copyFrom(`COPY ${table} (${columns.join(', ')}) FROM STDIN`));
  return new Sink(table, columns, stream, 'pg');
}

function progress(label, i, total) {
  if (!opts.quiet && i % 100000 === 0 && i > 0) process.stdout.write(`  ${label}: ${i.toLocaleString()} / ${total.toLocaleString()}\r`);
}

// ---------- main ----------
async function main() {
  const t0 = Date.now();
  const r = D.rng(opts.seed);
  const asOf = D.toDay(opts.asOf);
  const histStart = D.toDay('2023-01-01');
  let clientA = null, clientB = null;

  if (opts.target === 'pg') {
    pg = require('pg');
    copyFrom = require('pg-copy-streams').from;
    clientA = new pg.Client({ connectionString: opts.dbUrl });
    clientB = new pg.Client({ connectionString: opts.dbUrl });
    await clientA.connect(); await clientB.connect();
    log(`Creating schema in ${opts.dbUrl.replace(/:[^:@/]+@/, ':****@')}`);
    await clientA.query(fs.readFileSync(path.join(__dirname, '..', 'warehouse', 'schema.sql'), 'utf8'));
    await clientA.query('INSERT INTO dataset_meta (scale, seed, as_of) VALUES ($1, $2, $3)', [opts.scale, opts.seed, opts.asOf]);
  } else {
    fs.mkdirSync(opts.out, { recursive: true });
    fs.writeFileSync(path.join(opts.out, 'dataset_meta.csv'), `scale,seed,as_of\n${opts.scale},${opts.seed},${opts.asOf}\n`);
  }
  log(`Generating scale "${opts.scale}" (seed ${opts.seed}, data as of ${opts.asOf})`);

  // ----- products: 25 origins x 4 roasts x 4 sizes -----
  const products = [];
  {
    const sink = await openSink('products', ['id', 'sku', 'name', 'origin', 'roast', 'size', 'list_price', 'active'], clientA);
    let id = 0;
    D.ORIGINS.forEach(([origin, mult], oi) => D.ROASTS.forEach((roast, ri) => D.SIZES.forEach(([size, base], si) => {
      id++;
      const price = Math.round(base * mult * (roast === 'Light' ? 1.04 : 1) * 100) / 100;
      const ethiopian = origin.startsWith('Ethiopia');
      products.push({ id, price, size, ethiopian, retailW: (si === 0 ? 6 : si === 1 ? 3 : 0.3) * (ethiopian ? 2 : 1), wholesaleW: (si === 0 ? 0.5 : si === 1 ? 3 : 5) * (ethiopian ? 1.6 : 1) * (origin.includes('Blend') ? 2.5 : 1) });
      sink.write([id, `LCR-${D.pad(oi + 1, 2)}${ri + 1}${si + 1}`, `${origin}, ${roast} Roast, ${size}`, origin, roast, size, price.toFixed(2), r.chance(0.96)]);
    })));
    await sink.end();
  }
  const cumulate = (arr, f) => { let s = 0; return arr.map((x) => (s += f(x))); };
  const prodRetailCum = cumulate(products, (p) => p.retailW);
  const prodWholesaleCum = cumulate(products, (p) => p.wholesaleW);

  // ----- accounts -----
  const segPairs = Object.entries(D.SEGMENTS).map(([k, v]) => [k, v.w]);
  const cityPairs = D.CITIES.map((c, i) => [i, c[2]]);
  const accounts = new Array(N.accounts);
  {
    const sink = await openSink('accounts', ['id', 'warehouse_id', 'name', 'segment', 'tier', 'city', 'state', 'sales_rep', 'payment_terms', 'created_at', 'churned_at', 'updated_at'], clientA);
    const created0 = D.toDay('2021-06-01');
    for (let i = 0; i < N.accounts; i++) {
      const id = i + 1;
      const segment = r.weighted(segPairs);
      const [city, state] = D.CITIES[r.weighted(cityPairs)];
      // Pareto-ish size: a few large accounts place most of the orders
      const weight = 1 / Math.pow(r.int(1, N.accounts), 0.85);
      const tier = weight > 0.02 ? 'Platinum' : weight > 0.002 ? 'Gold' : r.chance(0.5) ? 'Silver' : 'Bronze';
      const created = r.int(created0, asOf - 60);
      const churned = r.chance(0.15) && created + 180 < asOf - 30 ? r.int(created + 180, asOf - 30) : null;
      const terms = segment === 'Office' || segment === 'University' || segment === 'Hotel' ? 'Net 30' : r.weighted([['Net 15', 5], ['Net 30', 3], ['Prepaid', 2]]);
      const suffix = r.pick(D.SEGMENTS[segment].suffix);
      const name = `${r.pick(D.PLACES)} ${suffix}${r.chance(0.35) ? ` #${r.int(2, 40)}` : ''}`;
      accounts[i] = { id, weight, tier, created, churned, terms };
      const updated = `${D.fromDay(Math.min(asOf, created + r.int(0, asOf - created)))} ${D.pad(r.int(0, 23), 2)}:${D.pad(r.int(0, 59), 2)}:00+00`;
      const p = sink.write([id, `ACC-${D.pad(id, 7)}`, name, segment, tier, city, state, r.pick(D.REPS), terms, D.fromDay(created), churned === null ? null : D.fromDay(churned), updated]);
      if (p) await p;
    }
    await sink.end();
  }
  const accountCum = cumulate(accounts, (a) => a.weight);

  // ----- contacts: 3 per account -----
  {
    const sink = await openSink('contacts', ['id', 'warehouse_id', 'account_id', 'first_name', 'last_name', 'title', 'email', 'phone', 'is_primary'], clientA);
    let id = 0;
    for (const a of accounts) {
      for (let k = 0; k < 3; k++) {
        id++;
        const first = r.pick(D.FIRST), last = r.pick(D.LAST);
        const p = sink.write([id, `CON-${D.pad(id, 7)}`, a.id, first, last, k === 0 ? 'Owner' : r.weighted(D.CONTACT_TITLES),
          `${first}.${last}.${id}@example.com`.toLowerCase(), `202-555-01${D.pad(r.int(0, 99), 2)}`, k === 0]);
        if (p) await p;
      }
    }
    await sink.end();
  }

  // ----- customers (direct to consumer) -----
  const customers = new Array(N.customers);
  {
    const sink = await openSink('customers', ['id', 'warehouse_id', 'first_name', 'last_name', 'email', 'city', 'state', 'subscriber', 'created_at'], clientA);
    const c0 = D.toDay('2021-01-01');
    for (let i = 0; i < N.customers; i++) {
      const id = i + 1;
      const subscriber = r.chance(0.25);
      const created = r.int(c0, asOf - 7);
      customers[i] = { id, created, w: subscriber ? 6 : 1 };
      const first = r.pick(D.FIRST), last = r.pick(D.LAST);
      const [city, state] = D.CITIES[r.weighted(cityPairs)];
      const p = sink.write([id, `CUS-${D.pad(id, 7)}`, first, last, `${first}.${last}.${id}@example.com`.toLowerCase(), city, state, subscriber, D.fromDay(created)]);
      if (p) await p;
      progress('customers', i, N.customers);
    }
    await sink.end();
  }
  const customerCum = cumulate(customers, (c) => c.w);

  // Seasonal, gently growing order dates
  const span = asOf - histStart;
  const orderDay = () => {
    for (;;) {
      const d = r.int(histStart, asOf);
      const month = new Date(d * 86400000).getUTCMonth();
      const accept = D.MONTH_WEIGHT[month] / 1.45 * (0.65 + 0.35 * (d - histStart) / span);
      if (r.next() < accept) return d;
    }
  };

  // Pick a buyer and a date inside the buyer's active window. Re-draw both a few times
  // (keeps the seasonal curve honest), then fall back to a random day in the window.
  const pickBuyer = (wholesale) => {
    let buyer, lo, hi;
    for (let tries = 0; tries < 8; tries++) {
      const day = orderDay();
      if (wholesale) {
        buyer = accounts[D.pickCumulative(accountCum, r.next())];
        lo = buyer.created; hi = buyer.churned === null ? asOf : buyer.churned;
      } else {
        buyer = customers[D.pickCumulative(customerCum, r.next())];
        lo = buyer.created; hi = asOf;
      }
      if (day >= lo && day <= hi) return { day, acct: wholesale ? buyer : null, cust: wholesale ? null : buyer };
    }
    const day = r.int(Math.max(lo, histStart), Math.max(hi, histStart));
    return { day, acct: wholesale ? buyer : null, cust: wholesale ? null : buyer };
  };

  // ----- orders + order lines, streamed side by side on two connections -----
  {
    const oCols = ['id', 'order_number', 'account_id', 'customer_id', 'order_date', 'ship_date', 'status', 'payment_status', 'channel', 'subtotal', 'discount', 'shipping', 'total', 'line_count'];
    const lCols = ['id', 'order_id', 'product_id', 'quantity', 'unit_price', 'line_total'];
    const oSink = await openSink('orders', oCols, clientA);
    const lSink = await openSink('order_lines', lCols, clientB);
    const TIER_PRICE = { Platinum: 0.7, Gold: 0.75, Silver: 0.8, Bronze: 0.85 };
    let lineId = 0;
    for (let i = 0; i < N.orders; i++) {
      const id = i + 1;
      const wholesale = r.chance(0.3);
      const { day, acct, cust } = pickBuyer(wholesale);
      const age = asOf - day;
      let status;
      if (age <= 2) status = r.chance(0.6) ? 'Placed' : 'Roasting';
      else if (age <= 6) status = r.chance(0.3) ? 'Roasting' : 'Shipped';
      else if (age <= 12) status = r.chance(0.5) ? 'Shipped' : 'Delivered';
      else status = r.chance(0.03) ? 'Cancelled' : 'Delivered';
      const shipDay = status === 'Shipped' || status === 'Delivered' ? Math.min(asOf, day + r.int(1, 4)) : null;

      // lines
      const nLines = wholesale ? r.int(2, 6) : r.weighted([[1, 50], [2, 30], [3, 20]]);
      let subtotal = 0;
      const used = new Set();
      for (let k = 0; k < nLines; k++) {
        let p = products[D.pickCumulative(wholesale ? prodWholesaleCum : prodRetailCum, r.next())];
        if (used.has(p.id)) p = products[r.int(0, products.length - 1)];
        used.add(p.id);
        const qty = wholesale ? r.int(1, p.size === '5 lb' ? 12 : 24) : r.weighted([[1, 75], [2, 20], [3, 5]]);
        const unit = Math.round(p.price * (wholesale ? TIER_PRICE[acct.tier] : 1) * 100) / 100;
        const lt = Math.round(unit * qty * 100) / 100;
        subtotal += lt;
        lineId++;
        const lp = lSink.write([lineId, id, p.id, qty, unit.toFixed(2), lt.toFixed(2)]);
        if (lp) await lp;
      }
      subtotal = Math.round(subtotal * 100) / 100;
      const discount = !wholesale && r.chance(0.15) ? Math.round(subtotal * 0.1 * 100) / 100 : 0;
      const shipping = wholesale ? (subtotal >= 250 ? 0 : 25) : (subtotal >= 50 ? 0 : 6.95);
      const total = Math.round((subtotal - discount + shipping) * 100) / 100;

      let payment;
      if (status === 'Cancelled') payment = 'Refunded';
      else if (!wholesale) payment = r.chance(0.015) ? 'Refunded' : 'Paid';
      else if (acct.terms === 'Prepaid') payment = 'Paid';
      else {
        const termDays = acct.terms === 'Net 15' ? 15 : 30;
        if (age < termDays) payment = 'Invoiced';
        else payment = r.chance(acct.churned !== null ? 0.12 : 0.04) ? 'Overdue' : 'Paid';
      }
      const channel = wholesale ? r.weighted([['Sales Rep', 4], ['Wholesale Portal', 5], ['Phone', 1]]) : r.weighted([['Shopify', 9], ['Pop-up Event', 1]]);

      const op = oSink.write([id, `LWO-${D.pad(id, 8)}`, acct ? acct.id : null, cust ? cust.id : null, D.fromDay(day),
        shipDay === null ? null : D.fromDay(shipDay), status, payment, channel, subtotal.toFixed(2), discount.toFixed(2), shipping.toFixed(2), total.toFixed(2), nLines]);
      if (op) await op;
      progress('orders', i, N.orders);
    }
    await Promise.all([oSink.end(), lSink.end()]);
    log(`  orders: ${oSink.rows.toLocaleString()}, order_lines: ${lSink.rows.toLocaleString()}            `);
  }

  // ----- support cases -----
  {
    const sink = await openSink('support_cases', ['id', 'case_number', 'account_id', 'customer_id', 'reason', 'priority', 'status', 'created_at', 'closed_at', 'csat'], clientA);
    for (let i = 0; i < N.cases; i++) {
      const id = i + 1;
      const forAccount = r.chance(0.4);
      const { day, acct, cust } = pickBuyer(forAccount);
      const reason = r.weighted(D.CASE_REASONS);
      const priority = reason === 'Equipment issue' || (forAccount && acct.tier === 'Platinum') ? r.weighted([['High', 5], ['Medium', 4], ['Low', 1]]) : r.weighted([['High', 1], ['Medium', 5], ['Low', 4]]);
      const age = asOf - day;
      const closed = age > 30 ? r.chance(0.995) : age > 10 ? r.chance(0.7) : r.chance(0.2);
      const status = closed ? 'Closed' : r.weighted([['New', 3], ['Working', 5], ['Escalated', 1]]);
      const closedDay = closed ? Math.min(asOf, day + r.int(0, 9)) : null;
      const csat = closed && r.chance(0.45) ? (reason === 'Late delivery' || reason === 'Damaged bag'
        ? r.weighted([[5, 20], [4, 25], [3, 25], [2, 15], [1, 15]]) : r.weighted([[5, 40], [4, 30], [3, 15], [2, 8], [1, 7]])) : null;
      const p = sink.write([id, `CS-${D.pad(id, 7)}`, acct ? acct.id : null, cust ? cust.id : null, reason, priority, status,
        D.fromDay(day), closedDay === null ? null : D.fromDay(closedDay), csat]);
      if (p) await p;
      progress('cases', i, N.cases);
    }
    await sink.end();
  }

  const loadSecs = ((Date.now() - t0) / 1000).toFixed(1);
  if (opts.target === 'pg') {
    log(`Rows loaded in ${loadSecs}s. Building keys, indexes and summary views...`);
    const sql = fs.readFileSync(path.join(__dirname, '..', 'warehouse', 'post_load.sql'), 'utf8')
      .split('\n').filter((l) => !l.startsWith('\\')).join('\n');
    const statements = sql.split(/;\s*\n/).map((s) => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean);
    let counts = null;
    for (const st of statements) {
      const t = Date.now();
      const res = await clientA.query(st);
      if (st.startsWith('SELECT')) counts = res.rows;
      else if (!opts.quiet && Date.now() - t > 2000) log(`  ${st.split('\n')[0].slice(0, 70)}  (${((Date.now() - t) / 1000).toFixed(1)}s)`);
    }
    const total = counts.reduce((s, row) => s + Number(row.rows), 0);
    log('\nTable            Rows');
    counts.forEach((row) => log(`${row.table_name.padEnd(16)} ${Number(row.rows).toLocaleString().padStart(11)}`));
    log(`${'TOTAL'.padEnd(16)} ${total.toLocaleString().padStart(11)}`);
    await clientA.end(); await clientB.end();
  } else {
    log(`CSV files written to ${opts.out} in ${loadSecs}s`);
  }
  log(`Done in ${((Date.now() - t0) / 1000).toFixed(1)}s.`);
}

main().catch((err) => { console.error('\nGeneration failed:', err.message); process.exit(1); });
