import { Component, OnDestroy, effect, input, signal } from '@angular/core';
import { formatMoney, LocalSummary } from '../services/local-report.service';

interface PromptInput {
  readonly type: 'text';
  readonly languages: readonly ['en'];
}

interface PromptOutput {
  readonly type: 'text';
  readonly languages: readonly ['en'];
}

interface LocalModelSession {
  prompt(text: string, options: { readonly signal: AbortSignal }): Promise<string>;
  destroy(): void;
}

interface LocalModelApi {
  availability(options: {
    readonly expectedInputs: readonly PromptInput[];
    readonly expectedOutputs: readonly PromptOutput[];
  }): Promise<string>;
  create(options: {
    readonly signal: AbortSignal;
    readonly expectedInputs: readonly PromptInput[];
    readonly expectedOutputs: readonly PromptOutput[];
  }): Promise<LocalModelSession>;
}

interface UserAgentData {
  readonly brands: readonly { readonly brand: string }[];
  readonly mobile: boolean;
  readonly platform: string;
}

@Component({
  selector: 'mizani-local-ai-note',
  standalone: true,
  template: `
    <section class="ai-panel" aria-labelledby="local-ai-heading">
      <div class="subpanel-heading">
        <div>
          <h3 id="local-ai-heading">Optional on-device note</h3>
          <p>For a brief description of this summary, a ready model in desktop Chrome can process its totals, currency, row count and up to six recent months. It does not receive individual records, category names, the CSV file or your report questions.</p>
        </div>
      </div>

      @if (modelApi) {
        <div class="ai-consent check-row">
          <input id="local-ai-consent" type="checkbox" [checked]="consented()" (change)="onConsentChange($event)">
          <label for="local-ai-consent">I agree to use these summary figures with Chrome’s on-device model.</label>
        </div>

        <div class="ai-actions">
          <button class="button button-dark" type="button" [disabled]="!consented() || working()" (click)="generate()">
            {{ working() ? 'Writing the note…' : 'Generate local note' }}
          </button>
          @if (working()) {
            <button class="button button-outline" type="button" (click)="cancel()">Cancel</button>
          }
        </div>
      } @else {
        <p>On-device AI is unavailable in this browser. You can still use the questions and calculated report above.</p>
      }

      @if (message()) {
        <p class="ai-message" role="status" aria-live="polite">{{ message() }}</p>
      }
      @if (error()) {
        <p class="ai-message ai-error" role="alert">{{ error() }}</p>
      }
      @if (note()) {
        <p class="ai-result" aria-live="polite" aria-label="On-device AI note">{{ note() }}</p>
        <p class="ai-disclaimer">AI generated. Check this description against the report. It is not financial advice.</p>
      }
    </section>
  `,
})
export class LocalAiNoteComponent implements OnDestroy {
  protected readonly modelApi = getDesktopChromeModel();
  readonly summary = input.required<LocalSummary>();
  readonly consented = signal(false);
  readonly working = signal(false);
  readonly message = signal('');
  readonly error = signal('');
  readonly note = signal('');

  private runId = 0;
  private activeController: AbortController | undefined;
  private activeSession: LocalModelSession | undefined;

  constructor() {
    effect(() => {
      this.summary();
      this.resetForSummaryChange();
    });
  }

  onConsentChange(event: Event): void {
    const accepted = (event.target as HTMLInputElement).checked;
    this.consented.set(accepted);
    this.note.set('');
    this.error.set('');

    if (!accepted) {
      this.cancel();
    }
  }

