import { createElement } from 'lwc';
import AdminLimitsCockpit from 'c/adminLimitsCockpit';
import getAdminCockpitSnapshot from '@salesforce/apex/OrgLimitsService.getAdminCockpitSnapshot';

jest.mock('@salesforce/apex/OrgLimitsService.getAdminCockpitSnapshot', () => ({ default: jest.fn() }), {
    virtual: true
});

const SNAPSHOT = {
    overallStatus: 'WARNING',
    generatedAt: '2026-10-25T08:00:00.000Z',
    errorFeedAvailable: true,
    limits: [
        {
            name: 'DailyApiRequests',
            label: 'Daily API Requests',
            current: 100,
            max: 1000,
            percentUsed: 10,
            status: 'OK'
        },
        { name: 'DataStorageMB', label: 'Data Storage (MB)', current: 4, max: 5, percentUsed: 80, status: 'WARNING' }
    ],
    recentErrors: [
        {
            logId: 'a01',
            message: 'Boom',
            origin: 'OpportunityService',
            loggedTime: '2026-10-25T07:00:00.000Z',
            severity: 'ERROR'
        }
    ]
};

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-admin-limits-cockpit', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function mount() {
        const element = createElement('c-admin-limits-cockpit', { is: AdminLimitsCockpit });
        document.body.appendChild(element);
        return element;
    }

    it('renders limit tiles, overall status and error rows', async () => {
        getAdminCockpitSnapshot.mockResolvedValue(SNAPSHOT);
        const element = mount();
        await flushPromises();

        const root = element.shadowRoot;
        expect(root.querySelectorAll('[data-id="limit-tile"]')).toHaveLength(2);
        expect(root.querySelector('[data-id="overall-status"]').textContent).toBe('WARNING');
        expect(root.querySelectorAll('[data-id="error-row"]')).toHaveLength(1);
        expect(root.querySelector('[data-id="no-errors"]')).toBeNull();
    });

    it('shows the empty state when there are no logged errors', async () => {
        getAdminCockpitSnapshot.mockResolvedValue({ ...SNAPSHOT, recentErrors: [] });
        const element = mount();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="no-errors"]')).not.toBeNull();
    });

    it('surfaces an unavailable error feed instead of hiding it', async () => {
        getAdminCockpitSnapshot.mockResolvedValue({
            ...SNAPSHOT,
            recentErrors: [],
            errorFeedAvailable: false,
            errorFeedMessage: 'Error feed unavailable: no access'
        });
        const element = mount();
        await flushPromises();

        const root = element.shadowRoot;
        expect(root.querySelector('[data-id="feed-unavailable"]').textContent).toContain('no access');
        expect(root.querySelector('[data-id="no-errors"]')).toBeNull();
    });

    it('re-queries Apex when refresh is clicked', async () => {
        getAdminCockpitSnapshot.mockResolvedValue(SNAPSHOT);
        const element = mount();
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button-icon').click();
        await flushPromises();
        expect(getAdminCockpitSnapshot).toHaveBeenCalledTimes(2);
    });

    it('shows an alert when the Apex call fails', async () => {
        getAdminCockpitSnapshot.mockRejectedValue({ body: { message: 'Insufficient access' } });
        const element = mount();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-alert_error').textContent).toBe('Insufficient access');
    });
});
