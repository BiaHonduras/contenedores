-- BIA Honduras | Control de contenedores y reclamos
-- Ejecutar en Supabase > SQL Editor con una cuenta propietaria del proyecto.
-- El script es idempotente: puede volver a ejecutarse para aplicar actualizaciones.

create extension if not exists pgcrypto;

-- 1. Perfiles, roles y agencias
create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  full_name text not null default '',
  employee_code text not null default '',
  role text not null default 'operador' check (role in ('admin', 'operador', 'consulta')),
  agency text not null default 'SPS' check (agency in ('SPS', 'CBA', 'SRC', 'TGU')),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_profiles_email_idx on public.user_profiles (lower(email));
create index if not exists user_profiles_agency_idx on public.user_profiles (agency, is_active);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_profiles_touch_updated_at on public.user_profiles;
create trigger user_profiles_touch_updated_at
before update on public.user_profiles
for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  is_first_user boolean;
  selected_agency text;
begin
  select not exists (select 1 from public.user_profiles) into is_first_user;
  selected_agency := upper(coalesce(new.raw_user_meta_data ->> 'agency', 'SPS'));
  if selected_agency not in ('SPS', 'CBA', 'SRC', 'TGU') then
    selected_agency := 'SPS';
  end if;

  insert into public.user_profiles (
    id, email, full_name, employee_code, role, agency, is_active
  ) values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'employee_code', ''),
    case when is_first_user then 'admin' else 'operador' end,
    selected_agency,
    is_first_user
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = case when public.user_profiles.full_name = '' then excluded.full_name else public.user_profiles.full_name end,
    employee_code = case when public.user_profiles.employee_code = '' then excluded.employee_code else public.user_profiles.employee_code end,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email, raw_user_meta_data on auth.users
for each row execute function public.handle_new_user();

-- Crea perfiles para usuarios que ya existían antes de instalar este script.
insert into public.user_profiles (id, email, full_name, employee_code, role, agency, is_active, created_at)
select
  u.id,
  coalesce(u.email, ''),
  coalesce(u.raw_user_meta_data ->> 'full_name', ''),
  coalesce(u.raw_user_meta_data ->> 'employee_code', ''),
  'operador',
  case
    when upper(coalesce(u.raw_user_meta_data ->> 'agency', 'SPS')) in ('SPS', 'CBA', 'SRC', 'TGU')
      then upper(coalesce(u.raw_user_meta_data ->> 'agency', 'SPS'))
    else 'SPS'
  end,
  false,
  coalesce(u.created_at, now())
from auth.users u
on conflict (id) do update set email = excluded.email;

-- Garantiza que exista al menos un administrador activo.
do $$
declare
  first_profile uuid;
begin
  if not exists (select 1 from public.user_profiles where role = 'admin') then
    select id into first_profile from public.user_profiles order by created_at asc limit 1;
    if first_profile is not null then
      update public.user_profiles set role = 'admin', is_active = true where id = first_profile;
    end if;
  end if;
end;
$$;

-- Funciones auxiliares de seguridad. SECURITY DEFINER evita recursión en RLS.
create or replace function public.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.user_profiles
    where id = auth.uid() and is_active = true
  );
$$;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select role from public.user_profiles where id = auth.uid();
$$;

create or replace function public.current_user_agency()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select agency from public.user_profiles where id = auth.uid();
$$;

revoke all on function public.current_user_is_active() from public;
revoke all on function public.current_user_role() from public;
revoke all on function public.current_user_agency() from public;
grant execute on function public.current_user_is_active() to authenticated;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.current_user_agency() to authenticated;

alter table public.user_profiles enable row level security;

drop policy if exists "Usuario consulta su perfil" on public.user_profiles;
create policy "Usuario consulta su perfil"
on public.user_profiles for select to authenticated
using (id = auth.uid() or public.current_user_role() = 'admin');

drop policy if exists "Administrador actualiza perfiles" on public.user_profiles;
create policy "Administrador actualiza perfiles"
on public.user_profiles for update to authenticated
using (public.current_user_is_active() and public.current_user_role() = 'admin')
with check (public.current_user_role() = 'admin');

