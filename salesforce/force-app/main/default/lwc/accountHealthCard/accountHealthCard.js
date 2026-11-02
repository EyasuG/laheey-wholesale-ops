import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHealth from '@salesforce/apex/AccountHealthController.getHealth';
import refreshFromWarehouse from '@salesforce/apex/AccountHealthController.refreshFromWarehouse';

// Level 5: @wire for cached, reactive reads; imperative Apex for the action that writes.
export default class AccountHealthCard extends LightningElement {
    @api recordId;
    view;
    error;
    refreshing = false;
    wiredResult;

    @wire(getHealth, { accountId: '$recordId' })
    wiredHealth(result) {
        this.wiredResult = result;
        if (result.data) {
            this.view = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.view = undefined;
            this.error = this.message(result.error);
        }
    }

    get scoreClass() {
        const s = this.view?.health?.status;
        return 'ring' + (s === 'Watch' ? ' watch' : s === 'At Risk' ? ' risk' : '');
    }

    get hasMonths() {
        return this.view?.months?.length > 0;
    }

    get bars() {
        const months = this.view?.months || [];
        const max = Math.max(...months.map((m) => m.revenue || 0), 1);
        return months.map((m) => ({
            label: m.label,
            short: m.label.split(' ')[0],
            title: `${m.label}: $${Math.round(m.revenue || 0).toLocaleString()} from ${m.orders || 0} orders`,
            style: `height: ${Math.max(2, Math.round(((m.revenue || 0) / max) * 100))}%`
        }));
    }

    get chartLabel() {
        return `Monthly revenue for the last ${this.view?.months?.length || 0} months`;
    }

    async handleRefresh() {
        this.refreshing = true;
        try {
            const msg = await refreshFromWarehouse({ accountId: this.recordId });
            await refreshApex(this.wiredResult);
            this.dispatchEvent(new ShowToastEvent({ title: 'Account refreshed', message: msg, variant: 'success' }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Refresh failed', message: this.message(e), variant: 'error' }));
        } finally {
            this.refreshing = false;
        }
    }

    message(e) {
        return e?.body?.message || e?.message || 'Something went wrong.';
    }
}
