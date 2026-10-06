import { fail, redirect } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';
export const load: PageServerLoad = ({ locals }) => { if (locals.user) throw redirect(303, '/app'); return {}; };
export const actions: Actions = {
  default: async ({ request, locals }) => {
    if (!locals.supabase) return fail(400, { message: 'Primero configura Supabase en .env.' });
    const data = await request.formData();
    const email = String(data.get('email') ?? '').trim();
    const password = String(data.get('password') ?? '');
    const { error } = await locals.supabase.auth.signInWithPassword({ email, password });
    if (error) return fail(400, { message: 'Revisa el correo y la contraseña.' });
    throw redirect(303, '/app');
  }
};
