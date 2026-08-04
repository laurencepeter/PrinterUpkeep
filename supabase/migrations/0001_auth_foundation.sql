-- ============================================================================
-- Supabase-native rewrite — Phase 1: authentication & role foundation
--
-- All PrinterUpkeep objects live in a dedicated `printerupkeep` schema, NOT in
-- `public`. This Supabase instance is shared with other apps, so `public`
-- already contains colliding names (e.g. an `app_role` enum without a 'viewer'
-- value, and other apps' tables). A dedicated schema keeps everything isolated.
--
-- After running this, expose the schema to the API so the Flutter client can
-- use it: Supabase Dashboard → Project Settings → API → "Exposed schemas" →
-- add `printerupkeep` (also add it to the Data API "Extra search path").
--
-- Roles mirror the current app: admin | ict_officer | viewer.
-- ============================================================================

create schema if not exists printerupkeep;

-- Let the PostgREST roles use the schema (RLS still governs row access).
grant usage on schema printerupkeep to anon, authenticated, service_role;

-- Role enum, namespaced so it never clashes with a public.app_role from
-- another app sharing this database.
do $$ begin
  create type printerupkeep.app_role as enum ('admin', 'ict_officer', 'viewer');
exception when duplicate_object then null; end $$;

-- One profile row per auth user, holding the app-specific role + display name.
create table if not exists printerupkeep.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text not null default '',
  role       printerupkeep.app_role not null default 'viewer',
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table printerupkeep.profiles enable row level security;

-- --- RLS helper functions ---------------------------------------------------
-- SECURITY DEFINER so they can read profiles regardless of the caller's own
-- row-level policies (avoids recursive policy evaluation). Every table policy
-- in Phase 2 calls these instead of re-querying profiles inline.

create or replace function printerupkeep.current_app_role()
  returns printerupkeep.app_role
  language sql stable security definer set search_path = printerupkeep, public as $$
  select role from printerupkeep.profiles where id = auth.uid();
$$;

create or replace function printerupkeep.is_admin()
  returns boolean
  language sql stable security definer set search_path = printerupkeep, public as $$
  select coalesce(printerupkeep.current_app_role() = 'admin', false);
$$;

-- Write access = admin or ICT officer (viewers are read-only), mirroring the
-- backend's writeAccess middleware.
create or replace function printerupkeep.can_write()
  returns boolean
  language sql stable security definer set search_path = printerupkeep, public as $$
  select coalesce(printerupkeep.current_app_role() in ('admin', 'ict_officer'), false);
$$;

-- --- profiles policies ------------------------------------------------------
drop policy if exists profiles_select on printerupkeep.profiles;
create policy profiles_select on printerupkeep.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update on printerupkeep.profiles;
create policy profiles_update on printerupkeep.profiles
  for update to authenticated
  using (id = auth.uid() or printerupkeep.is_admin())
  with check (id = auth.uid() or printerupkeep.is_admin());

drop policy if exists profiles_insert on printerupkeep.profiles;
create policy profiles_insert on printerupkeep.profiles
  for insert to authenticated with check (printerupkeep.is_admin());

-- --- auto-provision a profile on signup ------------------------------------
-- The trigger is uniquely named (…_printerupkeep) so it can't clobber another
-- app's trigger on the shared auth.users table. New users get a profile with
-- role from signup metadata, defaulting to viewer (no write access until an
-- admin promotes them).
create or replace function printerupkeep.handle_new_user()
  returns trigger
  language plpgsql security definer set search_path = printerupkeep, public as $$
begin
  insert into printerupkeep.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce((new.raw_user_meta_data->>'role')::printerupkeep.app_role, 'viewer')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_printerupkeep on auth.users;
create trigger on_auth_user_created_printerupkeep
  after insert on auth.users
  for each row execute function printerupkeep.handle_new_user();

-- keep updated_at fresh
create or replace function printerupkeep.touch_updated_at()
  returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists profiles_touch on printerupkeep.profiles;
create trigger profiles_touch before update on printerupkeep.profiles
  for each row execute function printerupkeep.touch_updated_at();

-- Future tables in this schema should be reachable by the API roles too
-- (RLS still enforces per-row access). Applied now so Phase 2 tables inherit it.
alter default privileges in schema printerupkeep
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
alter default privileges in schema printerupkeep
  grant usage, select on sequences to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema printerupkeep
  to anon, authenticated, service_role;
