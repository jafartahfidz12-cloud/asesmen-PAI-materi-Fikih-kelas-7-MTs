-- Jalankan setelah schema.sql dan seed.sql untuk memeriksa kelengkapan bank soal.
select 'jumlah_soal' as pemeriksaan, count(*)::text as hasil from public.exam_questions
union all
select 'jumlah_kunci', count(*)::text from public.answer_keys;
select topic, count(*) as jumlah
from public.exam_questions
group by topic
order by case topic
 when 'THARAH' then 1 when 'SOLAT' then 2 when 'SOLAT SUNNAH' then 3
 when 'MENYEMBELIH' then 4 when 'ADZAN DAN IQAMAH' then 5 else 6 end;
