/**
 * Level 4. The only class that talks HTTP to the Laheey warehouse API.
 * Endpoint and API key come from the Named Credential "Laheey_Warehouse" (see docs/SETUP.md, step 7),
 * so no URL or secret ever appears in code.
 */
public with sharing class WarehouseClient {

    public class WarehouseException extends Exception {}

    public static final String NAMED_CREDENTIAL = 'callout:Laheey_Warehouse';

    // ---------- sync pages ----------
    public static AccountPage syncAccounts(String cursor, Integer pageSize, Integer top) {
        return (AccountPage) getJson('/v1/sync/accounts?cursor=' + enc(cursor) + '&pageSize=' + pageSize + '&top=' + top, AccountPage.class);
    }
    public static ContactPage syncContacts(String cursor, Integer pageSize, Integer top) {
        return (ContactPage) getJson('/v1/sync/contacts?cursor=' + enc(cursor) + '&pageSize=' + pageSize + '&top=' + top, ContactPage.class);
    }
    public static OrderPage syncOrders(String cursor, Integer pageSize, Integer top, Integer days) {
        return (OrderPage) getJson('/v1/sync/orders?cursor=' + enc(cursor) + '&pageSize=' + pageSize + '&top=' + top + '&days=' + days, OrderPage.class);
    }
    public static MetricPage syncMetrics(String cursor, Integer pageSize, Integer top, Integer months) {
        return (MetricPage) getJson('/v1/sync/metrics?cursor=' + enc(cursor) + '&pageSize=' + pageSize + '&top=' + top + '&months=' + months, MetricPage.class);
    }

    // ---------- live lookups ----------
    /** Returns null when the warehouse has no such account. */
    public static AccountSummary getAccountSummary(String warehouseId) {
        return (AccountSummary) getJson('/v1/accounts/' + enc(warehouseId) + '/summary', AccountSummary.class);
    }
    /** Returns null when the warehouse has no such order. */
    public static OrderDetail getOrder(String orderNumber) {
        return (OrderDetail) getJson('/v1/orders/' + enc(orderNumber), OrderDetail.class);
    }

    // ---------- plumbing ----------
    private static Object getJson(String path, System.Type resultType) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + path);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);
        HttpResponse res = new Http().send(req);
        Integer status = res.getStatusCode();
        if (status == 404) {
            return null;
        }
        if (status < 200 || status > 299) {
            throw new WarehouseException('Warehouse returned HTTP ' + status + ' for ' + path + ': ' + res.getBody().left(300));
        }
        return JSON.deserialize(res.getBody(), resultType);
    }

    private static String enc(String value) {
        return EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8');
    }

    // ---------- response shapes (field names match the API's JSON) ----------
    public class AccountPage { public List<AccountDto> records; public String nextCursor; }
    public class ContactPage { public List<ContactDto> records; public String nextCursor; }
    public class OrderPage { public List<OrderDto> records; public String nextCursor; }
    public class MetricPage { public List<MetricDto> records; public String nextCursor; }

    public class AccountDto {
        public String warehouseId;
        public String name;
        public String segment;
        public String tier;
        public String city;
        public String state;
        public String salesRep;
        public String paymentTerms;
        public Decimal lifetimeRevenue;
        public Decimal revenue12m;
        public Integer orders90d;
        public Date lastOrderDate;
        public Integer openCases;
    }
    public class ContactDto {
        public String warehouseId;
        public String accountWarehouseId;
        public String firstName;
        public String lastName;
        public String title;
        public String email;
        public String phone;
        public Boolean isPrimary;
    }
    public virtual class OrderDto {
        public String warehouseId;
        public String orderNumber;
        public String accountWarehouseId;
        public Date orderDate;
        public Date shipDate;
        public String status;
        public String paymentStatus;
        public String channel;
        public Decimal subtotal;
        public Decimal discount;
        public Decimal shipping;
        public Decimal total;
        public Integer lineCount;
    }
    public class OrderDetail extends OrderDto {
        public List<OrderLineDto> lines;
    }
    public class OrderLineDto {
        public String product;
        public Integer quantity;
        public Decimal unitPrice;
        public Decimal lineTotal;
    }
    public class MetricDto {
        public String warehouseId;
        public String accountWarehouseId;
        public Date month;
        public Decimal revenue;
        public Integer orderCount;
        public Decimal avgOrderValue;
    }
    public class AccountSummary {
        public String warehouseId;
        public String name;
        public String tier;
        public String segment;
        public Decimal lifetimeRevenue;
        public Decimal revenue12m;
        public Integer orderCount;
        public Integer orders90d;
        public Date lastOrderDate;
        public Integer openCases;
        public Integer overdueOrders;
    }
}
