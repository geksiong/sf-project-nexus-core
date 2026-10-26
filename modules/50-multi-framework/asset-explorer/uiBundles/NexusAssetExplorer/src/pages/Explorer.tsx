import { useEffect, useState } from 'react';
import { useAsyncData } from '@/hooks/useAsyncData';
import {
  fetchAccountDetail,
  fetchAccounts,
  type AccountSummary,
} from '@/api/explorerApi';

const currency = new Intl.NumberFormat(undefined, {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
});

/** Debounces a value so typing in the search box does not send a query per keystroke. */
function useDebounced<T>(input: T, delayMs: number): T {
  const [debounced, setDebounced] = useState(input);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(input), delayMs);
    return () => clearTimeout(timer);
  }, [input, delayMs]);
  return debounced;
}

function AccountDetailPanel({ account }: { account: AccountSummary }) {
  const { data, loading, error } = useAsyncData(
    () => fetchAccountDetail(account.id),
    [account.id]
  );
  return (
    <section className="nx-panel" aria-label={`${account.name} details`}>
      <header className="nx-panel__header">
        <h2 className="nx-heading">{account.name}</h2>
        <p className="nx-muted">
          {[account.industry, account.type, account.city]
            .filter(Boolean)
            .join(' · ')}
        </p>
      </header>
      {loading && <p className="nx-muted">Loading assets…</p>}
      {error && (
        <p role="alert" className="nx-error">
          Could not load this account: {error}
        </p>
      )}
      {data && (
        <>
          <dl className="nx-stats">
            <div>
              <dt>Assets</dt>
              <dd>{data.assets.length}</dd>
            </div>
            <div>
              <dt>Installed</dt>
              <dd>{data.installedCount}</dd>
            </div>
            <div>
              <dt>Installed base value</dt>
              <dd>{currency.format(data.totalValue)}</dd>
            </div>
            <div>
              <dt>Open cases</dt>
              <dd>{data.openCases}</dd>
            </div>
          </dl>
          {data.assets.length === 0 ? (
            <p className="nx-muted">No assets for this account.</p>
          ) : (
            <table className="nx-table">
              <thead>
                <tr>
                  <th scope="col">Asset</th>
                  <th scope="col">Product</th>
                  <th scope="col">Status</th>
                  <th scope="col">Serial</th>
                  <th scope="col">Installed</th>
                  <th scope="col" className="nx-num">
                    Value
                  </th>
                </tr>
              </thead>
              <tbody>
                {data.assets.map(asset => (
                  <tr key={asset.id}>
                    <td>{asset.name}</td>
                    <td>{asset.product ?? '—'}</td>
                    <td>{asset.status ?? '—'}</td>
                    <td>{asset.serialNumber ?? '—'}</td>
                    <td>{asset.installDate ?? '—'}</td>
                    <td className="nx-num">
                      {currency.format(asset.price * (asset.quantity || 1))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}
    </section>
  );
}

export default function Explorer() {
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<AccountSummary | null>(null);
  const debouncedSearch = useDebounced(search, 300);
  const {
    data: accounts,
    loading,
    error,
  } = useAsyncData(() => fetchAccounts(debouncedSearch), [debouncedSearch]);

  return (
    <main className="nx-explorer">
      <aside className="nx-panel nx-explorer__list" aria-label="Accounts">
        <label className="nx-label" htmlFor="account-search">
          Search accounts
        </label>
        <input
          id="account-search"
          className="nx-input"
          type="search"
          value={search}
          placeholder="Account name"
          onChange={event => setSearch(event.target.value)}
        />
        {loading && <p className="nx-muted">Loading…</p>}
        {error && (
          <p role="alert" className="nx-error">
            Could not load accounts: {error}
          </p>
        )}
        {accounts && accounts.length === 0 && (
          <p className="nx-muted">No matching accounts.</p>
        )}
        <ul className="nx-list">
          {accounts?.map(account => (
            <li key={account.id}>
              <button
                type="button"
                className="nx-list__item"
                aria-pressed={selected?.id === account.id}
                onClick={() => setSelected(account)}
              >
                <span>{account.name}</span>
                <span className="nx-muted">{account.industry ?? ''}</span>
              </button>
            </li>
          ))}
        </ul>
      </aside>
      {selected ? (
        <AccountDetailPanel account={selected} />
      ) : (
        <section className="nx-panel nx-muted">
          Select an account to see its installed assets.
        </section>
      )}
    </main>
  );
}
