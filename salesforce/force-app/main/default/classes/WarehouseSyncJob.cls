/**
 * Level 4. Pulls the top-N accounts and their contacts, recent orders and monthly metrics from the warehouse,
 * one page per Queueable execution, and chains itself until every stage is done.
 *
 *   System.enqueueJob(new WarehouseSyncJob());                         // defaults: top 2000, 60 days, 12 months
 *   WarehouseSyncJob.Settings s = new WarehouseSyncJob.Settings();
 *   s.top = 50; s.days = 30; s.months = 6;                             // Developer Edition sized
 *   System.enqueueJob(new WarehouseSyncJob(s));
 *
 * Design notes (good interview material):
 *  - Callout first, DML after: Apex can't make a callout after uncommitted DML in the same transaction.
 *  - Upsert on Warehouse_Id__c makes every page idempotent: re-running a page never creates duplicates.
 *  - Children reference parents by external ID (Account__r.Warehouse_Id__c), so no Id lookups are needed.
 *  - allOrNone = false: one bad record is logged, the rest of the page still lands.
 *  - Each page is its own transaction with fresh governor limits.
 */
public with sharing class WarehouseSyncJob implements Queueable, Database.AllowsCallouts {

    public enum SyncStage { ACCOUNTS, CONTACTS, ORDERS, METRICS }

    public class Settings {
        public Integer top = 2000;     // how many accounts, ranked by 12-month revenue
        public Integer days = 60;      // how many days of orders
        public Integer months = 12;    // how many months of metrics
        public Boolean runHealthBatch = true;
    }

    private final SyncStage currentStage;
    private final String cursor;
    private final Settings cfg;

    public WarehouseSyncJob() {
        this(SyncStage.ACCOUNTS, '0', new Settings());
    }

    public WarehouseSyncJob(Settings cfg) {
        this(SyncStage.ACCOUNTS, '0', cfg);
    }

    @TestVisible
    private WarehouseSyncJob(SyncStage stage, String cursor, Settings cfg) {
        this.currentStage = stage;
        this.cursor = cursor;
        this.cfg = cfg;
    }

    public void execute(QueueableContext ctx) {
        Long started = System.currentTimeMillis();
        String next;
        Integer processed = 0;
        List<String> errors = new List<String>();
        try {
            switch on currentStage {
                when ACCOUNTS {
                    WarehouseClient.AccountPage page = WarehouseClient.syncAccounts(cursor, 200, cfg.top);
                    List<Account> rows = toAccounts(page.records);
                    errors = IntegrationLogger.collect(Database.upsert(rows, Account.Warehouse_Id__c, false), rows, 'Warehouse_Id__c');
                    processed = rows.size();
                    next = page.nextCursor;
                }
                when CONTACTS {
                    WarehouseClient.ContactPage page = WarehouseClient.syncContacts(cursor, 500, cfg.top);
                    List<Contact> rows = toContacts(page.records);
                    errors = IntegrationLogger.collect(Database.upsert(rows, Contact.Warehouse_Id__c, false), rows, 'Warehouse_Id__c');
                    processed = rows.size();
                    next = page.nextCursor;
                }
                when ORDERS {
                    WarehouseClient.OrderPage page = WarehouseClient.syncOrders(cursor, 1000, cfg.top, cfg.days);
                    List<Wholesale_Order__c> rows = toOrders(page.records);
                    WholesaleOrderTriggerHandler.bypassStatusRules = true;   // warehouse status wins
                    try {
                        errors = IntegrationLogger.collect(Database.upsert(rows, Wholesale_Order__c.Warehouse_Id__c, false), rows, 'Warehouse_Id__c');
                    } finally {
                        WholesaleOrderTriggerHandler.bypassStatusRules = false;
                    }
                    processed = rows.size();
                    next = page.nextCursor;
                }
                when METRICS {
                    WarehouseClient.MetricPage page = WarehouseClient.syncMetrics(cursor, 100, cfg.top, cfg.months);
                    List<Account_Metric__c> rows = toMetrics(page.records);
                    errors = IntegrationLogger.collect(Database.upsert(rows, Account_Metric__c.Warehouse_Id__c, false), rows, 'Warehouse_Id__c');
                    processed = rows.size();
                    next = page.nextCursor;
                }
            }
        } catch (Exception e) {
            IntegrationLogger.failure('WarehouseSyncJob', currentStage.name(), e, cursor, started);
            return;   // stop the chain; the log row says where to restart
        }
        IntegrationLogger.log('WarehouseSyncJob', currentStage.name(), processed, errors, next, started);
        enqueueNext(next);
    }

    private void enqueueNext(String next) {
        WarehouseSyncJob following;
        if (next != null) {
            following = new WarehouseSyncJob(currentStage, next, cfg);
        } else if (currentStage != SyncStage.METRICS) {
            following = new WarehouseSyncJob(SyncStage.values()[currentStage.ordinal() + 1], '0', cfg);
        }
        // Chained jobs can't be enqueued from a test; tests drive each stage directly
        if (Test.isRunningTest()) {
            return;
        }
        if (following != null) {
            System.enqueueJob(following);
        } else if (cfg.runHealthBatch) {
            Database.executeBatch(new AccountHealthBatch(), 200);
        }
    }

    // ---------- mapping ----------
    @TestVisible
    private static List<Account> toAccounts(List<WarehouseClient.AccountDto> dtos) {
        List<Account> rows = new List<Account>();
        for (WarehouseClient.AccountDto d : dtos) {
            Account a = new Account(
                Warehouse_Id__c = d.warehouseId,
                Name = d.name,
                Segment__c = d.segment,
                Tier__c = d.tier,
                BillingCity = d.city,
                Sales_Rep__c = d.salesRep,
                Payment_Terms__c = d.paymentTerms,
                Lifetime_Revenue__c = d.lifetimeRevenue,
                Revenue_12M__c = d.revenue12m,
                Orders_Last_90_Days__c = d.orders90d,
                Last_Order_Date__c = d.lastOrderDate,
                Open_Cases__c = d.openCases,
                Last_Synced__c = System.now()
            );
            setUsAddress(a, d.state);
            rows.add(a);
        }
        return rows;
    }

    // The warehouse sends US state codes ("DC"). Orgs with State and Country/Territory Picklists
    // (the default for new orgs) reject a state without a country and want the code fields;
    // older orgs only have the text fields. put() keeps this compiling in both.
    private static final Boolean STATE_PICKLISTS = Schema.SObjectType.Account.fields.getMap().containsKey('billingstatecode');

    private static void setUsAddress(Account a, String stateCode) {
        if (String.isBlank(stateCode)) {
            return;
        }
        if (STATE_PICKLISTS) {
            a.put('BillingCountryCode', 'US');
            a.put('BillingStateCode', stateCode);
        } else {
            a.BillingCountry = 'US';
            a.BillingState = stateCode;
        }
    }

    private static List<Contact> toContacts(List<WarehouseClient.ContactDto> dtos) {
        List<Contact> rows = new List<Contact>();
        for (WarehouseClient.ContactDto d : dtos) {
            rows.add(new Contact(
                Warehouse_Id__c = d.warehouseId,
                Account = new Account(Warehouse_Id__c = d.accountWarehouseId),
                FirstName = d.firstName,
                LastName = d.lastName,
                Title = d.title,
                Email = d.email,
                Phone = d.phone,
                Primary_Contact__c = d.isPrimary == true
            ));
        }
        return rows;
    }

    private static List<Wholesale_Order__c> toOrders(List<WarehouseClient.OrderDto> dtos) {
        List<Wholesale_Order__c> rows = new List<Wholesale_Order__c>();
        for (WarehouseClient.OrderDto d : dtos) {
            rows.add(new Wholesale_Order__c(
                Warehouse_Id__c = d.warehouseId,
                Name = d.orderNumber,
                Account__r = new Account(Warehouse_Id__c = d.accountWarehouseId),
                Order_Date__c = d.orderDate,
                Ship_Date__c = d.shipDate,
                Status__c = d.status,
                Payment_Status__c = d.paymentStatus,
                Channel__c = d.channel,
                Subtotal__c = d.subtotal,
                Discount__c = d.discount,
                Shipping__c = d.shipping,
                Line_Count__c = d.lineCount
            ));
        }
        return rows;
    }

    private static List<Account_Metric__c> toMetrics(List<WarehouseClient.MetricDto> dtos) {
        List<Account_Metric__c> rows = new List<Account_Metric__c>();
        for (WarehouseClient.MetricDto d : dtos) {
            rows.add(new Account_Metric__c(
                Warehouse_Id__c = d.warehouseId,
                Name = d.month == null ? d.warehouseId : String.valueOf(d.month).left(7),
                Account__r = new Account(Warehouse_Id__c = d.accountWarehouseId),
                Month__c = d.month,
                Revenue__c = d.revenue,
                Order_Count__c = d.orderCount,
                Avg_Order_Value__c = d.avgOrderValue
            ));
        }
        return rows;
    }
}
