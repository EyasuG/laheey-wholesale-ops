# 10-minute demo script

For a technical interview, a portfolio review or a recruiter screen with screen sharing. Have these open before you start: the GitHub README, a terminal with the API running, psql connected to the 10M database, and the Salesforce org on a top account.

## 0:00 · The problem (1 minute)

"Laheey sells coffee wholesale and online. Ten million rows of orders, lines, customers and support cases live in a warehouse. Sales reps work in Salesforce. They need to know which accounts are slipping and where an order is, without copying ten million rows into a CRM that charges for storage. This project is how I connected the two."

Show: the README architecture diagram.

## 1:00 · The data is real-sized (1.5 minutes)

```bash
curl -H "x-api-key: $KEY" localhost:8080/v1/stats
```
"10 million rows, generated from a fixed seed so anyone can reproduce them. Orders have seasonality and growth, accounts follow a power law, about 15% have churned."

Run walkthrough queries 2 and 3 (index on vs off): "0.7 ms vs 146 ms on 2.6 million orders. The same idea is why every SOQL query in the project filters on an indexed field."

## 2:30 · Getting it into Salesforce (2 minutes)

Open Integration Logs in the org.
"Salesforce pulls the slice people act on: the top 2,000 accounts, 60 days of orders and 12 months of metrics, through a Named Credential, so there are no URLs or secrets in code. Each page is its own Queueable transaction: callout, upsert on an external ID, log row. Re-running never duplicates, and a failure tells me the stage and cursor to resume from."

Show `WarehouseSyncJob.cls`: the `execute` method and the comment block. Mention the Bulk API 2.0 push path for initial loads.

## 4:30 · What a rep sees (2 minutes)

Open a top account record.
- Account Health card: score, status, the reasons, 12-month chart. Click **Refresh from warehouse** and show the toast.
- Order Explorer: scroll. "Keyset pagination, same as the API. OFFSET reads and throws away every skipped row; at 2 million rows that was 275 ms vs 0.09 ms."

## 6:30 · Business logic that holds up (1.5 minutes)

Show `WholesaleOrderTriggerHandler.cls` and a test.
"One trigger per object, logic in a handler, bulk-safe. Reps can only move orders forward; the integration user can skip steps because the warehouse is the source of truth, controlled by a custom permission rather than switching rules off. The tests insert 200 records to prove bulk safety."

## 8:00 · Agentforce (1.5 minutes)

In the agent panel: "Where is order LWO-…?" then "How is this account doing?"
"Both actions are invocable Apex. The insight action reuses the same health service as the batch and the card, so the agent never contradicts the page. If an order is older than the sync window, the action falls back to a live warehouse call. Order numbers are validated by a deterministic rule in Agent Script before the action runs."

## 9:30 · Close (30 seconds)

"It's on GitHub with a setup guide and CI. What I'd do next: Change Data Capture or Platform Events instead of a nightly pull, and Data 360 for the unstructured support notes."

## Questions you will likely get

| Question | Short answer |
|---|---|
| Why not sync everything? | Storage cost, query performance, and nobody acts on 2023 order lines. Sync what people act on; fetch the rest on demand. |
| Why not Salesforce Connect / external objects? | Good for browsing external data, but no triggers, roll-ups or most automation, and every view is a live query. I needed scoring and automation on recent data. |
| What happens if the API is down mid-sync? | That page logs Failed with the stage and cursor; the chain stops; nothing partial is lost because each page commits on its own. Resume from the logged cursor. |
| How do you avoid duplicates? | Unique external IDs and upsert, in both the pull sync and the Bulk API loads. |
| How did you test callouts? | `HttpCalloutMock` that routes by path and returns the API's real JSON shapes, including 404s and a forced 500. |
| Why Queueable over @future? | Chaining, non-primitive state (cursor, settings), and a job Id to monitor. |
| Governor limits? | One callout and a few hundred DML rows per transaction; aggregates instead of loops; batch for scoring. Nothing comes near a limit. |
| How would this change in production? | Real auth (OAuth client credentials), a stable host instead of a tunnel, alerts on Failed logs, and CDC or Platform Events for near real time. |
| What was hardest? | Pick a real one from your build, for example a first-deploy error or a test that failed at 200 records, and say what you changed. |
