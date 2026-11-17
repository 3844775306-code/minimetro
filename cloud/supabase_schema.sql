-- Mini Metro 纸城 · Supabase 云端排行榜 / 地图大厅
-- 在 Supabase Dashboard → SQL Editor 里整段执行。
-- 设计：客户端只允许 SELECT；所有写入走 security definer RPC。
-- 注意：这是"匿名玩家 ID"方案，适合原型；正式上线建议开启 Supabase 匿名登录，
-- 并在 Edge Function / RPC 里从 auth.uid() 取玩家身份，避免客户端伪造 player_id。

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

create table if not exists public.metro_daily_scores (
  id bigint generated always as identity primary key,
  date date not null,
  player_id uuid not null,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 16),
  score integer not null check (score >= 0),
  created_at timestamptz not null default now(),
  unique (date, player_id)
);

create table if not exists public.metro_best_scores (
  id bigint generated always as identity primary key,
  mode text not null check (mode in ('classic', 'endless', 'manager')),
  city_id text not null,
  player_id uuid not null,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 16),
  score integer not null check (score >= 0),
  updated_at timestamptz not null default now(),
  unique (mode, city_id, player_id)
);

create table if not exists public.metro_maps (
  id text primary key,
  name_zh text not null,
  name_en text,
  author text not null,
  width real not null default 100.0 check (width between 40.0 and 240.0),
  rivers jsonb not null check (jsonb_typeof(rivers) = 'array'),
  start_lines integer not null default 3,
  start_trains integer not null default 3,
  start_carriages integer not null default 0,
  start_interchanges integer not null default 0,
  start_bridges integer not null default 2,
  uploader_id uuid,
  downloads integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists metro_daily_scores_date_score_idx
  on public.metro_daily_scores (date desc, score desc);
create index if not exists metro_best_scores_board_idx
  on public.metro_best_scores (mode, city_id, score desc);
create index if not exists metro_maps_created_idx
  on public.metro_maps (created_at desc);

-- ---------------------------------------------------------------------------
-- RLS：只开放读；写操作只通过下面的 RPC
-- ---------------------------------------------------------------------------

alter table public.metro_daily_scores enable row level security;
alter table public.metro_best_scores enable row level security;
alter table public.metro_maps enable row level security;

revoke all on public.metro_daily_scores from anon, authenticated;
revoke all on public.metro_best_scores from anon, authenticated;
revoke all on public.metro_maps from anon, authenticated;
grant select on public.metro_daily_scores to anon, authenticated;
grant select on public.metro_best_scores to anon, authenticated;
grant select on public.metro_maps to anon, authenticated;

drop policy if exists "daily scores are public" on public.metro_daily_scores;
create policy "daily scores are public"
  on public.metro_daily_scores for select to anon, authenticated using (true);

drop policy if exists "best scores are public" on public.metro_best_scores;
create policy "best scores are public"
  on public.metro_best_scores for select to anon, authenticated using (true);

drop policy if exists "maps are public" on public.metro_maps;
create policy "maps are public"
  on public.metro_maps for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- 写入 RPC
-- ---------------------------------------------------------------------------

-- 每日挑战：每名玩家每天只有一条；已经交过就不再改（服务器端保证 one attempt）。
create or replace function public.submit_daily_score(
  p_date date,
  p_player_id uuid,
  p_display_name text,
  p_score integer
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_score < 0 then
    raise exception 'score must be non-negative';
  end if;
  if char_length(btrim(p_display_name)) not between 1 and 16 then
    raise exception 'display_name must be 1..16 characters';
  end if;
  insert into public.metro_daily_scores (date, player_id, display_name, score)
  values (p_date, p_player_id, btrim(p_display_name), p_score)
  on conflict (date, player_id) do nothing;
end;
$$;

-- 其他模式：同一玩家同一模式同一地图只保留最高分。
create or replace function public.submit_best_score(
  p_mode text,
  p_city_id text,
  p_player_id uuid,
  p_display_name text,
  p_score integer
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_mode not in ('classic', 'endless', 'manager') then
    raise exception 'invalid mode';
  end if;
  if p_score < 0 then
    raise exception 'score must be non-negative';
  end if;
  if char_length(btrim(p_display_name)) not between 1 and 16 then
    raise exception 'display_name must be 1..16 characters';
  end if;
  insert into public.metro_best_scores
    (mode, city_id, player_id, display_name, score, updated_at)
  values
    (p_mode, p_city_id, p_player_id, btrim(p_display_name), p_score, now())
  on conflict (mode, city_id, player_id) do update
    set score = greatest(metro_best_scores.score, excluded.score),
        display_name = excluded.display_name,
        updated_at = now();
end;
$$;

-- 上传 / 覆盖自己的地图（地图大厅）。
create or replace function public.upload_metro_map(
  p_id text,
  p_name_zh text,
  p_name_en text,
  p_author text,
  p_width real,
  p_rivers jsonb,
  p_start_lines integer,
  p_start_trains integer,
  p_start_carriages integer,
  p_start_interchanges integer,
  p_start_bridges integer,
  p_uploader_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if jsonb_typeof(p_rivers) <> 'array' or jsonb_array_length(p_rivers) = 0 then
    raise exception 'rivers must be a non-empty json array';
  end if;
  insert into public.metro_maps
    (id, name_zh, name_en, author, width, rivers, start_lines, start_trains,
     start_carriages, start_interchanges, start_bridges, uploader_id)
  values
    (p_id, p_name_zh, coalesce(p_name_en, p_name_zh), p_author, p_width, p_rivers,
     p_start_lines, p_start_trains, p_start_carriages, p_start_interchanges,
     p_start_bridges, p_uploader_id)
  on conflict (id) do update
    set name_zh = excluded.name_zh,
        name_en = excluded.name_en,
        author = excluded.author,
        width = excluded.width,
        rivers = excluded.rivers,
        start_lines = excluded.start_lines,
        start_trains = excluded.start_trains,
        start_carriages = excluded.start_carriages,
        start_interchanges = excluded.start_interchanges,
        start_bridges = excluded.start_bridges,
        uploader_id = excluded.uploader_id;
end;
$$;

-- 下载计数 +1。
create or replace function public.increment_map_downloads(p_id text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.metro_maps
    set downloads = downloads + 1
    where id = p_id;
end;
$$;

grant execute on function public.submit_daily_score(date, uuid, text, integer)
  to anon, authenticated;
grant execute on function public.submit_best_score(text, text, uuid, text, integer)
  to anon, authenticated;
grant execute on function public.upload_metro_map(
  text, text, text, text, real, jsonb, integer, integer, integer, integer, integer, uuid
) to anon, authenticated;
grant execute on function public.increment_map_downloads(text)
  to anon, authenticated;
