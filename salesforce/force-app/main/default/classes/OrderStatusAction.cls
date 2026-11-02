/**
 * Level 7. Agentforce action: "Where is my order?"
 * Looks the order up in Salesforce first; if it isn't synced (older than the sync window), asks the warehouse live.
 * The label and descriptions below are what the agent's reasoning engine reads to decide when to call this.
 */
public with sharing class OrderStatusAction {

    public class Request {
        @InvocableVariable(required=true label='Order Number' description='The order number, for example LWO-00001234. Ask the user for it if they did not give one.')
        public String orderNumber;
    }

    public class Result {
        @InvocableVariable(label='Found' description='True when the order exists.')
        public Boolean found;
        @InvocableVariable(label='Status' description='Placed, Roasting, Shipped, Delivered or Cancelled.')
        public String status;
        @InvocableVariable(label='Payment Status' description='Paid, Invoiced, Overdue or Refunded.')
        public String paymentStatus;
        @InvocableVariable(label='Ship Date' description='Date the order shipped, if it has.')
        public Date shipDate;
        @InvocableVariable(label='Total' description='Order total in US dollars.')
        public Decimal total;
        @InvocableVariable(label='Summary' description='One or two sentences to show the user.')
        public String summary;
    }

    @InvocableMethod(label='Get Wholesale Order Status' description='Returns the status, payment status, ship date and total of a wholesale order by its order number.' callout=true category='Laheey Wholesale')
    public static List<Result> getStatus(List<Request> requests) {
        Set<String> numbers = new Set<String>();
        for (Request r : requests) {
            if (String.isNotBlank(r.orderNumber)) {
                numbers.add(r.orderNumber.trim().toUpperCase());
            }
        }
        Map<String, Wholesale_Order__c> byNumber = new Map<String, Wholesale_Order__c>();
        for (Wholesale_Order__c o : [
            SELECT Name, Status__c, Payment_Status__c, Ship_Date__c, Total__c, Order_Date__c
            FROM Wholesale_Order__c WHERE Name IN :numbers WITH USER_MODE
        ]) {
            byNumber.put(o.Name.toUpperCase(), o);
        }

        List<Result> results = new List<Result>();
        for (Request r : requests) {
            String num = String.isBlank(r.orderNumber) ? '' : r.orderNumber.trim().toUpperCase();
            Result out = new Result();
            out.found = false;
            Wholesale_Order__c o = byNumber.get(num);
            if (o != null) {
                fill(out, num, o.Status__c, o.Payment_Status__c, o.Ship_Date__c, o.Total__c, o.Order_Date__c);
            } else if (String.isNotBlank(num)) {
                try {
                    WarehouseClient.OrderDetail d = WarehouseClient.getOrder(num);
                    if (d != null) {
                        fill(out, num, d.status, d.paymentStatus, d.shipDate, d.total, d.orderDate);
                    }
                } catch (Exception e) {
                    out.summary = 'I couldn\'t reach the order system just now. Please try again in a few minutes.';
                }
            }
            if (out.summary == null && !out.found) {
                out.summary = 'I couldn\'t find an order numbered ' + (String.isBlank(num) ? '(none given)' : num) + '. Please check the number.';
            }
            results.add(out);
        }
        return results;
    }

    private static void fill(Result out, String num, String status, String payment, Date shipDate, Decimal total, Date orderDate) {
        out.found = true;
        out.status = status;
        out.paymentStatus = payment;
        out.shipDate = shipDate;
        out.total = total;
        String s = 'Order ' + num + (orderDate == null ? '' : ' (placed ' + orderDate.format() + ')') + ' is ' + status;
        if (shipDate != null && (status == 'Shipped' || status == 'Delivered')) {
            s += ', shipped ' + shipDate.format();
        }
        out.summary = s + '. Total ' + (total == null ? 'n/a' : '$' + total.setScale(2).format()) + ', payment ' + payment + '.';
    }
}
