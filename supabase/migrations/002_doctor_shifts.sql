-- Migration 002: Gestión de jornadas de atención médica y turnos de 30 minutos
-- CitaCloud. Ejecutar en el SQL Editor de Supabase sobre una base de datos con la migración 001 aplicada.

-- 1. Tabla de jornadas de atención
create table if not exists public.doctor_shifts (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  work_date date not null,
  shift_type text not null default 'custom' check (shift_type in ('full_day','half_day','custom')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  break_starts_at timestamptz,
  break_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (
    (break_starts_at is null and break_ends_at is null) or
    (break_starts_at is not null and break_ends_at is not null and break_ends_at > break_starts_at and break_starts_at >= starts_at and break_ends_at <= ends_at)
  )
);

create index if not exists doctor_shifts_doctor_date_idx on public.doctor_shifts(doctor_id, work_date);
create index if not exists doctor_shifts_doctor_range_idx on public.doctor_shifts(doctor_id, starts_at, ends_at);

-- 2. Vincular los turnos a la jornada correspondiente de forma no destructiva
alter table public.schedule_slots
  add column if not exists shift_id uuid references public.doctor_shifts(id) on delete set null;

create index if not exists slots_shift_idx on public.schedule_slots(shift_id);

-- 3. Migración de datos existentes: conservar turnos y citas existentes creando jornadas agrupadas
insert into public.doctor_shifts (doctor_id, work_date, shift_type, starts_at, ends_at)
select
  s.doctor_id,
  (s.starts_at at time zone 'America/Lima')::date as work_date,
  'custom' as shift_type,
  min(s.starts_at) as starts_at,
  max(s.ends_at) as ends_at
from public.schedule_slots s
where s.shift_id is null
  and not exists (
    select 1 from public.doctor_shifts sh
    where sh.doctor_id = s.doctor_id
      and sh.work_date = (s.starts_at at time zone 'America/Lima')::date
  )
group by s.doctor_id, (s.starts_at at time zone 'America/Lima')::date
on conflict do nothing;

update public.schedule_slots s
set shift_id = sh.id
from public.doctor_shifts sh
where s.shift_id is null
  and s.doctor_id = sh.doctor_id
  and (s.starts_at at time zone 'America/Lima')::date = sh.work_date
  and s.starts_at >= sh.starts_at and s.ends_at <= sh.ends_at;

-- 4. Seguridad RLS
alter table public.doctor_shifts enable row level security;

-- Política de lectura: cualquier usuario autenticado puede consultar las jornadas para verificar disponibilidad
drop policy if exists shifts_read on public.doctor_shifts;
create policy shifts_read on public.doctor_shifts for select to authenticated using (true);

-- Permisos sobre la tabla
revoke all on public.doctor_shifts from anon, authenticated;
grant usage on schema public to authenticated;
grant select on public.doctor_shifts to authenticated;

-- 5. Función para crear o modificar jornadas de atención y generar turnos de 30 minutos
create or replace function public.save_doctor_shift(
  p_doctor_id uuid,
  p_work_date date,
  p_shift_type text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_break_starts_at timestamptz default null,
  p_break_ends_at timestamptz default null,
  p_shift_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_doctor_profile_id uuid;
  v_shift_id uuid;
  v_curr timestamptz;
  v_next timestamptz;
  v_has_break boolean := false;
  v_in_break boolean;
  v_conflict_starts timestamptz;
  v_count_slots int := 0;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión';
  end if;

  if not public.staff_aal2() then
    raise exception 'Se requiere autenticación de dos factores (AAL2) para gestionar jornadas';
  end if;

  select public.app_role() into v_role;
  select profile_id into v_doctor_profile_id from public.doctors where id = p_doctor_id and active;
  if not found then
    raise exception 'Médico no encontrado o inactivo';
  end if;

  if v_role = 'admin' then
    null;
  elsif v_role = 'doctor' and v_doctor_profile_id = auth.uid() then
    null;
  else
    raise exception 'Sin permiso para gestionar esta jornada';
  end if;

  -- Serializar cambios de jornadas del mismo médico.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_doctor_id::text, 0));

  if p_shift_type not in ('full_day', 'half_day', 'custom') then
    raise exception 'Tipo de jornada no válido';
  end if;

  if p_starts_at >= p_ends_at then
    raise exception 'La hora de inicio debe ser anterior a la hora de fin';
  end if;

  if p_ends_at - p_starts_at < interval '30 minutes' then
    raise exception 'La jornada debe tener una duración mínima de 30 minutos';
  end if;

  if p_work_date is distinct from (p_starts_at at time zone 'America/Lima')::date
     or p_work_date is distinct from ((p_ends_at - interval '1 microsecond') at time zone 'America/Lima')::date then
    raise exception 'El horario debe estar dentro de la fecha de jornada en Lima';
  end if;

  if p_work_date < (now() at time zone 'America/Lima')::date then
    raise exception 'No puedes registrar o modificar jornadas en fechas pasadas';
  end if;

  -- Validar descanso
  if p_break_starts_at is not null or p_break_ends_at is not null then
    if p_break_starts_at is null or p_break_ends_at is null then
      raise exception 'El descanso debe incluir hora de inicio y fin';
    end if;
    if p_break_ends_at <= p_break_starts_at then
      raise exception 'El fin del descanso debe ser posterior al inicio';
    end if;
    if p_break_starts_at < p_starts_at or p_break_ends_at > p_ends_at then
      raise exception 'El descanso debe estar dentro del horario de la jornada';
    end if;
    v_has_break := true;
  end if;

  -- Evitar jornadas superpuestas para el mismo médico
  if exists (
    select 1 from public.doctor_shifts
    where doctor_id = p_doctor_id
      and id <> coalesce(p_shift_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and (starts_at < p_ends_at and ends_at > p_starts_at)
  ) then
    raise exception 'Ya existe una jornada superpuesta en ese rango de horario para este médico';
  end if;

  -- Esperar reservas concurrentes antes de comprobar o cambiar sus turnos.
  perform 1 from public.schedule_slots s
  where s.doctor_id = p_doctor_id
    and (s.shift_id = p_shift_id or
      (s.shift_id is null and s.starts_at >= p_starts_at and s.ends_at <= p_ends_at))
  for update of s;

  -- Proteger citas confirmadas si se modifica una jornada
  if p_shift_id is not null then
    if not exists (select 1 from public.doctor_shifts where id = p_shift_id and doctor_id = p_doctor_id) then
      raise exception 'Jornada no encontrada';
    end if;

    select s.starts_at into v_conflict_starts
    from public.schedule_slots s
    join public.appointments a on a.slot_id = s.id
    where s.doctor_id = p_doctor_id
      and (s.shift_id = p_shift_id or
        (s.shift_id is null and s.starts_at >= p_starts_at and s.ends_at <= p_ends_at))
      and a.status = 'confirmed'
      and (
        s.starts_at < p_starts_at
        or s.ends_at > p_ends_at
        or (v_has_break and s.starts_at < p_break_ends_at and s.ends_at > p_break_starts_at)
      )
    limit 1;

    if v_conflict_starts is not null then
      raise exception 'No se puede modificar la jornada: existe una cita confirmada a las % que quedaría fuera del nuevo horario o en el descanso. Gestiona esa cita antes de modificar la jornada.',
        to_char(v_conflict_starts at time zone 'America/Lima', 'HH24:MI');
    end if;
  end if;

  -- Insertar o actualizar doctor_shifts
  if p_shift_id is not null then
    update public.doctor_shifts set
      work_date = p_work_date,
      shift_type = p_shift_type,
      starts_at = p_starts_at,
      ends_at = p_ends_at,
      break_starts_at = p_break_starts_at,
      break_ends_at = p_break_ends_at,
      updated_at = now()
    where id = p_shift_id;
    v_shift_id := p_shift_id;

    insert into public.audit_logs(actor_id, action, target_type, target_id)
    values (auth.uid(), 'shift.updated', 'shift', v_shift_id::text);
  else
    insert into public.doctor_shifts (doctor_id, work_date, shift_type, starts_at, ends_at, break_starts_at, break_ends_at)
    values (p_doctor_id, p_work_date, p_shift_type, p_starts_at, p_ends_at, p_break_starts_at, p_break_ends_at)
    returning id into v_shift_id;

    insert into public.audit_logs(actor_id, action, target_type, target_id)
    values (auth.uid(), 'shift.created', 'shift', v_shift_id::text);
  end if;

  -- Generar turnos de 30 minutos
  drop table if exists _new_slots;
  create temporary table _new_slots (
    starts_at timestamptz primary key,
    ends_at timestamptz not null
  ) on commit drop;

  v_curr := p_starts_at;
  while v_curr + interval '30 minutes' <= p_ends_at loop
    v_next := v_curr + interval '30 minutes';
    v_in_break := false;
    if v_has_break and (v_curr < p_break_ends_at and v_next > p_break_starts_at) then
      v_in_break := true;
    end if;
    if not v_in_break then
      insert into _new_slots(starts_at, ends_at) values (v_curr, v_next);
      v_count_slots := v_count_slots + 1;
    end if;
    v_curr := v_next;
  end loop;

  if v_count_slots = 0 then
    raise exception 'No se pudo generar ningún turno de 30 minutos dentro del horario y descanso definidos';
  end if;

  -- Una cita debe coincidir exactamente con un turno generado, no solo estar
  -- dentro de los extremos de la nueva jornada.
  select s.starts_at into v_conflict_starts
  from public.schedule_slots s
  join public.appointments a on a.slot_id = s.id and a.status = 'confirmed'
  where s.doctor_id = p_doctor_id
    and (s.shift_id = v_shift_id or
      (s.shift_id is null and s.starts_at >= p_starts_at and s.ends_at <= p_ends_at))
    and not exists (
      select 1 from _new_slots n where n.starts_at = s.starts_at and n.ends_at = s.ends_at
    )
  limit 1;
  if v_conflict_starts is not null then
    raise exception 'No se puede modificar la jornada: la cita confirmada de las % no coincide con los nuevos turnos de 30 minutos.',
      to_char(v_conflict_starts at time zone 'America/Lima', 'HH24:MI');
  end if;

  -- Eliminar turnos que ya no pertenecen al rango y que NO tienen citas
  delete from public.schedule_slots
  where doctor_id = p_doctor_id
    and (shift_id = v_shift_id or
      (shift_id is null and starts_at >= p_starts_at and ends_at <= p_ends_at))
    and starts_at not in (select starts_at from _new_slots)
    and not exists (select 1 from public.appointments a where a.slot_id = schedule_slots.id);

  -- Conservar el historial de citas canceladas sin volver a ofrecer esos turnos.
  update public.schedule_slots s set shift_id = null
  where s.doctor_id = p_doctor_id
    and (s.shift_id = v_shift_id or
      (s.shift_id is null and s.starts_at >= p_starts_at and s.ends_at <= p_ends_at))
    and not exists (select 1 from _new_slots n where n.starts_at = s.starts_at and n.ends_at = s.ends_at)
    and not exists (select 1 from public.appointments a where a.slot_id = s.id and a.status = 'confirmed');

  if exists (
    select 1 from public.schedule_slots s
    join _new_slots n on n.starts_at = s.starts_at
    where s.doctor_id = p_doctor_id and s.ends_at <> n.ends_at
      and exists (select 1 from public.appointments a where a.slot_id = s.id)
  ) then
    raise exception 'Un turno histórico tiene una duración distinta. Gestiona ese turno antes de cambiar la jornada.';
  end if;

  -- Insertar o asociar turnos de 30 minutos generados
  insert into public.schedule_slots (doctor_id, starts_at, ends_at, shift_id)
  select p_doctor_id, n.starts_at, n.ends_at, v_shift_id
  from _new_slots n
  on conflict (doctor_id, starts_at) do update
    set ends_at = excluded.ends_at,
        shift_id = v_shift_id;

  return v_shift_id;
end $$;

-- 6. Función para eliminar jornadas de atención médica protegiendo citas confirmadas
create or replace function public.delete_doctor_shift(p_shift_id uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_doctor_profile_id uuid;
  v_shift public.doctor_shifts%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión';
  end if;

  if not public.staff_aal2() then
    raise exception 'Se requiere autenticación de dos factores (AAL2) para eliminar jornadas';
  end if;

  select * into v_shift from public.doctor_shifts where id = p_shift_id;
  if not found then
    raise exception 'Jornada no encontrada';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_shift.doctor_id::text, 0));

  -- Las reservas bloquean cada turno; esperar su finalización antes de borrar.
  perform 1 from public.schedule_slots s where s.shift_id = p_shift_id for update of s;

  select public.app_role() into v_role;
  select profile_id into v_doctor_profile_id from public.doctors where id = v_shift.doctor_id and active;

  if v_role = 'admin' then
    null;
  elsif v_role = 'doctor' and v_doctor_profile_id = auth.uid() then
    null;
  else
    raise exception 'Sin permiso para eliminar esta jornada';
  end if;

  -- Proteger citas confirmadas
  if exists (
    select 1 from public.appointments a
    join public.schedule_slots s on s.id = a.slot_id
    where s.shift_id = p_shift_id and a.status = 'confirmed'
  ) then
    raise exception 'No se puede eliminar la jornada porque tiene citas confirmadas. Cancela o gestiona las citas primero.';
  end if;

  -- Eliminar turnos sin citas asociadas
  delete from public.schedule_slots
  where shift_id = p_shift_id
    and not exists (select 1 from public.appointments a where a.slot_id = schedule_slots.id);

  -- Si quedaron turnos históricos desvincularlos de la jornada
  update public.schedule_slots set shift_id = null where shift_id = p_shift_id;

  delete from public.doctor_shifts where id = p_shift_id;

  insert into public.audit_logs(actor_id, action, target_type, target_id)
  values (auth.uid(), 'shift.deleted', 'shift', p_shift_id::text);
