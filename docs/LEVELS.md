# Progressive skill levels

Eight levels, each building on the last. Each lists what to build, the files involved, a "done when" check, and the line to use in an interview. Weeks refer to the Salesforce Trail study plan.

Work the way you would on a team: one branch or a few commits per level, tests passing before you move on.

---

## Level 1 · Data model and security (week 1)

**Goal:** a Salesforce schema that mirrors the business, with the right access for the right people.

Do:
1. Run steps 1–6 of [SETUP.md](SETUP.md): warehouse at scale `s`, org created, metadata deployed.
2. In Object Manager, open each Laheey object and read its fields. For each relationship, write one sentence on why it is master-detail or lookup.
3. Open `Warehouse_Id__c` on Account: note *External ID* and *Unique*. Explain to yourself why both matter for upserts.
4. Setup → Sharing Settings: Wholesale Order is *Controlled by Parent*. Change Account's OWD to Private, then log in as a second user and confirm they can't see orders on accounts they can't see.
5. Compare the two permission sets. Why does only `Laheey_Integration` hold the custom permission?
6. Optional: rebuild one object by hand in Setup, then `sf project retrieve start --metadata CustomObject:Account_Metric__c` and diff it against the repo.

Files: `salesforce/force-app/main/default/objects/`, `permissionsets/`, `customPermissions/`.

Done when: the deploy succeeds, both permission sets are assigned, and you can explain OWD → role hierarchy → sharing rules → permission sets in that order.

Interview line: "Orders and metrics are master-detail to Account, so sharing and deletion follow the account. Every synced record has a unique external ID, which makes loads idempotent."

---

## Level 2 · Declarative automation (week 2)

**Goal:** solve with clicks first; know where clicks stop.

Do:
1. Test the validation rule: create an order with a ship date before its order date.
2. Build a **record-triggered Flow** in Flow Builder:
   - Object: Account. Trigger: when a record is updated. Entry condition: `Health_Status__c` is changed **and** equals `At Risk`. Optimize for: Actions and Related Records.
   - Action: Create Records → Task. Subject `At-risk account: call this week`, WhatId = the account, OwnerId = the account owner, ActivityDate = TODAY + 2 (formula resource).
   - Save as `Account_At_Risk_Follow_Up`, activate.
3. Run the health batch (`scripts/apex/run-health-batch.apex`) and confirm tasks appear for At Risk accounts.
4. Retrieve the flow into the repo: `sf project retrieve start --metadata Flow:Account_At_Risk_Follow_Up` and commit it.
5. Write down why order totals are Apex (Level 3) and not a Flow: they run on every bulk load of thousands of orders, and the rollup must skip synced orders.

Done when: the flow is active, retrieved into source control, and creates exactly one task per newly at-risk account.

Interview line: "I default to Flow for record-level reactions, like creating a follow-up task, and use Apex where volume, complexity or testability demands it."

---

## Level 3 · Apex triggers and tests (weeks 3–6)

**Goal:** bulk-safe business logic with tests that prove behavior, not just coverage.

Read, then rebuild from memory in a branch:
- `triggers/WholesaleOrderTrigger.trigger` + `classes/WholesaleOrderTriggerHandler.cls`: one trigger per object, logic in a handler, `switch on Trigger.operationType`, status-flow rule with `addError`, totals in *before* context (no DML needed).
- `triggers/OrderLineTrigger.trigger` + `classes/OrderLineRollup.cls`: one query for all affected orders, handles insert/update/delete/undelete and re-parenting.
- Tests: `WholesaleOrderTriggerTest`, `OrderLineRollupTest`, `TestDataFactory`.

Do:
1. Run `scripts/apex/sample-order-with-lines.apex` and read the debug log: find the SOQL count and the trigger order.
2. Break it on purpose: move the query inside the loop in `OrderLineRollup`, run `OrderLineRollupTest` (200 lines), read the error, revert.
3. Add a rule: an order can't be Cancelled once it is Shipped (already true; prove it with a new test).
4. Add a test for re-parenting a line from one order to another.
5. `sf apex run test --code-coverage --result-format human` and get every class over 85%.

Done when: all tests pass with meaningful asserts, and you can explain the order of execution from before triggers to commit.

Interview line: "Every trigger in the project handles 200 records with one query and one DML, and the tests insert 200 records to prove it."

---

## Level 4 · Integration: callouts, Queueable, Schedulable (week 7)

**Goal:** a production-style integration: secure, paged, idempotent, observable.

Read:
- `WarehouseClient.cls`: one class owns HTTP; `callout:Laheey_Warehouse`; DTOs match the API's JSON.
- `WarehouseSyncJob.cls`: one page per Queueable; callout, then upsert on external ID, then log; chains to the next page or stage.
- `IntegrationLogger.cls`, `WarehouseSyncScheduler.cls`, `WarehouseHttpMock.cls`, `WarehouseSyncJobTest.cls`.
- `api/server.js`: the other side of the contract.

