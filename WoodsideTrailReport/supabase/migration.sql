-- =============================================================
-- Woodside Trail Report — Supabase Database Migration
-- Run this in: Supabase Dashboard → SQL Editor
-- =============================================================

-- Reports table
create table if not exists reports (
  id              uuid             default gen_random_uuid() primary key,
  created_at      timestamptz      default now(),
  type            text             not null,
  description     text,
  location_lat    double precision not null,
  location_lng    double precision not null,
  nearest_street  text,
  cross_streets   text,
  phone           text,
  phone_type      text,            -- 'cell' | 'landline'
  contact_ok      boolean,
  email           text,
  status          text             default 'created',
  device_id       uuid             not null,
  routed_to       text,            -- 'woodside' | 'caltrans' | '911'
  photo_urls      jsonb            default '[]'::jsonb
);

-- Status history (shipping-style timeline)
create table if not exists report_status_history (
  id         uuid         default gen_random_uuid() primary key,
  report_id  uuid         references reports(id) on delete cascade,
  stage      text         not null,
  updated_at timestamptz  default now(),
  notes      text
);

-- Performance indexes
create index if not exists reports_device_id_idx    on reports(device_id);
create index if not exists reports_status_idx       on reports(status);
create index if not exists reports_created_at_idx   on reports(created_at desc);
create index if not exists status_history_report_idx on report_status_history(report_id);

-- =====================================================================
-- Row-Level Security
-- =====================================================================

alter table reports               enable row level security;
alter table report_status_history enable row level security;

-- Public (anon key): can INSERT new reports only
create policy "Public can insert reports"
  on reports for insert
  with check (true);

-- Public: cannot SELECT, UPDATE, or DELETE — use RPC functions below
-- Authenticated admin: full access to reports
create policy "Admin full access to reports"
  on reports for all
  using (auth.role() = 'authenticated');

-- Authenticated admin: full access to status history
create policy "Admin full access to history"
  on report_status_history for all
  using (auth.role() = 'authenticated');

-- =====================================================================
-- RPC Functions (called with anon key — bypasses RLS safely)
-- =====================================================================

-- Fetch reports for a specific device ID (My Reports screen)
create or replace function get_my_reports(p_device_id uuid)
returns setof reports
language sql
security definer
as $$
  select * from reports
  where device_id = p_device_id
  order by created_at desc;
$$;

grant execute on function get_my_reports(uuid) to anon;

-- Fetch status timeline for a specific report
create or replace function get_report_timeline(p_report_id uuid)
returns setof report_status_history
language sql
security definer
as $$
  select * from report_status_history
  where report_id = p_report_id
  order by updated_at asc;
$$;

grant execute on function get_report_timeline(uuid) to anon;

-- =====================================================================
-- Trigger: auto-insert "created" status entry on new report
-- =====================================================================

create or replace function fn_auto_created_status()
returns trigger
language plpgsql
as $$
begin
  insert into report_status_history(report_id, stage, notes)
  values (new.id, 'created', 'Request received. The correct team has been notified.');
  return new;
end;
$$;

drop trigger if exists trg_auto_created_status on reports;
create trigger trg_auto_created_status
  after insert on reports
  for each row
  execute function fn_auto_created_status();

-- =====================================================================
-- Storage: report-photos bucket
-- Create in Supabase Dashboard → Storage, then run these policies:
-- =====================================================================

-- Allow anon users to upload (INSERT) photos
-- (Create this policy in Dashboard → Storage → report-photos → Policies)
-- Policy name: "Public can upload photos"
-- Allowed operation: INSERT
-- Policy definition: true

-- =====================================================================
-- Admin user: create via Dashboard or run this query
-- Replace the email/password as needed before running.
-- =====================================================================
-- select auth.create_user(
--   '{"email":"admin@orlandonell.com","password":"adminisadmyn123","email_confirm":true}'
-- );
