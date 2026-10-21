begin;
-- Shared identity: auth.users. Shared site access: public.usuarios_sedes.
-- public.usuarios keeps the existing numeric IDs used by Devoluciones records.
alter table public.usuarios_sedes drop constraint if exists usuarios_sedes_rol_check;
alter table public.usuarios_sedes add constraint usuarios_sedes_rol_check check(rol in ('admin','operador','consulta'));
insert into public.usuarios_sedes(user_id,email,nombre,sede,rol,activo)
select p.id,p.email,p.full_name,p.agency,p.role,p.is_active from public.user_profiles p
where exists(select 1 from auth.users a where a.id=p.id)
on conflict(user_id,sede) do nothing;

create schema if not exists bia_identity_private;
revoke all on schema bia_identity_private from public,anon,authenticated;
create or replace function bia_identity_private.sync_identity(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_email text; v_name text; v_site text; v_active boolean; v_user integer;
begin
 select lower(a.email) into v_email from auth.users a where a.id=p_id;
 if v_email is null then return; end if;
 select s.nombre,d.nombre into v_name,v_site from public.usuarios_sedes s
 left join public.sedes d on d.codigo=s.sede where s.user_id=p_id
 order by s.activo desc,s.created_at,s.sede limit 1;
 select exists(select 1 from public.usuarios_sedes where user_id=p_id and activo) into v_active;
 select id into v_user from public.usuarios where auth_user_id=p_id;
 if v_user is null then
  select id into v_user from public.usuarios where lower(correo)=v_email and auth_user_id is null order by id limit 1;
 end if;
 if v_user is null then
  insert into public.usuarios(usuario,correo,rol,nombre_corto,sede,auth_user_id,activo)
  values('bia_'||replace(p_id::text,'-',''),v_email,'user',coalesce(v_name,v_email),v_site,p_id,v_active);
 else
  update public.usuarios set auth_user_id=p_id,correo=v_email,nombre_corto=coalesce(nullif(v_name,''),nombre_corto),
   sede=coalesce(v_site,sede),activo=v_active where id=v_user;
 end if;
end $$;
revoke all on function bia_identity_private.sync_identity(uuid) from public,anon,authenticated;
create or replace function bia_identity_private.sync_access() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform bia_identity_private.sync_identity(case when TG_OP='DELETE' then old.user_id else new.user_id end);
 return null;
end $$;
revoke all on function bia_identity_private.sync_access() from public,anon,authenticated;
drop trigger if exists bia_shared_identity on public.usuarios_sedes;
create trigger bia_shared_identity after insert or update or delete on public.usuarios_sedes
for each row execute function bia_identity_private.sync_access();
do $$declare v uuid; begin for v in select distinct user_id from public.usuarios_sedes loop
 perform bia_identity_private.sync_identity(v); end loop; end $$;

create or replace function public.bia_profile(p_sede text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s public.usuarios_sedes; a auth.users; v_master boolean;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into a from auth.users where id=auth.uid();
 if not public.usuario_password_actualizada() then raise exception 'CAMBIO_PASSWORD_REQUERIDO'; end if;
 v_master:=public.usuario_es_maestro();
 select * into s from public.usuarios_sedes where user_id=auth.uid()
 order by activo desc,(sede=upper(coalesce(p_sede,''))) desc,case sede when 'SPS' then 0 else 1 end,sede limit 1;
 return jsonb_build_object('id',a.id,'email',a.email,'full_name',coalesce(s.nombre,a.raw_user_meta_data->>'nombre',a.raw_user_meta_data->>'full_name',''),
 'employee_code','','role',case when v_master then 'admin' else coalesce(s.rol,'consulta') end,
 'agency',coalesce(s.sede,'SPS'),'is_active',v_master or coalesce(s.activo,false),
 'is_master',v_master,'sedes',public.obtener_sedes_usuario(),'created_at',a.created_at,'updated_at',s.updated_at);
end $$;
create or replace function public.bia_list_users() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',s.user_id,'email',s.email,'full_name',s.nombre,
 'employee_code','','role',s.rol,'agency',s.sede,'is_active',s.activo,'created_at',s.created_at,'updated_at',s.updated_at)
 order by s.email,s.sede),'[]'::jsonb)
 from public.usuarios_sedes s where auth.uid() is not null and public.usuario_es_admin_sede(s.sede);
