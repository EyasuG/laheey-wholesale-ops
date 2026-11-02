# Large data volumes

Measured on the 10,014,941-row dataset (scale `l`, PostgreSQL 16, cloud dev machine). Re-run `warehouse/walkthrough.sql` to get your own numbers; the ratios matter more than the milliseconds.

| Question | Slow way | Time | Fast way | Time | Speed-up |
|---|---|---|---|---|---|
| One account's 50 newest orders (2.6M orders) | Full scan, no index | 146 ms | Composite index `(account_id, order_date DESC, id DESC)` | 0.7 ms | ~200x |
| Page 40,001 of orders, 50 per page | `OFFSET 2000000` | 275 ms | Keyset: `WHERE id > :last ORDER BY id` | 0.09 ms | ~3,000x |
| 12-month revenue by segment (2.6M orders) | Aggregate raw orders at query time | 588 ms | Aggregate the pre-built `account_stats` view | 47 ms | ~12x |
| One account's lifetime stats | (same raw aggregate, per account) | n/a | Read one row of `account_stats` | 0.1 ms | n/a |
| Full load of 10M rows | (not measured) | | `COPY` streams, then build keys and indexes | 3 min 57 s | |

## The same ideas in Salesforce

**Selective queries.** Salesforce's query optimizer uses an index only when a filter is selective (roughly, it matches a small share of the table). Indexed by default: Id, Name, owner, lookup and master-detail fields, audit dates, and any **External ID** or **Unique** field. That's why every query in this project filters on `Warehouse_Id__c`, `Account__c` or Id. Use Developer Console → Query Plan to compare costs.

**Keyset pagination.** SOQL `OFFSET` stops at 2,000 rows. `OrderExplorerController` pages with `(Order_Date__c, Id) < (last date, last Id)`, the same trick as the API.

**Bulk API 2.0 for volume.** `load-salesforce.sh` uses `sf data upsert bulk`. Salesforce splits each job into batches and processes them asynchronously. Upserting on an external ID means no pre-lookup of Salesforce Ids and safe re-runs.

**Batch Apex for processing.** `AccountHealthBatch` uses a QueryLocator (up to 50 million records), handles 200 accounts per `execute`, runs one aggregate query per chunk, and updates only accounts whose score changed.

**Store aggregates, not raw rows.** 6.2M order lines become one `Subtotal__c` per order and 12 `Account_Metric__c` rows per account. Storage is expensive, and reports run faster on summaries.

**Data skew.** One parent with more than about 10,000 child records (account data skew), or one user owning more than about 10,000 records (ownership skew), causes lock contention and slow sharing recalculation during loads. The top account here has thousands of lifetime orders, but the 60-day sync window keeps each account to a few hundred children in Salesforce. Section 8 of `walkthrough.sql` measures the skew.

**Load order and locking.** Parents load before children. Loading children sorted by parent keeps rows for the same parent in the same batch, which reduces lock contention (the export sorts orders by id; sorting by account is a worthwhile Level 6 experiment).

**Defer what you can.** Big loads go faster with non-essential automation paused. Here, the status rule is skipped for the integration user via a custom permission rather than switched off for everyone.

## Questions to be ready for

- "How would you load 5 million records into Salesforce?" Bulk API 2.0, parents first, upsert on external IDs, children sorted by parent, automation deferred for the integration user, watch for skew, validate counts afterwards.
- "A report on Orders times out." Check filter selectivity, add an index-friendly filter (date range on an indexed field), consider a summary object, use a custom index request for a high-cardinality field.
- "How do you page through 100,000 records in an LWC?" Keyset pagination with a stable sort and a tie-breaker (Id), never OFFSET.
