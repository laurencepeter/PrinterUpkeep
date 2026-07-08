import { Router } from 'express';
import multer from 'multer';
import { asyncHandler, requireAuth, writeAccess } from '../middleware';
import { ticketRepo } from '../../infrastructure/repositories/ticketRepo';
import { vendorRepo } from '../../infrastructure/repositories/vendorRepo';
import { printerRepo } from '../../infrastructure/repositories/printerRepo';
import { departmentRepo } from '../../infrastructure/repositories/departmentRepo';
import { exportService, Row } from '../../application/exportService';
import { settingsRepo } from '../../infrastructure/repositories/lookupRepo';
import { ValidationError } from '../../domain/errors';
import ExcelJS from 'exceljs';

export const exportRoutes = Router();
exportRoutes.use(requireAuth);

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 20 * 1024 * 1024 } });

const ENTITIES: Record<string, (query: Record<string, unknown>) => Promise<Row[]>> = {
  tickets: (q) =>
    ticketRepo.listForExport({
      search: q.search as string | undefined,
      statusLabel: q.status as string | undefined,
      departmentId: q.department_id as string | undefined,
      vendorId: q.vendor_id as string | undefined,
      priority: q.priority as string | undefined,
      printerType: q.printer_type as string | undefined,
      dateFrom: q.date_from as string | undefined,
      dateTo: q.date_to as string | undefined,
      page: 1,
      pageSize: 100000,
    }) as Promise<Row[]>,
  vendors: () => vendorRepo.list({ includeInactive: true }) as Promise<Row[]>,
  printers: () => printerRepo.list() as Promise<Row[]>,
  departments: () => departmentRepo.list(true) as Promise<Row[]>,
};