Do:
1. Steps 7a–7e of [SETUP.md](SETUP.md): tunnel, External Credential, Named Credential, principal access, run the sync.
2. Watch requests arrive in the API log while Integration Log rows appear in Salesforce.
3. Run the sync twice. Confirm record counts don't change (idempotency).
4. Stop the API mid-sync (`docker compose stop api`). Find the Failed log row and its cursor. Restart and resume from that stage.
5. Change a picklist value in the warehouse (`UPDATE accounts SET segment='Bakery' WHERE id=...`, refresh views), sync, and find the Partial log row.
6. Schedule the nightly job (`scripts/apex/schedule-nightly-sync.apex`) and find it in Setup → Scheduled Jobs.

Done when: a full sync completes from the Named Credential with only Success rows, and you can recover from a failure using the log.

Interview line: "It's a pull integration through a Named Credential with keyset paging. Each page is its own Queueable transaction, upserts on external IDs, and writes a log row, so a failure is visible, resumable and never duplicates data."

---

## Level 5 · Lightning Web Components (weeks 8–9)

**Goal:** user-facing components that are fast and fail politely.

Read:
- `lwc/accountHealthCard`: `@wire(getHealth)` for cached reactive reads; imperative `refreshFromWarehouse` for the write; `refreshApex` afterwards; toasts for success and failure; a CSS bar chart built from data.
- `lwc/orderExplorer`: `lightning-datatable` with infinite loading; imperative calls to a cacheable method; keyset paging.
- `AccountHealthController.cls`, `OrderExplorerController.cls`.

Do:
1. Add both components to the Account record page (SETUP step 6).
2. Click *Refresh from warehouse* with the API running, then with it stopped. Compare the toasts.
3. Scroll the Order Explorer on the largest account; watch network calls in browser dev tools.
4. Add a column (Ship Date) and a status badge color to the order table.
5. Stretch: add Jest tests (`npm install @salesforce/sfdx-lwc-jest --save-dev` in `salesforce/`) mocking `getHealth`.

Done when: both components work on a real account and handle an API outage without breaking the page.

Interview line: "Reads use @wire against cacheable Apex; the refresh is imperative because it writes, then I call refreshApex so the card shows the new data."

---

## Level 6 · Large data volumes (weeks 10–12)

**Goal:** work confidently with millions of rows on both sides.

Do:
1. `npm run generate:l` (10M rows). Note the load time.
2. Run `warehouse/walkthrough.sql` and record your own timings for each pair. See [LARGE_DATA_VOLUMES.md](LARGE_DATA_VOLUMES.md).
3. Push a slice: `npm run export:subset` then `scripts/load-salesforce.sh laheey`. Watch the jobs in Setup → Bulk Data Load Jobs; note batches, records processed and time.
4. Re-run the load: zero new records, only updates.
5. Run `AccountHealthBatch`; check Apex Jobs for batches processed and the log row.
6. In the Developer Console, use the **Query Plan** tool on `SELECT Id FROM Account WHERE Warehouse_Id__c = 'ACC-0000123'` vs `WHERE Sales_Rep__c = 'Selam Haile'`. Explain the cost difference (external IDs are indexed; plain text fields aren't).

Done when: you can quote your own before/after timings and explain selectivity, keyset paging, pre-aggregation and data skew.

Interview line: "The warehouse has 10 million rows. Salesforce gets the 2,000 accounts people act on, recent orders and pre-aggregated monthly metrics. Deep pagination with OFFSET took 275 ms; keyset took 0.09 ms."

---

## Level 7 · Agentforce (weeks 13–16)

**Goal:** an assistant that answers real questions with real data and safe boundaries.

Read: `OrderStatusAction.cls`, `AccountInsightAction.cls`, `AgentActionsTest.cls`, and [AGENT_DESIGN.md](AGENT_DESIGN.md).

Do:
1. Set up an Agentforce-enabled org (SETUP step 9), deploy, load a slice.
2. Build the agent, its two subagents and actions per AGENT_DESIGN.md, including the deterministic rule in Agent Script.
3. Build the *Reorder Nudge* prompt template and ground it on Account and metrics.
4. Create the Testing Center suite from the utterance table and get it passing.
5. Try the guardrail prompts. Record a 60-second video of the agent answering an order question and an account question.

Done when: the test suite passes and the agent refuses out-of-scope requests.

Interview line: "The agent's actions are invocable Apex that reuse the same health service as the batch and the LWC, so the agent never contradicts the page. Order lookups check Salesforce first and fall back to the warehouse."

---

## Level 8 · DevOps and presenting it (weeks 17–18)

**Goal:** a project that someone else can run, and a story you can tell in ten minutes.

Do:
1. Push to GitHub; confirm the **warehouse** CI job passes on every push.
2. Enable the Salesforce CI job: create a Connected App with JWT (Trailhead: "Continuous Integration Using Salesforce DX"), add `SF_JWT_KEY`, `SF_CLIENT_ID`, `SF_USERNAME` as repository secrets and `ENABLE_SALESFORCE_CI=true` as a repository variable.
3. Add screenshots (health card, order explorer, integration logs, agent conversation) to a `docs/images/` folder and the README.
4. Rehearse [DEMO_SCRIPT.md](DEMO_SCRIPT.md) aloud, timed, twice.
5. Pin the repo on GitHub; link it on your resume and LinkedIn.

Done when: a stranger can clone, follow SETUP.md, and get to a working org; CI is green; you can deliver the demo in ten minutes.
