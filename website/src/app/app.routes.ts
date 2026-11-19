import { Routes } from '@angular/router';
import { HomeRedesignPageComponent } from './pages/home-redesign-page.component';

export const routes: Routes = [
  {
    path: '',
    component: HomeRedesignPageComponent,
    title: 'Mizani | Offline money tracking for Android',
    data: { description: 'Track cash, mobile money and bank activity with Mizani, an offline-first Android money tracker. Your encrypted ledger stays on your phone. No account or cloud sync.' },
  },
  {
    path: 'analysis',
    loadComponent: () => import('./pages/analysis-page.component').then((page) => page.AnalysisPageComponent),
    title: 'Private CSV report workspace | Mizani',
    data: {
      description: 'Review a Mizani transaction CSV in your browser with local cash-flow summaries, spending breakdowns and data-quality checks.',
      robots: 'noindex, nofollow',
    },
  },
  {
    path: 'terms',
    loadComponent: () => import('./pages/terms-page.component').then((page) => page.TermsPageComponent),
    title: 'Website terms | Mizani',
    data: { description: 'Read the terms for the Mizani website and its browser-local report workspace.' },
  },
  {
    path: 'privacy',
    loadComponent: () => import('./pages/privacy-page.component').then((page) => page.PrivacyPageComponent),
    title: 'Website privacy | Mizani',
    data: { description: 'Learn how the Mizani website and local report workspace handle your information.' },
  },
  { path: '**', redirectTo: '' },
];
