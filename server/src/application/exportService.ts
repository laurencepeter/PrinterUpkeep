import ExcelJS from 'exceljs';
import PDFDocument from 'pdfkit';

/**
 * Data portability + presentation layer: renders any tabular dataset as CSV,
 * a styled Excel workbook (with an in-sheet data-bar chart), a presentable PDF
 * (with a drawn bar chart) or JSON. The Excel/PDF renderers are designed to be
 * handed to management as-is — headed, formatted and charted — not just dumped.
 */

export type Row = Record<string, unknown>;

export interface ReportSection {
  title: string;
  rows: Row[];
}

// --- Column classification --------------------------------------------------

const TEXTISH = [
  'number', 'date', 'month', 'name', 'model', 'asset', 'serial', 'ip',
  'username', 'officer', 'vendor', 'department', 'issue', 'user', 'type',
  'status', 'decision', 'approval', 'priority',
];

const isTextCol = (c: string) => TEXTISH.some((t) => c.toLowerCase().includes(t));
const isCurrencyCol = (c: string) => /amount|cost|quoted|total|budget|price/i.test(c);
const isPercentCol = (c: string) => /pct|percent/i.test(c);
const isAvgCol = (c: string) => /avg|average|days/i.test(c);

function cellText(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function toNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const n = typeof value === 'number' ? value : parseFloat(String(value));
  return Number.isFinite(n) ? n : null;
}

/** Columns whose every populated value parses as a number, with the max seen. */
function numericColumns(rows: Row[], columns: string[]): Map<string, number> {
  const maxByCol = new Map<string, number>();
  for (const c of columns) {
    if (isTextCol(c)) continue;
    let max = 0;
    let any = false;
    let allNum = true;
    for (const r of rows) {
      const raw = cellText(r[c]);
      if (raw === '') continue;
      const n = toNumber(r[c]);
      if (n === null) { allNum = false; break; }
      any = true;
      if (n > max) max = n;
    }
    if (allNum && any) maxByCol.set(c, max);
  }
  return maxByCol;
}

/** Pick the label (first text column) and value (best numeric column) to chart. */
function chartColumns(rows: Row[], columns: string[]): { label: string; value: string } | null {
  if (rows.length === 0) return null;
  const numeric = numericColumns(rows, columns);
  const label = columns.find((c) => isTextCol(c)) ?? columns[0];
  // Prefer a count/amount column over an average/percentage for the bars.
  const numericCols = columns.filter((c) => numeric.has(c) && (numeric.get(c) ?? 0) > 0);
  const value =
    numericCols.find((c) => !isAvgCol(c) && !isPercentCol(c)) ??
    numericCols.find((c) => !isPercentCol(c)) ??
    numericCols[0];
  if (!label || !value || label === value) return null;
  return { label, value };
}

function prettyHeader(c: string): string {
  return c.replace(/_/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase());
}

// --- CSV --------------------------------------------------------------------

