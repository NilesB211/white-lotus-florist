-- White Lotus Florist bouquet builder: database setup
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run. Run it once.

create extension if not exists pgcrypto with schema extensions;

create table public.flowers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  color text not null default '',
  price numeric(8,2) not null default 0 check (price >= 0),
  photo text,
  available boolean not null default true,
  sort int not null default 0,
  updated_at timestamptz not null default now()
);
create table public.styles (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'posy' check (kind in ('posy','handtied','vase')),
  name text not null check (char_length(name) between 1 and 60),
  description text not null default '',
  stems int not null default 12 check (stems between 1 and 200),
  fee numeric(8,2) not null default 0 check (fee >= 0),
  active boolean not null default true,
  sort int not null default 0
);
create table public.settings (
  id int primary key default 1 check (id = 1),
  shop_name text not null default 'White Lotus Florist',
  phone text not null default '',
  email text not null default 'info@wlflorist.com',
  note text not null default '',
  max_flowers int not null default 4 check (max_flowers between 1 and 8),
  passcode_hash text not null
);
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  customer_name text not null,
  customer_phone text not null,
  needed_by text not null default '',
  note text not null default '',
  style_name text not null,
  items jsonb not null,
  total numeric(8,2) not null,
  status text not null default 'new' check (status in ('new','confirmed','done','cancelled'))
);
create table public.login_failures (at timestamptz not null default now());

alter table public.flowers enable row level security;
alter table public.styles enable row level security;
alter table public.settings enable row level security;
alter table public.orders enable row level security;
alter table public.login_failures enable row level security;

create policy "public reads available flowers" on public.flowers for select to anon, authenticated using (available);
create policy "public reads active styles" on public.styles for select to anon, authenticated using (active);

-- Starting owner passcode: fern-peony-103 (change it in the dashboard under Shop settings)
insert into public.settings (passcode_hash, note) values
 (extensions.crypt('fern-peony-103', extensions.gen_salt('bf')),
  'Pick up to 4 of today''s fresh flowers and we''ll show you three ways to arrange them.');

insert into public.styles (kind, name, description, stems, fee, sort) values
 ('posy','Petite Posy','A small round bouquet, perfect as a thank-you or table piece.',9,8,1),
 ('handtied','Hand-Tied Classic','Our signature wrapped bouquet with a satin ribbon.',18,12,2),
 ('vase','Grand Vase','A full arrangement ready to display in a glass vase.',30,25,3);

create or replace function public.get_shop() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('shop_name',shop_name,'phone',phone,'email',email,'note',note,'max_flowers',max_flowers) from settings where id=1
$$;

create or replace function public.place_order(p_name text, p_phone text, p_needed_by text, p_note text, p_style uuid, p_flowers uuid[])
returns json language plpgsql security definer set search_path = public as $$
declare s styles; mx int; n int; per int; extra int; items jsonb := '[]'::jsonb; tot numeric := 0; f record; i int := 0; q int; oid uuid;
begin
  p_name := btrim(coalesce(p_name,'')); p_phone := btrim(coalesce(p_phone,''));
  if char_length(p_name) < 2 or char_length(p_name) > 80 then raise exception 'Please enter your name.'; end if;
  if char_length(regexp_replace(p_phone,'\D','','g')) < 7 or char_length(p_phone) > 30 then raise exception 'Please enter a phone number we can reach you on.'; end if;
  if (select count(*) from orders where created_at > now() - interval '10 minutes') >= 30 then raise exception 'We are receiving a lot of orders right now. Please call the shop.'; end if;
  select * into s from styles where id = p_style and active;
  if not found then raise exception 'That bouquet style is no longer available.'; end if;
  select max_flowers into mx from settings where id=1;
  n := coalesce(array_length(p_flowers,1),0);
  if n < 1 or n > mx then raise exception 'Choose between 1 and % flowers.', mx; end if;
  per := s.stems / n; extra := s.stems % n;
  for f in select fl.id, fl.name, fl.price from unnest(p_flowers) with ordinality u(fid, ord) join flowers fl on fl.id = u.fid and fl.available order by u.ord loop
    i := i + 1; q := per + case when i <= extra then 1 else 0 end;
    items := items || jsonb_build_object('name', f.name, 'stems', q, 'price', f.price);
    tot := tot + q * f.price;
  end loop;
  if i <> n then raise exception 'One of your flowers just sold out. Please choose again.'; end if;
  tot := ceil(tot + s.fee);
  insert into orders (customer_name, customer_phone, needed_by, note, style_name, items, total)
  values (p_name, p_phone, left(coalesce(p_needed_by,''),60), left(coalesce(p_note,''),500), s.name, items, tot) returning id into oid;
  return json_build_object('id', oid, 'total', tot, 'style', s.name, 'items', items);
end $$;