end $$;

-- 7. La reserva solo acepta turnos de 30 minutos pertenecientes a una jornada vigente.
create or replace function public.book_slot(p_slot_id uuid, p_patient_id uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_patient uuid; v_slot public.schedule_slots%rowtype; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  v_patient := coalesce(p_patient_id, auth.uid());
  if v_patient <> auth.uid() and not (public.app_role() in ('admin','reception') and public.staff_aal2()) then
    raise exception 'No puedes reservar para otra persona';
  end if;
  if not exists(select 1 from public.profiles where id = v_patient and role = 'patient') then
    raise exception 'Selecciona un paciente válido';
  end if;
  select s.* into v_slot from public.schedule_slots s
  join public.doctors d on d.id = s.doctor_id and d.active
  where s.id = p_slot_id for update of s;
  if not found or v_slot.starts_at <= now() or v_slot.shift_id is null
     or v_slot.ends_at <> v_slot.starts_at + interval '30 minutes' then
    raise exception 'Horario no disponible';
  end if;
  if not exists (
    select 1 from public.doctor_shifts sh
    where sh.id = v_slot.shift_id and sh.doctor_id = v_slot.doctor_id
      and (v_slot.starts_at at time zone 'America/Lima')::date = sh.work_date
      and v_slot.starts_at >= sh.starts_at and v_slot.ends_at <= sh.ends_at
      and (sh.break_starts_at is null or v_slot.ends_at <= sh.break_starts_at or v_slot.starts_at >= sh.break_ends_at)
  ) then raise exception 'Horario no disponible'; end if;
  if exists(select 1 from public.appointments where slot_id = p_slot_id and status <> 'cancelled') then
    raise exception 'Este horario ya está reservado';
  end if;
  insert into public.appointments(slot_id, patient_id) values (p_slot_id, v_patient) returning id into v_id;
  return v_id;
end $$;

-- La pantalla ya publica jornadas completas; deshabilitar la antigua API de
-- intervalos libres, que podría ofrecer turnos de varias horas.
revoke all on function public.admin_add_slot(uuid,timestamptz,timestamptz) from public, authenticated;

-- 8. Permisos de ejecución
revoke all on function public.save_doctor_shift(uuid,date,text,timestamptz,timestamptz,timestamptz,timestamptz,uuid) from public;
grant execute on function public.save_doctor_shift(uuid,date,text,timestamptz,timestamptz,timestamptz,timestamptz,uuid) to authenticated;

revoke all on function public.delete_doctor_shift(uuid) from public;
grant execute on function public.delete_doctor_shift(uuid) to authenticated;

revoke all on function public.book_slot(uuid,uuid) from public;
grant execute on function public.book_slot(uuid,uuid) to authenticated;