export const exportService = {
  toCsv(rows: Row[]): string {
    if (rows.length === 0) return '';
    const headers = Object.keys(rows[0]);
    const escape = (s: string) => (/[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s);
    const lines = [headers.join(',')];
    for (const row of rows) {
      lines.push(headers.map((h) => escape(cellText(row[h]))).join(','));
    }
    return lines.join('\n');
  },

  // --- Excel ----------------------------------------------------------------

  /** Single styled report sheet. */
  async toExcel(rows: Row[], title: string, orgName = 'ICT Department'): Promise<Buffer> {
    const workbook = new ExcelJS.Workbook();
    workbook.creator = orgName;
    workbook.created = new Date();
    styleReportSheet(workbook, title, rows, orgName);
    return Buffer.from(await workbook.xlsx.writeBuffer());
  },

  /** Multi-report workbook: a contents sheet + one styled sheet per report. */
  async toWorkbook(sections: ReportSection[], orgName = 'ICT Department'): Promise<Buffer> {
    const workbook = new ExcelJS.Workbook();
    workbook.creator = orgName;
    workbook.created = new Date();

    const contents = workbook.addWorksheet('Contents', {
      properties: { tabColor: { argb: 'FF1F4E78' } },
    });
    contents.columns = [{ width: 6 }, { width: 44 }, { width: 14 }];
    contents.mergeCells('A1:C1');
    styleTitleCell(contents.getCell('A1'), orgName);
    contents.mergeCells('A2:C2');
    styleSubtitleCell(contents.getCell('A2'), `Reports pack · generated ${new Date().toLocaleString('en-GB')}`);
    contents.addRow([]);
    const head = contents.addRow(['#', 'Report', 'Rows']);
    head.eachCell((c) => styleHeaderCell(c));

    sections.forEach((section, i) => {
      styleReportSheet(workbook, section.title, section.rows, orgName);
      const r = contents.addRow([i + 1, section.title, section.rows.length]);
      r.getCell(2).font = { color: { argb: 'FF1F4E78' }, underline: true };
    });
    contents.views = [{ state: 'frozen', ySplit: 4 }];
    return Buffer.from(await workbook.xlsx.writeBuffer());
  },

  // --- PDF ------------------------------------------------------------------

  /** Single presentable report: header, bar chart, styled table. */
  toPdf(rows: Row[], title: string, orgName: string): Promise<Buffer> {
    return renderPdf((doc) => {
      drawReportHeader(doc, orgName, title);
      drawBarChart(doc, rows);
      drawTable(doc, rows);
    });
  },

  /** Multi-report pack: each report on its own page with chart + table. */
  toBundlePdf(sections: ReportSection[], orgName: string): Promise<Buffer> {
    return renderPdf((doc) => {
      drawReportHeader(doc, orgName, 'Reports Pack');
      doc.fontSize(9).font('Helvetica').fillColor('#555')
        .text(`${sections.length} reports · generated ${new Date().toLocaleString('en-GB')}`);
      sections.forEach((section) => {
        doc.addPage();
        drawReportHeader(doc, orgName, section.title);
        drawBarChart(doc, section.rows);
        drawTable(doc, section.rows);
      });
    });
  },
};

// --- Excel styling helpers --------------------------------------------------

const BRAND = 'FF1F4E78';        // deep blue
const BRAND_LIGHT = 'FFDCE6F1';  // banded row / header tint
const BAR_COLOR = 'FF5B9BD5';    // data-bar blue

function styleTitleCell(cell: ExcelJS.Cell, text: string) {
  cell.value = text;
  cell.font = { size: 15, bold: true, color: { argb: BRAND } };
  cell.alignment = { vertical: 'middle' };
}

function styleSubtitleCell(cell: ExcelJS.Cell, text: string) {
  cell.value = text;
  cell.font = { size: 10, italic: true, color: { argb: 'FF666666' } };
}

function styleHeaderCell(cell: ExcelJS.Cell) {
  cell.font = { bold: true, color: { argb: 'FFFFFFFF' } };
  cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: BRAND } };
  cell.alignment = { vertical: 'middle', horizontal: 'left', wrapText: true };
  cell.border = { bottom: { style: 'thin', color: { argb: BRAND } } };
}

/** Build one fully styled report worksheet: title, header, banded rows,
 *  number formats, totals and an in-sheet data-bar chart on the key column. */
