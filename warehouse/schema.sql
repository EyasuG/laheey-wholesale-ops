-- Laheey Commerce Warehouse: source-of-truth schema
-- Tables are created WITHOUT keys or indexes so bulk COPY is fast.
-- post_load.sql adds primary keys, foreign keys, indexes and summary views.

DROP MATERIALIZED VIEW IF EXISTS account_rank CASCADE;
DROP MATERIALIZED VIEW IF EXISTS account_monthly_metrics CASCADE;
DROP MATERIALIZED VIEW IF EXISTS account_stats CASCADE;
DROP TABLE IF EXISTS support_cases, order_lines, orders, customers, contacts, accounts, products, dataset_meta CASCADE;

-- One row describing the generated dataset (scale, seed, "today" for the data)
CREATE TABLE dataset_meta (
  scale        text        NOT NULL,
  seed         integer     NOT NULL,
  as_of        date        NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now()
);

-- Coffee catalog: 25 origins x 4 roasts x 4 sizes = 400 SKUs
CREATE TABLE products (
  id          integer       NOT NULL,
  sku         text          NOT NULL,
  name        text          NOT NULL,
  origin      text          NOT NULL,
  roast       text          NOT NULL,
  size        text          NOT NULL,
  list_price  numeric(10,2) NOT NULL,
  active      boolean       NOT NULL
);

-- Wholesale clients: cafes, grocers, offices, restaurants, hotels, universities
CREATE TABLE accounts (
  id            integer     NOT NULL,
  warehouse_id  text        NOT NULL,   -- ACC-0000123, the external ID Salesforce upserts on
  name          text        NOT NULL,
  segment       text        NOT NULL,
  tier          text        NOT NULL,   -- Bronze / Silver / Gold / Platinum
  city          text        NOT NULL,
  state         text        NOT NULL,
  sales_rep     text        NOT NULL,
  payment_terms text        NOT NULL,   -- Net 15 / Net 30 / Prepaid
  created_at    date        NOT NULL,
  churned_at    date,                   -- null = still active
  updated_at    timestamptz NOT NULL
);

-- People at wholesale clients
CREATE TABLE contacts (
  id           integer NOT NULL,
  warehouse_id text    NOT NULL,        -- CON-0000123
  account_id   integer NOT NULL,
  first_name   text    NOT NULL,
  last_name    text    NOT NULL,
  title        text    NOT NULL,
  email        text    NOT NULL,
  phone        text    NOT NULL,
  is_primary   boolean NOT NULL
);

-- Direct-to-consumer customers (Shopify store)
CREATE TABLE customers (
  id            integer NOT NULL,
  warehouse_id  text    NOT NULL,       -- CUS-0000123
  first_name    text    NOT NULL,
  last_name     text    NOT NULL,
  email         text    NOT NULL,
  city          text    NOT NULL,
  state         text    NOT NULL,
  subscriber    boolean NOT NULL,       -- coffee subscription
  created_at    date    NOT NULL
);

-- Orders from both channels: account_id XOR customer_id is set
CREATE TABLE orders (
  id             bigint        NOT NULL,
  order_number   text          NOT NULL,  -- LWO-00001234
  account_id     integer,
  customer_id    integer,
  order_date     date          NOT NULL,
  ship_date      date,
  status         text          NOT NULL,  -- Placed / Roasting / Shipped / Delivered / Cancelled
  payment_status text          NOT NULL,  -- Paid / Invoiced / Overdue / Refunded
  channel        text          NOT NULL,
  subtotal       numeric(12,2) NOT NULL,
  discount       numeric(12,2) NOT NULL,
  shipping       numeric(12,2) NOT NULL,
  total          numeric(12,2) NOT NULL,
  line_count     smallint      NOT NULL
);

CREATE TABLE order_lines (
  id          bigint        NOT NULL,
  order_id    bigint        NOT NULL,
  product_id  integer       NOT NULL,
  quantity    integer       NOT NULL,
  unit_price  numeric(10,2) NOT NULL,
  line_total  numeric(12,2) NOT NULL
);

CREATE TABLE support_cases (
  id          integer NOT NULL,
  case_number text    NOT NULL,         -- CS-0001234
  account_id  integer,
  customer_id integer,
  reason      text    NOT NULL,
  priority    text    NOT NULL,
  status      text    NOT NULL,         -- New / Working / Escalated / Closed
  created_at  date    NOT NULL,
  closed_at   date,
  csat        smallint                  -- 1-5, only on some closed cases
);
