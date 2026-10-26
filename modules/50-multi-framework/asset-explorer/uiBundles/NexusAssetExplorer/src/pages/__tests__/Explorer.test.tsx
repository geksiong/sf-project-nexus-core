import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Explorer from '../Explorer';
import { fetchAccountDetail, fetchAccounts } from '@/api/explorerApi';

vi.mock('@/api/explorerApi', () => ({
  fetchAccounts: vi.fn(),
  fetchAccountDetail: vi.fn(),
}));
const accountsMock = vi.mocked(fetchAccounts);
const detailMock = vi.mocked(fetchAccountDetail);

const ACME = {
  id: '001A',
  name: 'Acme Global',
  industry: 'Manufacturing',
  type: 'Customer',
  city: 'Austin',
};

describe('Explorer', () => {
  beforeEach(() => {
    accountsMock.mockReset();
    detailMock.mockReset();
  });

  it('lists accounts and shows the selected account’s assets', async () => {
    accountsMock.mockResolvedValue([ACME]);
    detailMock.mockResolvedValue({
      assets: [
        {
          id: '02i1',
          name: 'Line 3 gateway',
          product: 'IoT Gateway',
          status: 'Installed',
          serialNumber: 'SN-1',
          installDate: '2026-01-15',
          quantity: 1,
          price: 1200,
        },
      ],
      openCases: 2,
      installedCount: 1,
      totalValue: 1200,
    });

    render(<Explorer />);
    await userEvent.click(
      await screen.findByRole('button', { name: /Acme Global/ })
    );

    expect(
      await screen.findByRole('heading', { name: 'Acme Global' })
    ).toBeInTheDocument();
    expect(await screen.findByText('Line 3 gateway')).toBeInTheDocument();
    expect(screen.getByText('Open cases').nextSibling).toHaveTextContent('2');
    expect(detailMock).toHaveBeenCalledWith('001A');
  });

  it('searches as the user types (debounced)', async () => {
    accountsMock.mockResolvedValue([]);
    render(<Explorer />);
    await userEvent.type(screen.getByLabelText('Search accounts'), 'Glo');
    await waitFor(() => expect(accountsMock).toHaveBeenLastCalledWith('Glo'));
    expect(
      await screen.findByText('No matching accounts.')
    ).toBeInTheDocument();
  });

  it('reports load failures instead of failing silently', async () => {
    accountsMock.mockRejectedValue(
      new Error('GraphQL Error: insufficient access')
    );
    render(<Explorer />);
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'insufficient access'
    );
  });
});
