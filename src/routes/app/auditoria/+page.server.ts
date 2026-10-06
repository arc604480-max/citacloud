import { requireRole } from '$lib/server/auth';
import type { PageServerLoad } from './$types';
export const load: PageServerLoad = async (event) => {
  const {supabase}=await requireRole(event,['admin']);
  const [{data:logs},{data:training}]=await Promise.all([
    supabase.from('audit_logs').select('id,actor_id,action,target_type,target_id,created_at').order('created_at',{ascending:false}).limit(100),
    supabase.from('training_results').select('score,completed_at,user:profiles(full_name)').order('completed_at',{ascending:false}).limit(30)
  ]);
  const actors=[...new Set((logs??[]).map(l=>l.actor_id).filter(Boolean))];
  const {data:profiles}=actors.length ? await supabase.from('profiles').select('id,full_name').in('id',actors) : {data:[]};
  return {logs:logs??[],training:(training??[]) as any[],names:Object.fromEntries((profiles??[]).map(p=>[p.id,p.full_name]))};
};