function styleReportSheet(workbook: ExcelJS.Workbook, title: string, rows: Row[], orgName: string) {
  const sheet = workbook.addWorksheet(safeSheetName(title, workbook));
  const columns = rows.length ? Object.keys(rows[0]) : ['(no data)'];

  // Title band (rows 1-2).
  sheet.mergeCells(1, 1, 1, Math.max(columns.length, 1));
  styleTitleCell(sheet.getCell(1, 1), orgName);
  sheet.mergeCells(2, 1, 2, Math.max(columns.length, 1));
  styleSubtitleCell(sheet.getCell(2, 1), `${title} · generated ${new Date().toLocaleString('en-GB')}`);
  sheet.addRow([]);

  // Header row (row 4).
  const headerRow = sheet.addRow(columns.map(prettyHeader));
  const headerRowIndex = headerRow.number;
  headerRow.height = 22;
  headerRow.eachCell((c) => styleHeaderCell(c));

  if (!rows.length) {
    sheet.addRow(['No data for this report yet']);
    sheet.views = [{ state: 'frozen', ySplit: headerRowIndex }];
    return;
  }

  const numeric = numericColumns(rows, columns);

  // Data rows.
  rows.forEach((row, i) => {
    const dataRow = sheet.addRow(columns.map((c) => toNumber(row[c]) ?? (cellText(row[c]) || null)));
    if (i % 2 === 1) {
      dataRow.eachCell((c) => {
        c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: BRAND_LIGHT } };
      });
    }
    columns.forEach((c, j) => {
      const cell = dataRow.getCell(j + 1);
      if (numeric.has(c)) {
        cell.numFmt = isCurrencyCol(c) ? '#,##0.00' : isPercentCol(c) ? '0.0"%"' : isAvgCol(c) ? '#,##0.0' : '#,##0';
        cell.alignment = { horizontal: 'right' };
      }
    });
  });

  const firstDataRow = headerRowIndex + 1;
  const lastDataRow = headerRowIndex + rows.length;

  // Totals row for summable columns (counts + currency, never avg/percent).
  const totalsRow = sheet.addRow(
    columns.map((c, j) => {
      if (j === 0) return 'Total';
      if (numeric.has(c) && !isAvgCol(c) && !isPercentCol(c)) {
        const colLetter = sheet.getColumn(j + 1).letter;
        return { formula: `SUM(${colLetter}${firstDataRow}:${colLetter}${lastDataRow})` };
      }
      return null;
    }),
  );
  totalsRow.eachCell((c, colNumber) => {
    c.font = { bold: true };
    c.border = { top: { style: 'thin', color: { argb: BRAND } } };
    if (typeof c.value === 'object' && c.value && 'formula' in c.value) {
      const name = columns[colNumber - 1];
      c.numFmt = isCurrencyCol(name) ? '#,##0.00' : '#,##0';
      c.alignment = { horizontal: 'right' };
    }
  });

  // In-sheet "chart": data bars on the primary numeric column.
  const chart = chartColumns(rows, columns);
  if (chart) {
    const colIndex = columns.indexOf(chart.value) + 1;
    const colLetter = sheet.getColumn(colIndex).letter;
    try {
      sheet.addConditionalFormatting({
        ref: `${colLetter}${firstDataRow}:${colLetter}${lastDataRow}`,
        rules: [
          {
            type: 'dataBar',
            cfvo: [{ type: 'num', value: 0 }, { type: 'max' }],
            color: { argb: BAR_COLOR },
          },
        ],
      } as unknown as Parameters<ExcelJS.Worksheet['addConditionalFormatting']>[0]);
    } catch {
      /* data bars are decorative; never fail an export over them */
    }
  }

  // Column widths from content, clamped to a readable range.
  sheet.columns.forEach((col, i) => {
    const name = columns[i] ?? '';
    let max = prettyHeader(name).length;
    rows.forEach((r) => { max = Math.max(max, cellText(r[name]).length); });
    col.width = Math.min(48, Math.max(11, max + 2));
  });

  sheet.views = [{ state: 'frozen', ySplit: headerRowIndex }];
  sheet.autoFilter = {
    from: { row: headerRowIndex, column: 1 },
    to: { row: headerRowIndex, column: columns.length },
  };
}

/** Excel sheet names: ≤31 chars, no []:*?/\ and unique within the workbook. */
function safeSheetName(title: string, workbook: ExcelJS.Workbook): string {
  let base = title.replace(/[[\]:*?/\\]/g, ' ').slice(0, 31).trim() || 'Report';
  let name = base;
  let n = 2;
  while (workbook.worksheets.some((w) => w.name === name)) {
    name = `${base.slice(0, 28)} ${n++}`;
  }
  return name;
}

// --- PDF drawing helpers ----------------------------------------------------

function renderPdf(draw: (doc: InstanceType<typeof PDFDocument>) => void): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 40, size: 'A4', layout: 'landscape' });
    const chunks: Buffer[] = [];
    doc.on('data', (c: Buffer) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    draw(doc);
    doc.end();
  });
}

function drawReportHeader(doc: InstanceType<typeof PDFDocument>, orgName: string, title: string) {
  const left = doc.page.margins.left;
  doc.fillColor('#1F4E78').fontSize(16).font('Helvetica-Bold').text(orgName, left, doc.y);
  doc.fillColor('#000').fontSize(13).font('Helvetica-Bold').text(title);
  doc.fillColor('#666').fontSize(8).font('Helvetica')
    .text(`Generated ${new Date().toLocaleString('en-GB')}`);
  doc.moveDown(0.6);
  doc.fillColor('#000');
}

