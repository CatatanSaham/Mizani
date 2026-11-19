import { Injectable } from '@angular/core';
import { ImportedLedger, LedgerRow } from './finance-csv.service';

export interface CategoryTotal {
  readonly name: string;
  readonly amountMinor: bigint;
  readonly visualPercent: number;
}

export interface MonthTotal {
  readonly month: string;
  readonly incomeMinor: bigint;
  readonly expenseMinor: bigint;
  readonly refundMinor: bigint;
  readonly feeMinor: bigint;
  readonly transactionCount: number;
}

export interface LocalSummary {
  readonly currency: string;
  readonly fractionDigits: number;
  readonly incomeMinor: bigint;
  readonly expenseMinor: bigint;
  readonly refundMinor: bigint;
  readonly feeMinor: bigint;
  readonly netChangeMinor: bigint;
  readonly categoryTotals: readonly CategoryTotal[];
  readonly monthlyTotals: readonly MonthTotal[];
  readonly largestExpense: LedgerRow | null;
  readonly acceptedRows: number;
  readonly rejectedRows: number;
  readonly firstDate: string | null;
  readonly lastDate: string | null;
}

@Injectable({ providedIn: 'root' })
export class LocalReportService {
  summarize(ledger: ImportedLedger, currency: string): LocalSummary {
    const rows = ledger.rows.filter((row) => row.currency === currency);
    const fractionDigits = getCurrencyFractionDigits(currency);
    const incomeMinor = sum(rows.filter((row) => row.type === 'INCOME').map((row) => row.amountMinor));
    const expenseMinor = sum(rows.filter((row) => row.type === 'EXPENSE').map((row) => row.amountMinor));
    const refundMinor = sum(rows.filter((row) => row.type === 'REFUND').map((row) => row.amountMinor));
    const feeEligibleRows = rows.filter((row) => row.type !== 'ADJUSTMENT');
    const feeMinor = sum(feeEligibleRows.map((row) => row.feeMinor));
    const netChangeMinor = incomeMinor - expenseMinor - feeMinor + refundMinor;

    const categoryMap = new Map<string, bigint>();
    for (const row of rows) {
      if (row.type === 'EXPENSE') {
        categoryMap.set(row.category, (categoryMap.get(row.category) ?? 0n) + row.amountMinor);
      } else if (row.type === 'REFUND') {
        categoryMap.set(row.category, (categoryMap.get(row.category) ?? 0n) - row.amountMinor);
      }
    }
    const positiveCategoryTotals = [...categoryMap.entries()]
      .filter(([, amount]) => amount > 0n)
      .sort((left, right) => compareBigInt(right[1], left[1]));
    const largestCategory = positiveCategoryTotals[0]?.[1] ?? 0n;
    const categoryTotals = positiveCategoryTotals.slice(0, 6).map(([name, amountMinor]) => ({
      name,
      amountMinor,
      visualPercent: largestCategory === 0n
        ? 0
        : Number((amountMinor * 10_000n) / largestCategory) / 100,
    }));

    const monthMap = new Map<string, MonthTotal>();
    for (const row of rows) {
      const current = monthMap.get(row.month) ?? {
        month: row.month,
        incomeMinor: 0n,
        expenseMinor: 0n,
        refundMinor: 0n,
        feeMinor: 0n,
        transactionCount: 0,
      };
      monthMap.set(row.month, {
        month: row.month,
        incomeMinor: current.incomeMinor + (row.type === 'INCOME' ? row.amountMinor : 0n),
        expenseMinor: current.expenseMinor + (row.type === 'EXPENSE' ? row.amountMinor : 0n),
        refundMinor: current.refundMinor + (row.type === 'REFUND' ? row.amountMinor : 0n),
        feeMinor: current.feeMinor + (row.type === 'ADJUSTMENT' ? 0n : row.feeMinor),
        transactionCount: current.transactionCount + 1,
      });
    }
    const monthlyTotals = [...monthMap.values()].sort((a, b) => a.month.localeCompare(b.month)).slice(-6);
    const largestExpense = rows
      .filter((row) => row.type === 'EXPENSE')
      .reduce<LedgerRow | null>((largest, row) => {
        if (largest === null || row.amountMinor > largest.amountMinor) return row;
        return largest;
      }, null);
    const dates = rows.map((row) => row.date).sort();

    return {
      currency,
      fractionDigits,
      incomeMinor,
      expenseMinor,
      refundMinor,
      feeMinor,
      netChangeMinor,
      categoryTotals,
      monthlyTotals,
      largestExpense,
      acceptedRows: rows.length,
      rejectedRows: ledger.quality.rejectedRows,
      firstDate: dates[0] ?? null,
      lastDate: dates.at(-1) ?? null,
    };
  }

