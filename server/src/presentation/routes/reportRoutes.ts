import { Router } from 'express';
import { asyncHandler, requireAuth } from '../middleware';
import { reportRepo } from '../../infrastructure/repositories/reportRepo';
import { exportService, Row } from '../../application/exportService';
import { settingsRepo } from '../../infrastructure/repositories/lookupRepo';
import { ValidationError } from '../../domain/errors';

export const reportRoutes = Router();
reportRoutes.use(requireAuth);

const REPORTS: Record<string, { title: string; run: () => Promise<Row[]> }> = {
  'monthly-repairs':        { title: 'Monthly Repairs',          run: () => reportRepo.monthlyRepairs() as Promise<Row[]> },
  'vendor-performance':     { title: 'Vendor Performance',       run: () => reportRepo.vendorPerformance() as Promise<Row[]> },
  'department-usage':       { title: 'Department Usage',         run: () => reportRepo.departmentUsage() as Promise<Row[]> },
  'average-repair-time':    { title: 'Average Repair Time',      run: () => reportRepo.averageRepairTime() as Promise<Row[]> },
  'consumables-cost':       { title: 'Consumables Cost',         run: () => reportRepo.consumablesCost() as Promise<Row[]> },
  'common-issues':          { title: 'Most Common Issues',       run: () => reportRepo.commonIssues() as Promise<Row[]> },
  'most-repaired-printers': { title: 'Most Repaired Printers',   run: () => reportRepo.mostRepairedPrinters() as Promise<Row[]> },
  'tickets-by-officer':     { title: 'Tickets by ICT Officer',   run: () => reportRepo.ticketsByOfficer() as Promise<Row[]> },
  'owned-vs-leased':        { title: 'Owned vs Leased',          run: () => reportRepo.ownedVsLeased() as Promise<Row[]> },
};

reportRoutes.get('/', (_req, res) => {
  res.json(Object.entries(REPORTS).map(([key, r]) => ({ key, title: r.title })));
});

// GET /api/reports/:key?format=json|csv|xlsx|pdf
reportRoutes.get(
  '/:key',
  asyncHandler(async (req, res) => {
    const report = REPORTS[req.params.key];
    if (!report) throw new ValidationError(`Unknown report: ${req.params.key}`);
    const rows = await report.run();
    const format = (req.query.format as string) ?? 'json';
    const fileBase = req.params.key;

    switch (format) {
      case 'json':
        res.json({ title: report.title, rows });
        return;
      case 'csv':
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', `attachment; filename="${fileBase}.csv"`);
        res.send(exportService.toCsv(rows));
        return;
      case 'xlsx':
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.setHeader('Content-Disposition', `attachment; filename="${fileBase}.xlsx"`);
        res.send(await exportService.toExcel(rows, report.title));
        return;
      case 'pdf': {
        const orgName = (await settingsRepo.get('org_name')) ?? 'ICT Department';
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename="${fileBase}.pdf"`);
        res.send(await exportService.toPdf(rows, report.title, orgName));
        return;
      }
      default:
        throw new ValidationError(`Unsupported format: ${format}`);
    }
  }),
);
