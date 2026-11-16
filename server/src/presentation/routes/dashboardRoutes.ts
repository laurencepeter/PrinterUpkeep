import { Router } from 'express';
import { asyncHandler, requireAuth } from '../middleware';
import { dashboardRepo } from '../../infrastructure/repositories/dashboardRepo';
import { settingsRepo } from '../../infrastructure/repositories/lookupRepo';
import {
  classifyQuoteExpiry,
  QUOTE_EXPIRY_DEFAULTS,
  QUOTE_SENSITIVE_STAGES,
  quoteExpiryNextSteps,
} from '../../domain/quoteExpiry';

export const dashboardRoutes = Router();
dashboardRoutes.use(requireAuth);

dashboardRoutes.get(
  '/',
  asyncHandler(async (_req, res) => {
    const [stats, recentActivity, monthly, byDepartment, byVendor, ownedVsLeased, statusBreakdown] =
      await Promise.all([
        dashboardRepo.stats(),
        dashboardRepo.recentActivity(),
        dashboardRepo.monthlyRequests(),
        dashboardRepo.byDepartment(),
        dashboardRepo.byVendor(),
        dashboardRepo.ownedVsLeased(),
        dashboardRepo.statusBreakdown(),
      ]);
    const warnDays = await settingsRepo.getInt('quote_expiry_warn_days', QUOTE_EXPIRY_DEFAULTS.warnDays);
    const criticalDays = await settingsRepo.getInt('quote_expiry_critical_days', QUOTE_EXPIRY_DEFAULTS.criticalDays);
    const expiringQuotes = (
      await dashboardRepo.expiringQuotes(QUOTE_SENSITIVE_STAGES, Math.max(warnDays, criticalDays))
    ).map((q) => {
      const level = classifyQuoteExpiry(Number(q.days_to_expiry), warnDays, criticalDays) ?? 'ok';
      return { ...q, expiry_level: level, expiry_next_steps: quoteExpiryNextSteps(q.stage_code as string, level) };
    });
    res.json({
      stats,
      recent_activity: recentActivity,
      expiring_quotes: expiringQuotes,
      charts: {
        monthly_requests: monthly,
        by_department: byDepartment,
        by_vendor: byVendor,
        owned_vs_leased: ownedVsLeased,
        status_breakdown: statusBreakdown,
      },
    });
  }),
);
