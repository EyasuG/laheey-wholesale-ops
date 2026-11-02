@IsTest
private class OrderLineRollupTest {

    @IsTest
    static void rollsUpLinesOnInsertUpdateAndDelete() {
        Account a = TestDataFactory.accounts(1)[0];
        Wholesale_Order__c o = TestDataFactory.orders(a.Id, 1, 'Placed')[0];

        List<Order_Line__c> lines = new List<Order_Line__c>();
        for (Integer i = 0; i < 200; i++) {
            lines.add(new Order_Line__c(Wholesale_Order__c = o.Id, Product_Name__c = 'Ethiopia Sidamo 2 lb', Quantity__c = 2, Unit_Price__c = 10));
        }
        Test.startTest();
        insert lines;
        o = [SELECT Subtotal__c, Line_Count__c, Total__c FROM Wholesale_Order__c WHERE Id = :o.Id];
        Assert.areEqual(4000, o.Subtotal__c, '200 lines x 2 x $10');
        Assert.areEqual(200, o.Line_Count__c);
        Assert.areEqual(4025, o.Total__c, 'Total recalculated by the order trigger: 4000 + 25 shipping');

        lines[0].Quantity__c = 12;
        update lines[0];
        Assert.areEqual(4100, [SELECT Subtotal__c FROM Wholesale_Order__c WHERE Id = :o.Id].Subtotal__c);

        delete lines[0];
        Test.stopTest();
        o = [SELECT Subtotal__c, Line_Count__c FROM Wholesale_Order__c WHERE Id = :o.Id];
        Assert.areEqual(3980, o.Subtotal__c);
        Assert.areEqual(199, o.Line_Count__c);
    }

    @IsTest
    static void undeleteRestoresTheRollup() {
        Account a = TestDataFactory.accounts(1)[0];
        Wholesale_Order__c o = TestDataFactory.orders(a.Id, 1, 'Placed')[0];
        Order_Line__c line = new Order_Line__c(Wholesale_Order__c = o.Id, Product_Name__c = 'Kenya AA 5 lb', Quantity__c = 1, Unit_Price__c = 70);
        insert line;
        delete line;
        Assert.areEqual(0, [SELECT Subtotal__c FROM Wholesale_Order__c WHERE Id = :o.Id].Subtotal__c);
        undelete line;
        Assert.areEqual(70, [SELECT Subtotal__c FROM Wholesale_Order__c WHERE Id = :o.Id].Subtotal__c);
    }
}
