import { requireUser } from '$lib/server/auth';
import type { LayoutServerLoad } from './$types';
export const load: LayoutServerLoad = async (event) => {
  const { supabase, user } = await requireUser(event);
  const { data: profile } = await supabase.from('profiles').select('id,full_name,role').eq('id', user.id).single();
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  return { profile: profile ?? { id: user.id, full_name: user.email ?? 'Usuario', role: 'patient' }, aal2: aal?.currentLevel === 'aal2', email: user.email };
};
