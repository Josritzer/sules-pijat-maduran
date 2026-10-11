select grup, nama, harapan, hasil, case when lulus then 'LULUS' else 'GAGAL' end as status from t.hasil order by grup, nama;
select grup, count(*) filter (where lulus) as lulus, count(*) filter (where not lulus) as gagal, count(*) as total from t.hasil group by grup order by grup;
