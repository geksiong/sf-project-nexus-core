/**
 * @description Daily housekeeping for partner deal registrations: marks Approved registrations whose
 * reservation has lapsed (past Expires_On__c, or their opportunity closed) as Expired or Closed. The channel
 * conflict rule already treats lapsed reservations as released; this keeps statuses accurate for partners,
 * reports and list views. Scheduled by the setup script (scripts/org-init/schedule-jobs.apex).
 */
public with sharing class DealRegistrationExpiryJob implements Schedulable {
    public static final String JOB_NAME = 'Nexus Deal Registration Expiry';
    public static final String CRON_DAILY = '0 0 2 * * ?';

    public void execute(SchedulableContext context) {
        DealRegistrationService.releaseLapsedReservations();
    }
}
