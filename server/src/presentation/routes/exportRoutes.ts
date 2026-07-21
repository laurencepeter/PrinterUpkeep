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

/**
 * RFC-4180-style CSV parser implemented as a character state machine over the
 * whole text (not line-by-line) so a quoted field may itself contain commas
 * *and newlines* — essential for cells like a multi-line toner list. Escaped
 * quotes ("") inside a quoted field become a literal quote.
 */
function parseCsv(text: string): Row[] {
  const records: string[][] = [];
  let field = '';
  let record: string[] = [];
  let inQuotes = false;
  const pushField = () => { record.push(field); field = ''; };
  const pushRecord = () => { records.push(record); record = []; };
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') inQuotes = false;
      else field += ch;
    } else if (ch === '"') inQuotes = true;
    else if (ch === ',') pushField();
    else if (ch === '\r') { /* ignore, handled with \n */ }
    else if (ch === '\n') { pushField(); pushRecord(); }
    else field += ch;
  }
  if (field !== '' || record.length) { pushField(); pushRecord(); }

  // Drop records that are entirely empty (e.g. a trailing newline).
  const nonEmpty = records.filter((r) => r.some((c) => c.trim() !== ''));
  if (nonEmpty.length < 2) return [];
  const headers = nonEmpty[0].map((h) => h.trim());
  return nonEmpty.slice(1).map((values) => {
    const row: Row = {};
    headers.forEach((h, i) => {
      const v = values[i];
      row[h] = v === undefined || v.trim() === '' ? undefined : v;
    });
    return row;
  });
}

/** Coerce an exceljs cell value (hyperlink / rich text / formula / plain) to text. */
function cellToString(v: unknown): string | undefined {
  if (v === null || v === undefined) return undefined;
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    if (typeof o.text === 'string') return o.text || undefined; // hyperlink cell
    if (Array.isArray(o.richText)) {
      return (o.richText as Array<{ text?: string }>).map((r) => r.text ?? '').join('') || undefined;
    }
    if ('result' in o) return o.result == null ? undefined : String(o.result); // formula cell
    if (typeof o.hyperlink === 'string') return o.hyperlink || undefined;
  }
  const s = String(v);
  return s === '' ? undefined : s;
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
          record[h] = cellToString(values[i]);
        });
        rows.push(record);
      }
    });
    return rows;
  }
  throw new ValidationError('Supported import formats: .csv, .xlsx, .json');
}

// --- Field mapping helpers (tolerant header matching for imports) ----------

/** Normalise a header/key so "IP Address", "ip_address" and "ipAddress" all match. */
const normKey = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, '');

/** First non-empty value in `row` whose header matches any of `keys` (order-independent). */
function pick(row: Row, ...keys: string[]): string | undefined {
  const want = keys.map(normKey);
  for (const [k, v] of Object.entries(row)) {
    if (v === undefined || v === null) continue;
    if (want.includes(normKey(k))) {
      const s = String(v).trim();
      if (s !== '') return s;
    }
  }
  return undefined;
}

/** Map free-text status values onto the printer status enum. */
function normStatus(v?: string): 'active' | 'repair' | 'disposed' {
  const s = (v ?? '').toLowerCase();
  if (/repair|service|fault|broken|maintenance|down/.test(s)) return 'repair';
  if (/dispos|retir|decommission|scrap|write.?off|inactive|end.?of.?life/.test(s)) return 'disposed';
  return 'active';
}

/** Map free-text ownership values onto the printer_type enum. */
function normOwnership(v?: string): 'owned' | 'leased' {
  return /leas|rent|hire/.test((v ?? '').toLowerCase()) ? 'leased' : 'owned';
}

const TONER_COLORS: Record<string, string> = {
  black: 'black', k: 'black', bk: 'black', blk: 'black',
  cyan: 'cyan', c: 'cyan',
  magenta: 'magenta', m: 'magenta',
  yellow: 'yellow', y: 'yellow',
  tricolor: 'tricolor', tricolour: 'tricolor',
};

/**
 * Parse a multi-value toner cell into individual catalogue entries. Each value
 * is on its own line (or ; separated), typically "<Colour> <ModelCode>", e.g.
 *   Yellow   W9052MC
 *   Magenta  W9053MC
 * A leading colour word is recognised and split off; anything else is treated
 * as the model code with no colour.
 */
