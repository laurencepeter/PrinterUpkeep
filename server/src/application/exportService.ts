import ExcelJS from 'exceljs';
import PDFDocument from 'pdfkit';

/**
 * Data portability layer: renders any tabular dataset as CSV, Excel, PDF or
 * JSON so the data can migrate into a future enterprise system.
 */

export type Row = Record<string, unknown>;

function cellText(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

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

  async toExcel(rows: Row[], sheetName = 'Export'): Promise<Buffer> {
    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet(sheetName);
    if (rows.length > 0) {
      const headers = Object.keys(rows[0]);
      sheet.columns = headers.map((h) => ({ header: h, key: h, width: Math.max(14, h.length + 2) }));
      sheet.getRow(1).font = { bold: true };
      for (const row of rows) {
        sheet.addRow(headers.map((h) => cellText(row[h])));
      }
    }
    return Buffer.from(await workbook.xlsx.writeBuffer());
  },

  toPdf(rows: Row[], title: string, orgName: string): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      const doc = new PDFDocument({ margin: 36, size: 'A4', layout: 'landscape' });
      const chunks: Buffer[] = [];
      doc.on('data', (c: Buffer) => chunks.push(c));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      doc.fontSize(14).font('Helvetica-Bold').text(orgName);
      doc.fontSize(11).font('Helvetica').text(title);
      doc.fontSize(8).fillColor('#555').text(`Generated ${new Date().toISOString()}`);
      doc.moveDown();

      if (rows.length === 0) {
        doc.fillColor('#000').text('No data.');
      } else {
        const headers = Object.keys(rows[0]);
        const pageWidth = doc.page.width - 72;
        const colWidth = pageWidth / headers.length;
        const drawRow = (values: string[], bold: boolean) => {
          const y = doc.y;
          doc.font(bold ? 'Helvetica-Bold' : 'Helvetica').fontSize(7).fillColor('#000');
          values.forEach((v, i) => {
            doc.text(v.slice(0, 60), 36 + i * colWidth, y, { width: colWidth - 4, lineBreak: false });
          });
          doc.y = y + 14;
          if (doc.y > doc.page.height - 50) doc.addPage();
        };
        drawRow(headers, true);
        for (const row of rows) drawRow(headers.map((h) => cellText(row[h])), false);
      }
      doc.end();
    });
  },
};
