// Level 3 demo: create an order with lines and watch the triggers total it
Account a = [SELECT Id FROM Account WHERE Warehouse_Id__c != null ORDER BY Revenue_12M__c DESC NULLS LAST LIMIT 1];
Wholesale_Order__c o = new Wholesale_Order__c(Name = 'LWO-DEMO-' + String.valueOf(Crypto.getRandomInteger()).right(5),
    Account__c = a.Id, Order_Date__c = Date.today(), Status__c = 'Placed', Payment_Status__c = 'Invoiced',
    Channel__c = 'Sales Rep', Shipping__c = 0);
insert o;
insert new List<Order_Line__c>{
    new Order_Line__c(Wholesale_Order__c = o.Id, Product_Name__c = 'Ethiopia Yirgacheffe, Light Roast, 5 lb', Quantity__c = 6, Unit_Price__c = 71.40),
    new Order_Line__c(Wholesale_Order__c = o.Id, Product_Name__c = 'House Espresso Blend, Dark Roast, 5 lb', Quantity__c = 10, Unit_Price__c = 51.87)
};
o = [SELECT Name, Subtotal__c, Total__c, Line_Count__c FROM Wholesale_Order__c WHERE Id = :o.Id];
System.debug(o.Name + ': ' + o.Line_Count__c + ' lines, subtotal ' + o.Subtotal__c + ', total ' + o.Total__c);
