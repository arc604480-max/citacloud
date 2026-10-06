import { fail } from '@sveltejs/kit';
import { requireUser } from '$lib/server/auth';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
  const { supabase, user } = await requireUser(event);
  const now = new Date().toISOString();

  const [
    { data: specialties },
    { data: doctors },
    { data: slots },
    { data: taken },
    { data: mine }
  ] = await Promise.all([
    supabase.from('specialties').select('id,name').order('name'),
    supabase
      .from('doctors')
      .select('id,profile:profiles(full_name),specialty:specialties(id,name)')
      .eq('active', true),
    supabase
      .from('schedule_slots')
      .select('id,doctor_id,starts_at,ends_at')
      .not('shift_id', 'is', null)
      .gt('starts_at', now)
      .order('starts_at')
      .limit(1000),
    supabase.from('appointments').select('slot_id').neq('status', 'cancelled'),
    supabase
      .from('appointments')
      .select(
        'id,status,created_at,slot:schedule_slots(starts_at,doctor:doctors(profile:profiles(full_name),specialty:specialties(name)))'
      )
      .eq('patient_id', user.id)
      .order('created_at', { ascending: false })
      .limit(50)
  ]);

  const reserved = new Set((taken ?? []).map((a) => a.slot_id));
  const availableSlots = (slots ?? []).filter(
    (s) => !reserved.has(s.id) && new Date(s.ends_at).getTime() - new Date(s.starts_at).getTime() === 30 * 60 * 1000
  );

  return {
    specialties: specialties ?? [],
    doctors: (doctors ?? []) as any[],
    slots: availableSlots,
    appointments: (mine ?? []) as any[]
  };
};

export const actions: Actions = {
  book: async (event) => {
    const { supabase, user } = await requireUser(event);
    const { data: profile } = await supabase.from('profiles').select('role').eq('id', user.id).single();
    if (profile?.role !== 'patient') {
      return fail(403, { message: 'Solo las cuentas de paciente reservan citas desde esta pantalla.' });
    }

    const fd = await event.request.formData();
    const slotId = String(fd.get('slot_id') ?? '').trim();
    if (!slotId) return fail(400, { message: 'Debes seleccionar un horario válido.' });

    const { error } = await supabase.rpc('book_slot', { p_slot_id: slotId });
    return error
      ? fail(400, { message: error.message })
      : { success: '¡Cita confirmada! Tu turno ha sido reservado con éxito.' };
  },

  cancel: async (event) => {
    const { supabase } = await requireUser(event);
    const fd = await event.request.formData();
    const appointmentId = String(fd.get('appointment_id') ?? '').trim();
    if (!appointmentId) return fail(400, { message: 'Cita no especificada.' });

    const { error } = await supabase.rpc('cancel_appointment', { p_appointment_id: appointmentId });
    return error ? fail(400, { message: error.message }) : { success: 'Cita cancelada correctamente.' };
  }
};
