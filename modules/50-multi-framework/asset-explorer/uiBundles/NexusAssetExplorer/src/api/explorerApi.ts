/**
 * Data access for the Nexus Asset Explorer (Demo App 8). Everything goes through the UI API GraphQL
 * endpoint via the platform SDK (`executeGraphQL`), so results respect the running user's object, field
 * and sharing access: the React app never sees data the user could not see in Lightning.
 */
import { executeGraphQL } from './graphqlClient';

export const ACCOUNTS_QUERY = /* GraphQL */ `
  query ExplorerAccounts($search: String) {
    uiapi {
      query {
        Account(
          where: { Name: { like: $search } }
          orderBy: { Name: { order: ASC } }
          first: 50
        ) {
          edges {
            node {
              Id
              Name {
                value
              }
              Industry {
                value
              }
              Type {
                value
              }
              BillingCity {
                value
              }
            }
          }
        }
      }
    }
  }
`;

export const ACCOUNT_DETAIL_QUERY = /* GraphQL */ `
  query ExplorerAccountDetail($accountId: ID) {
    uiapi {
      query {
        Asset(
          where: { AccountId: { eq: $accountId } }
          orderBy: { Name: { order: ASC } }
          first: 100
        ) {
          edges {
            node {
              Id
              Name {
                value
              }
              Status {
                value
              }
              SerialNumber {
                value
              }
              InstallDate {
                value
              }
              Quantity {
                value
              }
              Price {
                value
              }
              Product2 {
                Name {
                  value
                }
              }
            }
          }
        }
        Case(
          where: {
            and: [
              { AccountId: { eq: $accountId } }
              { IsClosed: { eq: false } }
            ]
          }
        ) {
          totalCount
        }
      }
    }
  }
`;

type Field<T> = { value: T | null } | null | undefined;

export interface AccountSummary {
  id: string;
  name: string;
  industry: string | null;
  type: string | null;
  city: string | null;
}

export interface AssetRow {
  id: string;
  name: string;
  product: string | null;
  status: string | null;
  serialNumber: string | null;
  installDate: string | null;
  quantity: number;
  price: number;
}

export interface AccountDetail {
  assets: AssetRow[];
  openCases: number;
  installedCount: number;
  totalValue: number;
}

interface AccountsResponse {
  uiapi: {
    query: {
      Account: {
        edges: {
          node: {
            Id: string;
            Name: Field<string>;
            Industry: Field<string>;
            Type: Field<string>;
            BillingCity: Field<string>;
          };
        }[];
      };
    };
  };
}

interface AccountDetailResponse {
  uiapi: {
    query: {
      Asset: {
        edges: {
          node: {
            Id: string;
            Name: Field<string>;
            Status: Field<string>;
            SerialNumber: Field<string>;
            InstallDate: Field<string>;
            Quantity: Field<number>;
            Price: Field<number>;
            Product2: { Name: Field<string> } | null;
          };
        }[];
      };
      Case: { totalCount: number };
    };
  };
}

const value = <T>(field: Field<T>): T | null => field?.value ?? null;

/** Escapes LIKE wildcards in user input and wraps it as a "contains" pattern. */
export function searchPattern(search: string): string {
  const term = search.trim().replace(/[\\%_]/g, c => `\\${c}`);
  return `%${term}%`;
}

export function toAccountSummaries(
  response: AccountsResponse
): AccountSummary[] {
  return response.uiapi.query.Account.edges.map(({ node }) => ({
    id: node.Id,
    name: value(node.Name) ?? '(no name)',
    industry: value(node.Industry),
    type: value(node.Type),
    city: value(node.BillingCity),
  }));
}

export function toAccountDetail(
  response: AccountDetailResponse
): AccountDetail {
  const assets: AssetRow[] = response.uiapi.query.Asset.edges.map(
    ({ node }) => ({
      id: node.Id,
      name: value(node.Name) ?? '(no name)',
      product: value(node.Product2?.Name),
      status: value(node.Status),
      serialNumber: value(node.SerialNumber),
      installDate: value(node.InstallDate),
      quantity: value(node.Quantity) ?? 0,
      price: value(node.Price) ?? 0,
    })
  );
  return {
    assets,
    openCases: response.uiapi.query.Case.totalCount,
    installedCount: assets.filter(a => a.status === 'Installed').length,
    totalValue: assets.reduce((sum, a) => sum + a.price * (a.quantity || 1), 0),
  };
}

export async function fetchAccounts(search: string): Promise<AccountSummary[]> {
  const response = await executeGraphQL<AccountsResponse, { search: string }>(
    ACCOUNTS_QUERY,
    {
      search: searchPattern(search),
    }
  );
  return toAccountSummaries(response);
}

export async function fetchAccountDetail(
  accountId: string
): Promise<AccountDetail> {
  const response = await executeGraphQL<
    AccountDetailResponse,
    { accountId: string }
  >(ACCOUNT_DETAIL_QUERY, {
    accountId,
  });
  return toAccountDetail(response);
}
