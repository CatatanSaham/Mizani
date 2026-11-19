import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SiteFooterComponent, SiteHeaderComponent } from '../components/site-shell.component';

@Component({
  selector: 'mizani-terms-page',
  standalone: true,
  imports: [RouterLink, SiteHeaderComponent, SiteFooterComponent],
  template: `
    <mizani-site-header />
    <main id="main-content" tabindex="-1" class="legal-page page-width">
      <h1>Website Terms of Use</h1>
      <p class="legal-meta">Version 2026-11-19-4 · Effective 19 November 2026</p>
      <p class="legal-lede">These terms cover the Mizani promotional website and its optional local report page. They do not change the terms for the Android app or the rights provided by the project's open-source license.</p>

      <article class="legal-content">
        <section><h2>1. Provider and contact</h2><p>Provider: Nyota Foundry. Address: Kampala, Uganda. Contact: <a href="mailto:paul.ochieng.dev@gmail.com">paul.ochieng.dev&#64;gmail.com</a>.</p></section>
        <section><h2>2. What this website does</h2><p>This website describes Mizani and provides links to the project. Its report workspace reads a Mizani transaction CSV and calculates descriptive summaries in your browser without uploading or synchronizing your ledger. You can also explore the workspace with fictional sample records.</p></section>
        <section><h2>3. Use of the local report</h2><p>Use a private, trusted device and a file you are entitled to access. Mizani's CSV export is readable and unencrypted. The workspace accepts transaction CSV files. It analyzes rows that pass validation and identifies rejected rows. A report can be incomplete when records are missing or rejected.</p><p>The local question helper uses fixed rules and describes accepted records. On supported desktop Chrome, you can separately opt in to an AI-generated note about the summary figures if Chrome already has its on-device model ready. The AI note may omit important context or state figures incorrectly. Use the calculated report and your own records to check it. There is no external provider connection, subscription linking, or API key entry.</p></section>
        <section><h2>4. Not financial advice</h2><p>Mizani and this website are record-keeping and information tools. They are not a bank, payment service, lender, investment adviser, credit-scoring service, accountant, tax service, or fiduciary. Reports are not financial, investment, legal, accounting, or tax advice, and are not a recommendation to take any action. Check important decisions against your own records and appropriate professional advice.</p></section>
        <section><h2>5. The Android app</h2><p>The Android app is the complete Mizani client described on this website. The iOS client is an early preview and is not ready for financial use or App Store distribution. Do not rely on this website as a promise that a future app, feature, or platform will be available.</p></section>
        <section><h2>6. Availability and third-party services</h2><p>The website and project links may change or be unavailable. Vercel provides the planned website hosting, and GitHub provides the project repository. Vercel, GitHub, app marketplaces, internet providers, and other linked services operate under their own terms and privacy notices. Mizani does not control their availability or handling of information.</p></section>
        <section><h2>7. Intellectual property</h2><p>Mizani source code is licensed as described in the project's Apache-2.0 <a href="https://github.com/NyotaFoundry/Mizani/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">license</a> and <a href="https://github.com/NyotaFoundry/Mizani/blob/main/NOTICE" target="_blank" rel="noopener noreferrer">notice</a>. The Mizani name, logo, and third-party materials may have separate rights and are not granted by that source license.</p></section>
        <section><h2>8. Your information</h2><p>Do not provide information you have no right to use. You are responsible for keeping CSV exports and reports private, reviewing the report's data-quality summary, and checking results against your records.</p></section>
        <section><h2>9. Service limits</h2><p>The website is provided without a promise that it will always be available, error-free, or suitable for every device or purpose. To the extent allowed by law, the provider is not responsible for indirect loss caused by relying on a report or losing an export. Nothing in these terms limits a right or remedy that applicable law does not allow us to limit, including mandatory consumer protections.</p></section>
        <section><h2>10. Changes and applicable law</h2><p>These terms may change when the website or its data flows change. The effective date and version above identify this copy. Mandatory laws that apply where you live continue to apply. For a question about these terms, contact the provider at the address above.</p></section>
      </article>
      <div class="legal-back"><a class="text-link" routerLink="/analysis">Return to the report workspace</a></div>
    </main>
    <mizani-site-footer />
  `,
})
export class TermsPageComponent {}