-- 2. Reclamos y recepciones
create table if not exists public.supplier_claims (
  id uuid primary key default gen_random_uuid(),
  document_number text not null default '',
  supplier text not null,
  transport text not null default '',
  driver_name text not null default '',
  plate_number text not null default '',
  claim_number text not null default '',
  claim_date date not null default current_date,
  agency text not null default 'SPS',
  has_damage_claim boolean not null default false,
  observations text not null default '',
  received_by text not null default '',
  driver_signature_name text not null default '',
  items jsonb not null default '[]'::jsonb,
  container_photos text[] not null default '{}',
  damage_photos text[] not null default '{}',
  status text not null default 'borrador' check (status in ('borrador', 'recibido', 'reclamo')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.supplier_claims add column if not exists agency text not null default 'SPS';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'supplier_claims_agency_check'
      and conrelid = 'public.supplier_claims'::regclass
  ) then
    alter table public.supplier_claims
      add constraint supplier_claims_agency_check check (agency in ('SPS', 'CBA', 'SRC', 'TGU'));
  end if;
end;
$$;

create index if not exists supplier_claims_date_idx on public.supplier_claims (claim_date desc);
create index if not exists supplier_claims_supplier_idx on public.supplier_claims (supplier);
create index if not exists supplier_claims_agency_idx on public.supplier_claims (agency, claim_date desc);

drop trigger if exists supplier_claims_touch_updated_at on public.supplier_claims;
create trigger supplier_claims_touch_updated_at
before update on public.supplier_claims
for each row execute function public.touch_updated_at();

alter table public.supplier_claims enable row level security;

drop policy if exists "Equipo puede consultar reclamos" on public.supplier_claims;
drop policy if exists "Usuarios activos consultan reclamos" on public.supplier_claims;
create policy "Usuarios activos consultan reclamos"
on public.supplier_claims for select to authenticated
using (
  public.current_user_is_active()
  and (public.current_user_role() = 'admin' or agency = public.current_user_agency())
);

drop policy if exists "Equipo puede crear reclamos" on public.supplier_claims;
drop policy if exists "Operadores crean reclamos" on public.supplier_claims;
create policy "Operadores crean reclamos"
on public.supplier_claims for insert to authenticated
with check (
  public.current_user_is_active()
  and public.current_user_role() in ('admin', 'operador')
  and created_by = auth.uid()
  and (public.current_user_role() = 'admin' or agency = public.current_user_agency())
);

drop policy if exists "Equipo puede actualizar reclamos" on public.supplier_claims;
drop policy if exists "Operadores actualizan reclamos" on public.supplier_claims;
create policy "Operadores actualizan reclamos"
on public.supplier_claims for update to authenticated
using (
  public.current_user_is_active()
  and public.current_user_role() in ('admin', 'operador')
  and (public.current_user_role() = 'admin' or agency = public.current_user_agency())
)
with check (
  public.current_user_is_active()
  and public.current_user_role() in ('admin', 'operador')
  and (public.current_user_role() = 'admin' or agency = public.current_user_agency())
);

drop policy if exists "Equipo puede eliminar reclamos" on public.supplier_claims;
drop policy if exists "Administrador elimina reclamos" on public.supplier_claims;
create policy "Administrador elimina reclamos"
on public.supplier_claims for delete to authenticated
using (public.current_user_is_active() and public.current_user_role() = 'admin');

-- 3. Almacenamiento privado de fotografías
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'evidencias',
  'evidencias',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Equipo puede ver evidencias" on storage.objects;
drop policy if exists "Usuarios activos ven evidencias" on storage.objects;
create policy "Usuarios activos ven evidencias"
on storage.objects for select to authenticated
using (bucket_id = 'evidencias' and public.current_user_is_active());

drop policy if exists "Equipo puede subir evidencias" on storage.objects;
drop policy if exists "Operadores suben evidencias" on storage.objects;
create policy "Operadores suben evidencias"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'evidencias'
  and public.current_user_is_active()
  and public.current_user_role() in ('admin', 'operador')
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Equipo puede eliminar evidencias" on storage.objects;
drop policy if exists "Propietario o administrador elimina evidencias" on storage.objects;
create policy "Propietario o administrador elimina evidencias"
on storage.objects for delete to authenticated
using (
  bucket_id = 'evidencias'
  and public.current_user_is_active()
  and (
    public.current_user_role() = 'admin'
    or (storage.foldername(name))[1] = auth.uid()::text
  )
);

grant usage on schema public to authenticated;
grant select, update on public.user_profiles to authenticated;
grant select, insert, update, delete on public.supplier_claims to authenticated;

-- 4. Catálogo existente de códigos
-- La app solo necesita leer código, código de barras y descripción.
-- Si la tabla tiene RLS activo, esta política permite la consulta a usuarios activos.
do $$
begin
  if to_regclass('public.codigos') is not null then
    execute 'alter table public.codigos enable row level security';
    execute 'revoke select on public.codigos from anon';
    execute 'grant select (codigo, codigo_barra, descripcion) on public.codigos to authenticated';
    execute 'drop policy if exists "Usuarios activos consultan catalogo" on public.codigos';
    execute 'create policy "Usuarios activos consultan catalogo" on public.codigos for select to authenticated using (public.current_user_is_active())';
  end if;
end;
$$;

-- Listo: vuelve a la app, pega Project URL y la clave publishable/anon,
-- crea la primera cuenta y luego administra colaboradores desde Usuarios.
