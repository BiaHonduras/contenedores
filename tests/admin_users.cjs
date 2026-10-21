const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('node:assert/strict');
const ts=require(process.env.BIA_TYPESCRIPT_MODULE||'typescript');
const source=fs.readFileSync(path.join(__dirname,'../supabase/functions/admin-users/index.ts'),'utf8').replace(/^import .*\n/,'');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None},reportDiagnostics:true});
assert.equal((compiled.diagnostics||[]).filter(x=>x.category===ts.DiagnosticCategory.Error).length,0);
async function run({authorized=true,existing=false,upsertError=false,token=true}={}){
 let handler;const calls=[];
 const admin={auth:{getUser:async()=>({data:{user:{id:'actor'}}}),admin:{listUsers:async()=>({data:{users:existing?[{id:'existing',email:'new@example.test'}]:[]}}),createUser:async body=>{calls.push(['create',body]);return{data:{user:{id:'new'}}}},deleteUser:async id=>{calls.push(['delete',id]);return{}}}},from:table=>({upsert:async body=>{calls.push(['upsert',table,body]);return{error:upsertError?{message:'fixture failure'}:null}}})};
 const caller={rpc:async()=>({data:authorized})};let client=0;
 const context={createClient:()=>++client===1?admin:caller,Deno:{env:{get:key=>({SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'server-secret',SUPABASE_ANON_KEY:'public-key'})[key]},serve:f=>handler=f},crypto:require('crypto').webcrypto,Response,console};
 vm.createContext(context);vm.runInContext(compiled.outputText,context);
 const response=await handler(new Request('https://example.test',{method:'POST',headers:token?{Authorization:'Bearer test'}:{},body:JSON.stringify({action:'create_or_assign',email:'new@example.test',nombre:'New User',sede:'SPS',rol:'operador'})}));
 return{status:response.status,body:await response.json(),calls};
}
(async()=>{
 let x=await run();assert.equal(x.status,200);assert.equal(x.body.created,true);assert(x.body.initial_password.length>=8);assert.equal(x.calls.find(c=>c[0]==='create')[1].email_confirm,true);assert.equal(x.calls.find(c=>c[0]==='create')[1].app_metadata.must_change_password,true);assert.equal(x.calls.find(c=>c[0]==='upsert')[1],'usuarios_sedes');
 x=await run({existing:true});assert.equal(x.body.created,false);assert.equal(x.body.initial_password,undefined);assert(!x.calls.some(c=>c[0]==='create'));
 x=await run({authorized:false});assert.equal(x.status,403);assert.equal(x.calls.length,0);
 x=await run({token:false});assert.equal(x.status,401);assert.equal(x.calls.length,0);
 x=await run({upsertError:true});assert.equal(x.status,400);assert(x.calls.some(c=>c[0]==='delete'));
 console.log('PASS shared user creation: authenticated administrator only, temporary password, mandatory password change, existing account reuse, rollback on assignment failure; no SMTP dependency');
})().catch(e=>{console.error(e);process.exitCode=1});
