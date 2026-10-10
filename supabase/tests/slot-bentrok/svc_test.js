const fs=require('fs');
const s=fs.readFileSync('/home/claude/sules-pijat-maduran/index.html','utf8');
const m=s.match(/async function getSlotTerisi\(tanggal\) \{[\s\S]*?\n  \}/)[0];
let last; const supabaseClient={rpc:async(n,a)=>{last=[n,a]; return mock;}}; let mock;
const f=eval('('+m+')');
(async()=>{
 const out=[];
 mock={data:[{mulai_menit:600,selesai_menit:690},{mulai_menit:'1350',selesai_menit:1440},{mulai_menit:5,selesai_menit:5}],error:null};
 out.push(['mapping+filter', JSON.stringify(await f('2027-06-01')), '[{"mulai_menit":600,"selesai_menit":690},{"mulai_menit":1350,"selesai_menit":1440}]']);
 out.push(['rpc', JSON.stringify(last), '["get_slot_terisi",{"p_tanggal":"2027-06-01"}]']);
 mock={data:null,error:null}; out.push(['data null', JSON.stringify(await f('2027-06-01')), '[]']);
 let e1; try{await f('01/06/2027')}catch(e){e1=e.message}; out.push(['tanggal buruk', e1, 'Tanggal tidak valid.']);
 mock={data:null,error:new Error('x')}; let e2; try{await f('2027-06-01')}catch(e){e2=e.message}; out.push(['error rpc dilempar', e2, 'x']);
 let bad=0; for(const [n,g,w] of out){const ok=g===w; if(!ok)bad++; console.log(ok?'LULUS':'GAGAL',n,g);} console.log('gagal',bad);
})();
