import type { PageServerLoad } from './$types';
export const load: PageServerLoad = async ({ locals }) => ({ configured: !!locals.supabase, signedIn: !!locals.user });
