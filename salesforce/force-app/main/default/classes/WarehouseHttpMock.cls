/**
 * Fakes the warehouse API in tests. Real callouts are not allowed in Apex tests.
 * Routes on the path and returns JSON shaped exactly like api/server.js.
 */
@IsTest
public class WarehouseHttpMock implements HttpCalloutMock {

    public Integer forceStatus;           // set to 500 to simulate an outage
    public List<String> calledPaths = new List<String>();

    public HttpResponse respond(HttpRequest req) {
        String path = req.getEndpoint().substringAfter('callout:Laheey_Warehouse');
        calledPaths.add(path);
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        if (forceStatus != null) {
            res.setStatusCode(forceStatus);
            res.setBody('{"error":"simulated failure"}');
            return res;
        }
        res.setStatusCode(200);
        String today = String.valueOf(Date.today());
        String month = String.valueOf(Date.today().toStartOfMonth());
        if (path.startsWith('/v1/sync/accounts')) {
            res.setBody('{"records":['
                + '{"warehouseId":"ACC-0000001","name":"Blue Door Cafe","segment":"Cafe","tier":"Platinum","city":"Washington","state":"DC","salesRep":"Selam Haile","paymentTerms":"Net 15","lifetimeRevenue":120000.50,"revenue12m":48000,"orders90d":40,"lastOrderDate":"' + today + '","openCases":1},'
                + '{"warehouseId":"ACC-0000002","name":"Capitol Market","segment":"Grocery","tier":"Gold","city":"Laurel","state":"MD","salesRep":"Ana Lopez","paymentTerms":"Net 30","lifetimeRevenue":56000,"revenue12m":21000,"orders90d":12,"lastOrderDate":"' + today + '","openCases":0},'
                + '{"warehouseId":"ACC-0000003","name":"Bad Row","segment":"Not A Segment","tier":"Gold","city":"X","state":"MD","salesRep":"X","paymentTerms":"Net 30","lifetimeRevenue":1,"revenue12m":1,"orders90d":1,"lastOrderDate":"' + today + '","openCases":0}'
                + '],"nextCursor":"3"}');
        } else if (path.startsWith('/v1/sync/contacts')) {
            res.setBody('{"records":[{"warehouseId":"CON-0000001","accountWarehouseId":"ACC-0000001","firstName":"Hana","lastName":"Bekele","title":"Owner","email":"hana.bekele.1@example.com","phone":"202-555-0101","isPrimary":true}],"nextCursor":null}');
        } else if (path.startsWith('/v1/sync/orders')) {
            res.setBody('{"records":[' + orderJson('LWO-00000001', 'ACC-0000001', 'Delivered') + ',' + orderJson('LWO-00000002', 'ACC-0000001', 'Placed') + '],"nextCursor":null}');
        } else if (path.startsWith('/v1/sync/metrics')) {
            res.setBody('{"records":[{"warehouseId":"ACC-0000001-' + month.left(7) + '","accountWarehouseId":"ACC-0000001","month":"' + month + '","revenue":4000,"orderCount":12,"avgOrderValue":333.33}],"nextCursor":null}');
        } else if (path.startsWith('/v1/accounts/') && path.endsWith('/summary')) {
            if (path.contains('ACC-MISSING')) { res.setStatusCode(404); res.setBody('{"error":"No account"}'); return res; }
            res.setBody('{"warehouseId":"ACC-9000000","name":"Test Cafe 0","tier":"Gold","segment":"Cafe","lifetimeRevenue":99999,"revenue12m":15000,"orderCount":300,"orders90d":21,"lastOrderDate":"' + today + '","openCases":2,"overdueOrders":0}');
        } else if (path.startsWith('/v1/orders/')) {
            if (path.contains('LWO-99999999')) { res.setStatusCode(404); res.setBody('{"error":"No order"}'); return res; }
            String detail = orderJson(path.substringAfter('/v1/orders/'), 'ACC-0000001', 'Shipped');
            res.setBody(detail.removeEnd('}') + ',"lines":[{"product":"Ethiopia Guji, Light Roast, 5 lb","quantity":4,"unitPrice":70,"lineTotal":280}]}');
        } else {
            res.setStatusCode(404);
            res.setBody('{"error":"No route"}');
        }
        return res;
    }

    private static String orderJson(String num, String accountWid, String status) {
        String d = String.valueOf(Date.today().addDays(-3));
        return '{"warehouseId":"' + num + '","orderNumber":"' + num + '","accountWarehouseId":"' + accountWid + '","orderDate":"' + d
            + '","shipDate":' + (status == 'Placed' ? 'null' : '"' + d + '"') + ',"status":"' + status + '","paymentStatus":"Paid","channel":"Sales Rep",'
            + '"subtotal":280,"discount":0,"shipping":0,"total":280,"lineCount":1}';
    }
}
