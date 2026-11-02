#!/usr/bin/env bash
# Upserts the exported CSVs into Salesforce with Bulk API 2.0, parents first.
# Usage: scripts/load-salesforce.sh <org-alias> [exports-dir]
set -euo pipefail
ORG="${1:?Usage: scripts/load-salesforce.sh <org-alias> [exports-dir]}"
DIR="${2:-exports}"

load () {   # sobject file
  echo "==> Upserting $2 into $1"
  sf data upsert bulk --sobject "$1" --file "$DIR/$2" --external-id Warehouse_Id__c --line-ending LF --wait 30 --target-org "$ORG"
}

load Account            accounts.csv
load Contact            contacts.csv
load Wholesale_Order__c orders.csv
load Account_Metric__c  metrics.csv
echo "Done. Next: run the health batch from Anonymous Apex: Database.executeBatch(new AccountHealthBatch(), 200);"
