// Pull the full scratch-org slice: top 2000 accounts, 60 days of orders, 12 months of metrics (~45 MB)
System.enqueueJob(new WarehouseSyncJob());
