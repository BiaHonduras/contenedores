begin;
create schema if not exists bia_private;
revoke all on schema bia_private from public, anon, authenticated;
create table if not exists bia_private.management_counters (
 agency text primary key, last_number bigint not null check(last_number >= 0)
);
alter table bia_private.management_counters enable row level security;
alter table public.supplier_claims add column if not exists management_number text;
-- Preserve legacy claim_number and assign stable management IDs to existing receipts.
with numbered as (
 select id,agency,row_number() over(partition by agency order by created_at,id) as n
 from public.supplier_claims
) update public.supplier_claims c
set management_number='RP-BIAHN-'||n.agency||'-'||lpad(n.n::text,5,'0')
from numbered n where c.id=n.id and c.management_number is null;
insert into bia_private.management_counters(agency,last_number)
select agency,max(substring(management_number from '[0-9]+$')::bigint)
from public.supplier_claims group by agency
on conflict(agency) do update set last_number=greatest(management_counters.last_number,excluded.last_number);
create unique index if not exists supplier_claims_management_number_key on public.supplier_claims(management_number);
create or replace function bia_private.assign_management_number()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
declare n bigint; existing_number text; existing_agency text;
begin
 if auth.uid() is null or not public.current_user_is_active()
    or public.current_user_role() not in ('admin','operador') then
   raise exception 'Usuario sin permiso para guardar gestiones' using errcode='42501';
 end if;
 if public.current_user_role()<>'admin' and new.agency<>public.current_user_agency() then
   raise exception 'La sede no corresponde al usuario' using errcode='42501';
 end if;
 if tg_op='UPDATE' then
   if new.agency<>old.agency then raise exception 'La sede de una gestión guardada no se puede modificar'; end if;
   new.management_number:=old.management_number;
   new.created_by:=old.created_by;
   return new;
 end if;
 -- UPSERT executes BEFORE INSERT even when the UUID already exists.
 select management_number,agency into existing_number,existing_agency from public.supplier_claims where id=new.id;
 if found then
   if new.agency<>existing_agency then raise exception 'La sede de una gestión guardada no se puede modificar'; end if;
   new.management_number:=existing_number;
   return new;
 end if;
 insert into bia_private.management_counters(agency,last_number) values(new.agency,1)
 on conflict(agency) do update set last_number=management_counters.last_number+1
 returning last_number into n;
 new.management_number:='RP-BIAHN-'||new.agency||'-'||case when n<100000 then lpad(n::text,5,'0') else n::text end;
 return new;
end $$;
revoke all on function bia_private.assign_management_number() from public,anon,authenticated;
drop trigger if exists supplier_claims_management_number on public.supplier_claims;
create trigger supplier_claims_management_number before insert or update on public.supplier_claims
for each row execute function bia_private.assign_management_number();
alter table public.supplier_claims alter column management_number set not null;
commit;
