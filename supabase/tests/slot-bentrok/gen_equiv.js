const fs=require('fs');
const src=fs.readFileSync('/home/claude/sules-pijat-maduran/index.html','utf8');
function grab(re,name){const m=src.match(re); if(!m) throw new Error('tidak ketemu '+name); return m[0];}
const code=[
 grab(/const MORNING_SLOTS = .*;/,'MORNING'),
 grab(/const EVENING_SLOTS = .*;/,'EVENING'),
 grab(/function jamToMenit\(jamStr\) \{[\s\S]*?\n\}/,'jamToMenit'),
 grab(/function menitToJam\(menit\) \{[\s\S]*?\n\}/,'menitToJam'),
 grab(/function generateSlotsForDurasi\(durasiMenit\) \{[\s\S]*?\n\}/,'gen'),
 grab(/function slotBentrokDenganTerisi\(slot, durasiMenit, terisi\) \{[\s\S]*?\n\}/,'bentrok'),
].join('\n')+'\nmodule.exports={generateSlotsForDurasi,slotBentrokDenganTerisi,jamToMenit,menitToJam};';
fs.writeFileSync('/var/tmp/pgt/real_fn.js',code);
const {generateSlotsForDurasi:G,slotBentrokDenganTerisi:K,jamToMenit:J,menitToJam:M}=require('/var/tmp/pgt/real_fn.js');
const durs=[90,120,180];
const rows=[]; let n=0;
// last-slot checks
const last={}; for(const d of durs){const g=G(d); last[d]={pagi:g.pagi.at(-1),malam:g.malam.at(-1),np:g.pagi.length,nm:g.malam.length};}
console.error(JSON.stringify(last));
for(const de of durs){ const g=G(de); for(const e of [...g.pagi,...g.malam]){
  for(const dc of durs){ const gc=G(dc); const valid=new Set([...gc.pagi,...gc.malam]);
    for(let mm=0;mm<24*60;mm+=30){ const c=M(mm);
      const exp = valid.has(c) && !K(c,dc,[{mulai_menit:J(e),selesai_menit:J(e)+de}]) ? 'OK' : (valid.has(c)?'BENTROK':'DI_LUAR_JAM_OPERASIONAL');
      rows.push(`(${n++},'${e}',${de},'${c}',${dc},'${exp}')`);
    }}}}
fs.writeFileSync('/var/tmp/pgt/equiv_cases.sql',
`\\set ON_ERROR_STOP on
create table if not exists t.eq(i int, e text, de int, c text, dc int, exp text, got text);
truncate t.eq;
insert into t.eq(i,e,de,c,dc,exp) values
${rows.join(',\n')};
do $$ declare r record; ex uuid; cand uuid; d date;
begin
  for r in select * from t.eq order by i loop
    d := date '2030-01-01' + r.i;
    ex := t.bk(d, r.e::time, r.de, 'DITERIMA');
    cand := t.bk(d, r.c::time, r.dc, 'MENUNGGU');
    update t.eq set got = t.acc(cand) where i = r.i;
  end loop;
end $$;
insert into t.hasil
select 'ekuivalensi', 'JS (generateSlots+slotBentrok) vs SQL accept_booking', count(*)||' kasus', count(*) filter (where exp=got)||' cocok', count(*) = count(*) filter (where exp=got) from t.eq;
select exp, got, count(*) from t.eq group by 1,2 order by 1,2;
select count(*) filter (where exp='OK') as ok_js, count(*) filter (where got='OK') as ok_sql, count(*) as total from t.eq;
`);
console.error('kasus',rows.length);
