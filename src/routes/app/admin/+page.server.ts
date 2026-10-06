import { fail } from '@sveltejs/kit';
import { requireRole } from '$lib/server/auth';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async (event) => {
  const { supabase } = await requireRole(event, ['admin']);
  const [
    { data: profiles },
    { data: doctors },
    { data: specialties },
    { data: shifts },
    { data: slots },
    { data: appointments }
  ] = await Promise.all([
    supabase.from('profiles').select('id,full_name,role').order('created_at', { ascending: false }).limit(100),
    supabase
      .from('doctors')
      .select('id,profile_id,profile:profiles(full_name),specialty:specialties(name)')
      .order('id'),
    supabase.from('specialties').select('id,name').order('name'),
    supabase
      .from('doctor_shifts')
      .select('id,doctor_id,work_date,shift_type,starts_at,ends_at,break_starts_at,break_ends_at,doctor:doctors(profile:profiles(full_name),specialty:specialties(name))')
      .gte('work_date', new Date(Date.now() - 86400000).toISOString().slice(0, 10))
      .order('work_date', { ascending: true })
      .order('starts_at', { ascending: true }),
    supabase
      .from('schedule_slots')
      .select('id,shift_id,doctor_id,starts_at,ends_at,doctor:doctors(profile:profiles(full_name))')
      .gte('starts_at', new Date().toISOString())
      .order('starts_at')
      .limit(200),
    supabase.from('appointments').select('slot_id,status').neq('status', 'cancelled')
  ]);

  return {
    profiles: profiles ?? [],
    doctors: (doctors ?? []) as any[],
    specialties: specialties ?? [],
    shifts: (shifts ?? []) as any[],
    slots: (slots ?? []) as any[],
    appointments: appointments ?? []
  };
};

export const actions: Actions = {
  role: async (event) => {
    const { supabase } = await requireRole(event, ['admin']);
    const fd = await event.request.formData();
    const { error } = await supabase.rpc('admin_set_role', {
      p_user_id: String(fd.get('user_id') ?? ''),
      p_role: String(fd.get('role') ?? '')
    });
    return error ? fail(400, { message: error.message }) : { success: 'Rol actualizado.' };
  },

  doctor: async (event) => {
    const { supabase } = await requireRole(event, ['admin']);
    const fd = await event.request.formData();
    const { error } = await supabase.rpc('admin_add_doctor', {
      p_profile_id: String(fd.get('user_id') ?? ''),
      p_specialty_id: Number(fd.get('specialty_id'))
    });
    return error ? fail(400, { message: error.message }) : { success: 'Médico añadido.' };
  },

  save_shift: async (event) => {
    const { supabase } = await requireRole(event, ['admin']);
    const fd = await event.request.formData();
    const rawShiftId = String(fd.get('shift_id') ?? '').trim();
    const shift_id = rawShiftId.length > 0 ? rawShiftId : null;
    const doctor_id = String(fd.get('doctor_id') ?? '').trim();
    const work_date = String(fd.get('work_date') ?? '').trim();
    const shift_type = String(fd.get('shift_type') ?? 'custom').trim();
    const start_time = String(fd.get('start_time') ?? '').trim();
    const end_time = String(fd.get('end_time') ?? '').trim();
    const has_break = fd.get('has_break') === 'on' || fd.get('has_break') === 'true';
    const break_start_time = String(fd.get('break_start_time') ?? '').trim();
    const break_end_time = String(fd.get('break_end_time') ?? '').trim();

    if (!doctor_id) return fail(400, { message: 'Selecciona un médico.' });
    if (!/^\d{4}-\d{2}-\d{2}$/.test(work_date)) {
      return fail(400, { message: 'Fecha de jornada inválida (formato YYYY-MM-DD).' });
    }
    if (!/^\d{2}:\d{2}$/.test(start_time) || !/^\d{2}:\d{2}$/.test(end_time)) {
      return fail(400, { message: 'Horarios de inicio y fin inválidos (formato HH:MM).' });
    }

    const starts_at = `${work_date}T${start_time}:00-05:00`;
    const ends_at = `${work_date}T${end_time}:00-05:00`;

    let break_starts_at: string | null = null;
    let break_ends_at: string | null = null;
    if (has_break) {
      if (!/^\d{2}:\d{2}$/.test(break_start_time) || !/^\d{2}:\d{2}$/.test(break_end_time)) {
        return fail(400, { message: 'Horarios de descanso inválidos (formato HH:MM).' });
      }
      break_starts_at = `${work_date}T${break_start_time}:00-05:00`;
      break_ends_at = `${work_date}T${break_end_time}:00-05:00`;
    }

    const { error } = await supabase.rpc('save_doctor_shift', {
      p_doctor_id: doctor_id,
      p_work_date: work_date,
      p_shift_type: shift_type,
      p_starts_at: starts_at,
      p_ends_at: ends_at,
      p_break_starts_at: break_starts_at,
      p_break_ends_at: break_ends_at,
      p_shift_id: shift_id
    });

    if (error) return fail(400, { message: error.message });

    return {
      success: shift_id
        ? 'Jornada médica actualizada y turnos sincronizados.'
        : 'Jornada médica creada con turnos de 30 minutos disponibles.'
    };
  },

  delete_shift: async (event) => {
    const { supabase } = await requireRole(event, ['admin']);
    const fd = await event.request.formData();
    const shift_id = String(fd.get('shift_id') ?? '').trim();
    if (!shift_id) return fail(400, { message: 'Jornada no especificada.' });

    const { error } = await supabase.rpc('delete_doctor_shift', { p_shift_id: shift_id });
    if (error) return fail(400, { message: error.message });

    return { success: 'Jornada médica eliminada.' };
  }
};
