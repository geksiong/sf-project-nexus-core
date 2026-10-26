import { createElement } from 'lwc';
import HospitalityArticles from 'c/hospitalityArticles';
import getPublishedArticles from '@salesforce/apex/PortalContentController.getPublishedArticles';

jest.mock(
    '@salesforce/apex/PortalContentController.getPublishedArticles',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

const ARTICLES = [
    {
        id: 'a01',
        title: 'Spring spa offer',
        summary: 'Two nights, one price',
        body: 'Book by May.',
        category: 'Offers',
        publishedOn: '2026-10-20T08:00:00.000Z'
    },
    { id: 'a02', title: 'Harbour festival', summary: 'Live music', body: 'All weekend.', category: 'Events' }
];

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount(props = {}) {
    const element = createElement('c-hospitality-articles', { is: HospitalityArticles });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

describe('c-hospitality-articles', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders in light DOM with a card per published article', async () => {
        const element = mount();
        getPublishedArticles.emit(ARTICLES);
        await flushPromises();

        expect(element.shadowRoot).toBeNull();
        const titles = [...element.querySelectorAll('.nexus-articles__title')].map((n) => n.textContent.trim());
        expect(titles).toEqual(['Spring spa offer', 'Harbour festival']);
        expect(element.querySelector('.nexus-articles__date').textContent).not.toBe('');
        expect(element.querySelector('h2').textContent).toBe('Latest from Nexus Hospitality');
    });

    it('passes the configured category to Apex', async () => {
        mount({ category: 'Events', heading: 'Events' });
        await flushPromises();
        expect(getPublishedArticles.getLastConfig()).toEqual({ category: 'Events' });
    });

    it('shows an empty state when nothing is published', async () => {
        const element = mount();
        getPublishedArticles.emit([]);
        await flushPromises();
        expect(element.querySelector('.nexus-articles__empty')).not.toBeNull();
        expect(element.querySelector('.nexus-articles__list')).toBeNull();
    });

    it('shows a friendly error when content cannot be loaded', async () => {
        const element = mount();
        getPublishedArticles.error();
        await flushPromises();
        expect(element.querySelector('.nexus-articles__error').textContent).toContain('temporarily unavailable');
        expect(element.querySelector('.nexus-articles__empty')).toBeNull();
    });
});