// GET /api/export/:entity?format=csv|xlsx|pdf|json  (+ same filters as list)
exportRoutes.get(
  '/:entity',
  asyncHandler(async (req, res) => {
    const run = ENTITIES[req.params.entity];
    if (!run) throw new ValidationError(`Unknown entity: ${req.params.entity}`);
    const rows = await run(req.query as Record<string, unknown>);
    const format = (req.query.format as string) ?? 'csv';
    const fileBase = `${req.params.entity}-${new Date().toISOString().slice(0, 10)}`;

    switch (format) {
      case 'json':
        res.setHeader('Content-Disposition', `attachment; filename="${fileBase}.json"`);
        res.json(rows);
        return;
      case 'csv':
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', `attachment; filename="${fileBase}.csv"`);
        res.send(exportService.toCsv(rows));
        return;
      case 'xlsx':
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.setHeader('Content-Disposition', `attachment; filename="${fileBase}.xlsx"`);
        res.send(await exportService.toExcel(rows, req.params.entity));
        return;
      case 'pdf': {
        const orgName = (await settingsRepo.get('org_name')) ?? 'ICT Department';
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename="${fileBase}.pdf"`);
        res.send(await exportService.toPdf(rows, `Export: ${req.params.entity}`, orgName));
        return;
      }
      default:
        throw new ValidationError(`Unsupported format: ${format}`);
    }
  }),
);

// --- Import ---------------------------------------------------------------

function parseCsv(text: string): Row[] {
  const lines = text.split(/\r?\n/).filter((l) => l.trim() !== '');
  if (lines.length < 2) return [];
  const parseLine = (line: string): string[] => {
    const out: string[] = [];
    let cur = '';
    let inQuotes = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (inQuotes) {
        if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; }
        else if (ch === '"') inQuotes = false;
        else cur += ch;
      } else if (ch === '"') inQuotes = true;
      else if (ch === ',') { out.push(cur); cur = ''; }
      else cur += ch;
    }
    out.push(cur);
    return out;
  };
  const headers = parseLine(lines[0]).map((h) => h.trim());
  return lines.slice(1).map((line) => {
    const values = parseLine(line);
    const row: Row = {};
    headers.forEach((h, i) => (row[h] = values[i] === '' ? undefined : values[i]));
    return row;
  });
}

async function parseUpload(file: Express.Multer.File): Promise<Row[]> {
  const name = file.originalname.toLowerCase();
  if (name.endsWith('.json')) {
    const data = JSON.parse(file.buffer.toString('utf8'));
    if (!Array.isArray(data)) throw new ValidationError('JSON import must be an array of objects');
    return data as Row[];
  }
  if (name.endsWith('.csv')) return parseCsv(file.buffer.toString('utf8'));
  if (name.endsWith('.xlsx')) {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(file.buffer as unknown as ArrayBuffer);
    const sheet = workbook.worksheets[0];
    const rows: Row[] = [];
    const headers: string[] = [];
    sheet.eachRow((row, rowNumber) => {
      const values = (row.values as unknown[]).slice(1); // exceljs is 1-indexed
      if (rowNumber === 1) {
        values.forEach((v) => headers.push(String(v ?? '')));
      } else {
        const record: Row = {};
        headers.forEach((h, i) => {
          const v = values[i];
          record[h] = v === null || v === undefined || v === '' ? undefined : String(v);
        });
        rows.push(record);
      }
    });
    return rows;
  }
  throw new ValidationError('Supported import formats: .csv, .xlsx, .json');
}

/**
 * POST /api/export/import/:entity — bulk import with duplicate validation.
 * Duplicates (by natural key) are reported and skipped, never overwritten.
 */
exportRoutes.post(
  '/import/:entity',
  writeAccess,
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) throw new ValidationError('No file uploaded (field name: file)');
    const rows = await parseUpload(req.file);
    const result = { imported: 0, skipped_duplicates: [] as string[], errors: [] as string[] };

    if (req.params.entity === 'vendors') {
      for (const row of rows) {
        const name = String(row.company_name ?? row.companyName ?? '').trim();
        if (!name) { result.errors.push('Row missing company_name'); continue; }
        if (await vendorRepo.byName(name)) { result.skipped_duplicates.push(name); continue; }
        await vendorRepo.create({
          companyName: name,
          address: row.address as string | undefined,
          phone: row.phone as string | undefined,
          email: row.email as string | undefined,
          contactPerson: (row.contact_person ?? row.contactPerson) as string | undefined,
          website: row.website as string | undefined,
          notes: row.notes as string | undefined,
        });
        result.imported++;
      }
    } else if (req.params.entity === 'printers') {
      for (const row of rows) {
        const assetNumber = String(row.asset_number ?? row.assetNumber ?? '').trim();
        const model = String(row.model ?? '').trim();
        if (!assetNumber || !model) { result.errors.push('Row missing asset_number/model'); continue; }
        const existing = await printerRepo.list({ search: assetNumber });
        if (existing.some((p) => p.asset_number === assetNumber)) {
          result.skipped_duplicates.push(assetNumber);
          continue;
        }
        await printerRepo.create({
          assetNumber,
          model,
          serialNumber: (row.serial_number ?? row.serialNumber) as string | undefined,
          printerType: String(row.printer_type ?? row.printerType ?? 'owned'),
          location: row.location as string | undefined,
          building: row.building as string | undefined,
          floor: row.floor as string | undefined,
        });
        result.imported++;
      }
    } else if (req.params.entity === 'departments') {
      const existing = await departmentRepo.list(true);
      const names = new Set(existing.map((d) => String(d.name).toLowerCase()));
      for (const row of rows) {
        const name = String(row.name ?? '').trim();
        if (!name) { result.errors.push('Row missing name'); continue; }
        if (names.has(name.toLowerCase())) { result.skipped_duplicates.push(name); continue; }
        await departmentRepo.create({
          name,
          code: row.code as string | undefined,
          building: row.building as string | undefined,
          floor: row.floor as string | undefined,
        });
        names.add(name.toLowerCase());
        result.imported++;
      }
    } else {
      throw new ValidationError(`Import not supported for entity: ${req.params.entity}`);
    }
    res.json(result);
  }),
);