  answer(question: string, summary: LocalSummary): string {
    const query = question.trim().toLocaleLowerCase();
    if (!query) return 'Choose a question or type one about this report.';

    if (hasAny(query, ['top category', 'where did i spend', 'spend most', 'biggest category', 'category'])) {
      const top = summary.categoryTotals[0];
      return top
        ? `${top.name} is the largest category in this ${summary.currency} report at ${formatMoney(top.amountMinor, summary.currency, summary.fractionDigits)}. This uses EXPENSE amounts less REFUND amounts; fees are shown separately.`
        : 'There are no categorized expense or refund amounts in the accepted rows for this currency.';
    }
    if (hasAny(query, ['fee', 'fees', 'charges'])) {
      return `Eligible recorded fees add up to ${formatMoney(summary.feeMinor, summary.currency, summary.fractionDigits)}. Positive fees on income, expense, refund and transfer rows count; adjustments do not.`;
    }
    if (hasAny(query, ['refund', 'refunded'])) {
      return `The accepted rows contain ${formatMoney(summary.refundMinor, summary.currency, summary.fractionDigits)} in recorded refunds. The CSV does not prove whether unrecorded refunds exist.`;
    }
    if (hasAny(query, ['income', 'earned', 'received'])) {
      return `Recorded income totals ${formatMoney(summary.incomeMinor, summary.currency, summary.fractionDigits)} before fees. This describes only accepted INCOME rows in the selected currency.`;
    }
    if (hasAny(query, ['net', 'change', 'left over', 'leftover', 'balance'])) {
      return `The recorded change is ${formatMoney(summary.netChangeMinor, summary.currency, summary.fractionDigits)}. It includes refunds and eligible fees. Transfer amounts and balance adjustments are excluded.`;
    }
    if (hasAny(query, ['month', 'trend', 'compare', 'comparison'])) {
      const months = summary.monthlyTotals.slice(-2);
      if (months.length < 2) return 'At least two months of accepted rows are needed for a month-to-month comparison.';
      const [previous, current] = months;
      const previousSpend = previous.expenseMinor - previous.refundMinor;
      const currentSpend = current.expenseMinor - current.refundMinor;
      const difference = currentSpend - previousSpend;
      const direction = difference > 0n ? 'higher' : difference < 0n ? 'lower' : 'the same';
      const comparison = difference === 0n
        ? 'Recorded spending was the same in both months.'
        : `Recorded spending in the later month was ${direction} by ${formatMoney(abs(difference), summary.currency, summary.fractionDigits)}.`;
      return `Expenses less refunds, before fees, were ${formatMoney(previousSpend, summary.currency, summary.fractionDigits)} in ${previous.month} and ${formatMoney(currentSpend, summary.currency, summary.fractionDigits)} in ${current.month}. ${comparison}`;
    }
    if (hasAny(query, ['how many', 'count', 'transactions', 'records', 'rows'])) {
      return `${summary.acceptedRows} rows in ${summary.currency} were accepted for this report. ${summary.rejectedRows} nonblank rows were rejected and excluded; the data-quality section lists the reasons.`;
    }
    if (hasAny(query, ['spend', 'expense', 'spent'])) {
      return `Recorded expense amounts are ${formatMoney(summary.expenseMinor, summary.currency, summary.fractionDigits)} before fees and refunds. Recorded refunds are ${formatMoney(summary.refundMinor, summary.currency, summary.fractionDigits)}, and fees are listed separately.`;
    }

    return 'I can answer about recorded income, expense amounts, refunds, fees, net change, the largest category, accepted rows, or recent month comparisons. This helper uses fixed rules on this device; it is not AI.';
  }

