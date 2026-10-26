import { describe, expect, it, vi, beforeEach } from 'vitest';
import {
  fetchAccounts,
  fetchAccountDetail,
  searchPattern,
  toAccountDetail,
} from '../explorerApi';
import { executeGraphQL } from '../graphqlClient';

vi.mock('../graphqlClient', () => ({ executeGraphQL: vi.fn() }));
const mockedGraphQL = vi.mocked(executeGraphQL);

const asset = (
  id: string,
  status: string | null,
  price: number | null,
  quantity: number | null
) => ({
  node: {
    Id: id,
    Name: { value: `Asset ${id}` },
    Status: { value: status },
    SerialNumber: { value: `SN-${id}` },
    InstallDate: { value: '2026-01-15' },
    Quantity: { value: quantity },
    Price: { value: price },
    Product2: { Name: { value: 'IoT Gateway' } },
  },
});

describe('explorerApi', () => {
  beforeEach(() => mockedGraphQL.mockReset());

  it('escapes LIKE wildcards in search input', () => {
    expect(searchPattern('  Acme ')).toBe('%Acme%');
    expect(searchPattern('100%_off')).toBe('%100\\%\\_off%');
    expect(searchPattern('')).toBe('%%');
  });

  it('maps accounts and sends the search pattern', async () => {
    mockedGraphQL.mockResolvedValue({
      uiapi: {
        query: {
          Account: {
            edges: [
              {
                node: {
                  Id: '001A',
                  Name: { value: 'Acme' },
                  Industry: { value: 'Manufacturing' },
                  Type: null,
                  BillingCity: { value: null },
                },
              },
            ],
          },
        },
      },
    });

    const accounts = await fetchAccounts('Ac');

    expect(mockedGraphQL).toHaveBeenCalledWith(
      expect.stringContaining('ExplorerAccounts'),
      { search: '%Ac%' }
    );
    expect(accounts).toEqual([
      {
        id: '001A',
        name: 'Acme',
        industry: 'Manufacturing',
        type: null,
        city: null,
      },
    ]);
  });

  it('summarises installed base value and open cases', () => {
    const detail = toAccountDetail({
      uiapi: {
        query: {
          Asset: {
            edges: [
              asset('1', 'Installed', 1000, 2),
              asset('2', 'Shipped', 500, null),
              asset('3', null, null, 3),
            ],
          },
          Case: { totalCount: 4 },
        },
      },
    });

    expect(detail.assets).toHaveLength(3);
    expect(detail.installedCount).toBe(1);
    expect(detail.totalValue).toBe(2500);
    expect(detail.openCases).toBe(4);
    expect(detail.assets[0]).toMatchObject({
      product: 'IoT Gateway',
      serialNumber: 'SN-1',
      quantity: 2,
    });
  });

  it('queries one account by id', async () => {
    mockedGraphQL.mockResolvedValue({
      uiapi: { query: { Asset: { edges: [] }, Case: { totalCount: 0 } } },
    });
    const detail = await fetchAccountDetail('001A');
    expect(mockedGraphQL).toHaveBeenCalledWith(
      expect.stringContaining('ExplorerAccountDetail'),
      { accountId: '001A' }
    );
    expect(detail).toEqual({
      assets: [],
      openCases: 0,
      installedCount: 0,
      totalValue: 0,
    });
  });
});
