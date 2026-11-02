-- Runs after the bulk load. Order matters: keys first, then indexes, then views.
\timing on

-- Primary keys (built once over the loaded data: much faster than during COPY)
ALTER TABLE products      ADD PRIMARY KEY (id);
ALTER TABLE accounts      ADD PRIMARY KEY (id);
ALTER TABLE contacts      ADD PRIMARY KEY (id);
ALTER TABLE customers     ADD PRIMARY KEY (id);
ALTER TABLE orders        ADD PRIMARY KEY (id);
ALTER TABLE order_lines   ADD PRIMARY KEY (id);
ALTER TABLE support_cases ADD PRIMARY KEY (id);

-- External IDs must be unique, exactly like Warehouse_Id__c in Salesforce
CREATE UNIQUE INDEX accounts_warehouse_id_uq  ON accounts (warehouse_id);
CREATE UNIQUE INDEX contacts_warehouse_id_uq  ON contacts (warehouse_id);
CREATE UNIQUE INDEX customers_warehouse_id_uq ON customers (warehouse_id);
CREATE UNIQUE INDEX orders_number_uq          ON orders (order_number);
CREATE UNIQUE INDEX cases_number_uq           ON support_cases (case_number);

-- Foreign keys
ALTER TABLE contacts      ADD FOREIGN KEY (account_id)  REFERENCES accounts (id);
ALTER TABLE orders        ADD FOREIGN KEY (account_id)  REFERENCES accounts (id);
ALTER TABLE orders        ADD FOREIGN KEY (customer_id) REFERENCES customers (id);
ALTER TABLE order_lines   ADD FOREIGN KEY (order_id)    REFERENCES orders (id);
ALTER TABLE order_lines   ADD FOREIGN KEY (product_id)  REFERENCES products (id);
ALTER TABLE support_cases ADD FOREIGN KEY (account_id)  REFERENCES accounts (id);
ALTER TABLE support_cases ADD FOREIGN KEY (customer_id) REFERENCES customers (id);
ALTER TABLE orders ADD CONSTRAINT orders_one_buyer CHECK ((account_id IS NULL) <> (customer_id IS NULL));

-- Indexes that the API and the walkthrough queries rely on
CREATE INDEX orders_account_date_idx  ON orders (account_id, order_date DESC, id DESC) WHERE account_id IS NOT NULL;
CREATE INDEX orders_customer_idx      ON orders (customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX orders_date_idx          ON orders (order_date);
CREATE INDEX order_lines_order_idx    ON order_lines (order_id);
CREATE INDEX order_lines_product_idx  ON order_lines (product_id);
CREATE INDEX contacts_account_idx     ON contacts (account_id);
CREATE INDEX cases_account_idx        ON support_cases (account_id) WHERE account_id IS NOT NULL;
CREATE INDEX cases_open_idx           ON support_cases (account_id) WHERE status <> 'Closed';
CREATE INDEX accounts_updated_idx     ON accounts (updated_at);

-- Lifetime and recent stats per wholesale account (what Salesforce shows on the Account)
CREATE MATERIALIZED VIEW account_stats AS
SELECT a.id AS account_id,
       COALESCE(SUM(o.total) FILTER (WHERE o.status <> 'Cancelled'), 0)::numeric(14,2)                           AS lifetime_revenue,
       COUNT(o.id) FILTER (WHERE o.status <> 'Cancelled')                                                       AS order_count,
       COUNT(o.id) FILTER (WHERE o.status <> 'Cancelled' AND o.order_date > m.as_of - 90)                       AS orders_90d,
       COALESCE(SUM(o.total) FILTER (WHERE o.status <> 'Cancelled' AND o.order_date > m.as_of - 365), 0)::numeric(14,2) AS revenue_12m,
       MAX(o.order_date) FILTER (WHERE o.status <> 'Cancelled')                                                 AS last_order_date,
       (SELECT COUNT(*) FROM support_cases c WHERE c.account_id = a.id AND c.status <> 'Closed')                 AS open_cases
FROM accounts a
CROSS JOIN dataset_meta m
LEFT JOIN orders o ON o.account_id = a.id
GROUP BY a.id, m.as_of;
CREATE UNIQUE INDEX account_stats_pk ON account_stats (account_id);

-- Monthly revenue per wholesale account for the last 24 months (charted in the LWC)
CREATE MATERIALIZED VIEW account_monthly_metrics AS
SELECT o.account_id,
       date_trunc('month', o.order_date)::date AS month,
       SUM(o.total)::numeric(14,2)             AS revenue,
       COUNT(*)                                AS order_count,
       ROUND(AVG(o.total), 2)                  AS avg_order_value
FROM orders o
CROSS JOIN dataset_meta m
WHERE o.account_id IS NOT NULL
  AND o.status <> 'Cancelled'
  AND o.order_date >= date_trunc('month', m.as_of) - interval '23 months'
GROUP BY o.account_id, date_trunc('month', o.order_date);
CREATE UNIQUE INDEX account_monthly_metrics_pk ON account_monthly_metrics (account_id, month);

-- Accounts ranked by last-12-month revenue: the "top N" subset that is synced into Salesforce
CREATE MATERIALIZED VIEW account_rank AS
SELECT s.account_id,
       ROW_NUMBER() OVER (ORDER BY s.revenue_12m DESC, s.account_id) AS rank
FROM account_stats s
JOIN accounts a ON a.id = s.account_id
WHERE a.churned_at IS NULL;
CREATE UNIQUE INDEX account_rank_rank_idx ON account_rank (rank);
CREATE UNIQUE INDEX account_rank_account_idx ON account_rank (account_id);

ANALYZE;

SELECT 'products' AS table_name, COUNT(*) AS rows FROM products
UNION ALL SELECT 'accounts', COUNT(*) FROM accounts
UNION ALL SELECT 'contacts', COUNT(*) FROM contacts
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_lines', COUNT(*) FROM order_lines
UNION ALL SELECT 'support_cases', COUNT(*) FROM support_cases;
