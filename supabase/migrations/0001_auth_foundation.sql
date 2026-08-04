-- ============================================================================
-- Supabase-native rewrite — Phase 1: authentication & role foundation
--
-- Establishes the bridge between Supabase Auth (auth.users) and the app's
-- role model, plus the RLS helper functions every later policy depends on.
-- Additive and self-contained: it does not touch the existing `printerupkeep`
-- schema or the Node backend, so the current app keeps working while the
-- Supabase-native side is built up alongside it.
--
-- Roles mirror the current app: admin | ict_officer | viewer.
-- ============================================================================

-- Role enum (matches the existing roles.code values).
do $$ begin
  create type public.app_role as enum ('admin', 'ict_officer', 'viewer');
exception when duplicate_object then null; end $$;

-- One profile row per auth user, holding the app-specific role + display name.
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text not null default '',
  role       public.app_role not null default 'viewer',
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- --- RLS helper functions ---------------------------------------------------
-- SECURITY DEFINER so they can read profiles regardless of the caller's own
-- row-level policies (avoids recursive policy evaluation). Every table policy
-- in Phase 2 will call these instead of re-querying profiles inline.

create or replace function public.current_app_role()
  returns public.app_role
  language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
  returns boolean
  language sql stable security definer set search_path = public as $$
  select coalesce(public.current_app_role() = 'admin', false);
$$;

-- Write access = admin or ICT officer (viewers are read-only), mirroring the
-- backend's writeAccess middleware.
create or replace function public.can_write()
  returns boolean
  language sql stable security definer set search_path = public as $$
  select coalesce(public.current_app_role() in ('admin', 'ict_officer'), false);
$$;

-- --- profiles policies ------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated with check (public.is_admin());

-- --- auto-provision a profile on signup ------------------------------------
-- New auth users get a profile automatically. full_name / role can be passed
-- in the signup metadata (raw_user_meta_data); role defaults to viewer so a
-- self-signed-up user has no write access until an admin promotes them.
create or replace function public.handle_new_user()
  returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce((new.raw_user_meta_data->>'role')::public.app_role, 'viewer')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- keep updated_at fresh
create or replace function public.touch_updated_at()
  returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();
