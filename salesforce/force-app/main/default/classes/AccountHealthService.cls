/**
 * Level 6. One place that decides how healthy a wholesale account is, so the batch, the LWC and the
 * Agentforce action always agree. Pure logic (no SOQL), which makes it easy to unit test.
 *
 * Score out of 100:
 *   Recency  40  days since the last order
 *   Trend    35  revenue in the last 3 months vs the 3 months before
 *   Service  25  open support cases
 * Status: 70+ Healthy, 40-69 Watch, under 40 At Risk.
 */
public with sharing class AccountHealthService {

    public class Result {
        @AuraEnabled public Integer score;
        @AuraEnabled public String status;
        @AuraEnabled public List<String> reasons = new List<String>();
    }

    public static Result score(Date lastOrderDate, Decimal revenueLast3, Decimal revenuePrior3, Decimal openCases, Date today) {
        Result r = new Result();
        Integer points = 0;

        // Recency
        if (lastOrderDate == null) {
            r.reasons.add('No orders on record.');
        } else {
            Integer days = lastOrderDate.daysBetween(today);
            if (days <= 14) { points += 40; }
            else if (days <= 30) { points += 30; }
            else if (days <= 60) { points += 15; r.reasons.add('Last order was ' + days + ' days ago.'); }
            else { r.reasons.add('No order in ' + days + ' days.'); }
        }

        // Trend
        Decimal recent = revenueLast3 == null ? 0 : revenueLast3;
        Decimal prior = revenuePrior3 == null ? 0 : revenuePrior3;
        if (prior == 0) {
            points += recent > 0 ? 35 : 0;
            if (recent == 0) { r.reasons.add('No revenue in the last 6 months.'); }
        } else {
            Decimal ratio = recent / prior;
            if (ratio >= 1) { points += 35; }
            else if (ratio >= 0.8) { points += 25; }
            else if (ratio >= 0.5) { points += 10; r.reasons.add('Revenue down ' + pct(1 - ratio) + ' vs the prior 3 months.'); }
            else { r.reasons.add('Revenue down ' + pct(1 - ratio) + ' vs the prior 3 months.'); }
        }

        // Service
        Integer cases = openCases == null ? 0 : openCases.intValue();
        if (cases == 0) { points += 25; }
        else if (cases <= 2) { points += 15; }
        else if (cases <= 5) { points += 5; r.reasons.add(cases + ' open support cases.'); }
        else { r.reasons.add(cases + ' open support cases.'); }

        r.score = points;
        r.status = points >= 70 ? 'Healthy' : (points >= 40 ? 'Watch' : 'At Risk');
        if (r.reasons.isEmpty()) {
            r.reasons.add('Ordering steadily with no open issues.');
        }
        return r;
    }

    /** Sums Account_Metric__c revenue into [last 3 months, prior 3 months] per account, in one aggregate query. */
    public static Map<Id, Decimal[]> revenueWindows(Set<Id> accountIds, Date today) {
        Date thisMonth = today.toStartOfMonth();
        Date recentStart = thisMonth.addMonths(-2);   // e.g. Aug, Sep, Oct
        Date priorStart = thisMonth.addMonths(-5);    // e.g. May, Jun, Jul
        Map<Id, Decimal[]> out = new Map<Id, Decimal[]>();
        for (Id accountId : accountIds) {
            out.put(accountId, new Decimal[]{ 0, 0 });
        }
        for (AggregateResult ar : [
            SELECT Account__c acct, Month__c mth, SUM(Revenue__c) revenue
            FROM Account_Metric__c
            WHERE Account__c IN :accountIds AND Month__c >= :priorStart
            GROUP BY Account__c, Month__c
        ]) {
            Decimal[] w = out.get((Id) ar.get('acct'));
            Decimal revenue = (Decimal) ar.get('revenue');
            Date month = (Date) ar.get('mth');
            if (revenue == null) { continue; }
            if (month >= recentStart) { w[0] += revenue; } else { w[1] += revenue; }
        }
        return out;
    }

    private static String pct(Decimal fraction) {
        return String.valueOf((fraction * 100).setScale(0)) + '%';
    }
}
