# Mizani website

This folder contains a standalone Angular website for the Mizani Android app and a browser-local
report page. It is not part of the Android Gradle build and has no server or account system.

## Requirements

- Node.js 24.15.0+ (the website package targets Node 24.x, Vercel's current default).
- Angular 22 also supports Node 22.22.3+ and 26.0.0+ for local use.
- npm 11 or newer is recommended.

The app uses Angular 22 standalone components, strict TypeScript and Angular's default zone-based
change detection. It does not use a component library, remote fonts, analytics, or third-party
scripts.

The homepage uses WebP crops of four supplied Android demo screens and two photographer-sourced
Pexels photos. The hero uses separate portrait and mobile crops, and its image is prioritized for
the initial render. Optimized files and JPEG fallbacks are in `public/assets/product/`. The
screenshots contain fictional records. See the [asset credits](../docs/ASSET_CREDITS.md) for
provenance.

## Install and run locally

```powershell
cd website
npm install
npm run start
```

Open the local URL printed by Angular CLI, normally `http://localhost:4200`. Angular Router uses
ordinary paths for `/`, `/analysis`, `/terms`, and `/privacy`; the hosting platform must serve the
Angular app shell for those client-side routes.

## Build and host

```powershell
npm run build
```

The static application is emitted under `dist/mizani-website/browser`. Vercel uses the build,
output directory, SPA rewrite, and response security headers in `vercel.json`. The Content Security
Policy intentionally keeps `connect-src 'none'`: the site makes no application network requests.
Angular inserts runtime style elements, so `style-src 'unsafe-inline'` is required; scripts remain
same-origin. Do not add a CDN, provider endpoint, analytics script, or external font without a
security and privacy review.

The build also writes route-specific HTML shells for `/analysis`, `/terms`, and `/privacy`, so a
direct link has a useful title and description before Angular starts. The report route is marked
`noindex` in its HTML and response headers. The landing-page share card uses a public, source-
controlled image URL while the production website hostname is undecided. Once that hostname is
chosen, add matching canonical URLs, `og:url`, and a sitemap before launch.

## Deploy on Vercel

Import this repository as a Vercel project and set **Root Directory** to `website`. Vercel reads
`website/vercel.json` from that project root. The file specifies Angular, `npm run build`,
`dist/mizani-website/browser`, route rewrites for Angular Router, and security response headers.
`package.json` selects Node 24.x, which Vercel currently uses by default. Leave dependency
installation on Vercel's automatic npm detection. There is no environment variable or secret to
configure.

Before assigning the production domain, deploy a Preview and confirm:

- Direct visits and reloads work at `/`, `/analysis`, `/terms`, and `/privacy`.
- `/analysis` returns `X-Robots-Tag: noindex, nofollow`.
- The pages return the configured Content Security Policy and HSTS headers, and the browser reports
  no blocked application resources.
- The report still works without network calls after the page is loaded.
- The Android download link resolves to the intended public or testing listing in the target markets.

Vercel previews and deployments can be rolled back by promoting a previous successful deployment in
the Vercel dashboard. No production deployment has been configured or performed from this repository.

## Local report data boundary

The workspace can open a fictional sample report without a user file. To analyze personal records,
it accepts only the transaction CSV exported from Mizani. It does not accept Excel
workbooks or encrypted backups. The CSV is human-readable and unencrypted. Before selecting one, a
visitor must acknowledge the Website Terms and Privacy Notice and the unencrypted-file notice.

The selected CSV is decoded and parsed in the current browser tab. The parser enforces a 10 MB file
limit, a 50,000-row limit, maximum cell lengths, the Mizani header names, valid ISO dates, supported
transaction types, ISO currency codes, and exact decimal precision. Money remains `bigint` minor
units. Invalid rows are reported by reason, not silently included. Only date, type, amount, currency,
fee, and category values are retained in the report state; payees, notes, wallet names, provider
references, exchange details and the original file name are excluded from the displayed report.

The original file text and cells exist temporarily in browser memory while parsing. Accepted
records, totals, categories, and local question-and-answer text stay in page memory until the report
is cleared, the page is closed, or navigation unloads it. The page does not use cookies,
`localStorage`, `sessionStorage`, or a backend. Downloading a text report or printing creates a
user-controlled, unencrypted copy.

The report Q&A uses fixed local rules on every supported browser. A separate optional note uses
[Chrome's built-in Prompt API](https://developer.chrome.com/docs/ai/prompt-api) on supported desktop
Chrome if the model already reports that it is ready. The user opts in for the current report and
then explicitly generates the note. The model receives only the currency, accepted row count, five
summary totals and up to six monthly net expense totals with month labels. It receives no CSV rows,
category labels or report questions. The note remains in page memory and is removed when the user
withdraws consent, clears the report, changes currency or leaves the page. The site does not start
a model download or offer external provider connections, subscriptions, or API-key entry.

## Legal pages

- [Website Terms](src/app/pages/terms-page.component.ts) are available at `/terms`.
- [Website Privacy Notice](src/app/pages/privacy-page.component.ts) is available at `/privacy`.

These website notices are separate from the Android app's in-app legal documents. The planned host is
Vercel; review its privacy notice, project logging settings, and applicable legal requirements before
public launch or any change to data flows.
