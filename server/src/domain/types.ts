/** Shared domain types used across application and presentation layers. */

export type RoleCode = 'admin' | 'ict_officer' | 'viewer';

export interface AuthUser {
  id: string;
  username: string;
  fullName: string;
  role: RoleCode;
}

export type Priority = 'low' | 'medium' | 'high' | 'critical';

export type ReportingMethod = 'walk_in' | 'phone' | 'email' | 'ict_ticket' | 'vendor_ticket';

export type PrinterType = 'owned' | 'leased';

export type PrinterStatus = 'active' | 'inactive' | 'repair' | 'disposed';

export type VendorType = 'printer' | 'consumables' | 'maintenance' | 'other';

export type FileCategory =
  | 'screenshot'
  | 'photo'
  | 'document'
  | 'quotation'
  | 'requisition'
  | 'purchase_order'
  | 'delivery_note';

export interface Page<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}
