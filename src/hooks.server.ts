import { createServerClient } from '@supabase/ssr';
import { env } from '$env/dynamic/public';
import type { Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
  const PUBLIC_SUPABASE_URL = env.PUBLIC_SUPABASE_URL ?? '';
  const PUBLIC_SUPABASE_PUBLISHABLE_KEY = env.PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? '';
  const configured = PUBLIC_SUPABASE_URL.startsWith('https://') && !PUBLIC_SUPABASE_URL.includes('YOUR_PROJECT') && PUBLIC_SUPABASE_PUBLISHABLE_KEY !== 'YOUR_PUBLISHABLE_KEY';
  if (!configured) {
    event.locals.supabase = null;
    event.locals.user = null;
    return resolve(event);
  }
  event.locals.supabase = createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
    cookies: {
      getAll: () => event.cookies.getAll(),
      setAll: (items: { name: string; value: string; options: Record<string, any> }[]) => items.forEach(({ name, value, options }) => event.cookies.set(name, value, { ...options, path: '/' }))
    }
  });
  const { data: { user } } = await event.locals.supabase.auth.getUser();
  event.locals.user = user;
  return resolve(event, { filterSerializedResponseHeaders: (name) => name === 'content-range' });
};
