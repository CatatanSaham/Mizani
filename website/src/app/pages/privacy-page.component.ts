import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SiteFooterComponent, SiteHeaderComponent } from '../components/site-shell.component';

@Component({
  selector: 'mizani-privacy-page',
  standalone: true,
  imports: [RouterLink, SiteFooterComponent, SiteHeaderComponent],
  template: `
    <mizani-site-header />
    <main id="main-content" tabindex="-1" class="legal-page page-width">
      <h1>Website Privacy Notice</h1>
      <p class="legal-meta">Version 2026-11-19-4 · Effective 19 November 2026</p>
      <p class="legal-lede">This notice covers the Mizani website and its browser-local report page. It is separate from the Mizani Android app's privacy notice.</p>

      <article class="legal-content">
        <section><h2>1. Who is responsible</h2><p>Provider: Nyota Foundry. Address: Kampala, Uganda. Contact: <a href="mailto:paul.ochieng.dev@gmail.com">paul.ochieng.dev&#64;gmail.com</a>.</p></section>
        <section><h2>2. What the website itself receives</h2><p>The website has no account, advertising, analytics, tracking pixels, or contact form. It does not ask for your name, email, or phone number. The planned host is Vercel. Vercel may process visitor and request information such as IP address, location derived from IP address, device and browser details, timestamps, and service logs to provide and secure hosting. See <a href="https://vercel.com/legal/privacy-notice" target="_blank" rel="noopener noreferrer">Vercel's Privacy Notice</a>. Confirm the project's actual logging and retention settings before public launch.</p></section>
        <section><h2>3. The local report page</h2><p>If you choose a Mizani transaction CSV, your browser reads it on your device. The file is not sent to a Mizani server or AI provider. The page reads date, transaction type, amount, currency, fee, and category fields needed for the summaries. Payees, notes, wallet names, mobile-money references, and the original file name are excluded from the displayed report and retained report state.</p><p>The parser holds the file text and parsed cells in temporary browser memory while it validates rows. Accepted rows, derived totals, category labels, and question-and-answer text remain in the current page's memory so the report can work. This information is not written to cookies, local storage, session storage, or a Mizani account. Use <strong>Clear report</strong> or close the tab to clear the page's active references. Your browser, device, extensions, or operating system may retain or expose data outside Mizani's control.</p><p>The app's CSV export is human-readable and unencrypted. The report page does not accept encrypted backups or Excel workbooks. Any report you download or print is a new local file that you control and must protect.</p></section>
        <section><h2>4. Optional on-device AI note</h2><p>Calculations and the question helper always run locally using fixed rules. If you separately opt in and generate an AI note in supported desktop Google Chrome, Mizani provides the installed browser model with the report currency, accepted row count, five summary totals and up to six monthly spending totals with their month labels. The model receives no original file, individual transaction rows, category or wallet names, notes, payees, or questions you type into the report helper.</p><p>Chrome processes the note on your device. Mizani only uses a model that is already ready and does not request a model download, send figures to a cloud service, or ask for credentials. The note is held in the tab and removed when you clear or change the report, withdraw your opt-in, or close the tab. See <a href="https://developer.chrome.com/docs/ai/prompt-api" target="_blank" rel="noopener noreferrer">Chrome’s documentation on its on-device model</a>.</p></section>
        <section><h2>5. Network, cookies and third parties</h2><p>Your browser must load the website code and images from its host. The report page does not make network requests with the selected file or financial values. No third-party fonts, analytics scripts, or embedded social widgets are used. If you follow a link to GitHub or another service, that service receives your request and applies its own privacy terms.</p></section>
        <section><h2>6. Retention and control</h2><p>Mizani does not retain a server copy of the selected CSV or its report. Your downloaded exports remain under your control. Vercel's handling of hosting and request information is described in its Privacy Notice and depends on the project's configured services and log settings. Those settings must be reviewed before public launch. To clear a report, use <strong>Clear report</strong> or close the tab.</p></section>
        <section><h2>7. Your privacy choices</h2><p>You may decline to use the report page, select a different file, or clear the current report at any time. For a request or question about information handled by the website provider, email <a href="mailto:paul.ochieng.dev@gmail.com">paul.ochieng.dev&#64;gmail.com</a>. Do not email financial records unless needed to resolve your request.</p><p>Privacy rights depend on the law that applies where you live. The website provider will review and respond to requests as required by that law.</p></section>
        <section><h2>8. Children</h2><p>The website is not designed to collect information from children. Anyone below the age of legal capacity should use Mizani only with permission from a parent or legal guardian.</p></section>
        <section><h2>9. Changes</h2><p>The version and effective date above identify this notice. Mizani will update it before releasing a change to how the website handles personal data.</p></section>
      </article>
      <div class="legal-back"><a class="text-link" routerLink="/analysis">Return to the report workspace</a></div>
    </main>
    <mizani-site-footer />
  `,
})
export class PrivacyPageComponent {}
