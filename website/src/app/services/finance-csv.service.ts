import { Injectable } from '@angular/core';

export type LedgerType = 'INCOME' | 'EXPENSE' | 'REFUND' | 'TRANSFER' | 'ADJUSTMENT';

export interface LedgerRow {
  readonly date: string;
  readonly month: string;
  readonly type: LedgerType;
  readonly amountMinor: bigint;
  readonly feeMinor: bigint;
  readonly currency: string;
  readonly category: string;
}

export interface ImportQuality {
  readonly totalRows: number;
  readonly acceptedRows: number;
  readonly rejectedRows: number;
  readonly blankRows: number;
  readonly rejectionReasons: Readonly<Record<string, number>>;
}

export interface ImportedLedger {
  readonly rows: readonly LedgerRow[];
  readonly quality: ImportQuality;
  readonly currencies: readonly string[];
  readonly firstDate: string | null;
  readonly lastDate: string | null;
}

const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_DATA_ROWS = 50_000;
const MAX_FIELD_CHARACTERS = 32_767;
const MAX_SIGNED_LONG = 9_223_372_036_854_775_807n;
const REQUIRED_HEADERS = ['date', 'type', 'amount', 'currency', 'fee'] as const;
const LEDGER_TYPES = new Set<LedgerType>([
  'INCOME',
  'EXPENSE',
  'REFUND',
  'TRANSFER',
  'ADJUSTMENT',
]);

@Injectable({ providedIn: 'root' })
export class FinanceCsvService {
  async readFile(file: File): Promise<ImportedLedger> {
    if (!file.name.toLocaleLowerCase().endsWith('.csv')) {
      throw new Error('Choose the transaction CSV exported from Mizani. Excel workbooks and encrypted backups are not supported here.');
    }
    if (file.size === 0) {
      throw new Error('This CSV is empty. Export your transactions again from Mizani and try once more.');
    }
    if (file.size > MAX_FILE_BYTES) {
      throw new Error('This CSV is larger than the 10 MB limit. Export a shorter date range from Mizani.');
    }

    let source: string;
    try {
      source = new TextDecoder('utf-8', { fatal: true }).decode(await file.arrayBuffer());
    } catch {
      throw new Error('The CSV is not valid UTF-8 text. Export it again from Mizani and try once more.');
    }

    const matrix = parseCsv(source.replace(/^\uFEFF/, ''));
    if (matrix.length < 1 || matrix[0].length === 0) {
      throw new Error('No CSV header was found. Export the transaction CSV from Mizani.');
    }
    if (matrix.length - 1 > MAX_DATA_ROWS) {
      throw new Error('This CSV has more than 50,000 data rows. Export a shorter date range from Mizani.');
    }

    const headers = matrix[0].map((header) => header.trim().toLocaleLowerCase());
    const headerIndexes = new Map<string, number>();
    headers.forEach((header, index) => {
      if (header && headerIndexes.has(header)) {
        throw new Error(`This CSV has a duplicate “${header}” column.`);
      }
      if (header) {
        headerIndexes.set(header, index);
      }
    });
    const missing = REQUIRED_HEADERS.filter((header) => !headerIndexes.has(header));
    if (missing.length > 0) {
      throw new Error(`This file is missing Mizani CSV columns: ${missing.join(', ')}.`);
    }

    const indexes = {
      date: headerIndexes.get('date')!,
      type: headerIndexes.get('type')!,
      amount: headerIndexes.get('amount')!,
      currency: headerIndexes.get('currency')!,
      fee: headerIndexes.get('fee')!,
      category: headerIndexes.get('category'),
    };

    const validRows: LedgerRow[] = [];
    const rejectionReasons: Record<string, number> = Object.create(null) as Record<string, number>;
    let totalRows = 0;
    let rejectedRows = 0;
    let blankRows = 0;

    for (const cells of matrix.slice(1)) {
      if (cells.every((cell) => cell.trim() === '')) {
        blankRows += 1;
        continue;
      }
      totalRows += 1;

      const reject = (reason: string): void => {
        rejectedRows += 1;
        rejectionReasons[reason] = (rejectionReasons[reason] ?? 0) + 1;
      };

      if (cells.length !== headers.length) {
        reject('Wrong number of columns');
        continue;
      }

      const date = cells[indexes.date].trim();
      if (!isIsoDate(date)) {
        reject('Invalid or missing date');
        continue;
      }

      const rawType = cells[indexes.type].trim().toLocaleUpperCase();
      if (!LEDGER_TYPES.has(rawType as LedgerType)) {
        reject('Unknown transaction type');
        continue;
      }
      const type = rawType as LedgerType;

      const currency = cells[indexes.currency].trim().toLocaleUpperCase();
      if (!/^[A-Z]{3}$/.test(currency)) {
        reject('Invalid currency code');
        continue;
      }

      const fractionDigits = getCurrencyFractionDigits(currency);
      if (fractionDigits === null) {
        reject('Unsupported currency code');
        continue;
      }

      const amountMinor = parseMinorUnits(cells[indexes.amount].trim(), fractionDigits);
      if (amountMinor === null || (type !== 'ADJUSTMENT' && amountMinor < 0n)) {
        reject('Invalid amount or currency precision');
        continue;
      }
      const feeMinor = parseMinorUnits(cells[indexes.fee].trim(), fractionDigits);
      if (feeMinor === null || feeMinor < 0n) {
        reject('Invalid fee or currency precision');
        continue;
      }

      const category = indexes.category === undefined
        ? ''
        : cells[indexes.category].trim();
      if (category.length > 120) {
        reject('Category label is longer than 120 characters');
        continue;
      }

      validRows.push({
        date,
        month: date.slice(0, 7),
        type,
        amountMinor,
        feeMinor,
        currency,
        category: category || 'Uncategorised',
      });
    }

    const sortedDates = validRows.map((row) => row.date).sort();
    const currencies = [...new Set(validRows.map((row) => row.currency))].sort();

    return {
      rows: validRows,
      quality: {
        totalRows,
        acceptedRows: validRows.length,
        rejectedRows,
        blankRows,
        rejectionReasons,
      },
      currencies,
      firstDate: sortedDates[0] ?? null,
      lastDate: sortedDates.at(-1) ?? null,
    };
  }
}

