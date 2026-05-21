create extension if not exists postgis;

create table if not exists public.route_sessions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  motoboy_id uuid references public.profiles(id),
  order_id uuid references public.deliveries(id),
  origin geography(point, 4326),
  destination geography(point, 4326),
  osrm_eta_seconds integer,
  gemini_eta_seconds integer,
  actual_duration_seconds integer,
  ai_savings_seconds integer generated always as (
    greatest(coalesce(osrm_eta_seconds, 0) - coalesce(actual_duration_seconds, osrm_eta_seconds, 0), 0)
  ) stored,
  toll_cost_brl numeric(8, 2) not null default 0,
  traffic_ratio numeric(4, 2) not null default 1.0,
  routing_source varchar(30) not null default 'osrm',
  alerts_count integer not null default 0,
  reroutes_accepted integer not null default 0
);

comment on table public.route_sessions is 'Telemetria de roteamento por corrida do ArkGO.';
comment on column public.route_sessions.osrm_eta_seconds is 'ETA estimado pelo OSRM em segundos.';
comment on column public.route_sessions.gemini_eta_seconds is 'ETA com IA/trafego em tempo real em segundos.';
comment on column public.route_sessions.actual_duration_seconds is 'Duracao real da corrida ao ser concluida.';
comment on column public.route_sessions.traffic_ratio is 'Razao entre ETA com trafego e ETA normal.';
comment on column public.route_sessions.routing_source is 'Fonte final do motor de roteamento.';

create index if not exists route_sessions_motoboy_idx
  on public.route_sessions (motoboy_id);
create index if not exists route_sessions_order_idx
  on public.route_sessions (order_id);
create index if not exists route_sessions_created_at_idx
  on public.route_sessions (created_at desc);
create index if not exists route_sessions_routing_source_idx
  on public.route_sessions (routing_source);

create table if not exists public.route_cache (
  id uuid primary key default gen_random_uuid(),
  cache_key text not null unique,
  payload jsonb not null,
  expires_at timestamptz not null,
  hit_count integer not null default 0,
  created_at timestamptz not null default now()
);

comment on table public.route_cache is 'Cache de rotas e agregacoes de analytics.';

create or replace function public.refresh_daily_efficiency()
returns void
language plpgsql
security definer
as $$
begin
  refresh materialized view public.daily_efficiency;
exception
  when undefined_table then
    null;
end;
$$;

drop materialized view if exists public.daily_efficiency;
create materialized view public.daily_efficiency as
select
  date(created_at) as day,
  count(*)::bigint as total_rides,
  round(sum(ai_savings_seconds) / 60.0, 2) as total_minutes_saved,
  round(avg(traffic_ratio)::numeric, 2) as avg_traffic_ratio,
  round(sum(toll_cost_brl), 2) as total_tolls_brl,
  round(
    avg(
      case
        when gemini_eta_seconds is null or actual_duration_seconds is null then 0
        when abs(gemini_eta_seconds - actual_duration_seconds) < 120 then 1
        else 0
      end
    ) * 100,
    2
  ) as ai_vs_osrm_accuracy
from public.route_sessions
group by date(created_at);

create unique index if not exists daily_efficiency_day_idx
  on public.daily_efficiency (day);

create or replace function public.refresh_daily_efficiency_trigger()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.refresh_daily_efficiency();
  return new;
end;
$$;

drop trigger if exists route_sessions_refresh_daily_efficiency
on public.route_sessions;

create trigger route_sessions_refresh_daily_efficiency
after insert on public.route_sessions
for each statement
execute function public.refresh_daily_efficiency_trigger();

alter table public.route_sessions enable row level security;
alter table public.route_cache enable row level security;

drop policy if exists "route_sessions own read" on public.route_sessions;
create policy "route_sessions own read"
  on public.route_sessions
  for select
  using (
    auth.uid() = motoboy_id
    or exists (
      select 1
      from public.users
      where users.id = auth.uid()
        and users.role = 'admin'
    )
  );

drop policy if exists "route_sessions service write" on public.route_sessions;
create policy "route_sessions service write"
  on public.route_sessions
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

drop policy if exists "route_cache service only" on public.route_cache;
create policy "route_cache service only"
  on public.route_cache
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- Seed rapido para testes:
-- insert into public.route_sessions (
--   motoboy_id, order_id, origin, destination, osrm_eta_seconds,
--   gemini_eta_seconds, actual_duration_seconds, toll_cost_brl, traffic_ratio, routing_source
-- ) values (
--   null, null,
--   st_geogfromtext('POINT(-46.6333 -23.5505)'),
--   st_geogfromtext('POINT(-46.6550 -23.5630)'),
--   1400, 1560, 1320, 4.80, 1.11, 'google'
-- );