create or replace function public._owner_ok(p text) returns boolean
language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  if (select count(*) from login_failures where at > now() - interval '15 minutes') >= 10 then
    raise exception 'Too many wrong passcodes. Wait 15 minutes and try again.';
  end if;
  select passcode_hash = extensions.crypt(coalesce(p,''), passcode_hash) into ok from settings where id=1;
  if not ok then
    insert into login_failures default values;
    delete from login_failures where at < now() - interval '1 day';
  end if;
  return ok;
end $$;

create or replace function public._owner_require(p text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not _owner_ok(p) then raise exception 'Wrong passcode.'; end if;
end $$;

create or replace function public.owner_load(p text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform _owner_require(p);
  return json_build_object(
    'settings', (select json_build_object('shop_name',shop_name,'phone',phone,'email',email,'note',note,'max_flowers',max_flowers) from settings where id=1),
    'flowers', coalesce((select json_agg(f order by f.sort, f.name) from flowers f),'[]'),
    'styles', coalesce((select json_agg(s order by s.sort, s.name) from styles s),'[]'),
    'orders', coalesce((select json_agg(o order by o.created_at desc) from (select * from orders order by created_at desc limit 100) o),'[]'));
end $$;

create or replace function public.owner_save_flower(p text, f json) returns uuid
language plpgsql security definer set search_path = public as $$
declare fid uuid := nullif(f->>'id','')::uuid;
begin
  perform _owner_require(p);
  if fid is null then
    insert into flowers (name,color,price,photo,available,sort)
    values (f->>'name', coalesce(f->>'color',''), coalesce((f->>'price')::numeric,0), f->>'photo', coalesce((f->>'available')::boolean,true), coalesce((f->>'sort')::int,0))
    returning id into fid;
  else
    update flowers set name=f->>'name', color=coalesce(f->>'color',''), price=coalesce((f->>'price')::numeric,0),
      photo=case when (f::jsonb) ? 'photo' then f->>'photo' else photo end,
      available=coalesce((f->>'available')::boolean,available), sort=coalesce((f->>'sort')::int,sort), updated_at=now()
    where id=fid;
  end if;
  return fid;
end $$;

create or replace function public.owner_delete_flower(p text, fid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin perform _owner_require(p); delete from flowers where id=fid; end $$;

create or replace function public.owner_set_all_available(p text, val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin perform _owner_require(p); update flowers set available=val, updated_at=now() where true; end $$;

create or replace function public.owner_save_style(p text, s json) returns uuid
language plpgsql security definer set search_path = public as $$
declare sid uuid := nullif(s->>'id','')::uuid;
begin
  perform _owner_require(p);
  if sid is null then
    insert into styles (kind,name,description,stems,fee,active,sort)
    values (coalesce(s->>'kind','posy'), s->>'name', coalesce(s->>'description',''), (s->>'stems')::int, (s->>'fee')::numeric, coalesce((s->>'active')::boolean,true), coalesce((s->>'sort')::int,0))
    returning id into sid;
  else
    update styles set kind=coalesce(s->>'kind',kind), name=s->>'name', description=coalesce(s->>'description',''), stems=(s->>'stems')::int,
      fee=(s->>'fee')::numeric, active=coalesce((s->>'active')::boolean,active), sort=coalesce((s->>'sort')::int,sort) where id=sid;
  end if;
  return sid;
end $$;

create or replace function public.owner_delete_style(p text, sid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin perform _owner_require(p); delete from styles where id=sid; end $$;

create or replace function public.owner_save_settings(p text, s json) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _owner_require(p);
  update settings set shop_name=coalesce(s->>'shop_name',shop_name), phone=coalesce(s->>'phone',phone), email=coalesce(s->>'email',email),
    note=coalesce(s->>'note',note), max_flowers=coalesce((s->>'max_flowers')::int,max_flowers) where id=1;
end $$;

create or replace function public.owner_change_passcode(p text, newp text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _owner_require(p);
  if char_length(coalesce(newp,'')) < 8 then raise exception 'Use at least 8 characters for the new passcode.'; end if;
  update settings set passcode_hash = extensions.crypt(newp, extensions.gen_salt('bf')) where id=1;
end $$;

create or replace function public.owner_set_order_status(p text, oid uuid, st text) returns void
language plpgsql security definer set search_path = public as $$
begin perform _owner_require(p); update orders set status=st where id=oid; end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.get_shop(), public.place_order(text,text,text,text,uuid,uuid[]),
  public.owner_load(text), public.owner_save_flower(text,json), public.owner_delete_flower(text,uuid),
  public.owner_set_all_available(text,boolean), public.owner_save_style(text,json), public.owner_delete_style(text,uuid),
  public.owner_save_settings(text,json), public.owner_change_passcode(text,text), public.owner_set_order_status(text,uuid,text)
  to anon, authenticated;
