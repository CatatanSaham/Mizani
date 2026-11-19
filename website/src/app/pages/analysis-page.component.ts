import { Component, HostListener, Injector, OnDestroy, afterNextRender, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { LocalAiNoteComponent } from '../components/local-ai-note.component';
import { demoLedgerFile } from '../services/demo-ledger';
import { SiteFooterComponent, SiteHeaderComponent } from '../components/site-shell.component';
import {
  FinanceCsvService,
  ImportedLedger,
} from '../services/finance-csv.service';
import {
  formatMoney,
  LocalReportService,
  LocalSummary,
} from '../services/local-report.service';

interface ChatMessage {
  readonly question: string;
  readonly answer: string;
}

type ReportSource = 'csv' | 'demo';

interface MonthBar {
  readonly month: string;
  readonly amountLabel: string;
  readonly heightPercent: number;
  readonly negative: boolean;
}

@Component({
  selector: 'mizani-analysis-page',
  standalone: true,
  imports: [RouterLink, SiteFooterComponent, SiteHeaderComponent, LocalAiNoteComponent],
  template: `
    <mizani-site-header />
    <main id="main-content" tabindex="-1" class="analysis-page page-width">
      <section class="analysis-intro" aria-labelledby="analysis-title">
        <div>
          <p class="overline"><span class="overline-rule" aria-hidden="true"></span> Mizani CSV analysis</p>
          <h1 id="analysis-title">Report workspace</h1>
          <p class="analysis-lede">Review cash flow, spending categories and changes over time using a transaction export from Mizani.</p>
        </div>
        <aside class="local-seal" aria-label="Report privacy">
          <strong>Processed in this tab</strong>
          <p>Your CSV stays on this device. Clear the report or close the tab to end the session.</p>
        </aside>
      </section>

      <section class="import-panel" aria-labelledby="import-heading">
        <div class="panel-heading">
          <h2 id="import-heading" tabindex="-1">Open a transaction CSV</h2>
          <p>In Mizani’s export settings, choose <strong>Download transactions (CSV)</strong>. The file is readable and unencrypted. Use a device you trust.</p>
        </div>
        <div class="acknowledgements">
          <div class="check-row"><input id="terms-acknowledged" type="checkbox" [checked]="termsAccepted()" (change)="onAcknowledgement('terms', $event)"><label for="terms-acknowledged">I have read and agree to the Website Terms.</label><a routerLink="/terms" target="_blank" rel="noopener" aria-label="Read the Website Terms in a new tab">Read terms</a></div>
          <div class="check-row"><input id="privacy-acknowledged" type="checkbox" [checked]="privacyAccepted()" (change)="onAcknowledgement('privacy', $event)"><label for="privacy-acknowledged">I have read the Website Privacy Notice.</label><a routerLink="/privacy" target="_blank" rel="noopener" aria-label="Read the Website Privacy Notice in a new tab">Read notice</a></div>
          <label class="check-row"><input type="checkbox" [checked]="fileWarningAccepted()" (change)="onAcknowledgement('file', $event)"><span>I understand this export is unencrypted and the report only reflects accepted rows.</span></label>
          <p class="ack-note">Acknowledgements are kept in this tab for this session.</p>
        </div>

        <div class="file-actions">
          <input #csvPicker type="file" accept=".csv,text/csv" hidden [disabled]="!canChooseFile() || loading()" (change)="onFileSelected($event)">
          <button class="button button-dark" type="button" [disabled]="!canChooseFile() || loading()" [attr.aria-describedby]="errorMessage() ? 'file-limits import-error' : 'file-limits'" (click)="openPicker(csvPicker)">
            {{ loading() ? 'Reading records…' : source() === 'csv' ? 'Choose another CSV' : 'Choose transaction CSV' }}
          </button>
          @if (!ledger()) {
            <button class="button button-outline" type="button" [disabled]="loading()" (click)="openDemo()">Try sample report</button>
          }
        </div>
        <p id="file-limits" class="file-limits">Transaction CSV only, up to 10 MB and 50,000 rows. Use the Android app to open a Mizani backup.</p>

        @if (errorMessage()) {
          <p id="import-error" class="import-error" role="alert">{{ errorMessage() }}</p>
        }
        @if (loadMessage()) {
          <p class="import-status" role="status" aria-live="polite">{{ loadMessage() }}</p>
        }
      </section>

      @if (ledger(); as report) {
        <section class="quality-panel" aria-labelledby="quality-heading">
          <div class="panel-heading">
            <h2 id="quality-heading" tabindex="-1">Data quality</h2><p>The report uses rows that pass validation. Check any rejection reasons below.</p>
          </div>
          <div class="quality-counts">
            <div><strong>{{ report.quality.totalRows }}</strong><span>nonblank rows</span></div>
            <div><strong>{{ report.quality.acceptedRows }}</strong><span>accepted</span></div>
            <div><strong>{{ report.quality.rejectedRows }}</strong><span>rejected</span></div>
            <div><strong>{{ report.quality.blankRows }}</strong><span>blank rows skipped</span></div>
          </div>
          @if (qualityReasons().length > 0) {
            <ul class="quality-reasons" aria-label="Reasons rows were rejected">
              @for (reason of qualityReasons(); track reason.name) {
                <li><span>{{ reason.name }}</span><strong>{{ reason.count }}</strong></li>
              }
            </ul>
          }
          @if (report.rows.length === 0) {
            <p class="empty-report">No rows passed validation. Check the reason counts and export your CSV again from Mizani.</p>
            <button class="button button-outline empty-report" type="button" (click)="clearReport()">Clear report</button>
          }
        </section>
      }

      @if (summary(); as totals) {
        <section class="report-workspace" aria-labelledby="report-heading">
          <div class="report-toolbar">
            <h2 id="report-heading" tabindex="-1">{{ source() === 'demo' ? 'Sample transaction report' : 'Transaction report' }}</h2>
            <div class="toolbar-actions">
              @if ((ledger()?.currencies?.length ?? 0) > 1) {
                <label class="currency-picker">Currency
                  <select [value]="selectedCurrency()" (change)="onCurrencyChange($event)" aria-label="Choose currency for this report">
                    @for (currency of ledger()?.currencies ?? []; track currency) { <option [value]="currency">{{ currency }}</option> }
                  </select>
                </label>
              }
              <button class="button button-outline" type="button" (click)="downloadReport(totals)">Download text</button>
              <button class="button button-outline" type="button" (click)="printReport()">Print report</button>
              <button class="button button-outline" type="button" (click)="clearReport()">Clear report</button>
            </div>
          </div>

          @if ((ledger()?.currencies?.length ?? 0) > 1) {
            <p class="currency-note">Currency selection filters the report; it does not convert amounts.</p>
          }

          <p class="report-provenance">{{ dateRangeText(totals) }} · {{ totals.currency }} · {{ totals.acceptedRows }} accepted rows @if (source() === 'demo') { · Fictional records }</p>

          <div class="summary-ledger" aria-label="Financial summary">
            <article class="summary-cell"><span>Recorded income</span><strong>{{ money(totals.incomeMinor, totals) }}</strong><small>Before recorded fees</small></article>
            <article class="summary-cell"><span>Expense amounts</span><strong>{{ money(totals.expenseMinor, totals) }}</strong><small>Before fees and refunds</small></article>
            <article class="summary-cell"><span>Refund amounts</span><strong>{{ money(totals.refundMinor, totals) }}</strong><small>Recorded refunds only</small></article>
            <article class="summary-cell"><span>Eligible fees</span><strong>{{ money(totals.feeMinor, totals) }}</strong><small>Positive fees; adjustments excluded</small></article>
            <article class="summary-cell summary-net"><span>Recorded change</span><strong>{{ money(totals.netChangeMinor, totals) }}</strong><small>Income − expenses − fees + refunds</small></article>
          </div>
          <p class="method-note">Transfers do not count as income or expense; their positive fees do count. Balance adjustments are excluded. These numbers describe accepted entries only.</p>

          <div class="report-grid">
            <section class="report-card-panel category-panel" aria-labelledby="category-heading">
              <div class="subpanel-heading"><div><h3 id="category-heading">Where recorded spending went</h3><p>Expense amounts less refunds, by category. Fees are excluded from this chart.</p></div></div>
              @if (totals.categoryTotals.length > 0) {
                <figure class="category-figure">
                  <ul class="bar-list">
                    @for (category of totals.categoryTotals; track category.name) {
                      <li>
                        <div class="bar-label"><span>{{ category.name }}</span><strong>{{ money(category.amountMinor, totals) }}</strong></div>
                        <div class="bar-track"><span class="bar-fill" [style.width.%]="category.visualPercent"></span></div>
                      </li>
                    }
                  </ul>
                  <figcaption>Up to six categories with the highest positive net spending.</figcaption>
                </figure>
              } @else {
                <p class="empty-report">No positive category totals are available in these accepted rows.</p>
              }
            </section>

            <section class="report-card-panel month-panel" aria-labelledby="month-heading">
              <div class="subpanel-heading"><div><h3 id="month-heading">Monthly spending</h3><p>Up to six months with accepted records. Expenses less refunds, before fees.</p></div></div>
              @if (monthBars().length > 0) {
                <figure class="month-figure">
                  <div class="month-bars" aria-hidden="true">
                    @for (bar of monthBars(); track bar.month) {
                      <div class="month-column">
                        <div class="month-track month-positive"><span class="month-fill" [style.height.%]="bar.negative ? 0 : bar.heightPercent"></span></div>
                        @if (hasNegativeMonth()) {
                          <div class="month-track month-negative"><span class="month-fill" [style.height.%]="bar.negative ? bar.heightPercent : 0"></span></div>
                        }
                        <span class="month-label">{{ formatMonth(bar.month) }}</span>
                      </div>
                    }
                  </div>
                  <ul class="month-text-alternative">
                    @for (bar of monthBars(); track bar.month) { <li><span>{{ formatMonth(bar.month) }}</span><strong>{{ bar.amountLabel }}</strong></li> }
                  </ul>
                  @if (hasNegativeMonth()) {
                    <figcaption>A bar below the baseline means recorded refunds exceeded expenses that month.</figcaption>
                  }
                </figure>
              } @else {
                <p class="empty-report">No month history is available yet.</p>
              }
            </section>

            <section class="report-card-panel largest-panel" aria-labelledby="largest-heading">
              <div class="subpanel-heading"><div><h3 id="largest-heading">Largest expense amount</h3><p>The largest single expense before fees.</p></div></div>
              @if (totals.largestExpense; as largest) {
                <div class="largest-expense"><strong>{{ money(largest.amountMinor, totals) }}</strong><span>{{ largest.category }}</span><small>{{ largest.date }}</small></div>
              } @else {
                <p class="empty-report">No expense rows were accepted for this currency.</p>
              }
            </section>

            <section class="report-card-panel assistant-panel" aria-labelledby="assistant-heading">
              <div class="subpanel-heading"><div><h3 id="assistant-heading">Ask this report</h3><p>Get rule-based answers about the figures in this report.</p></div></div>
              <div class="question-chips" aria-label="Suggested questions">
                <button type="button" (click)="askPreset('What was my recorded income?')">Recorded income</button>
                <button type="button" (click)="askPreset('Where did I spend most?')">Largest category</button>
                <button type="button" (click)="askPreset('How much did I pay in fees?')">Fees</button>
                <button type="button" (click)="askPreset('Compare the last two recorded months')">Compare months</button>
              </div>
              <ol class="chat-list" aria-live="polite" aria-relevant="additions text" aria-label="Local report answers">
                @for (message of messages(); track $index) {
                  <li><p class="chat-question">{{ message.question }}</p><p class="chat-answer">{{ message.answer }}</p></li>
                }
              </ol>
              <form class="question-form" (submit)="submitQuestion($event)">
                <label class="sr-only" for="report-question">Ask about this report</label>
                <input id="report-question" type="text" maxlength="200" autocomplete="off" [value]="question()" (input)="onQuestionInput($event)" placeholder="Ask about this report">
                <button type="submit" class="button button-dark" [disabled]="!question().trim()">Ask</button>
              </form>
              <p class="assistant-footnote">Typed questions stay in this tab.</p>
            </section>
          </div>
          <mizani-local-ai-note [summary]="totals" />
          <p class="report-disclaimer">The report is for record-keeping. Check the figures against your own records before making decisions.</p>
        </section>
      }
    </main>
    <mizani-site-footer />
  `,
})
export class AnalysisPageComponent implements OnDestroy {
  private readonly injector = inject(Injector);
  private loadSequence = 0;
  readonly termsAccepted = signal(false);
  readonly privacyAccepted = signal(false);
  readonly fileWarningAccepted = signal(false);
  readonly loading = signal(false);
  readonly errorMessage = signal('');
  readonly loadMessage = signal('');
  readonly ledger = signal<ImportedLedger | null>(null);
  readonly source = signal<ReportSource | null>(null);
  readonly selectedCurrency = signal('');
  readonly question = signal('');
  readonly messages = signal<readonly ChatMessage[]>([]);

  readonly canChooseFile = computed(() =>
    this.termsAccepted() && this.privacyAccepted() && this.fileWarningAccepted(),
  );
  readonly summary = computed(() => {
    const currentLedger = this.ledger();
    const currency = this.selectedCurrency();
    if (!currentLedger || !currency || currentLedger.rows.length === 0) return null;
    return this.reportService.summarize(currentLedger, currency);
  });
  readonly qualityReasons = computed(() => {
    const quality = this.ledger()?.quality;
    return quality ? Object.entries(quality.rejectionReasons).map(([name, count]) => ({ name, count })) : [];
  });
  readonly monthBars = computed<readonly MonthBar[]>(() => {
    const current = this.summary();
    if (!current) return [];
    const values = current.monthlyTotals.map((item) => item.expenseMinor - item.refundMinor);
    const magnitude = (value: bigint): bigint => value < 0n ? -value : value;
    const max = values.reduce((largest, value) => magnitude(value) > largest ? magnitude(value) : largest, 0n);
    return current.monthlyTotals.map((item, index) => ({
      month: item.month,
      amountLabel: this.money(values[index], current),
      heightPercent: max === 0n ? 0 : Number((magnitude(values[index]) * 10_000n) / max) / 100,
      negative: values[index] < 0n,
    }));
  });
  readonly hasNegativeMonth = computed(() => this.monthBars().some((bar) => bar.negative));

  constructor(
    private readonly csvService: FinanceCsvService,
    private readonly reportService: LocalReportService,
  ) {}

  onAcknowledgement(kind: 'terms' | 'privacy' | 'file', event: Event): void {
    const checked = (event.target as HTMLInputElement).checked;
    if (kind === 'terms') this.termsAccepted.set(checked);
    if (kind === 'privacy') this.privacyAccepted.set(checked);
    if (kind === 'file') this.fileWarningAccepted.set(checked);
  }

  openPicker(input: HTMLInputElement): void {
    if (this.canChooseFile() && !this.loading()) input.click();
  }

  onFileSelected(event: Event): void {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.item(0);
    input.value = '';
    if (file && this.canChooseFile() && !this.loading()) {
      void this.loadFile(file, 'csv');
    }
  }

  openDemo(): void {
    if (!this.ledger() && !this.loading()) {
      void this.loadFile(demoLedgerFile(), 'demo');
    }
  }

  private async loadFile(file: File, source: ReportSource): Promise<void> {
    const sequence = ++this.loadSequence;
    this.errorMessage.set('');
    this.loadMessage.set('Reading transaction records in this tab.');
    this.loading.set(true);
    try {
      const candidate = await this.csvService.readFile(file);
      if (sequence !== this.loadSequence) return;
      this.ledger.set(candidate);
      this.source.set(source);
      this.selectedCurrency.set(candidate.currencies[0] ?? '');
      this.messages.set([]);
      this.question.set('');
      this.loadMessage.set(source === 'demo'
        ? 'Sample report ready. It uses fictional records.'
        : `${candidate.quality.acceptedRows} rows accepted. ${candidate.quality.rejectedRows} rows rejected.`);
      afterNextRender({
        write: () => {
          if (sequence !== this.loadSequence || document.activeElement !== document.body) return;
          document.getElementById(source === 'demo' ? 'report-heading' : 'quality-heading')?.focus();
        },
      }, { injector: this.injector });
    } catch (error: unknown) {
      if (sequence !== this.loadSequence) return;
      this.errorMessage.set(error instanceof Error ? error.message : 'The file could not be read.');
      this.loadMessage.set(this.ledger() ? 'Your previous report remains open.' : '');
    } finally {
      if (sequence === this.loadSequence) this.loading.set(false);
    }
  }

  onCurrencyChange(event: Event): void {
    const value = (event.target as HTMLSelectElement).value;
    if (this.ledger()?.currencies.includes(value)) {
      this.selectedCurrency.set(value);
      this.messages.set([]);
      this.question.set('');
    }
  }

  onQuestionInput(event: Event): void {
    this.question.set((event.target as HTMLInputElement).value);
  }

  submitQuestion(event: Event): void {
    event.preventDefault();
    this.askPreset(this.question().trim());
  }

  askPreset(text: string): void {
    const current = this.summary();
    if (!text || !current) return;
    this.messages.update((items) => [
      ...items,
      { question: text, answer: this.reportService.answer(text, current) },
    ].slice(-8));
    this.question.set('');
  }

  money(amount: bigint, summary: LocalSummary): string {
    return formatMoney(amount, summary.currency, summary.fractionDigits);
  }

  formatMonth(month: string): string {
    const date = new Date(`${month}-01T00:00:00Z`);
    return new Intl.DateTimeFormat(undefined, { month: 'short', year: '2-digit', timeZone: 'UTC' }).format(date);
  }

  dateRangeText(summary: LocalSummary): string {
    if (!summary.firstDate || !summary.lastDate) return 'No accepted date range';
    if (summary.firstDate === summary.lastDate) return summary.firstDate;
    return `${summary.firstDate} to ${summary.lastDate}`;
  }

  downloadReport(summary: LocalSummary): void {
    const current = this.ledger();
    if (!current) return;
    const content = this.reportService.buildTextReport(current, summary, new Date(), this.source() === 'demo');
    const reportFile = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(reportFile);
    const link = document.createElement('a');
    link.href = url;
    link.download = this.source() === 'demo' ? 'mizani-sample-report.txt' : 'mizani-local-report.txt';
    link.rel = 'noopener';
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  printReport(): void {
    window.print();
  }

  clearReport(): void {
    this.resetReport();
    this.loadMessage.set('The report has been cleared from this tab.');
    document.getElementById('import-heading')?.focus();
  }

  @HostListener('window:pagehide')
  resetReport(): void {
    this.loadSequence += 1;
    this.loading.set(false);
    this.ledger.set(null);
    this.source.set(null);
    this.selectedCurrency.set('');
    this.messages.set([]);
    this.question.set('');
    this.errorMessage.set('');
    this.loadMessage.set('');
  }

  ngOnDestroy(): void {
    this.resetReport();
  }
}
