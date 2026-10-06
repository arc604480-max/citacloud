-- CitaCloud. Ejecutar una vez en SQL Editor de Supabase.
create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Usuario',
  role text not null default 'patient' check (role in ('patient','doctor','reception','admin')),
  created_at timestamptz not null default now()
);
create table public.specialties (
  id bigint generated always as identity primary key,
  name text not null unique
);
create table public.doctors (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id),
  specialty_id bigint not null references public.specialties(id),
  active boolean not null default true
);
create table public.schedule_slots (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  check (ends_at > starts_at),
  unique (doctor_id, starts_at)
);
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references public.schedule_slots(id),
  patient_id uuid not null references public.profiles(id),
  status text not null default 'confirmed' check (status in ('confirmed','cancelled','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index one_active_appointment_per_slot on public.appointments(slot_id) where status <> 'cancelled';
create index appointments_patient_idx on public.appointments(patient_id, created_at desc);
create index slots_doctor_start_idx on public.schedule_slots(doctor_id, starts_at);
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  target_type text not null,
  target_id text,
  created_at timestamptz not null default now()
);
create table public.training_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  score int not null check (score between 0 and 3),
  completed_at timestamptz not null default now()
);

-- El registro público siempre empieza como paciente; nunca acepta un rol enviado por el navegador.
create function public.create_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name, role)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), 'Usuario'), 'patient');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.create_profile();

create function public.app_role() returns text language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = (select auth.uid())
$$;
create function public.staff_aal2() returns boolean language sql stable set search_path = '' as $$
  select (select auth.jwt()->>'aal') = 'aal2'
$$;
create function public.doctor_has_patient(p_patient uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.appointments a
    join public.schedule_slots s on s.id = a.slot_id
    join public.doctors d on d.id = s.doctor_id
    where a.patient_id = p_patient and d.profile_id = (select auth.uid())
  )
$$;

alter table public.profiles enable row level security;
alter table public.specialties enable row level security;
alter table public.doctors enable row level security;
alter table public.schedule_slots enable row level security;
alter table public.appointments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.training_results enable row level security;

create policy profiles_read on public.profiles for select to authenticated using (
  id = (select auth.uid()) or role = 'doctor'
  or (public.app_role() in ('admin','reception') and public.staff_aal2())
  or (public.app_role() = 'doctor' and public.staff_aal2() and public.doctor_has_patient(id))
);
create policy specialties_read on public.specialties for select to authenticated using (true);
create policy doctors_read on public.doctors for select to authenticated using (true);
create policy slots_read on public.schedule_slots for select to authenticated using (true);
create policy appointments_read on public.appointments for select to authenticated using (
  patient_id = (select auth.uid())
  or (public.app_role() in ('admin','reception') and public.staff_aal2())
  or (public.app_role() = 'doctor' and public.staff_aal2() and exists (
    select 1 from public.schedule_slots s join public.doctors d on d.id = s.doctor_id
    where s.id = slot_id and d.profile_id = (select auth.uid())
  ))
);
create policy audits_read on public.audit_logs for select to authenticated using (
  public.app_role() = 'admin' and public.staff_aal2()
);
create policy training_read on public.training_results for select to authenticated using (
  user_id = (select auth.uid()) or (public.app_role() = 'admin' and public.staff_aal2())
);
create policy training_insert on public.training_results for insert to authenticated with check (
  user_id = (select auth.uid()) and public.app_role() <> 'patient' and public.staff_aal2()
);

-- Se otorgan solo operaciones necesarias; las escrituras de citas van por funciones verificadas.
revoke all on public.profiles, public.specialties, public.doctors, public.schedule_slots,
  public.appointments, public.audit_logs, public.training_results from anon, authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles, public.specialties, public.doctors, public.schedule_slots,
  public.appointments, public.audit_logs, public.training_results to authenticated;
grant insert on public.training_results to authenticated;
grant usage on sequence public.audit_logs_id_seq to authenticated;

create function public.log_appointment() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs(actor_id, action, target_type, target_id)
  values (auth.uid(), case when tg_op = 'INSERT' then 'appointment.created' else 'appointment.' || new.status end,
    'appointment', new.id::text);
  return new;
end $$;
create trigger appointment_audit after insert or update of status on public.appointments
  for each row execute function public.log_appointment();