$$;
create or replace function public.bia_update_access(p_user_id uuid,p_sede text,p_role text,p_active boolean,p_name text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.usuario_es_admin_sede(p_sede) then raise exception 'SOLO_ADMINISTRADOR_SEDE'; end if;
 if p_role not in ('admin','operador','consulta') then raise exception 'ROL_INVALIDO'; end if;
 if p_user_id=auth.uid() and (not p_active or p_role<>'admin') then raise exception 'NO_PUEDE_RETIRAR_SU_PROPIO_ACCESO'; end if;
 update public.usuarios_sedes set rol=p_role,activo=p_active,nombre=nullif(trim(p_name),''),updated_at=now()
 where user_id=p_user_id and sede=upper(p_sede);
 if not found then raise exception 'ACCESO_NO_ENCONTRADO'; end if;
 return true;
end $$;
revoke all on function public.bia_profile(text),public.bia_list_users(),public.bia_update_access(uuid,text,text,boolean,text) from public,anon;
grant execute on function public.bia_profile(text),public.bia_list_users(),public.bia_update_access(uuid,text,text,boolean,text) to authenticated;
-- Contenedores policies now consult the shared access table, including site scope.
create or replace function public.current_user_is_active() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.usuario_password_actualizada() and (public.usuario_es_maestro() or exists(select 1 from public.usuarios_sedes where user_id=auth.uid() and activo)); $$;
create or replace function public.current_user_role() returns text language sql stable security definer set search_path='' as $$
 select case when public.usuario_es_maestro() then 'admin' else (select rol from public.usuarios_sedes where user_id=auth.uid() and activo order by case rol when 'admin' then 0 when 'operador' then 1 else 2 end limit 1) end; $$;
create or replace function public.current_user_agency() returns text language sql stable security definer set search_path='' as $$
 select sede from public.usuarios_sedes where user_id=auth.uid() and activo order by case sede when 'SPS' then 0 else 1 end,sede limit 1; $$;
drop policy if exists "Usuarios activos consultan reclamos" on public.supplier_claims;
create policy "Usuarios activos consultan reclamos" on public.supplier_claims for select to authenticated using(public.usuario_puede_sede(agency));
drop policy if exists "Operadores crean reclamos" on public.supplier_claims;
create policy "Operadores crean reclamos" on public.supplier_claims for insert to authenticated with check(created_by=auth.uid() and public.usuario_password_actualizada() and (public.usuario_es_maestro() or exists(select 1 from public.usuarios_sedes s where s.user_id=auth.uid() and s.sede=agency and s.activo and s.rol in ('admin','operador'))));
drop policy if exists "Operadores actualizan reclamos" on public.supplier_claims;
create policy "Operadores actualizan reclamos" on public.supplier_claims for update to authenticated using(public.usuario_password_actualizada() and (public.usuario_es_maestro() or exists(select 1 from public.usuarios_sedes s where s.user_id=auth.uid() and s.sede=agency and s.activo and s.rol in ('admin','operador')))) with check(public.usuario_password_actualizada() and (public.usuario_es_maestro() or exists(select 1 from public.usuarios_sedes s where s.user_id=auth.uid() and s.sede=agency and s.activo and s.rol in ('admin','operador'))));
drop policy if exists "Administrador elimina reclamos" on public.supplier_claims;
create policy "Administrador elimina reclamos" on public.supplier_claims for delete to authenticated using(public.usuario_es_admin_sede(agency));
-- No legacy profile may be used to grant access independently.
revoke insert,update,delete on public.user_profiles from authenticated,anon;
create or replace function public.master_asignar_usuario_existente(p_email text,p_nombre text,p_sede text,p_rol text,p_puede_cierre boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_email text:=lower(trim(p_email)); v_sede text:=upper(p_sede);
begin
 if auth.uid() is null or not public.usuario_es_admin_sede(v_sede) then raise exception 'SOLO_ADMINISTRADOR_SEDE'; end if;
 if v_sede not in ('SPS','CBA','SRC','TGU','AMT') then raise exception 'SEDE_INVALIDA'; end if;
 if p_rol not in ('admin','operador','consulta') then raise exception 'ROL_INVALIDO'; end if;
 select id into v_id from auth.users where lower(email)=v_email;
 if v_id is null then raise exception 'USUARIO_AUTH_NO_EXISTE_USE_CONTRASENA'; end if;
 insert into public.usuarios_sedes(user_id,email,nombre,sede,rol,puede_cierre_dia,activo,updated_at)
 values(v_id,v_email,nullif(trim(coalesce(p_nombre,'')),''),v_sede,p_rol,coalesce(p_puede_cierre,false),true,now())
 on conflict(user_id,sede) do update set email=excluded.email,nombre=coalesce(excluded.nombre,public.usuarios_sedes.nombre),rol=excluded.rol,puede_cierre_dia=excluded.puede_cierre_dia,activo=true,updated_at=now();
 return true;
end $$;
revoke all on function public.master_asignar_usuario_existente(text,text,text,text,boolean) from public,anon;
grant execute on function public.master_asignar_usuario_existente(text,text,text,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
