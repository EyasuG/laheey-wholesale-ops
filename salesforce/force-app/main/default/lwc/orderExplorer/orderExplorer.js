import { LightningElement, api, wire } from 'lwc';
import getOrders from '@salesforce/apex/OrderExplorerController.getOrders';
import getSummary from '@salesforce/apex/OrderExplorerController.getSummary';

const PAGE = 50;
const COLUMNS = [
    { label: 'Order', fieldName: 'url', type: 'url', typeAttributes: { label: { fieldName: 'Name' } } },
    { label: 'Date', fieldName: 'Order_Date__c', type: 'date-local' },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Payment', fieldName: 'Payment_Status__c' },
    { label: 'Channel', fieldName: 'Channel__c' },
    { label: 'Lines', fieldName: 'Line_Count__c', type: 'number', initialWidth: 80 },
    { label: 'Total', fieldName: 'Total__c', type: 'currency', typeAttributes: { currencyCode: 'USD' } }
];

// Level 5-6: infinite scroll over keyset pages. Each page asks for orders older than the last row shown.
export default class OrderExplorer extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    rows = [];
    hasMore = true;
    loading = false;
    error;
    summary;

    @wire(getSummary, { accountId: '$recordId' })
    wiredSummary({ data }) {
        if (data) this.summary = data;
    }

    connectedCallback() {
        this.fetchPage();
    }

    get title() {
        return `Wholesale Orders (${this.rows.length}${this.hasMore ? '+' : ''})`;
    }

    get summaryText() {
        if (!this.summary) return 'Loading summary...';
        const revenue = Math.round(this.summary.revenue || 0).toLocaleString();
        return `${this.summary.orders} synced orders, $${revenue} total, ${this.summary.overdue} overdue.`;
    }

    loadMore() {
        this.fetchPage();
    }

    async fetchPage() {
        if (this.loading || !this.hasMore) return;
        this.loading = true;
        const last = this.rows[this.rows.length - 1];
        try {
            const page = await getOrders({
                accountId: this.recordId,
                beforeDate: last ? last.Order_Date__c : null,
                beforeId: last ? last.Id : null,
                pageSize: PAGE
            });
            const mapped = page.map((o) => ({ ...o, url: `/${o.Id}` }));
            this.rows = [...this.rows, ...mapped];
            this.hasMore = page.length === PAGE;
        } catch (e) {
            this.error = e?.body?.message || 'Could not load orders.';
            this.hasMore = false;
        } finally {
            this.loading = false;
        }
    }
}
