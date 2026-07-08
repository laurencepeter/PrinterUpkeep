import express from 'express';
import cors from 'cors';
import { config } from './config';
import { runMigrations } from './db/migrate';
import { authService } from './application/authService';
import { notificationService } from './application/notificationService';
import { errorHandler } from './presentation/middleware';
import { authRoutes } from './presentation/routes/authRoutes';
import { lookupRoutes } from './presentation/routes/lookupRoutes';
import { ticketRoutes } from './presentation/routes/ticketRoutes';
import { vendorRoutes } from './presentation/routes/vendorRoutes';
import { printerRoutes } from './presentation/routes/printerRoutes';
import { departmentRoutes } from './presentation/routes/departmentRoutes';
import { userRoutes } from './presentation/routes/userRoutes';
import { dashboardRoutes } from './presentation/routes/dashboardRoutes';
import { reportRoutes } from './presentation/routes/reportRoutes';
import { exportRoutes } from './presentation/routes/exportRoutes';
import { fileRoutes } from './presentation/routes/fileRoutes';
import { auditRoutes, notificationRoutes, settingsRoutes } from './presentation/routes/miscRoutes';

async function main(): Promise<void> {
  await runMigrations();
  await authService.bootstrapAdmin();

  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '2mb' }));

  app.get('/api/health', (_req, res) => res.json({ status: 'ok' }));

  app.use('/api/auth', authRoutes);
  app.use('/api/lookups', lookupRoutes);
  app.use('/api/tickets', ticketRoutes);
  app.use('/api/vendors', vendorRoutes);
  app.use('/api/printers', printerRoutes);
  app.use('/api/departments', departmentRoutes);
  app.use('/api/users', userRoutes);
  app.use('/api/dashboard', dashboardRoutes);
  app.use('/api/reports', reportRoutes);
  app.use('/api/export', exportRoutes);
  app.use('/api/files', fileRoutes);
  app.use('/api/notifications', notificationRoutes);
  app.use('/api/audit-logs', auditRoutes);
  app.use('/api/settings', settingsRoutes);

  app.use(errorHandler);

  // Overdue/vendor-delay scan: at boot, then hourly.
  notificationService.scan().catch((err) => console.error('[notify] scan failed', err));
  setInterval(
    () => notificationService.scan().catch((err) => console.error('[notify] scan failed', err)),
    60 * 60 * 1000,
  );

  app.listen(config.port, () => {
    console.log(`[api] listening on :${config.port} (${config.env})`);
  });
}

main().catch((err) => {
  console.error('Fatal startup error:', err);
  process.exit(1);
});
