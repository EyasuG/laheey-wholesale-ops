# Setup guide

From a clean laptop to a Salesforce org showing warehouse data, an account health score and an AI assistant. Steps 1–6 take about 30 minutes. Steps 7–9 are Levels 4, 6 and 7, done in the week the roadmap introduces them.

## 0. Prerequisites

| Tool | Why | Install |
|---|---|---|
| Docker Desktop | Runs PostgreSQL and the API | docker.com/products/docker-desktop |
| Node.js 20 or newer | Generator, API, export script | nodejs.org (LTS) |
| Git | Version control; publish to GitHub | git-scm.com |
| Salesforce CLI (`sf`) | Deploy, test, Bulk API loads | `npm install --global @salesforce/cli` |
| VS Code + Salesforce Extension Pack | Apex and LWC editing | marketplace.visualstudio.com |
| cloudflared | Lets Salesforce reach your local API (step 7 only) | developers.cloudflare.com, "cloudflared downloads" |

Disk space: about 300 MB for scale `s`, 1 GB for `m`, 3 GB for `l` (data plus index builds).

## 1. Get the code into your own GitHub repo

```bash
unzip laheey-wholesale-ops.zip && cd laheey-wholesale-ops
git init && git add . && git commit -m "Laheey Wholesale Ops: initial import"
# Create an empty repo on GitHub named laheey-wholesale-ops, then:
git remote add origin https://github.com/<your-user>/laheey-wholesale-ops.git
git branch -M main && git push -u origin main
```

Commit as you finish each level. Employers read commit history: small, clearly named commits ("Level 3: bulk-safe order trigger and tests") tell the story of how you built it.

## 2. Install and configure

```bash
npm install
cp .env.example .env
```

Edit `.env` and set `API_KEY` to a long random string. You'll paste the same value into Salesforce in step 7. `.env` is in `.gitignore`; never commit it.

## 3. Start the warehouse database

```bash
docker compose up -d db
docker compose ps          # wait until db shows "healthy"
```

## 4. Generate the data

Pick a scale. Start with `s`; move to `l` when you work on Level 6.

```bash
npm run generate:s         # ~1.0M rows
npm run generate:m         # ~3.0M rows
npm run generate:l         # ~10.0M rows
```

What happens: the schema is created, rows stream into Postgres with `COPY`, then keys, indexes and summary views are built. The run ends with a table of row counts:

```
Table                   Rows      (scale l, measured)
order_lines        6,214,541
orders             2,600,000
customers            600,000
support_cases        400,000
contacts             150,000
accounts              50,000
products                 400
TOTAL             10,014,941
```

Useful options: `--seed 7` gives a different but equally reproducible dataset; `--as-of 2026-12-31` ends the data on that date (default: today, which keeps health scores meaningful); `--target csv --out ./data` writes CSV files without a database.

Re-running `generate` drops and rebuilds everything.

## 5. Start and check the API

```bash
docker compose up -d api
curl localhost:8080/health
curl -H "x-api-key: <your key>" localhost:8080/v1/stats
curl -H "x-api-key: <your key>" "localhost:8080/v1/sync/accounts?top=3&pageSize=3"
curl -H "x-api-key: <your key>" localhost:8080/v1/orders/LWO-00000001
```

Prefer running the API without Docker while you change it? `npm run api` (reads `DATABASE_URL` and `API_KEY` from your shell).

