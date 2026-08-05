-- ============================================================================
-- Supabase-native rewrite — Phase 2: core asset tables (departments, vendors,
-- printers) with Row-Level Security.
--
-- These are the first tables the Flutter client will talk to directly via the
-- Supabase API. Security is enforced by RLS, keyed to the role helpers from
-- Phase 1 (printerupkeep.can_write / is_admin): any signed-in user can READ,
-- only admins/ICT officers can WRITE. Depends on 0001_auth_foundation.sql.
--
-- All objects live in the printerupkeep schema (exposed to the API in Phase 1).
-- ============================================================================

set search_path to printerupkeep, public;

-- --- Departments ------------------------------------------------------------
create table if not exists printerupkeep.departments (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  code       text unique,
  building   text,
  floor      text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- --- Vendors ----------------------------------------------------------------
create table if not exists printerupkeep.vendors (
  id             uuid primary key default gen_random_uuid(),
  company_name   text not null,
  address        text,
  phone          text,
  email          text,
  contact_person text,
  website        text,
  notes          text,
  vendor_types   text[] not null default '{}',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists ux_vendors_company_name
  on printerupkeep.vendors (lower(company_name));

-- --- Printers ---------------------------------------------------------------
create table if not exists printerupkeep.printers (
  id              uuid primary key default gen_random_uuid(),
  asset_number    text not null unique,
  model           text not null,
  name            text,
  serial_number   text unique,
  printer_type    text not null default 'owned'
                  check (printer_type in ('owned', 'leased')),
  department_id   uuid references printerupkeep.departments(id),
  vendor_id       uuid references printerupkeep.vendors(id),
  location        text,
  building        text,
  floor           text,
  ip_address      text,
  status          text not null default 'active'
                  check (status in ('active', 'inactive', 'repair', 'disposed')),
  is_color        boolean not null default false,
  warranty_expiry date,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists ix_printers_department on printerupkeep.printers (department_id);
create index if not exists ix_printers_vendor     on printerupkeep.printers (vendor_id);

-- keep updated_at fresh (reuses the trigger fn from Phase 1)
drop trigger if exists departments_touch on printerupkeep.departments;
create trigger departments_touch before update on printerupkeep.departments
  for each row execute function printerupkeep.touch_updated_at();
drop trigger if exists vendors_touch on printerupkeep.vendors;
create trigger vendors_touch before update on printerupkeep.vendors
  for each row execute function printerupkeep.touch_updated_at();
drop trigger if exists printers_touch on printerupkeep.printers;
create trigger printers_touch before update on printerupkeep.printers
  for each row execute function printerupkeep.touch_updated_at();

-- --- Row-Level Security -----------------------------------------------------
-- Read: any authenticated user. Write: admins / ICT officers only.
do $$
declare t text;
begin
  foreach t in array array['departments', 'vendors', 'printers'] loop
    execute format('alter table printerupkeep.%I enable row level security', t);

    execute format('drop policy if exists %I on printerupkeep.%I', t || '_select', t);
    execute format(
      'create policy %I on printerupkeep.%I for select to authenticated using (true)',
      t || '_select', t);

    execute format('drop policy if exists %I on printerupkeep.%I', t || '_write', t);
    execute format(
      'create policy %I on printerupkeep.%I for all to authenticated '
      || 'using (printerupkeep.can_write()) with check (printerupkeep.can_write())',
      t || '_write', t);
  end loop;
end $$;