create function public.book_slot(p_slot_id uuid, p_patient_id uuid default null) returns uuid
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
  select s.* into v_slot from public.schedule_slots s join public.doctors d on d.id = s.doctor_id
    where s.id = p_slot_id and d.active for update of s;
  if not found or v_slot.starts_at <= now() then raise exception 'Horario no disponible'; end if;
  if exists(select 1 from public.appointments where slot_id = p_slot_id and status <> 'cancelled') then
    raise exception 'Este horario ya está reservado';
  end if;
  insert into public.appointments(slot_id, patient_id) values (p_slot_id, v_patient) returning id into v_id;
  return v_id;
end $$;

create function public.cancel_appointment(p_appointment_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_a public.appointments%rowtype; v_start timestamptz;
begin
  select * into v_a from public.appointments where id = p_appointment_id for update;
  if not found or v_a.status <> 'confirmed' then raise exception 'Cita no cancelable'; end if;
  if v_a.patient_id <> auth.uid() and not (public.app_role() in ('admin','reception') and public.staff_aal2()) then
    raise exception 'Sin permiso';
  end if;
  select starts_at into v_start from public.schedule_slots where id = v_a.slot_id;
  if v_start <= now() then raise exception 'No puedes cancelar una cita pasada'; end if;
  update public.appointments set status = 'cancelled', updated_at = now() where id = p_appointment_id;
end $$;

create function public.complete_appointment(p_appointment_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not (public.app_role() in ('doctor','admin') and public.staff_aal2()) then raise exception 'Sin permiso'; end if;
  update public.appointments a set status = 'completed', updated_at = now()
  from public.schedule_slots s join public.doctors d on d.id = s.doctor_id
  where a.id = p_appointment_id and a.slot_id = s.id and a.status = 'confirmed'
    and (public.app_role() = 'admin' or d.profile_id = auth.uid());
  if not found then raise exception 'Cita no disponible'; end if;
end $$;

create function public.admin_set_role(p_user_id uuid, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.app_role() <> 'admin' or not public.staff_aal2() then raise exception 'Sin permiso'; end if;
  if p_role not in ('patient','doctor','reception','admin') or p_user_id = auth.uid() then raise exception 'Cambio de rol no permitido'; end if;
  update public.profiles set role = p_role where id = p_user_id;
  if not found then raise exception 'Usuario inexistente'; end if;
  insert into public.audit_logs(actor_id,action,target_type,target_id) values(auth.uid(),'role.' || p_role,'profile',p_user_id::text);
end $$;

create function public.admin_add_doctor(p_profile_id uuid, p_specialty_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.app_role() <> 'admin' or not public.staff_aal2() then raise exception 'Sin permiso'; end if;
  if not exists(select 1 from public.profiles where id=p_profile_id and role='doctor') then raise exception 'Primero asigna el rol médico'; end if;
  insert into public.doctors(profile_id,specialty_id) values (p_profile_id,p_specialty_id);
  insert into public.audit_logs(actor_id,action,target_type,target_id) values(auth.uid(),'doctor.created','profile',p_profile_id::text);
end $$;

create function public.admin_add_slot(p_doctor_id uuid, p_starts_at timestamptz, p_ends_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if public.app_role() <> 'admin' or not public.staff_aal2() then raise exception 'Sin permiso'; end if;
  if p_starts_at <= now() or p_ends_at <= p_starts_at or p_ends_at > p_starts_at + interval '4 hours' then
    raise exception 'Horario inválido';
  end if;
  insert into public.schedule_slots(doctor_id,starts_at,ends_at) values (p_doctor_id,p_starts_at,p_ends_at) returning id into v_id;
  insert into public.audit_logs(actor_id,action,target_type,target_id) values(auth.uid(),'slot.created','slot',v_id::text);
end $$;

revoke all on function public.create_profile(), public.log_appointment() from public;
revoke all on function public.app_role(), public.staff_aal2(), public.doctor_has_patient(uuid), public.book_slot(uuid,uuid),
  public.cancel_appointment(uuid), public.complete_appointment(uuid), public.admin_set_role(uuid,text),
  public.admin_add_doctor(uuid,bigint), public.admin_add_slot(uuid,timestamptz,timestamptz) from public;
grant execute on function public.app_role(), public.staff_aal2(), public.doctor_has_patient(uuid), public.book_slot(uuid,uuid),
  public.cancel_appointment(uuid), public.complete_appointment(uuid), public.admin_set_role(uuid,text),
  public.admin_add_doctor(uuid,bigint), public.admin_add_slot(uuid,timestamptz,timestamptz) to authenticated;

insert into public.specialties(name) values ('Medicina general'),('Pediatría'),('Dermatología'),('Odontología');
