import { fail } from '@sveltejs/kit';
import { requireRole } from '$lib/server/auth';
import type { PageServerLoad, Actions } from './$types';
export const load: PageServerLoad = async (event) => {
  const { supabase } = await requireRole(event,['reception','admin']);
  const [{data: patients},{data: slots},{data: taken},{data: appointments}] = await Promise.all([
    supabase.from('profiles').select('id,full_name').eq('role','patient').order('full_name').limit(100),
    supabase.from('schedule_slots').select('id,starts_at,ends_at,doctor:doctors(profile:profiles(full_name))').not('shift_id','is',null).gt('starts_at',new Date().toISOString()).order('starts_at').limit(500),
    supabase.from('appointments').select('slot_id').neq('status','cancelled'),
    supabase.from('appointments').select('id,status,patient:profiles(full_name),slot:schedule_slots(starts_at,doctor:doctors(profile:profiles(full_name)))').order('created_at',{ascending:false}).limit(100)
  ]);
  const booked = new Set((taken ?? []).map(a=>a.slot_id));
  return { patients:patients ?? [], slots:(slots ?? []).filter(s=>!booked.has(s.id) && new Date(s.ends_at).getTime()-new Date(s.starts_at).getTime()===30*60*1000) as any[], appointments:(appointments ?? []) as any[] };
};
export const actions: Actions = {
  book: async (event) => {
    const { supabase } = await requireRole(event,['reception','admin']);
    const fd = await event.request.formData();
    const {error} = await supabase.rpc('book_slot',{p_slot_id:String(fd.get('slot_id')??''),p_patient_id:String(fd.get('patient_id')??'')});
    return error ? fail(400,{message:error.message}) : {success:'Reserva registrada para el paciente.'};
  },
  cancel: async (event) => {
    const { supabase } = await requireRole(event,['reception','admin']);
    const fd = await event.request.formData();
    const {error} = await supabase.rpc('cancel_appointment',{p_appointment_id:String(fd.get('id')??'')});
    return error ? fail(400,{message:error.message}) : {success:'Cita cancelada.'};
  }
};
