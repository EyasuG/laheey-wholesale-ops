# Troubleshooting

## Warehouse and API

| Symptom | Fix |
|---|---|
| `ECONNREFUSED 127.0.0.1:5432` when generating | Start the database: `docker compose up -d db`, wait for `healthy` in `docker compose ps`. |
| Port 5432 already in use | Another Postgres is running. Stop it, or change the left side of `"5432:5432"` in `docker-compose.yml` (e.g. `"5433:5432"`) and set `DATABASE_URL` to port 5433. |
| Scale `l` is slow or runs out of disk | Give Docker Desktop at least 4 GB of memory and 10 GB of disk (Settings → Resources). Index builds are the slowest part. |
| `401 Missing or invalid x-api-key` | The header must be `x-api-key` and match `API_KEY` in the API's environment. After editing `.env`: `docker compose up -d api` to recreate it. |
| API tests show "skipped" | They need a generated warehouse. Run `npm run generate:s` first. |
| `/v1/sync/...` returns empty records | Generate the data first; `account_rank` only includes active (non-churned) accounts. |

## Salesforce deploy

The Apex was syntax-checked and the project converts cleanly with the Salesforce CLI, but it had not been deployed to a live org when it was written. If the first deploy fails:

| Message | Fix |
|---|---|
| `Variable does not exist` / `Invalid type` | A typo or a field name mismatch between a class and the object metadata. The error names the file and line; compare with `objects/*/fields/`. |
| `Field ... is not writeable` on a permission set | Required and master-detail fields can't be in field permissions. Remove that `<fieldPermissions>` block. |
| `Custom object ... not found` while deploying triggers | Deploy objects first: `sf project deploy start --metadata CustomObject` then deploy everything. |
| `Entity type ... does not support history` | Turn on field history for the object in Setup, or remove `<trackHistory>` from that field. |
| Tests fail on `Assert` with a date-related value | The health score uses today's date. Regenerate data with the default `--as-of` (today) before loading. |

Read the whole error before changing anything, fix one thing, redeploy. Keep notes: this is good interview material.

## Data loads

| Symptom | Fix |
|---|---|
| `STORAGE_LIMIT_EXCEEDED` | Developer Edition holds 5 MB. Export with `--profile dev-edition`, or use a scratch org. Delete old loads in Setup → Mass Delete or with `sf data delete bulk`. |
| `Foreign key external ID: ACC-... not found` | Children were loaded before parents, or the account wasn't in the export. Run `load-salesforce.sh` in full (it loads parents first). |
| `An order can't move from Delivered to Placed` during a load | The loading user lacks the **Laheey Integration** permission set (Bypass Order Status Rules). Assign it and re-run. |
| `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` | A warehouse value isn't in the Salesforce picklist. Add the value or fix the data; the rest of the job still loads. |

## Callouts and Named Credential

| Symptom | Fix |
|---|---|
| `Unable to tunnel through proxy` / `Unauthorized endpoint` | Use the Named Credential, never a raw URL. The endpoint must start with `callout:Laheey_Warehouse`. |
| `We couldn't access the credential(s)` | Add the External Credential principal to the **Laheey Integration** permission set (SETUP 7d) and assign it to the running user. |
| Warehouse returns 401 to Salesforce | Check the custom header value is exactly `{!$Credential.Laheey_Warehouse_Key.ApiKey}` and **Allow Formulas in HTTP Header** is on. |
| Worked yesterday, fails today | The quick tunnel URL changed. Copy the new one into the Named Credential URL. |
| `You have uncommitted work pending` | A callout after DML in the same transaction. Keep callouts first, DML after (see `WarehouseSyncJob.execute`). |
| Sync stopped partway | Open Integration Logs; the Failed row shows the stage and cursor. Fix the cause and re-run. Upserts make re-running safe. |

## LWC

| Symptom | Fix |
|---|---|
| Component not in Lightning App Builder | It targets Account record pages only. Check deployment and refresh the builder. |
| Health card shows "No monthly metrics yet" | Load `metrics.csv` or run the sync's METRICS stage. |
| Refresh button shows an error toast | The API or tunnel is down, or the account has no Warehouse Id. The message says which. |
