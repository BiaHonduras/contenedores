const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('node:assert/strict');
const code=fs.readFileSync(path.join(__dirname,'../_next/static/chunks/app/page-e03e9ef51e579945.js'),'utf8');
const start=code.indexOf('e1=(0,r.useMemo)(()=>'),end=code.indexOf(',e2=',start),expression=code.slice(start+3,end);
const base={r:{useMemo:f=>f()},L:'',l:['SPS','CBA','SRC','TGU','AMT'].map(agency=>({agency,supplier:'Proveedor',claimDate:'2026-10-22'})),W:{role:'admin',agency:'TGU'},siteFilter:'',supplierFilter:'',claimFilter:'',reportStart:'',reportEnd:''};
function filter(override){return vm.runInNewContext(expression,{...base,...override})}
assert.equal(filter({}).length,5);for(const site of ['SPS','CBA','SRC','TGU','AMT'])assert.equal(filter({siteFilter:site})[0].agency,site);
assert.equal(filter({W:{role:'operador',agency:'TGU'}}).length,1);assert.equal(filter({W:{role:'consulta',agency:'TGU'},siteFilter:'SPS'}).length,0);
assert.equal(filter({siteFilter:'SPS',reportStart:'2026-10-23'}).length,0);assert.equal(filter({siteFilter:'SPS',supplierFilter:'OTRO'}).length,0);
assert(code.includes('value:e1.length,label:"Registros"'));assert(code.includes('e2=e1.filter'));assert(code.includes('e4=e1.reduce'));assert(code.includes('children:W.shortName'));assert(!code.includes('children:W.fullName||W.email'));
console.log('PASS: all five admin site filters, own-site operator/viewer scope, combined filters, filtered counters and short-name identity');
