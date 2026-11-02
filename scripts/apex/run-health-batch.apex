// Score every synced account (run after a Bulk API load; the pull sync runs it automatically)
Database.executeBatch(new AccountHealthBatch(), 200);
