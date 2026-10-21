const fs=require('fs'),vm=require('vm'),assert=require('assert'),crypto=require('crypto');
const code=fs.readFileSync(require('path').join(__dirname,'../_next/static/chunks/app/page-e03e9ef51e579945.js'),'utf8');
const source=code.slice(code.indexOf('function eV()'),code.indexOf('function eG('));
let effects=[];const jsx=(type,props)=>({type,props});const context={
 r:{useState:v=>[typeof v==='function'?v():v,()=>{}],useMemo:f=>f(),useCallback:f=>f,useEffect:f=>effects.push(f)},
 t:{jsx,jsxs:jsx},eq:()=>({id:'draft',agency:'SPS',containerPhotos:[],damagePhotos:[],items:[]}),eU:()=>null,eB:()=>{},
 window:{matchMedia:()=>({matches:false}),navigator:{}},navigator:{onLine:true},Date,crypto,Intl
};vm.createContext(context);vm.runInContext(source+';this.render=eV;',context);const tree=context.render();
const json=JSON.stringify(tree);assert(json.includes('Inicia sesión para continuar'));assert(!json.includes('fieldset'));assert(!json.includes('Guardar registro'));assert(!json.includes('supplier'));
assert(code.includes('ew=!!(ef&&Q&&W?.isActive'));
assert(code.includes('event==="SIGNED_OUT"'));
assert(code.includes('location.replace("./login.html")'));
const login=fs.readFileSync(require('path').join(__dirname,'../login.html'),'utf8');assert(login.includes("location.replace('./index.html')"));assert(!login.includes("location.replace('./cronometros.html')"));assert(login.includes('autocomplete="current-password"'));
console.log('PASS: unauthenticated render exposes only login; no operational form; login redirect; strict session permission and signout reset');
