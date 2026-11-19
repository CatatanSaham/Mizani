import { Component, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { MIZANI_PLAY_STORE_URL, SiteFooterComponent, SiteHeaderComponent } from '../components/site-shell.component';

const appViews = [
  {
    name: 'Record',
    title: 'Save it while it’s fresh.',
    description: 'Log income or spending, move money between wallets, or share a supported mobile-money confirmation into Mizani. You review and edit the suggested entry before saving.',
    image: 'record',
    alt: 'Mizani’s Add expense screen with amount, wallet and category controls.',
  },
  {
    name: 'See wallets',
    title: 'See what’s across your wallets.',
    description: 'Keep separate records for cash, mobile money and bank accounts. Check wallet balances after confirming with your app PIN or enabled biometrics.',
    image: 'wallets',
    alt: 'Mizani’s Wallets screen showing cash, mobile money and savings.',
  },
  {
    name: 'Find patterns',
    title: 'Understand where it went.',
    description: 'Review spending by category and see how cash flow changes. Money Outlook helps you plan around recent spending and commitments you’ve recorded.',
    image: 'insights',
    alt: 'Mizani’s Insights screen with a spending-by-category chart and cash-flow summary.',
  },
] as const;

@Component({
  selector: 'mizani-home-redesign-page',
  standalone: true,
  imports: [RouterLink, SiteHeaderComponent, SiteFooterComponent],
  template: `
    <mizani-site-header />
    <main id="main-content" tabindex="-1" class="home-page">
      <section class="home-hero" aria-labelledby="hero-title">
        <div class="hero-layout page-width">
          <div class="hero-text">
            <p class="overline"><span class="overline-rule" aria-hidden="true"></span> Offline money tracking for Android</p>
            <h1 id="hero-title">Your money.<br><em>Yours to keep.</em></h1>
            <p class="hero-description">Track cash, mobile money and bank activity in one private ledger. Mizani works offline and keeps your records on your phone.</p>
            <div class="hero-actions">
              <a class="play-store-badge" [href]="playStoreUrl">
                <img src="/assets/google-play-badge.png" width="646" height="250" alt="Get it on Google Play" decoding="async">
              </a>
              <a class="hero-text-link" routerLink="/" fragment="the-app">Explore the app</a>
            </div>
          </div>

          <figure class="hero-art">
            <picture>
              <source media="(max-width: 45rem)" srcset="/assets/product/hero-wide-800.webp 800w, /assets/product/hero-wide-1200.webp 1200w" sizes="calc(100vw - 2rem)" type="image/webp">
              <source srcset="/assets/product/hero-portrait-960.webp 960w, /assets/product/hero-portrait-1200.webp 1200w" sizes="(max-width: 77rem) 44vw, 38rem" type="image/webp">
              <img class="hero-human" src="/assets/product/hero-portrait-1200.jpg" width="1200" height="1500" alt="A woman in Lagos smiling as she checks her phone." fetchpriority="high" decoding="async">
            </picture>
          </figure>
        </div>
      </section>

      <div class="section-stack">
      <section id="the-app" tabindex="-1" class="app-section stacked-panel" aria-labelledby="app-title">
        <div class="app-section-inner page-width">
        <span id="how-it-works" class="section-anchor" aria-hidden="true"></span>
        <header class="split-heading">
          <h2 id="app-title">A place for every<br class="desktop-break"> way you pay.</h2>
          <p>See what you have across wallets, then find the entries that explain a balance. Mizani keeps transfers, refunds and adjustments with the rest of your activity.</p>
        </header>

        <div class="app-explorer">
          <div class="explorer-controls">
            <fieldset class="app-view-options">
              <legend>Explore the Android app</legend>
              @for (view of appViews; track view.image) {
                <label class="app-view-option" [class.active-view]="view.image === selectedView().image">
                  <input type="radio" name="app-view" [checked]="view.image === selectedView().image" (change)="selectedView.set(view)">
                  <span>{{ view.name }}</span>
                </label>
              }
            </fieldset>
            <div class="app-view-copy" aria-live="polite">
              <h3>{{ selectedView().title }}</h3>
              <p>{{ selectedView().description }}</p>
            </div>
          </div>
          <figure class="app-preview" [attr.data-view]="selectedView().image">
            @for (view of [selectedView()]; track view.image) {
              <img class="preview-device" [src]="'/assets/product/' + view.image + '-600.webp'" [attr.data-jpeg-fallback]="'/assets/product/' + view.image + '-600.jpg'" (error)="useJpegFallback($event)" width="600" height="1295" loading="lazy" decoding="async" [alt]="view.alt">
            }
          </figure>
        </div>
        </div>
      </section>

      <section id="offline-first" tabindex="-1" class="offline-story stacked-panel" aria-labelledby="offline-title">
        <div class="offline-spread page-width">
          <div class="offline-copy">
            <p class="overline"><span class="overline-rule" aria-hidden="true"></span> Offline by design</p>
            <h2 id="offline-title">No signal?<br><em>Keep going.</em></h2>
            <p>Record a payment, check your wallets or review spending even when you’re offline. Your ledger lives in an encrypted database on your Android phone. There’s no account to set up or cloud sync to wait for.</p>
            <details class="offline-detail">
              <summary>When does Mizani need internet?</summary>
              <p>Internet is used for optional currency-rate lookups and app update checks. Rate lookups send the two currency codes. The app keeps transaction amounts, names and notes on your device.</p>
            </details>
          </div>
          <figure class="offline-photo">
            <picture>
              <source srcset="/assets/product/offline-journal-640.webp 640w, /assets/product/offline-journal-960.webp 960w" sizes="(max-width: 720px) 100vw, 44vw" type="image/webp">
              <img src="/assets/product/offline-journal-960.jpg" alt="A woman writes in a notebook while holding her phone." width="960" height="1120" loading="lazy" decoding="async">
            </picture>
          </figure>
        </div>
      </section>

      <section id="analysis" class="report-story stacked-panel" aria-labelledby="report-story-title">
        <div class="report-story-inner page-width">
        <div class="report-story-copy">
          <p class="overline"><span class="overline-rule" aria-hidden="true"></span> Browser report</p>
          <h2 id="report-story-title">A bigger picture<br>on a bigger screen.</h2>
          <p>Open a transaction CSV from Mizani to compare spending, check fees and ask questions about your report. The browser calculates the results in this tab after the page loads. Your file stays on your device.</p>
          <a class="button button-dark" routerLink="/analysis">Open the report workspace</a>
        </div>
        <figure class="report-specimen" aria-label="Sample Mizani report. Category spending shows food at 360,000 Ugandan shillings, transport at 215,000, and utilities at 150,000.">
          <div aria-hidden="true">
            <div class="specimen-header"><span>Spending by category</span><span>UGX</span></div>
            <div class="specimen-row"><span>Food</span><strong>360,000</strong><i style="--value: 100%"></i></div>
            <div class="specimen-row"><span>Transport</span><strong>215,000</strong><i style="--value: 60%"></i></div>
            <div class="specimen-row"><span>Utilities</span><strong>150,000</strong><i style="--value: 42%"></i></div>
          </div>
        </figure>
        </div>
      </section>
      </div>

      <section id="faq" class="faq-section" aria-labelledby="faq-title">
        <div class="faq-layout page-width">
          <div class="faq-intro">
            <p class="overline"><span class="overline-rule" aria-hidden="true"></span> Questions, answered</p>
            <h2 id="faq-title">Before you<br><em>begin.</em></h2>
            <p>A few useful answers about offline use, privacy and moving your records.</p>
            <a class="text-link" [href]="playStoreUrl">Find Mizani on Google Play</a>
          </div>
          <div class="faq-list">
            <details class="faq-item">
              <summary>What is Mizani?</summary>
              <p>Mizani is an Android money tracker for recording cash, mobile money and bank activity in one place. Add entries yourself, organize them by wallet and see a clearer picture of where your money goes.</p>
            </details>
            <details class="faq-item">
              <summary>Can I use Mizani without internet?</summary>
              <p>Yes. Your everyday records and saved summaries are available offline. Internet is only needed for optional currency-rate lookups and app update checks.</p>
            </details>
            <details class="faq-item">
              <summary>Where are my financial records stored?</summary>
              <p>Your ledger is encrypted and kept on your phone. Mizani has no account or cloud sync. You stay in control of your records and any backups you choose to make.</p>
            </details>
            <details class="faq-item">
              <summary>What should I do when I get a new phone?</summary>
              <p>Before changing phones, create an encrypted backup in Mizani and keep its passphrase safe. Restore it on your new Android phone, then check your records before erasing the old one. Transfer is manual; without the backup and passphrase, Mizani cannot recover lost records.</p>
            </details>
            <details class="faq-item">
              <summary>Does Mizani connect to banks or read my messages?</summary>
              <p>No. You choose what to record. You can also share a supported payment confirmation into Mizani, review it and decide whether to save it. The app does not read messages in the background.</p>
            </details>
            <details class="faq-item">
              <summary>Can I use Mizani on an iPhone?</summary>
              <p>Mizani is currently available on Android through Google Play. The iOS version is still an early preview and is not ready for financial use.</p>
            </details>
            <details class="faq-item">
              <summary>Can I review my records on a computer?</summary>
              <p>Yes. Open a Mizani transaction CSV in the website’s report workspace to review summaries in your browser. The file stays in that tab; downloaded CSVs and reports are readable files, so store them carefully.</p>
            </details>
            <details class="faq-item">
              <summary>Is Mizani financial advice?</summary>
              <p>No. Mizani helps you keep track of your own records. Its summaries are for information and are not financial, investment, legal, accounting or tax advice.</p>
            </details>
          </div>
        </div>
      </section>
    </main>
    <mizani-site-footer />
  `,
})
export class HomeRedesignPageComponent {
  readonly playStoreUrl = MIZANI_PLAY_STORE_URL;
  readonly appViews = appViews;
  readonly selectedView = signal<(typeof appViews)[number]>(appViews[0]);

  useJpegFallback(event: Event): void {
    const image = event.currentTarget as HTMLImageElement;
    const fallback = image.dataset['jpegFallback'];
    if (fallback && image.src !== new URL(fallback, document.baseURI).href) {
      image.src = fallback;
    }
  }
}