function parseToners(raw?: string): Array<{ color: string | null; modelCode: string | null }> {
  if (!raw) return [];
  const out: Array<{ color: string | null; modelCode: string | null }> = [];
  for (const part of raw.split(/[\r\n;]+/)) {
    const line = part.trim();
    if (!line) continue;
    const m = line.match(/^(\S+)\s+(.*)$/);
    if (m && TONER_COLORS[normKey(m[1])]) {
      out.push({ color: TONER_COLORS[normKey(m[1])], modelCode: m[2].trim() || null });
    } else if (TONER_COLORS[normKey(line)]) {
      out.push({ color: TONER_COLORS[normKey(line)], modelCode: null });
    } else {
      out.push({ color: null, modelCode: line });
    }
  }
  return out;
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
      // Load existing printers once and index their natural keys so duplicates
      // are detected in a single pass (also catches duplicates *within* the file).
      const existing = await printerRepo.list();
      const lc = (v: unknown) => String(v ?? '').trim().toLowerCase();
      const serials = new Set(existing.map((p) => lc(p.serial_number)).filter(Boolean));
      const ips = new Set(existing.map((p) => lc(p.ip_address)).filter(Boolean));
      const assets = new Set(existing.map((p) => lc(p.asset_number)).filter(Boolean));

      // Resolve department names to ids, auto-creating any that don't exist yet.
      const deptList = await departmentRepo.list(true);
      const deptByName = new Map(deptList.map((d) => [lc(d.name), String(d.id)]));

      let autoSeq = 0;
      for (const row of rows) {
        const model = pick(row, 'model');
        if (!model) { result.errors.push('Row missing Model'); continue; }

        const serial = pick(row, 'serial_number', 'serial');
        const ipRaw = pick(row, 'ip_address', 'ip');
        // Only accept a syntactically valid IPv4 (the column has a unique index).
        const ip = ipRaw && /^(\d{1,3}\.){3}\d{1,3}$/.test(ipRaw) ? ipRaw : undefined;

        // The sheet has no asset number; fall back to the serial, else generate
        // a stable placeholder (asset_number is NOT NULL UNIQUE in the schema).
        let assetNumber = pick(row, 'asset_number', 'asset', 'tag') ?? serial;
        if (!assetNumber) {
          do { assetNumber = `IMP-${Date.now()}-${++autoSeq}`; } while (assets.has(lc(assetNumber)));
        }

        // Skip if this printer already exists (by serial, IP, or asset number).
        const dup =
          (serial && serials.has(lc(serial)) && `serial ${serial}`) ||
          (ip && ips.has(lc(ip)) && `IP ${ip}`) ||
          (assets.has(lc(assetNumber)) && `asset ${assetNumber}`) ||
          null;
        if (dup) { result.skipped_duplicates.push(`${model} (${dup})`); continue; }

        // Resolve / auto-create the department.
        let departmentId: string | undefined;
        const deptName = pick(row, 'department', 'department_name', 'dept');
        if (deptName) {
          departmentId = deptByName.get(lc(deptName));
          if (!departmentId) {
            const createdDept = await departmentRepo.create({ name: deptName });
            departmentId = String(createdDept!.id);
            deptByName.set(lc(deptName), departmentId);
          }
        }

        // Parse the multi-value toner cell + optional waste toner into a
        // structured consumables catalogue.
        const toners = parseToners(pick(row, 'toner_model', 'toner', 'toner_models', 'toners'));
        const wasteToner = pick(row, 'waste_toner_model', 'waste_toner', 'wastetoner');
        const isColor = toners.some((t) => ['cyan', 'magenta', 'yellow'].includes(t.color ?? ''));

        // Columns with no dedicated printer field are preserved in notes.
        const path = pick(row, 'path', 'network_path', 'location_path');
        const notes = path ? `Path: ${path}` : undefined;

        const created = await printerRepo.create({
          assetNumber,
          model,
          serialNumber: serial,
          printerType: normOwnership(pick(row, 'ownership_status', 'ownership', 'printer_type')),
          status: normStatus(pick(row, 'status')),
          ipAddress: ip,
          departmentId,
          isColor,
          notes,
        });

        const items = [
          ...toners.map((t) => ({ kind: 'toner', color: t.color, modelCode: t.modelCode, label: null })),
          ...(wasteToner
            ? [{ kind: 'other', color: null, modelCode: wasteToner, label: 'Waste Toner' }]
            : []),
        ];
        if (items.length) await printerRepo.replaceConsumables(String(created!.id), items);

        assets.add(lc(assetNumber));
        if (serial) serials.add(lc(serial));
        if (ip) ips.add(lc(ip));
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
