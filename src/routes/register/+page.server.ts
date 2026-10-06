import { fail, redirect } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';
export const load: PageServerLoad = ({ locals }) => { if (locals.user) throw redirect(303, '/app'); return {}; };
export const actions: Actions = {
  default: async ({ request, locals, url }) => {
    if (!locals.supabase) return fail(400, { message: 'Primero configura Supabase en .env.' });
    const data = await request.formData();
    const full_name = String(data.get('full_name') ?? '').trim();
    const email = String(data.get('email') ?? '').trim();
    const password = String(data.get('password') ?? '');
    if (full_name.length < 2 || password.length < 10) return fail(400, { message: 'Escribe tu nombre y una contraseña de al menos 10 caracteres.' });
    const { data: signed, error } = await locals.supabase.auth.signUp({ email, password, options: { data: { full_name }, emailRedirectTo: `${url.origin}/auth/callback` } });
    if (error) return fail(400, { message: 'No se pudo registrar la cuenta. Comprueba el correo o prueba otro.' });
    if (signed.session) throw redirect(303, '/app');
    return { success: 'Cuenta creada. Revisa tu correo para confirmar el registro y luego inicia sesión.' };
  }
};
