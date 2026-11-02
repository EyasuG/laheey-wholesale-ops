#!/usr/bin/env node
'use strict';
/*
 * Exports the slice of the warehouse that fits in a Salesforce org, as Bulk API 2.0 CSV files.
 * Column headers are Salesforce field API names, and parent links use external IDs
 * (Account__r.Warehouse_Id__c), so the files upsert in any order-safe sequence with no Salesforce Ids.
 *
 *   node scripts/export-subset.js                      scratch org defaults: top 2000 accounts, 60 days, 12 months
 *   node scripts/export-subset.js --profile dev-edition   Developer Edition (5 MB): top 50, 30 days, 6 months
 */
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, arr) => {
  if (a.startsWith('--')) acc.push([a.slice(2), arr[i + 1] && !arr[i + 1].startsWith('--') ? arr[i + 1] : 'true']);
  return acc;
}, []));
const PROFILES = { 'scratch': { top: 2000, days: 60, months: 12 }, 'dev-edition': { top: 50, days: 30, months: 6 } };
const p = PROFILES[args.profile || 'scratch'];
if (!p) { console.error('Unknown --profile. Use scratch or dev-edition.'); process.exit(1); }
const top = Number(args.top || p.top), days = Number(args.days || p.days), months = Number(args.months || p.months);
const out = args.out || path.join(__dirname, '..', 'exports');

const csv = (v) => { if (v === null || v === undefined) return ''; const s = v instanceof Date ? v.toISOString().slice(0, 10) : String(v); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };

async function dump(client, file, header, sql, params) {
  const { rows } = await client.query(sql, params);
  const lines = [header.join(',')].concat(rows.map((r) => Object.values(r).map(csv).join(',')));
  fs.writeFileSync(path.join(out, file), lines.join('\n') + '\n');
  console.log(`${file.padEnd(14)} ${String(rows.length).padStart(7)} rows`);
  return rows.length;
}

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const client = new Client({ connectionString: process.env.DATABASE_URL || 'postgres://laheey:laheey@localhost:5432/warehouse' });
  await client.connect();
  console.log(`Exporting top ${top} accounts, ${days} days of orders, ${months} months of metrics to ${out}`);
  let total = 0;

  total += await dump(client, 'accounts.csv',
    ['Name', 'Warehouse_Id__c', 'Segment__c', 'Tier__c', 'BillingCity', 'BillingState', 'Sales_Rep__c', 'Payment_Terms__c',
      'Lifetime_Revenue__c', 'Revenue_12M__c', 'Orders_Last_90_Days__c', 'Last_Order_Date__c', 'Open_Cases__c'],
    `SELECT a.name, a.warehouse_id, a.segment, a.tier, a.city, a.state, a.sales_rep, a.payment_terms,
            s.lifetime_revenue, s.revenue_12m, s.orders_90d, s.last_order_date, s.open_cases
     FROM account_rank r JOIN accounts a ON a.id = r.account_id JOIN account_stats s ON s.account_id = r.account_id
     WHERE r.rank <= $1 ORDER BY r.rank`, [top]);

  total += await dump(client, 'contacts.csv',
    ['FirstName', 'LastName', 'Title', 'Email', 'Phone', 'Warehouse_Id__c', 'Primary_Contact__c', 'Account.Warehouse_Id__c'],
    `SELECT c.first_name, c.last_name, c.title, c.email, c.phone, c.warehouse_id, c.is_primary, a.warehouse_id AS account_wid
     FROM contacts c JOIN account_rank r ON r.account_id = c.account_id AND r.rank <= $1 JOIN accounts a ON a.id = c.account_id
     ORDER BY c.id`, [top]);

  total += await dump(client, 'orders.csv',
    ['Name', 'Warehouse_Id__c', 'Account__r.Warehouse_Id__c', 'Order_Date__c', 'Ship_Date__c', 'Status__c', 'Payment_Status__c',
      'Channel__c', 'Subtotal__c', 'Discount__c', 'Shipping__c', 'Line_Count__c'],
    `SELECT o.order_number, o.order_number AS wid, a.warehouse_id AS account_wid, o.order_date, o.ship_date, o.status, o.payment_status,
            o.channel, o.subtotal, o.discount, o.shipping, o.line_count
     FROM orders o JOIN account_rank r ON r.account_id = o.account_id AND r.rank <= $1 JOIN accounts a ON a.id = o.account_id
     CROSS JOIN dataset_meta m
     WHERE o.order_date > m.as_of - $2::int ORDER BY o.id`, [top, days]);

  total += await dump(client, 'metrics.csv',
    ['Name', 'Warehouse_Id__c', 'Account__r.Warehouse_Id__c', 'Month__c', 'Revenue__c', 'Order_Count__c', 'Avg_Order_Value__c'],
    `SELECT to_char(mm.month, 'YYYY-MM'), a.warehouse_id || '-' || to_char(mm.month, 'YYYY-MM'), a.warehouse_id, mm.month,
            mm.revenue, mm.order_count, mm.avg_order_value
     FROM account_monthly_metrics mm JOIN account_rank r ON r.account_id = mm.account_id AND r.rank <= $1
     JOIN accounts a ON a.id = mm.account_id CROSS JOIN dataset_meta m
     WHERE mm.month >= date_trunc('month', m.as_of) - make_interval(months => $2 - 1)
     ORDER BY r.rank, mm.month`, [top, months]);

  console.log(`${'TOTAL'.padEnd(14)} ${String(total).padStart(7)} records (about ${Math.round(total * 2 / 1024)} MB of Salesforce data storage at ~2 KB each)`);
  await client.end();
})().catch((e) => { console.error(e.message); process.exit(1); });
