import fs from 'fs';
import path from 'path';
import PDFDocument from 'pdfkit';

/**
 * Renders the Ministry "REQUISITION FORM" as a print-ready PDF that mirrors the
 * official paper layout: coat-of-arms header, requester block, supply-priority
 * boxes, a priced line-item table with sub-total / VAT / total, a justification
 * memo and the Accounts + Permanent Secretary + Procurement Officer approval
 * blocks. Everything is pre-filled from the ticket so officers only sign, stamp
 * and forward it.
 */

export interface RequisitionItem {
  quantity?: number | string | null;
  unit?: string | null;
  description?: string | null;
  unit_price?: number | string | null;
}

export interface RequisitionFormData {
  requisition: Record<string, unknown> & { items?: RequisitionItem[] };
  ticket: Record<string, unknown>;
  settings: {
    govName: string;
    ministry: string;
    orgName: string;
    vatRate: number;
    /** Optional base64-encoded PNG (no data: prefix) of the coat of arms. */
    logoBase64?: string;
  };
}

const PAGE_MARGIN = 40;

function money(value: number): string {
  return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function num(value: unknown): number {
  const n = typeof value === 'number' ? value : parseFloat(String(value ?? ''));
  return Number.isFinite(n) ? n : 0;
}

function text(value: unknown): string {
  return value === null || value === undefined || value === '' ? '' : String(value);
}

/** Resolve the coat-of-arms image: settings base64 first, then a bundled asset. */
function resolveLogo(logoBase64?: string): Buffer | null {
  if (logoBase64 && logoBase64.trim()) {
    try {
      return Buffer.from(logoBase64.replace(/^data:image\/\w+;base64,/, ''), 'base64');
    } catch {
      /* fall through to asset */
    }
  }
  const assetPath = path.resolve(__dirname, '../../assets/coat-of-arms.png');
  if (fs.existsSync(assetPath)) return fs.readFileSync(assetPath);
  return null;
}

export function renderRequisitionForm(doc: InstanceType<typeof PDFDocument>, data: RequisitionFormData): void {
  const { requisition, ticket, settings } = data;
  const left = PAGE_MARGIN;
  const right = doc.page.width - PAGE_MARGIN;
  const width = right - left;

  // --- Header: coat of arms + government + ministry -------------------------
  const logo = resolveLogo(settings.logoBase64);
  if (logo) {
    try {
      doc.image(logo, doc.page.width / 2 - 28, doc.y, { width: 56, height: 56 });
      doc.y += 60;
    } catch {
      /* ignore an unreadable image and keep the text header */
    }
  }
  doc.fontSize(11).font('Helvetica-Bold').text(settings.govName, left, doc.y, { width, align: 'center' });
  doc.fontSize(10).font('Helvetica').text(settings.ministry, { width, align: 'center' });
  doc.moveDown(0.6);
  doc.fontSize(13).font('Helvetica-Bold').text('REQUISITION FORM', { width, align: 'center' });
  doc.moveDown(0.8);

  // --- Requester block ------------------------------------------------------
  const labelValue = (label: string, value: string, x: number, y: number, w: number) => {
    doc.fontSize(9).font('Helvetica-Bold').text(label, x, y, { continued: false });
    const lw = doc.widthOfString(label) + 4;
    doc.font('Helvetica').text(value || ' ', x + lw, y, { width: w - lw });
    doc.moveTo(x + lw, y + 11).lineTo(x + w, y + 11).lineWidth(0.5).stroke();
  };
  const col = width / 2;
  let y = doc.y;
  labelValue('REQUESTED BY:', text(requisition.requested_by || ticket.reported_by), left, y, col - 10);
  labelValue('DEPARTMENT:', text(requisition.department_name || ticket.department_name), left + col, y, col - 10);
  y += 22;
  labelValue('DATE:', text(requisition.prepared_date).slice(0, 10), left, y, col - 10);
  labelValue('FILE #:', text(requisition.file_number || requisition.requisition_number), left + col, y, col - 10);
  y += 22;

  // --- Supply priority ------------------------------------------------------
  const priority = text(requisition.supply_priority).toLowerCase();
  doc.fontSize(9).font('Helvetica-Bold').text('SUPPLY PRIORITY:', left, y);
  let px = left + doc.widthOfString('SUPPLY PRIORITY:') + 10;
  const priorityBox = (labelText: string, key: string) => {
    doc.rect(px, y, 9, 9).lineWidth(0.7).stroke();
    if (priority === key) {
      doc.font('Helvetica-Bold').fontSize(9).text('X', px + 1.5, y - 0.5);
    }
    doc.font('Helvetica').fontSize(9).text(labelText, px + 13, y);
    px += 13 + doc.widthOfString(labelText) + 22;
  };
  priorityBox('Emergency', 'emergency');
  priorityBox('Urgent', 'urgent');
  priorityBox('Regular', 'regular');
  y += 20;

  // --- Line-item table ------------------------------------------------------
  const items = Array.isArray(requisition.items) ? requisition.items : [];
  const cols = [
    { title: 'Qty', w: 40 },
    { title: 'Unit', w: 50 },
    { title: 'Description of Works/Goods/Services', w: width - 40 - 50 - 90 - 90 },
    { title: 'Estimated Unit Price ($TT)', w: 90 },
    { title: 'Estimated Total ($TT)', w: 90 },
  ];
  const colX = (i: number) => left + cols.slice(0, i).reduce((s, c) => s + c.w, 0);

  const drawRow = (cells: string[], opts: { header?: boolean; height?: number; align?: ('l' | 'r')[] } = {}) => {
    const h = opts.height ?? 18;
    doc.font(opts.header ? 'Helvetica-Bold' : 'Helvetica').fontSize(opts.header ? 8 : 8.5);
    cells.forEach((cell, i) => {
      const x = colX(i);
      doc.rect(x, y, cols[i].w, h).lineWidth(0.5).stroke();
      const align = opts.align?.[i] === 'r' ? 'right' : 'left';
      doc.text(cell, x + 3, y + (opts.header ? 3 : 5), { width: cols[i].w - 6, align, lineBreak: opts.header });
    });
    y += h;
  };

  drawRow(cols.map((c) => c.title), { header: true, height: 26 });

  let subtotal = 0;
  const bodyRows = Math.max(items.length, 5); // always show a few blank rows to write on
  for (let i = 0; i < bodyRows; i++) {
    const item = items[i];
    if (item) {
      const qty = num(item.quantity);
      const price = num(item.unit_price);
      const total = qty * price;
      subtotal += total;
      drawRow(
        [
          qty ? String(qty) : '',
          text(item.unit),
          text(item.description),
          price ? money(price) : '',
          total ? money(total) : '',
        ],
        { align: ['l', 'l', 'l', 'r', 'r'] },
      );
    } else {
      drawRow(['', '', '', '', '']);
    }
  }

  // Totals: Sub-Total / VAT / Total, right-aligned under the price columns.
  const vatRate = num(requisition.vat_rate) || settings.vatRate || 0;
  const vat = subtotal * (vatRate / 100);
  const total = subtotal + vat;
  const totalsLabelX = colX(3);
  const totalsLabelW = cols[3].w;
  const totalsValX = colX(4);
  const totalsValW = cols[4].w;
  const totalRow = (label: string, value: number) => {
    doc.rect(totalsLabelX, y, totalsLabelW, 16).lineWidth(0.5).stroke();
    doc.rect(totalsValX, y, totalsValW, 16).lineWidth(0.5).stroke();
    doc.font('Helvetica-Bold').fontSize(8.5).text(label, totalsLabelX + 3, y + 4, { width: totalsLabelW - 6, align: 'right' });
    doc.font('Helvetica').text(money(value), totalsValX + 3, y + 4, { width: totalsValW - 6, align: 'right' });
    y += 16;
  };
  totalRow('Sub-Total:', subtotal);
  totalRow(`VAT ${vatRate}%:`, vat);
  totalRow('Total:', total);
  y += 10;

  // --- Memorandum of justification -----------------------------------------
  doc.font('Helvetica-Bold').fontSize(9).text('Memorandum of Justification:', left, y, { continued: true });
  doc.font('Helvetica').text('  (Indicate reason for the need for these goods/services/works)');
  y = doc.y + 4;
  doc.rect(left, y, width, 44).lineWidth(0.5).stroke();
  if (text(requisition.memorandum)) {
    doc.font('Helvetica').fontSize(9).text(text(requisition.memorandum), left + 4, y + 4, { width: width - 8, height: 38 });
  }
  y += 54;

  // --- Prepared by ----------------------------------------------------------
  labelValue('PREPARED BY:', text(requisition.prepared_by), left, y, col + 40);
  labelValue('DATE:', '', left + col + 60, y, col - 60 - 10);
  doc.font('Helvetica-Oblique').fontSize(7.5).text('(Head of Department)', left + doc.widthOfString('PREPARED BY:') + 4, y + 12);
  y += 30;

  // --- Accounts department block -------------------------------------------
  doc.moveTo(left, y).lineTo(right, y).lineWidth(1).stroke();
  y += 6;
  doc.font('Helvetica-BoldOblique').fontSize(9).text('Accounts Department & Accounting Officer Only', left, y, { width, align: 'center' });
  y += 18;
  labelValue('EXPENSE ITEM (CODE):', text(requisition.expense_code), left, y, col - 10);
  labelValue('ANNUAL BUDGET:', requisition.annual_budget != null ? money(num(requisition.annual_budget)) : '', left + col, y, col - 10);
  y += 22;
  labelValue('EXPENDITURE TO DATE:', requisition.expenditure_to_date != null ? money(num(requisition.expenditure_to_date)) : '', left, y, col - 10);
  labelValue('AMOUNT AVAILABLE:', requisition.amount_available != null ? money(num(requisition.amount_available)) : '', left + col, y, col - 10);
  y += 26;
  labelValue('AUTHORISED MANAGER:', text(requisition.authorised_manager), left, y, col + 30);
  labelValue('DATE:', '', left + col + 50, y, col - 50 - 10);
  doc.font('Helvetica-Oblique').fontSize(7).text('In accordance with Financial Delegated Authority', left, y + 12);
  y += 26;
  labelValue('ACCOUNTING OFFICER:', text(requisition.accounting_officer), left, y, col + 30);
  labelValue('DATE:', '', left + col + 50, y, col - 50 - 10);
  doc.font('Helvetica-Oblique').fontSize(7).text('In accordance with Financial Delegated Authority', left, y + 12);
  y += 30;

  // --- Approvals ------------------------------------------------------------
  doc.moveTo(left, y).lineTo(right, y).lineWidth(1).stroke();
  y += 8;
  const approvalRow = (label: string) => {
    doc.font('Helvetica-Bold').fontSize(9).text(label, left, y, { continued: false });
    const lw = doc.widthOfString(label) + 4;
    doc.moveTo(left + lw, y + 11).lineTo(left + col + 20, y + 11).lineWidth(0.5).stroke();
    doc.font('Helvetica-Bold').text('DATE:', left + col + 40, y);
    doc.moveTo(left + col + 40 + doc.widthOfString('DATE:') + 4, y + 11).lineTo(right, y + 11).stroke();
    y += 18;
    // Approved / Not Approved boxes
    let bx = left + 20;
    const box = (labelText: string) => {
      doc.rect(bx, y, 9, 9).lineWidth(0.7).stroke();
      doc.font('Helvetica').fontSize(9).text(labelText, bx + 13, y);
      bx += 13 + doc.widthOfString(labelText) + 30;
    };
    box('APPROVED');
    box('NOT APPROVED');
    y += 24;
  };
  approvalRow('Permanent Secretary / Deputy PS:');
  approvalRow('Named Procurement Officer:');
}
