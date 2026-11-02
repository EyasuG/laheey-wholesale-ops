# Architecture

## The business problem

Laheey's warehouse has years of orders: millions of rows. Sales reps and operations staff need to know, in Salesforce, which wholesale accounts are healthy, which are slipping, what each recently ordered and where a given order is. They don't need every 2023 order line from every direct customer.

So the design question is: **what belongs in Salesforce, and how does it get there reliably?**

## Components

| Component | Tech | Role | Real-world equivalent |
|---|---|---|---|
| Data generator | Node.js, seeded PRNG, `COPY` | Creates 1–10M realistic, reproducible rows | Years of production history |
| Warehouse | PostgreSQL 16 | Source of truth: all orders, lines, cases, customers | ERP / e-commerce database / data warehouse |
| System API | Node.js + Express | Read-only, paginated, key-protected access to the warehouse | A MuleSoft System API |
| Export + Bulk load | Node.js, `sf data upsert bulk` | Moves a slice as CSV via Bulk API 2.0 | Initial migration / data loads |
| Sync job | Apex Queueable + Schedulable | Pulls the slice nightly through a Named Credential | Scheduled integration |
| Health batch | Batch Apex | Scores every synced account | Nightly analytics job |
| UI | Two LWCs on the Account page | Health score with reasons; order history | Rep-facing Lightning pages |
| Agent | Agentforce + 2 invocable Apex actions | Answers order and account questions | AI assistant for staff |
| Observability | `Integration_Log__c` | One row per sync page or batch run | Integration monitoring |

## What goes into Salesforce

| Data | Warehouse rows (scale l) | Sent to Salesforce | Why |
|---|---|---|---|
| Wholesale accounts | 50,000 | Top 2,000 active by 12-month revenue (50 in Developer Edition) | Where reps spend their time |
| Contacts | 150,000 | Contacts of those accounts | Who to call |
| Orders | 2,600,000 | Last 60 days for those accounts (30 in DE) | Recent activity; older orders on demand via a live lookup |
| Order lines | 6,214,541 | None | Aggregated into order subtotals and monthly metrics |
| Monthly metrics | computed | 12 months per account (6 in DE) | Powers the chart and the health trend |
| Direct customers, cases | 600,000 / 400,000 | Counts only (Open Cases on Account) | Not worked by the wholesale team |

Data storage is the hard constraint: a Developer Edition org holds 5 MB (about 2,500 records at roughly 2 KB each), a scratch org about 200 MB. Production orgs pay for storage too, so "sync everything" is rarely the right answer at any company.

## Data flow

1. **Generate.** `generate.js` streams rows into Postgres with `COPY` (two connections in parallel for orders and their lines), then `post_load.sql` adds keys, indexes and materialized views. Loading first and indexing second is several times faster than indexing during the load.
2. **Rank.** The `account_rank` view orders active accounts by 12-month revenue. "Top N" means `rank <= N`, so every consumer agrees on the same slice.
3. **Move the slice, two ways:**
   - **Pull.** `WarehouseSyncJob` requests one page, upserts it, logs it, and enqueues itself for the next page; stages run accounts → contacts → orders → metrics, then the health batch.
   - **Push.** `export-subset.js` writes CSVs whose parent columns are external IDs (`Account__r.Warehouse_Id__c`), and `load-salesforce.sh` upserts them with Bulk API 2.0.
4. **Score.** `AccountHealthBatch` runs `AccountHealthService` over every synced account in chunks of 200.
5. **Use.** The LWCs read Salesforce data (fast, cached) and can refresh one account live. Agent actions read Salesforce first and fall back to a live warehouse lookup for older orders.

## Design decisions and trade-offs

**External IDs everywhere.** Every synced record carries `Warehouse_Id__c` (unique, indexed). Upserts become idempotent: re-running a failed page or a whole load never creates duplicates. Children point at parents by external ID, so loads need no Salesforce Id lookups.

**Callout first, DML second.** Apex can't make an HTTP callout after uncommitted DML in the same transaction. Each sync page does its one callout, then its upserts, then its log insert.

**One page per Queueable.** Each execution is its own transaction with fresh governor limits, so a 2,000-account sync never approaches a limit. Page sizes (200 accounts, 500 contacts, 1,000 orders, 100 accounts of metrics) keep heap and DML rows small. Trade-off: about 50 chained jobs instead of one; that is the point.

**Partial success, visible failure.** Upserts use `allOrNone = false`. One bad record (say, an unknown picklist value) is logged with its external ID; the other 199 land. A failed callout stops the chain and logs the stage and cursor, so you know where to resume.

**Keyset pagination, not OFFSET.** The API and the Order Explorer page with `(order_date, id) < (last_date, last_id)`. OFFSET reads and discards every skipped row (275 ms at 2M rows in the warehouse) and SOQL caps OFFSET at 2,000. Keyset costs the same on any page (0.09 ms).

**Pre-aggregate, then sync the aggregate.** Summing 6.2M order lines on the fly takes 1.4 s in Postgres; in Salesforce it would be impractical. Materialized views do the work once (12-month revenue by segment drops from 588 ms to 47 ms), and Salesforce gets 12 summary rows per account.

**One scoring service, three callers.** The batch, the LWC and the agent action all call `AccountHealthService`, so a rep never sees one status on the page and hears another from the agent.

**The warehouse wins on status.** Reps are held to Placed → Roasting → Shipped → Delivered. The sync (static flag) and bulk loads (custom permission `Bypass_Order_Status_Rules`) skip that rule, because a synced order may legitimately jump steps between syncs.

**Why not Salesforce Connect / external objects?** They show external rows without storing them, which suits browsing. They don't support triggers, roll-ups or most automation, and every view is a live query. This project needs scoring and automation on recent data, so it copies a slice. Being able to explain this choice is worth more than the choice itself.

## Security

- No secrets in code: the API key lives in an External Credential and is injected as a header by the Named Credential.
- The API is read-only and requires `x-api-key`; the tunnel URL is temporary.
- Apex classes run `with sharing`; queries use `WITH USER_MODE` and DML uses `update as user` where a person triggers them, so object, field and record permissions are enforced.
- Two permission sets separate everyday users from the integration user.
- The agent's actions only read data, and they return "not found or no access" rather than leaking whether a record exists.
