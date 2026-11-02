# Data model

## Warehouse (PostgreSQL)

| Table | Rows (s / l) | Key columns | Notes |
|---|---|---|---|
| `products` | 400 / 400 | `sku`, `origin`, `roast`, `size`, `list_price` | 25 origins x 4 roasts x 4 sizes. Ethiopian origins sell about 2x. |
| `accounts` | 5,000 / 50,000 | `warehouse_id` (ACC-0000123), `segment`, `tier`, `payment_terms`, `created_at`, `churned_at` | Wholesale clients. About 15% churned. Order volume follows a power law: a few accounts are huge. |
| `contacts` | 15,000 / 150,000 | `warehouse_id` (CON-...), `account_id`, `title`, `is_primary` | 3 per account; the first is the Owner. |
| `customers` | 60,000 / 600,000 | `warehouse_id` (CUS-...), `subscriber` | Direct buyers from the Shopify store; 25% are subscribers and order 6x as often. |
| `orders` | 260,000 / 2,600,000 | `order_number` (LWO-00001234), `account_id` XOR `customer_id`, `status`, `payment_status`, `total` | 30% wholesale, 70% retail. Jan 2023 to the as-of date, with growth and November–December peaks. |
| `order_lines` | ~620k / ~6.2M | `order_id`, `product_id`, `quantity`, `unit_price` | Wholesale: 2–6 lines at tier prices; retail: 1–3 lines at list price. |
| `support_cases` | 40,000 / 400,000 | `case_number`, `reason`, `priority`, `status`, `csat` | Late deliveries and damaged bags score the lowest satisfaction. |
| `dataset_meta` | 1 | `scale`, `seed`, `as_of` | Describes the generated dataset. |

Rules the data follows (enforced by tests or constraints):
- Every order has exactly one buyer (`CHECK ((account_id IS NULL) <> (customer_id IS NULL))`).
- `subtotal` = sum of its lines; `total = subtotal - discount + shipping`.
- Orders fall inside the buyer's active window (after `created_at`, before `churned_at`).
- Status follows age: orders under 3 days old are Placed or Roasting; older than 12 days are Delivered (3% Cancelled).
- Payment: Net 15/30 accounts are Invoiced until terms pass, then Paid, or Overdue (4%; 12% for churned accounts).

Materialized views (rebuilt by `post_load.sql`):
- `account_stats`: lifetime and 12-month revenue, order counts, last order date, open cases per account.
- `account_monthly_metrics`: revenue, orders and average order value per account per month, last 24 months.
- `account_rank`: active accounts ranked by 12-month revenue. Defines "top N".

## Salesforce

```
Account (standard, extended)
 ├── Contact (standard, extended)                    lookup
 ├── Wholesale_Order__c                              master-detail
 │     └── Order_Line__c                             master-detail
 └── Account_Metric__c                               master-detail
Integration_Log__c                                   standalone
```

| Object | Name field | Fields added |
|---|---|---|
| Account | Name | `Warehouse_Id__c` (external ID, unique), `Segment__c`, `Tier__c`, `Sales_Rep__c`, `Payment_Terms__c`, `Lifetime_Revenue__c`, `Revenue_12M__c`, `Orders_Last_90_Days__c`, `Last_Order_Date__c`, `Open_Cases__c`, `Health_Score__c`, `Health_Status__c` (history tracked), `Last_Synced__c` |
| Contact | Name | `Warehouse_Id__c`, `Primary_Contact__c` |
| Wholesale_Order__c | Order Number (text) | `Account__c` (MD), `Warehouse_Id__c`, `Order_Date__c`, `Ship_Date__c`, `Status__c`, `Payment_Status__c` (both history tracked), `Channel__c`, `Subtotal__c`, `Discount__c`, `Shipping__c`, `Total__c`, `Line_Count__c`; validation rule: ship date not before order date |
| Order_Line__c | LINE-000001 (auto) | `Wholesale_Order__c` (MD), `Product_Name__c`, `Quantity__c`, `Unit_Price__c`, `Line_Total__c` (formula) |
| Account_Metric__c | Month text (2026-09) | `Account__c` (MD), `Warehouse_Id__c` (ACC-0000123-2026-09), `Month__c`, `Revenue__c`, `Order_Count__c`, `Avg_Order_Value__c` |
| Integration_Log__c | LOG-000001 (auto) | `Job__c`, `Stage__c`, `Status__c`, `Records_Processed__c`, `Errors__c`, `Cursor__c`, `Duration_Ms__c`, `Message__c` |

Why master-detail for orders and metrics: they have no meaning without their account, sharing should follow the account, and deleting an account should remove them. Why a lookup for Contact: it's a standard relationship, and contacts can outlive an account relationship.

## Mapping

| Warehouse | API field | Salesforce |
|---|---|---|
| `accounts.warehouse_id` | `warehouseId` | `Account.Warehouse_Id__c` |
| `accounts.city / state` | `city` / `state` | `BillingCity` / `BillingState` |
| `account_stats.revenue_12m` | `revenue12m` | `Revenue_12M__c` |
| `account_stats.orders_90d` | `orders90d` | `Orders_Last_90_Days__c` |
| `contacts.account_id` → account | `accountWarehouseId` | `Contact.Account` via `Account.Warehouse_Id__c` |
| `orders.order_number` | `orderNumber` / `warehouseId` | `Wholesale_Order__c.Name` and `Warehouse_Id__c` |
| `orders.account_id` → account | `accountWarehouseId` | `Account__r.Warehouse_Id__c` |
| `orders.total` | `total` | recalculated as `Total__c` by the trigger (same formula) |
| `account_monthly_metrics` row | `warehouseId` = ACC-…-YYYY-MM | `Account_Metric__c` |
