import { Router } from 'express';
import { asyncHandler, requireAuth } from '../middleware';
import { dashboardRepo } from '../../infrastructure/repositories/dashboardRepo';

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
    res.json({
      stats,
      recent_activity: recentActivity,
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
