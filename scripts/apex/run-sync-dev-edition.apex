// Pull a Developer Edition-sized slice from the warehouse (fits in 5 MB of data storage)
WarehouseSyncJob.Settings s = new WarehouseSyncJob.Settings();
s.top = 50;      // accounts
s.days = 30;     // days of orders
s.months = 6;    // months of metrics
System.enqueueJob(new WarehouseSyncJob(s));
