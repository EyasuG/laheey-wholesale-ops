/**
 * Level 7. Agentforce action: "How is this account doing?"
 * Uses the same AccountHealthService as the batch and the LWC, so the agent never contradicts the page.
 */
public with sharing class AccountInsightAction {

    public class Request {
        @InvocableVariable(required=true label='Account Id' description='Salesforce Id of the wholesale account.')
        public Id accountId;
    }

    public class Result {
        @InvocableVariable(label='Health Status' description='Healthy, Watch or At Risk.')
        public String healthStatus;
        @InvocableVariable(label='Health Score' description='0 to 100.')
        public Integer healthScore;
        @InvocableVariable(label='Summary' description='A short briefing for a sales rep: revenue, recency, trend, open cases and suggested next step.')
        public String summary;
    }

    @InvocableMethod(label='Get Wholesale Account Insights' description='Summarizes a wholesale account: health score and status, 12-month revenue, last order, revenue trend, open support cases and a suggested next step.' category='Laheey Wholesale')
    public static List<Result> getInsights(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request r : requests) {
            ids.add(r.accountId);
        }
        Map<Id, Account> accounts = new Map<Id, Account>([
            SELECT Id, Name, Tier__c, Segment__c, Revenue_12M__c, Last_Order_Date__c, Open_Cases__c, Sales_Rep__c
            FROM Account WHERE Id IN :ids WITH USER_MODE
        ]);
        Date today = Date.today();
        Map<Id, Decimal[]> windows = AccountHealthService.revenueWindows(accounts.keySet(), today);

        List<Result> results = new List<Result>();
        for (Request r : requests) {
            Result out = new Result();
            Account a = accounts.get(r.accountId);
            if (a == null) {
                out.summary = 'I couldn\'t find that account, or you don\'t have access to it.';
                results.add(out);
                continue;
            }
            Decimal[] w = windows.get(a.Id);
            AccountHealthService.Result h = AccountHealthService.score(a.Last_Order_Date__c, w[0], w[1], a.Open_Cases__c, today);
            out.healthStatus = h.status;
            out.healthScore = h.score;
            out.summary = a.Name + ' (' + a.Tier__c + ' ' + a.Segment__c + ') is ' + h.status + ' with a score of ' + h.score + '/100. '
                + '12-month revenue: $' + (a.Revenue_12M__c == null ? '0' : a.Revenue_12M__c.setScale(0).format()) + '. '
                + 'Last order: ' + (a.Last_Order_Date__c == null ? 'none' : a.Last_Order_Date__c.format()) + '. '
                + String.join(h.reasons, ' ') + ' '
                + nextStep(h.status, a);
            results.add(out);
        }
        return results;
    }

    private static String nextStep(String status, Account a) {
        if (status == 'At Risk') {
            return 'Suggested next step: ' + (a.Sales_Rep__c == null ? 'the account owner' : a.Sales_Rep__c) + ' should call this week and review open cases.';
        }
        if (status == 'Watch') {
            return 'Suggested next step: send a reorder reminder and check on any open cases.';
        }
        return 'Suggested next step: a good candidate for a new-origin sample or a larger standing order.';
    }
}