/** Horizontal bar chart of the primary category vs its main numeric metric. */
function drawBarChart(doc: InstanceType<typeof PDFDocument>, rows: Row[]) {
  if (rows.length === 0) return;
  const columns = Object.keys(rows[0]);
  const chart = chartColumns(rows, columns);
  if (!chart) return;

  const data = rows
    .map((r) => ({ label: cellText(r[chart.label]) || '—', value: toNumber(r[chart.value]) ?? 0 }))
    .filter((d) => d.value > 0)
    .sort((a, b) => b.value - a.value)
    .slice(0, 12);
  if (data.length === 0) return;

  const max = Math.max(...data.map((d) => d.value));
  const left = doc.page.margins.left;
  const labelW = 130;
  const chartLeft = left + labelW;
  const chartRight = doc.page.width - doc.page.margins.right - 60;
  const chartW = chartRight - chartLeft;
  const barH = 14;
  const gap = 6;

  doc.fontSize(10).font('Helvetica-Bold').fillColor('#000')
    .text(`${prettyHeader(chart.value)} by ${prettyHeader(chart.label)}`, left, doc.y);
  doc.moveDown(0.3);
  let y = doc.y;

  for (const d of data) {
    const w = max > 0 ? Math.max(2, (d.value / max) * chartW) : 2;
    doc.font('Helvetica').fontSize(8).fillColor('#333')
      .text(d.label.slice(0, 26), left, y + 3, { width: labelW - 6, lineBreak: false });
    doc.rect(chartLeft, y, chartW, barH).fill('#EEF3F9');
    doc.rect(chartLeft, y, w, barH).fill('#5B9BD5');
    doc.fillColor('#000').fontSize(8)
      .text(formatNumber(d.value, chart.value), chartRight + 4, y + 3, { width: 56, lineBreak: false });
    y += barH + gap;
    if (y > doc.page.height - doc.page.margins.bottom - barH) break;
  }
  doc.y = y + 6;
  doc.fillColor('#000');
}

/** Styled table: filled header, banded rows, right-aligned numbers. */
function drawTable(doc: InstanceType<typeof PDFDocument>, rows: Row[]) {
  if (rows.length === 0) {
    doc.fontSize(10).font('Helvetica').fillColor('#666').text('No data for this report yet.');
    return;
  }
  const columns = Object.keys(rows[0]);
  const numeric = numericColumns(rows, columns);
  const left = doc.page.margins.left;
  const tableW = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const colW = tableW / columns.length;
  const rowH = 15;

  const drawHeader = () => {
    const y = doc.y;
    doc.rect(left, y, tableW, rowH).fill('#1F4E78');
    doc.fillColor('#FFF').font('Helvetica-Bold').fontSize(7.5);
    columns.forEach((c, i) => {
      doc.text(prettyHeader(c).slice(0, 22), left + i * colW + 3, y + 4, {
        width: colW - 6, align: numeric.has(c) ? 'right' : 'left', lineBreak: false,
      });
    });
    doc.y = y + rowH;
    doc.fillColor('#000');
  };

  drawHeader();
  rows.forEach((row, r) => {
    if (doc.y > doc.page.height - doc.page.margins.bottom - rowH) {
      doc.addPage();
      drawHeader();
    }
    const y = doc.y;
    if (r % 2 === 1) doc.rect(left, y, tableW, rowH).fill('#F2F6FB');
    doc.fillColor('#000').font('Helvetica').fontSize(7.5);
    columns.forEach((c, i) => {
      const isNum = numeric.has(c);
      const text = isNum ? formatNumber(toNumber(row[c]) ?? 0, c) : cellText(row[c]);
      doc.text(text.slice(0, 40), left + i * colW + 3, y + 4, {
        width: colW - 6, align: isNum ? 'right' : 'left', lineBreak: false,
      });
    });
    doc.y = y + rowH;
  });
}

function formatNumber(n: number, col: string): string {
  if (isPercentCol(col)) return `${n.toFixed(1)}%`;
  if (isCurrencyCol(col)) return n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (isAvgCol(col)) return n.toLocaleString('en-US', { maximumFractionDigits: 1 });
  return n.toLocaleString('en-US');
}
