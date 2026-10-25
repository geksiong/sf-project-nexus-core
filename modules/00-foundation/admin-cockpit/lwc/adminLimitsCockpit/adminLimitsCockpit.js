import { LightningElement } from 'lwc';
import getAdminCockpitSnapshot from '@salesforce/apex/OrgLimitsService.getAdminCockpitSnapshot';

const BADGE_CLASS = {
    OK: 'slds-badge slds-theme_success',
    WARNING: 'slds-badge slds-theme_warning',
    CRITICAL: 'slds-badge slds-theme_error'
};

export default class AdminLimitsCockpit extends LightningElement {
    snapshot;
    errorMessage;
    isLoading = false;

    connectedCallback() {
        this.loadSnapshot();
    }

    get hasErrors() {
        return this.snapshot?.recentErrors?.length > 0;
    }

    get showNoErrors() {
        return this.snapshot?.errorFeedAvailable && !this.hasErrors;
    }

    async loadSnapshot() {
        this.isLoading = true;
        try {
            const data = await getAdminCockpitSnapshot();
            this.snapshot = {
                ...data,
                overallBadgeClass: BADGE_CLASS[data.overallStatus] ?? BADGE_CLASS.OK,
                limits: data.limits.map((l) => ({
                    ...l,
                    badgeClass: BADGE_CLASS[l.status] ?? BADGE_CLASS.OK,
                    progressVariant: l.status === 'CRITICAL' ? 'expired' : 'base'
                })),
                recentErrors: data.recentErrors.map((e) => ({
                    ...e,
                    badgeClass: e.severity === 'ERROR' ? BADGE_CLASS.CRITICAL : BADGE_CLASS.WARNING
                }))
            };
            this.errorMessage = undefined;
        } catch (error) {
            this.errorMessage = error?.body?.message ?? 'Unable to load org telemetry.';
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.loadSnapshot();
    }
}
