const {PGlite}=require(process.env.BIA_PGLITE_MODULE||'@electric-sql/pglite');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
(async()=>{const db=new PGlite();await db.exec(`
create role anon; create role authenticated; create schema auth;
create table auth.users(id uuid primary key,email text,raw_app_meta_data jsonb default '{}',raw_user_meta_data jsonb default '{}',created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.sedes(codigo text primary key,nombre text);
insert into public.sedes values ('SPS','San Pedro Sula'),('TGU','Tegucigalpa');
create table public.usuarios(id serial primary key,usuario text unique,correo text unique,rol text,nombre_corto text,sede text,auth_user_id uuid unique,activo boolean);
create table public.usuarios_sedes(id uuid default gen_random_uuid(),user_id uuid references auth.users,sede text,email text,nombre text,rol text,activo boolean,puede_cierre_dia boolean default false,created_at timestamptz default now(),updated_at timestamptz default now(),unique(user_id,sede),constraint usuarios_sedes_rol_check check(rol in ('admin','consulta')));
grant select on public.usuarios_sedes to authenticated;
create table public.user_profiles(id uuid,email text,full_name text,agency text,role text,is_active boolean);
create table public.supplier_claims(id uuid default gen_random_uuid(),agency text,created_by uuid);alter table public.supplier_claims enable row level security;
grant usage on schema public,auth to authenticated,anon;grant select,insert,update,delete on public.supplier_claims to authenticated,anon;
create function public.usuario_password_actualizada() returns boolean language sql stable security definer as $$select exists(select 1 from auth.users where id=auth.uid() and coalesce(raw_app_meta_data->>'must_change_password','false')<>'true')$$;
create function public.usuario_es_maestro() returns boolean language sql stable security definer as $$select public.usuario_password_actualizada() and exists(select 1 from auth.users where id=auth.uid() and email='master@example.test')$$;
create function public.usuario_es_admin_sede(p_sede text) returns boolean language sql stable security definer as $$select public.usuario_password_actualizada() and (public.usuario_es_maestro() or exists(select 1 from public.usuarios_sedes where user_id=auth.uid() and sede=upper(p_sede) and activo and rol='admin'))$$;
create function public.usuario_puede_sede(p_sede text) returns boolean language sql stable security definer as $$select public.usuario_password_actualizada() and (public.usuario_es_maestro() or exists(select 1 from public.usuarios_sedes where user_id=auth.uid() and sede=upper(p_sede) and activo))$$;
create function public.obtener_sedes_usuario() returns text[] language sql stable security definer as $$select array(select sede from public.usuarios_sedes where user_id=auth.uid() and activo)$$;
insert into auth.users(id,email) values ('00000000-0000-0000-0000-000000000001','admin@example.test'),('00000000-0000-0000-0000-000000000002','operator@example.test'),('00000000-0000-0000-0000-000000000003','viewer@example.test');
insert into public.usuarios_sedes(user_id,email,nombre,sede,rol,activo) values ('00000000-0000-0000-0000-000000000001','admin@example.test','Admin','SPS','admin',true),('00000000-0000-0000-0000-000000000003','viewer@example.test','Viewer','SPS','consulta',true);
insert into public.user_profiles values ('00000000-0000-0000-0000-000000000002','operator@example.test','Operator','TGU','operador',true);
`);
const sql=fs.readFileSync(path.join(__dirname,'../database/usuarios_compartidos.sql'),'utf8');await db.exec(sql);await db.exec(sql); // reruns preserve identities and roles
assert.equal((await db.query('select count(*)::int n from usuarios')).rows[0].n,3);
assert.equal((await db.query('select count(*)::int n from usuarios_sedes')).rows[0].n,3);
async function as(id,role='authenticated'){await db.exec(`reset role;set role ${role};select set_config('request.jwt.claim.sub','${id}',false);`)}
await as('00000000-0000-0000-0000-000000000002');let profile=(await db.query('select bia_profile() p')).rows[0].p;assert.equal(profile.role,'operador');assert.equal(profile.agency,'TGU');
assert.equal((await db.query('select bia_list_users() p')).rows[0].p.length,0);
await assert.rejects(()=>db.query("select bia_update_access('00000000-0000-0000-0000-000000000003','SPS','admin',true,'Viewer')"),/SOLO_ADMINISTRADOR/);
await db.query("insert into supplier_claims(agency,created_by) values('TGU',auth.uid())");
await assert.rejects(()=>db.query("insert into supplier_claims(agency,created_by) values('SPS',auth.uid())"),/row-level security/);
await as('00000000-0000-0000-0000-000000000003');await assert.rejects(()=>db.query("insert into supplier_claims(agency,created_by) values('SPS',auth.uid())"),/row-level security/);
await as('00000000-0000-0000-0000-000000000001');assert.equal((await db.query('select bia_list_users() p')).rows[0].p.length,2);
await db.query("select bia_update_access('00000000-0000-0000-0000-000000000003','SPS','consulta',false,'Viewer Updated')");
await db.exec('reset role');assert.equal((await db.query("select activo from usuarios where correo='viewer@example.test'")).rows[0].activo,false);
await as('','anon');await assert.rejects(()=>db.query('select bia_profile()'),/permission denied/);await assert.rejects(()=>db.query("insert into supplier_claims(agency,created_by) values('SPS',null)"),/row-level security/);
console.log('PASS shared identity: idempotent migration, legacy backfill, role preservation, shared deactivation, site scope, operator write, viewer/anonymous denial, non-admin authorization');await db.close();})().catch(e=>{console.error(e);process.exitCode=1});
