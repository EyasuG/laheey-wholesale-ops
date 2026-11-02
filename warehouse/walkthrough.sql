-- Large-data-volume walkthrough. Run each block in psql and compare the "Execution Time" lines.
--   docker exec -it laheey-warehouse-db psql -U laheey warehouse
--   \timing on
-- Measured on the 10M-row scale (laptop-class machine); your numbers will differ but the ratios hold.

-- 1. How big is this? (counts from table statistics: instant, even at 10M rows)
SELECT relname AS table_name, n_live_tup AS approx_rows, pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_stat_user_tables ORDER BY n_live_tup DESC;

-- 2. Selective query on an indexed column: one account's 50 newest orders.  Measured: 0.7 ms
EXPLAIN ANALYZE
SELECT id, order_number, order_date, total
FROM orders
WHERE account_id = (SELECT account_id FROM account_rank WHERE rank = 1)
ORDER BY order_date DESC, id DESC
LIMIT 50;

-- 3. The same query with indexes switched off: a full scan of 2.6M orders.  Measured: 146 ms (~200x slower)
SET enable_indexscan = off; SET enable_bitmapscan = off;
EXPLAIN ANALYZE
SELECT id, order_number, order_date, total
FROM orders
WHERE account_id = (SELECT account_id FROM account_rank WHERE rank = 1)
ORDER BY order_date DESC, id DESC
LIMIT 50;
RESET enable_indexscan; RESET enable_bitmapscan;

-- 4. OFFSET pagination deep into the table: reads and throws away 2M rows.  Measured: 275 ms
EXPLAIN ANALYZE SELECT id FROM orders ORDER BY id LIMIT 50 OFFSET 2000000;

-- 5. Keyset pagination to the same place: jumps straight there through the index.  Measured: 0.09 ms
--    This is why the API and the orderExplorer LWC page with (date, id) < (last date, last id).
EXPLAIN ANALYZE SELECT id FROM orders WHERE id > 2000000 ORDER BY id LIMIT 50;

-- 6. Aggregating 6.2M order lines on the fly.  Measured: 1.4 s
EXPLAIN ANALYZE
SELECT p.origin, SUM(l.line_total) AS revenue
FROM order_lines l JOIN products p ON p.id = l.product_id
GROUP BY p.origin ORDER BY revenue DESC;

-- 7. Pre-aggregation: 12-month revenue by segment, from raw orders vs from the account_stats view.
--    Measured: 588 ms vs 47 ms. One account's stats from the view: 0.1 ms.
--    Salesforce equivalent: sync Account_Metric__c summaries, not millions of raw lines.
EXPLAIN ANALYZE
SELECT a.segment, SUM(o.total) FROM orders o JOIN accounts a ON a.id = o.account_id
WHERE o.status <> 'Cancelled' AND o.order_date > (SELECT as_of FROM dataset_meta) - 365
GROUP BY a.segment;
EXPLAIN ANALYZE
SELECT a.segment, SUM(s.revenue_12m) FROM account_stats s JOIN accounts a ON a.id = s.account_id GROUP BY a.segment;
EXPLAIN ANALYZE SELECT * FROM account_stats WHERE account_id = 42;

-- 8. Data skew: how lopsided is ordering? The top 1% of accounts vs everyone else.
--    In Salesforce, one parent with more than ~10,000 children ("account data skew") causes record locking
--    during big loads. Our sync window keeps each synced account well under that.
WITH ranked AS (
  SELECT s.account_id, s.order_count, NTILE(100) OVER (ORDER BY s.order_count DESC) AS pct
  FROM account_stats s)
SELECT CASE WHEN pct = 1 THEN 'top 1%' ELSE 'other 99%' END AS accounts,
       COUNT(*) AS n, SUM(order_count) AS orders, MAX(order_count) AS max_orders_one_account
FROM ranked GROUP BY 1;

-- 9. Business questions an interviewer may ask you to answer live
-- 9a. Revenue by segment, last 12 months
SELECT a.segment, ROUND(SUM(s.revenue_12m)) AS revenue_12m, COUNT(*) AS accounts
FROM account_stats s JOIN accounts a ON a.id = s.account_id
GROUP BY a.segment ORDER BY 2 DESC;

-- 9b. Churned accounts that still have overdue invoices
SELECT a.warehouse_id, a.name, a.churned_at, COUNT(*) AS overdue_orders, SUM(o.total) AS overdue_amount
FROM accounts a JOIN orders o ON o.account_id = a.id
WHERE a.churned_at IS NOT NULL AND o.payment_status = 'Overdue'
GROUP BY a.id ORDER BY overdue_amount DESC LIMIT 20;

-- 9c. Which complaint drives the worst satisfaction?
SELECT reason, COUNT(*) AS cases, ROUND(AVG(csat), 2) AS avg_csat
FROM support_cases WHERE csat IS NOT NULL
GROUP BY reason ORDER BY avg_csat;

-- 9d. Best-selling Ethiopian coffees by revenue
SELECT p.origin, p.roast, SUM(l.quantity) AS units, ROUND(SUM(l.line_total)) AS revenue
FROM order_lines l JOIN products p ON p.id = l.product_id
WHERE p.origin LIKE 'Ethiopia%'
GROUP BY p.origin, p.roast ORDER BY revenue DESC LIMIT 10;
