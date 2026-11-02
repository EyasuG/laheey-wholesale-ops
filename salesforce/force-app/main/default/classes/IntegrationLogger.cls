/**
 * Writes one Integration_Log__c row per sync page or batch run, so failures are visible in the org
 * (and reportable) instead of hiding in debug logs.
 */
public with sharing class IntegrationLogger {

    public static Integration_Log__c log(String job, String stage, Integer processed, List<String> errors, String cursor, Long startedMs) {
        Integer errorCount = errors == null ? 0 : errors.size();
        String status = errorCount == 0 ? 'Success' : (processed > errorCount ? 'Partial' : 'Failed');
        Integration_Log__c row = new Integration_Log__c(
            Job__c = job,
            Stage__c = stage,
            Status__c = status,
            Records_Processed__c = processed,
            Errors__c = errorCount,
            Cursor__c = cursor,
            Duration_Ms__c = startedMs == null ? null : System.currentTimeMillis() - startedMs,
            Message__c = errorCount == 0 ? null : String.join(errors, '\n').left(32000)
        );
        insert row;
        return row;
    }

    public static Integration_Log__c failure(String job, String stage, Exception e, String cursor, Long startedMs) {
        return log(job, stage, 0, new List<String>{ e.getTypeName() + ': ' + e.getMessage() }, cursor, startedMs);
    }

    /** Turns failed rows of a partial-success DML into readable messages. */
    public static List<String> collect(List<Database.UpsertResult> results, List<SObject> records, String keyField) {
        List<String> errors = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                List<String> parts = new List<String>();
                for (Database.Error err : results[i].getErrors()) {
                    parts.add(err.getStatusCode() + ' ' + err.getMessage());
                }
                errors.add(String.valueOf(records[i].get(keyField)) + ': ' + String.join(parts, '; '));
            }
        }
        return errors;
    }
}
