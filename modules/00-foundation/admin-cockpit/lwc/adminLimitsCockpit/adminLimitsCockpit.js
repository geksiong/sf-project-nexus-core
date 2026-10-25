import { LightningElement, wire } from 'lwc';
import getAdminCockpitSnapshot from '@salesforce/apex/OrgLimitsService.getAdminCockpitSnapshot';

export default class AdminLimitsCockpit extends LightningElement {
    snapshot;
    isLoading = true;

    @wire(getAdminCockpitSnapshot)
    wiredSnapshot({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.snapshot = {
                limits: data.limits.map(l => ({
                    ...l,
                    formattedPercent: Math.round(l.percentUsed),
                    badgeVariant: l.status === 'CRITICAL' ? 'error' : (l.status === 'WARNING' ? 'warning' : 'success'),
                    progressVariant: l.status === 'CRITICAL' ? 'expired' : 'base'
                })),
                recentErrors: data.recentErrors.map(e => ({
                    ...e,
                    badgeVariant: e.severity === 'CRITICAL' || e.severity === 'ERROR' ? 'error' : 'inverse'
                }))
            };
        } else if (error) {
            console.error('Error fetching org telemetry:', error);
        }
    }
}