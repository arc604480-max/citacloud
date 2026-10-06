import { requireUser } from '$lib/server/auth';
import type { PageServerLoad, Actions } from './$types';
import { redirect } from '@sveltejs/kit';
export const load: PageServerLoad = async (event) => {
  const { supabase, user } = await requireUser(event);
  const { data: profile } = await supabase.from('profiles').select('role').eq('id',user.id).single();
  const isPatient = profile?.role === 'patient';
  const { data: appointments } = await supabase.from('appointments').select('id,status,slot:schedule_slots(starts_at,doctor:doctors(profile:profiles(full_name),specialty:specialties(name)))').eq(isPatient ? 'patient_id' : 'status',isPatient ? user.id : 'confirmed').order('created_at',{ascending:false}).limit(8);
  return { appointments: (appointments ?? []) as any[] };
};
export const actions: Actions = { logout: async ({ locals }) => { await locals.supabase?.auth.signOut(); throw redirect(303, '/'); } };
