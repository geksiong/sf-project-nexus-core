// Schedules Nexus Core background jobs (full profile). Idempotent: skips jobs that are already scheduled.
if ([SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :DealRegistrationExpiryJob.JOB_NAME] == 0) {
    System.schedule(
        DealRegistrationExpiryJob.JOB_NAME,
        DealRegistrationExpiryJob.CRON_DAILY,
        new DealRegistrationExpiryJob()
    );
    System.debug('Scheduled ' + DealRegistrationExpiryJob.JOB_NAME + ' (daily 02:00)');
} else {
    System.debug(DealRegistrationExpiryJob.JOB_NAME + ' already scheduled - skipped');
}
