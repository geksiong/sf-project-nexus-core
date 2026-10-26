import type { RouteObject } from 'react-router';
import AppLayout from '@/appLayout';
import Explorer from './pages/Explorer';
import NotFound from './pages/NotFound';

export const routes: RouteObject[] = [
  {
    path: '/',
    element: <AppLayout />,
    children: [
      {
        index: true,
        element: <Explorer />,
        handle: { showInNavigation: true, label: 'Accounts & Assets' },
      },
      {
        path: '*',
        element: <NotFound />,
      },
    ],
  },
];
