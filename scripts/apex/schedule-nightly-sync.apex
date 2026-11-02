// Every night at 2:00 AM (org time zone)
System.schedule('Laheey nightly warehouse sync', '0 0 2 * * ?', new WarehouseSyncScheduler());
