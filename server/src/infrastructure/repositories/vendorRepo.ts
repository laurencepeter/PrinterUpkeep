import { query, queryOne } from '../../db/pool';

export const vendorRepo = {
  async list(opts: { search?: string; includeInactive?: boolean } = {}) {
    const where: string[] = [];
    const params: unknown[] = [];
    if (!opts.includeInactive) where.push('v.is_active');
    if (opts.search) {
      params.push(`%${opts.search}%`);
      where.push(`v.company_name ILIKE $${params.length}`);
    }
    return query(
      `SELECT v.*, (SELECT count(*) FROM tickets t WHERE t.vendor_id = v.id)::int AS ticket_count
       FROM vendors v
       ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
       ORDER BY v.company_name`,
      params,
    );
  },

  async byId(id: string) {
    return queryOne(`SELECT * FROM vendors WHERE id = $1`, [id]);
  },

  async byName(companyName: string) {
    return queryOne(`SELECT * FROM vendors WHERE lower(company_name) = lower($1)`, [companyName]);
  },

  async create(data: {
    companyName: string;
    address?: string | null;
    phone?: string | null;
    email?: string | null;
    contactPerson?: string | null;
    website?: string | null;
    notes?: string | null;
    vendorTypes?: string[];
  }) {
    return queryOne(
      `INSERT INTO vendors (company_name, address, phone, email, contact_person, website, notes, vendor_types)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [
        data.companyName,
        data.address ?? null,
        data.phone ?? null,
        data.email ?? null,
        data.contactPerson ?? null,
        data.website ?? null,
        data.notes ?? null,
        data.vendorTypes ?? [],
      ],
    );
  },

  async update(
    id: string,
    data: {
      companyName?: string;
      address?: string | null;
      phone?: string | null;
      email?: string | null;
      contactPerson?: string | null;
      website?: string | null;
      notes?: string | null;
      vendorTypes?: string[];
      isActive?: boolean;
    },
  ) {
    return queryOne(
      `UPDATE vendors SET
         company_name   = COALESCE($2, company_name),
         address        = COALESCE($3, address),
         phone          = COALESCE($4, phone),
         email          = COALESCE($5, email),
         contact_person = COALESCE($6, contact_person),
         website        = COALESCE($7, website),
         notes          = COALESCE($8, notes),
         vendor_types   = COALESCE($9, vendor_types),
         is_active      = COALESCE($10, is_active),
         updated_at     = now()
       WHERE id = $1 RETURNING *`,
      [
        id,
        data.companyName ?? null,
        data.address ?? null,
        data.phone ?? null,
        data.email ?? null,
        data.contactPerson ?? null,
        data.website ?? null,
        data.notes ?? null,
        data.vendorTypes ?? null,
        data.isActive ?? null,
      ],
    );
  },
};