  async generate(): Promise<void> {
    if (!this.modelApi || !this.consented() || this.working()) return;

    const summary = this.summary();
    const controller = new AbortController();
    const runId = ++this.runId;
    this.activeController = controller;
    this.working.set(true);
    this.message.set('Checking whether the on-device model is ready. No model download will be started.');
    this.error.set('');
    this.note.set('');

    try {
      const readiness = await this.modelApi.availability(MODEL_CAPABILITIES);
      if (!this.isCurrentRun(runId, summary, controller)) return;

      if (readiness !== 'available') {
        this.message.set('Chrome’s on-device model is not ready on this device. No download or provider request was made.');
        return;
      }

      this.message.set('Writing a note with Chrome’s on-device model.');
      const session = await this.modelApi.create({
        ...MODEL_CAPABILITIES,
        signal: controller.signal,
      });
      if (!this.isCurrentRun(runId, summary, controller)) {
        session.destroy();
        return;
      }

      this.activeSession = session;
      const response = await session.prompt(buildPrompt(summary), {
        signal: controller.signal,
      });
      if (!this.isCurrentRun(runId, summary, controller)) return;

      const safeNote = response.trim().slice(0, MAX_NOTE_LENGTH);
      if (!safeNote) {
        this.message.set('');
        this.error.set('Chrome did not return a note. Your report is still available.');
      } else {
        this.note.set(safeNote);
        this.message.set('The note was generated on this device and will disappear when this report changes or the page closes.');
      }
    } catch {
      if (this.isCurrentRun(runId, summary, controller)) {
        this.message.set('');
        this.error.set('The on-device model could not write a note. Your local report is still available.');
      }
    } finally {
      if (this.runId === runId) {
        this.activeSession?.destroy();
        this.activeSession = undefined;
        this.activeController = undefined;
        this.working.set(false);
      }
    }
  }

  cancel(): void {
    this.runId += 1;
    this.activeController?.abort();
    this.activeController = undefined;
    this.activeSession?.destroy();
    this.activeSession = undefined;
    this.working.set(false);
    this.message.set('On-device note stopped.');
  }

  ngOnDestroy(): void {
    this.cancel();
  }

  private isCurrentRun(
    runId: number,
    summary: LocalSummary,
    controller: AbortController,
  ): boolean {
    return this.runId === runId && !controller.signal.aborted && this.summary() === summary;
  }

  private resetForSummaryChange(): void {
    this.cancel();
    this.consented.set(false);
    this.note.set('');
    this.error.set('');
    this.message.set('');
  }
}

const MODEL_CAPABILITIES = {
  expectedInputs: [{ type: 'text', languages: ['en'] }] as const,
  expectedOutputs: [{ type: 'text', languages: ['en'] }] as const,
};

const MAX_NOTE_LENGTH = 1_000;

function getDesktopChromeModel(): LocalModelApi | undefined {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') return undefined;

  const userAgentData = (navigator as Navigator & { userAgentData?: UserAgentData }).userAgentData;
  const isDesktopChrome = Boolean(
    userAgentData
    && userAgentData.brands.some(({ brand }) => brand === 'Google Chrome')
    && !userAgentData.mobile
    && ['Windows', 'macOS', 'Linux', 'Chrome OS'].includes(userAgentData.platform),
  );
  if (!isDesktopChrome) return undefined;

  const api = (window as Window & { LanguageModel?: LocalModelApi }).LanguageModel;
  return api && typeof api.availability === 'function' && typeof api.create === 'function'
    ? api
    : undefined;
}

function buildPrompt(summary: LocalSummary): string {
  const recentMonths = summary.monthlyTotals.slice(-6).map((month) =>
    `${month.month}: ${formatMoney(month.expenseMinor - month.refundMinor, summary.currency, summary.fractionDigits)}`,
  );

  return [
    'Write one brief, neutral observation of the provided Mizani summary.',
    'Use only the supplied figures. Never give advice, invent causes, make predictions, or imply this is complete financial history.',
    'Month values represent recorded expenses less recorded refunds. Fees, transfer amounts, balance adjustments, category names and payee details are not included in the monthly values.',
    'State that the description covers accepted rows only. Use plain language and no more than two sentences.',
    '',
    `Currency: ${summary.currency}`,
    `Accepted rows: ${summary.acceptedRows}`,
    `Recorded income before fees: ${formatMoney(summary.incomeMinor, summary.currency, summary.fractionDigits)}`,
    `Recorded expense amounts before fees and refunds: ${formatMoney(summary.expenseMinor, summary.currency, summary.fractionDigits)}`,
    `Recorded refunds: ${formatMoney(summary.refundMinor, summary.currency, summary.fractionDigits)}`,
    `Eligible recorded fees: ${formatMoney(summary.feeMinor, summary.currency, summary.fractionDigits)}`,
    `Recorded change: ${formatMoney(summary.netChangeMinor, summary.currency, summary.fractionDigits)}`,
    'Recent monthly recorded expenses less refunds:',
    ...(recentMonths.length > 0 ? recentMonths : ['No monthly figures are available.']),
  ].join('\n');
}
