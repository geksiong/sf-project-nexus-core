import { LightningElement, api, wire } from 'lwc';
import getPublishedArticles from '@salesforce/apex/PortalContentController.getPublishedArticles';

/**
 * Published hospitality articles for the Nexus Hospitality LWR site (Demo App 5). Light DOM so the site
 * theme styles it and it stays compatible with Lightning Web Security; data comes from
 * PortalContentController, which runs as the site guest user.
 */
export default class HospitalityArticles extends LightningElement {
    static renderMode = 'light';

    /** Optional category filter (Offers, Events, Travel Tips); empty shows all. */
    @api category;
    @api heading = 'Latest from Nexus Hospitality';

    articles = [];
    error;
    loaded = false;

    @wire(getPublishedArticles, { category: '$category' })
    wiredArticles({ data, error }) {
        if (data) {
            this.articles = data.map((article) => ({
                ...article,
                publishedLabel: article.publishedOn ? new Date(article.publishedOn).toLocaleDateString() : ''
            }));
            this.error = undefined;
            this.loaded = true;
        } else if (error) {
            this.articles = [];
            this.error = 'Content is temporarily unavailable. Please try again later.';
            this.loaded = true;
        }
    }

    get hasArticles() {
        return this.articles.length > 0;
    }

    get isEmpty() {
        return this.loaded && !this.error && this.articles.length === 0;
    }
}
