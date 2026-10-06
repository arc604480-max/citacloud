import { fail } from '@sveltejs/kit';
import { requireRole } from '$lib/server/auth';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async (event) => {
  const { supabase, user } = await requireRole(event, ['doctor']);
  const { data: doctor } = await supabase
    .from('doctors')
    .select('id,profile_id,specialty:specialties(name)')
    .eq('profile_id', user.id)
    .single();

  if (!doctor) {
    return { doctor: null, shifts: [], slots: [], appointments: [] };
  }

  const [{ data: shifts }, { data: slots }] = await Promise.all([
    supabase
      .from('doctor_shifts')
      .select('*')
      .eq('doctor_id', doctor.id)
      .order('work_date', { ascending: true })
      .order('starts_at', { ascending: true }),
    supabase
      .from('schedule_slots')
      .select('id,shift_id,doctor_id,starts_at,ends_at')
      .eq('doctor_id', doctor.id)
      .gte('starts_at', new Date(Date.now() - 86400000).toISOString())
      .order('starts_at')
  ]);

  const slotIds = (slots ?? []).map((s) => s.id);
  const { data: appointments } = slotIds.length
    ? await supabase
        .from('appointments')
        .select('id,slot_id,status,created_at,patient:profiles(full_name)')
        .in('slot_id', slotIds)
        .neq('status', 'cancelled')
    : { data: [] };

  return {
    doctor,
    shifts: shifts ?? [],
    slots: slots ?? [],
    appointments: (appointments ?? []) as any[]
  };
};

export const actions: Actions = {
  save_shift: async (event) => {
    const { supabase, user } = await requireRole(event, ['doctor']);
    const { data: doctor } = await supabase
      .from('doctors')
      .select('id')
      .eq('profile_id', user.id)
      .single();

    if (!doctor) return fail(400, { message: 'No se encontró el registro médico de tu usuario.' });

    const fd = await event.request.formData();
    const rawShiftId = String(fd.get('shift_id') ?? '').trim();
    const shift_id = rawShiftId.length > 0 ? rawShiftId : null;
    const work_date = String(fd.get('work_date') ?? '').trim();
    const shift_type = String(fd.get('shift_type') ?? 'custom').trim();
    const start_time = String(fd.get('start_time') ?? '').trim();
    const end_time = String(fd.get('end_time') ?? '').trim();
    const has_break = fd.get('has_break') === 'on' || fd.get('has_break') === 'true';
    const break_start_time = String(fd.get('break_start_time') ?? '').trim();
    const break_end_time = String(fd.get('break_end_time') ?? '').trim();

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
      p_doctor_id: doctor.id,
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
        ? 'Jornada actualizada y turnos sincronizados exitosamente.'
        : 'Jornada de atención creada. Se han generado turnos de 30 minutos automáticamente.'
    };
  },

  delete_shift: async (event) => {
    const { supabase } = await requireRole(event, ['doctor']);
    const fd = await event.request.formData();
    const shift_id = String(fd.get('shift_id') ?? '').trim();
    if (!shift_id) return fail(400, { message: 'Jornada no especificada.' });

    const { error } = await supabase.rpc('delete_doctor_shift', { p_shift_id: shift_id });
    if (error) return fail(400, { message: error.message });

    return { success: 'Jornada eliminada exitosamente.' };
  },

  complete: async (event) => {
    const { supabase } = await requireRole(event, ['doctor']);
    const fd = await event.request.formData();
    const { error } = await supabase.rpc('complete_appointment', {
      p_appointment_id: String(fd.get('id') ?? '')
    });
    return error ? fail(400, { message: error.message }) : { success: 'Atención marcada como completada.' };
  }
};
