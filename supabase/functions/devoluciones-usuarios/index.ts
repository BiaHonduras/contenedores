// Compatibility endpoint: all platforms use the same authorized creation method.
Deno.serve(async (request: Request) => {
 const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
 if(request.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(request.method!=='POST')return new Response(JSON.stringify({error:'METODO_NO_PERMITIDO'}),{status:405,headers:{...cors,'Content-Type':'application/json'}});
 let body;
 try{body=await request.json()}catch{return new Response(JSON.stringify({error:'JSON_INVALIDO'}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}
 const result=await fetch(Deno.env.get('SUPABASE_URL')+'/functions/v1/admin-users',{
  method:'POST',headers:{Authorization:request.headers.get('Authorization')||'',apikey:Deno.env.get('SUPABASE_ANON_KEY')||'','Content-Type':'application/json'},
  body:JSON.stringify({...body,action:'create_or_assign',rol:body.rol||'operador',puede_cierre_dia:false})
 });
 return new Response(await result.text(),{status:result.status,headers:{...cors,'Content-Type':'application/json'}});
});
