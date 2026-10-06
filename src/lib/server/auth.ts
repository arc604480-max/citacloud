import { redirect, error } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';

export type Role = 'patient' | 'doctor' | 'reception' | 'admin';
export type Profile = { id: string; full_name: string; role: Role };

export async function requireUser(event: RequestEvent) {
  if (!event.locals.supabase) throw redirect(303, '/?setup=1');
  if (!event.locals.user) throw redirect(303, '/login');
  return { supabase: event.locals.supabase, user: event.locals.user };
}

export async function requireRole(event: RequestEvent, roles: Role[]) {
  const { supabase, user } = await requireUser(event);
  const { data: profile } = await supabase.from('profiles').select('id,full_name,role').eq('id', user.id).single();
  if (!profile || !roles.includes(profile.role as Role)) throw error(403, 'No tienes permiso para esta sección.');
  if (profile.role !== 'patient') {
    const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (data?.currentLevel !== 'aal2') throw redirect(303, '/app/seguridad');
  }
  return { supabase, user, profile: profile as Profile };
}