Run the tests at any time: `npm test` (the API tests skip themselves if the database isn't running).

## 6. Create a Salesforce org and deploy (Level 1)

Choose one:

**Option A: Developer Edition org** (free, permanent, 5 MB of data storage)
1. Sign up at developer.salesforce.com/signup with a personal email.
2. `sf org login web --alias laheey --set-default`

**Option B: scratch org** (free, 30 days, about 200 MB of data: holds the full slice)
1. In your Developer Edition org: Setup → Dev Hub → Enable Dev Hub.
2. `sf org login web --alias devhub --set-default-dev-hub`
3. ```bash
   cd salesforce
   sf org create scratch --definition-file config/project-scratch-def.json --alias laheey --duration-days 30 --set-default --wait 10
   ```

Then deploy, assign access and run the tests:

```bash
cd salesforce
sf project deploy start --target-org laheey
sf org assign permset --name Laheey_Wholesale_Ops --name Laheey_Integration --target-org laheey
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 20 --target-org laheey
sf org open --target-org laheey
```

If the deploy reports an error, read [TROUBLESHOOTING.md](TROUBLESHOOTING.md). Fixing a first-deploy error and explaining what it was is a good interview story.

Finish the setup in the org:
- **Account page layout:** Setup → Object Manager → Account → Page Layouts → add the **Wholesale Orders** and **Monthly Metrics** related lists, and the Laheey fields (Segment, Tier, Revenue (12 Months), Health Status, Health Score, Last Synced).
- **Account record page:** open any account → gear icon → Edit Page → drag **Account Health (Laheey)** and **Order Explorer (Laheey)** onto the page → Save → Activate as org default.

## 7. Connect Salesforce to the warehouse: pull sync (Level 4)

Salesforce can't reach `localhost`, so you expose the API through a temporary HTTPS tunnel.

**7a. Open a tunnel** (leave this terminal running):
```bash
cloudflared tunnel --url http://localhost:8080
```
Copy the `https://<random-words>.trycloudflare.com` address it prints. It changes every time you restart the tunnel; update the Named Credential URL when it does.

**7b. External Credential** (holds the API key):
1. Setup → Named Credentials → **External Credentials** tab → New.
2. Label `Laheey Warehouse Key`, Name `Laheey_Warehouse_Key`, Authentication Protocol **Custom** → Save.
3. Principals → New: Parameter Name `WarehousePrincipal`, Identity Type **Named Principal**. Under Authentication Parameters add Name `ApiKey`, Value = your `API_KEY` → Save.
4. Custom Headers → New: Name `x-api-key`, Value `{!$Credential.Laheey_Warehouse_Key.ApiKey}`, Sequence `1` → Save.

**7c. Named Credential** (holds the URL):
1. **Named Credentials** tab → New.
2. Label `Laheey Warehouse`, Name `Laheey_Warehouse` (the code uses `callout:Laheey_Warehouse`).
3. URL = your tunnel address, no trailing slash. Enabled for Callouts ✓.
4. External Credential = `Laheey Warehouse Key`. Generate Authorization Header ✗ (off). **Allow Formulas in HTTP Header ✓** (needed for the `x-api-key` formula). Save.

**7d. Give your user access to the credential:**
Setup → Permission Sets → **Laheey Integration** → External Credential Principal Access → Edit → add `Laheey_Warehouse_Key - WarehousePrincipal` → Save.

**7e. Run the sync** (Developer Edition size; use `run-sync-scratch.apex` for a scratch org):
```bash
sf apex run --file ../scripts/apex/run-sync-dev-edition.apex --target-org laheey
```
Watch the API terminal: you'll see `GET /v1/sync/accounts?...` calls arrive. In Salesforce, open the **Integration Logs** tab: one row per page, with records processed, errors and duration. When the last stage finishes, the job starts **AccountHealthBatch** automatically.

**7f. Schedule it nightly** (optional; only while your tunnel runs):
```bash
sf apex run --file ../scripts/apex/schedule-nightly-sync.apex --target-org laheey
```

## 8. Bulk-load a slice instead: push (Level 6)

No tunnel needed. From the project root:

```bash
npm run export:subset -- --profile dev-edition     # top 50 accounts, 30 days, 6 months (~1.5k records, ~3 MB)
npm run export:subset                              # scratch org: top 2000, 60 days, 12 months (~22k records, ~45 MB)
scripts/load-salesforce.sh laheey
sf apex run --file scripts/apex/run-health-batch.apex --target-org laheey
```

`load-salesforce.sh` upserts parents first (Account, Contact, then orders and metrics) with Bulk API 2.0, matching on `Warehouse_Id__c`. Re-running it updates records in place; it never duplicates them. Check progress in Setup → Bulk Data Load Jobs.

The `Laheey Integration` permission set includes the **Bypass Order Status Rules** custom permission, so loads can move an order from Placed straight to Delivered (the warehouse is the source of truth). Users without it are held to the normal Placed → Roasting → Shipped → Delivered flow.

## 9. Build the Agentforce assistant (Level 7)

You need an org with Agentforce and Prompt Builder. The simplest route: the special Developer Edition org that the Trailhead **Apex for Agentforce** superbadge provisions (or an Agentforce Labs org). Deploy this project there (step 6), load a Developer Edition slice (step 8), then follow [AGENT_DESIGN.md](AGENT_DESIGN.md).

## Daily commands

```bash
docker compose up -d                 # start warehouse + API
docker compose logs -f api           # watch API calls
docker compose down                  # stop (data is kept in a Docker volume)
docker compose down -v               # stop and delete the data
npm test                             # generator + API tests
cd salesforce && sf project deploy start && sf apex run test --test-level RunLocalTests --wait 20
```