  buildTextReport(ledger: ImportedLedger, summary: LocalSummary, generatedAt: Date, sample = false): string {
    const dateRange = summary.firstDate && summary.lastDate
      ? `${summary.firstDate} to ${summary.lastDate}`
      : 'No accepted dates';
    const lines = [
      sample ? 'Mizani sample report (fictional records)' : 'Mizani local report',
      `Created in this browser: ${generatedAt.toLocaleString()}`,
      `Date range: ${dateRange}`,
      `Currency: ${summary.currency}`,
      `Rows accepted: ${summary.acceptedRows}`,
      `Rows rejected: ${ledger.quality.rejectedRows}`,
      `Recorded income: ${formatMoney(summary.incomeMinor, summary.currency, summary.fractionDigits)} (before fees)`,
      `Expense amounts: ${formatMoney(summary.expenseMinor, summary.currency, summary.fractionDigits)} (before fees and refunds)`,
      `Refund amounts: ${formatMoney(summary.refundMinor, summary.currency, summary.fractionDigits)}`,
      `Eligible fees: ${formatMoney(summary.feeMinor, summary.currency, summary.fractionDigits)}`,
      `Recorded change: ${formatMoney(summary.netChangeMinor, summary.currency, summary.fractionDigits)}`,
      '',
      'Largest categories (expense amounts less refunds; fees are excluded):',
      ...(summary.categoryTotals.length === 0
        ? ['No categorized expense or refund amounts.']
        : summary.categoryTotals.map((item) => `- ${item.name}: ${formatMoney(item.amountMinor, summary.currency, summary.fractionDigits)}`)),
      '',
      'Monthly spending (expense amounts less refunds; fees are excluded):',
      ...summary.monthlyTotals.map((month) => `- ${month.month}: ${formatMoney(month.expenseMinor - month.refundMinor, summary.currency, summary.fractionDigits)}`),
      '',
      'Method: income minus expense amounts and positive fees on income, expense, refund and transfer rows, plus refunds. Transfer amounts and balance adjustments are excluded.',
      'This report describes accepted records only. It is not financial, investment, tax, or accounting advice.',
    ];
    return lines.join('\n');
  }
}

export function formatMoney(value: bigint, currency: string, fractionDigits: number): string {
  const sign = value < 0n ? '−' : '';
  const absolute = abs(value);
  const scale = 10n ** BigInt(fractionDigits);
  const whole = absolute / scale;
  const fraction = absolute % scale;
  const groupedWhole = new Intl.NumberFormat('en', { maximumFractionDigits: 0 }).format(whole);
  const fractionText = fractionDigits === 0
    ? ''
    : `.${fraction.toString().padStart(fractionDigits, '0')}`;
  return `${sign}${currency} ${groupedWhole}${fractionText}`;
}

function getCurrencyFractionDigits(currency: string): number {
  return new Intl.NumberFormat('en', { style: 'currency', currency }).resolvedOptions().maximumFractionDigits ?? 2;
}

function sum(values: readonly bigint[]): bigint {
  return values.reduce((total, value) => total + value, 0n);
}

function compareBigInt(left: bigint, right: bigint): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function abs(value: bigint): bigint {
  return value < 0n ? -value : value;
}

function hasAny(value: string, choices: readonly string[]): boolean {
  return choices.some((choice) => value.includes(choice));
}
