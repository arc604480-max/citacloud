import { fail } from '@sveltejs/kit';
import { requireRole } from '$lib/server/auth';
import type { PageServerLoad, Actions } from './$types';
export const load: PageServerLoad = async (event) => {
  const {supabase,user}=await requireRole(event,['doctor','reception','admin']);
  const {data:results}=await supabase.from('training_results').select('score,completed_at').eq('user_id',user.id).order('completed_at',{ascending:false}).limit(5);
  return {results:results ?? []};
};
export const actions: Actions = { submit: async(event) => {
  const {supabase,user}=await requireRole(event,['doctor','reception','admin']);
  const fd=await event.request.formData();
  const answers=['reportar','verificar','no-compartir'];
  const score=answers.reduce((n,answer,i)=>n+(fd.get(`q${i+1}`)===answer?1:0),0);
  const {error}=await supabase.from('training_results').insert({user_id:user.id,score});
  return error ? fail(400,{message:error.message}) : {success:`Resultado registrado: ${score} de 3 respuestas correctas.`};
}};