function parseCsv(source: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let insideQuotes = false;
  let closedQuote = false;

  const pushField = (): void => {
    row.push(field);
    field = '';
    closedQuote = false;
  };
  const pushRow = (): void => {
    pushField();
    rows.push(row);
    row = [];
    if (rows.length > MAX_DATA_ROWS + 1) {
      throw new Error('This CSV has more than 50,000 data rows. Export a shorter date range from Mizani.');
    }
  };
  const append = (character: string): void => {
    field += character;
    if (field.length > MAX_FIELD_CHARACTERS) {
      throw new Error('A CSV cell is longer than the 32,767-character limit.');
    }
  };

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (insideQuotes) {
      if (character === '"') {
        if (source[index + 1] === '"') {
          append('"');
          index += 1;
        } else {
          insideQuotes = false;
          closedQuote = true;
        }
      } else {
        append(character);
      }
      continue;
    }

    if (closedQuote && character !== ',' && character !== '\r' && character !== '\n') {
      throw new Error('The CSV has an unexpected character after a quoted value. Export it again from Mizani.');
    }
    if (character === '"') {
      if (field.length !== 0) {
        throw new Error('The CSV has a quote inside an unquoted value. Export it again from Mizani.');
      }
      insideQuotes = true;
    } else if (character === ',') {
      pushField();
    } else if (character === '\r' || character === '\n') {
      pushRow();
      if (character === '\r' && source[index + 1] === '\n') {
        index += 1;
      }
    } else {
      append(character);
    }
  }

  if (insideQuotes) {
    throw new Error('The CSV ends inside a quoted value. Export it again from Mizani.');
  }
  if (field.length > 0 || row.length > 0 || closedQuote) {
    pushRow();
  }
  return rows;
}

function isIsoDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < 1 || month < 1 || month > 12 || day < 1) return false;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= daysInMonth[month - 1];
}

function getCurrencyFractionDigits(currency: string): number | null {
  try {
    return new Intl.NumberFormat('en', {
      style: 'currency',
      currency,
    }).resolvedOptions().maximumFractionDigits ?? null;
  } catch {
    return null;
  }
}

function parseMinorUnits(value: string, fractionDigits: number): bigint | null {
  if (!/^-?\d+(?:\.\d+)?$/.test(value)) return null;
  const negative = value.startsWith('-');
  const unsigned = negative ? value.slice(1) : value;
  const [wholeText, fractionText = ''] = unsigned.split('.');
  if (fractionText.length > fractionDigits) return null;

  try {
    const scale = 10n ** BigInt(fractionDigits);
    const whole = BigInt(wholeText);
    const fraction = fractionDigits === 0
      ? 0n
      : BigInt((fractionText + '0'.repeat(fractionDigits)).slice(0, fractionDigits));
    const absolute = whole * scale + fraction;
    if (absolute > MAX_SIGNED_LONG) return null;
    return negative ? -absolute : absolute;
  } catch {
    return null;
  }
}
