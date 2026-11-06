-- ASESMEN FIKIH ONLINE 2026 — skema final
-- Jalankan SEKALI di Supabase SQL Editor setelah membuat project.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'student' check (role in ('student','admin')),
  display_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.participants (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  class_name text not null,
  participant_no text not null unique,
  pin_hash text not null,
  exam_year text not null default '2026/2027',
  created_at timestamptz not null default now()
);

create table if not exists public.exam_questions (
  id integer primary key,
  topic text not null,
  prompt text not null,
  options jsonb not null check(jsonb_typeof(options)='array' and jsonb_array_length(options)=5)
);
create table if not exists public.answer_keys (
  question_id integer primary key references public.exam_questions(id) on delete cascade,
  correct_option text not null check(correct_option in ('A','B','C','D','E'))
);

create table if not exists public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null unique references public.participants(id) on delete cascade,
  token_hash text not null unique,
  question_order jsonb not null,
  option_order jsonb not null,
  started_at timestamptz not null default now(),
  deadline_at timestamptz not null default (now()+interval '90 minutes'),
  submitted_at timestamptz,
  status text not null default 'in_progress' check(status in ('in_progress','submitted')),
  correct_count integer,
  wrong_count integer,
  unanswered_count integer,
  score integer
);

create table if not exists public.exam_answers (
  attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  question_id integer not null references public.exam_questions(id),
  selected_option text check(selected_option in ('A','B','C','D','E')),
  updated_at timestamptz not null default now(),
  primary key(attempt_id,question_id)
);

create index if not exists participants_class_idx on public.participants(class_name);
create index if not exists attempts_status_idx on public.exam_attempts(status);

alter table public.profiles enable row level security;
alter table public.participants enable row level security;
alter table public.exam_questions enable row level security;
alter table public.answer_keys enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.exam_answers enable row level security;

-- Tidak ada akses tabel langsung dari browser. Semua operasi peserta melalui RPC.
revoke all on public.profiles, public.participants, public.exam_questions,
 public.answer_keys, public.exam_attempts, public.exam_answers from anon, authenticated;
grant usage on schema public to anon, authenticated;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $$;

create or replace function public.student_start_exam(p_participant_no text,p_pin text)
returns jsonb language plpgsql security definer set search_path=public,extensions
as $$
declare
 v_p public.participants; v_a public.exam_attempts; v_token text;
 v_q record; v_opts jsonb; v_map jsonb:='{}'::jsonb; v_qorder jsonb:='[]'::jsonb;
 v_questions jsonb:='[]'::jsonb; v_ids jsonb; v_texts jsonb; v_count int;
begin
 if length(trim(coalesce(p_participant_no,'')))<1 or p_pin !~ '^[0-9]{4,8}$' then
   raise exception 'Nomor peserta atau PIN tidak valid.';
 end if;
 select * into v_p from public.participants
 where upper(participant_no)=upper(trim(p_participant_no))
 and pin_hash=crypt(p_pin,pin_hash);
 if not found then raise exception 'Nomor peserta atau PIN tidak sesuai.'; end if;
 select * into v_a from public.exam_attempts where participant_id=v_p.id;
 if found then
   if v_a.status='submitted' then raise exception 'Peserta ini telah menyelesaikan asesmen. Percobaan kedua tidak diizinkan.'; end if;
   raise exception 'Ujian peserta ini sudah dimulai. Gunakan perangkat sebelumnya atau hubungi guru untuk bantuan.';
 end if;
 select count(*) into v_count from public.exam_questions q join public.answer_keys k on k.question_id=q.id;
 if v_count<>50 then raise exception 'Bank soal belum lengkap. Hubungi administrator.'; end if;
 for v_q in select * from public.exam_questions order by random() loop
   select jsonb_agg(x.elem order by random()) into v_opts
   from jsonb_array_elements(v_q.options) x(elem);
   select jsonb_agg(x.elem->>'id' order by x.ord) into v_ids
   from jsonb_array_elements(v_opts) with ordinality x(elem,ord);
   select jsonb_agg(x.elem->>'text' order by x.ord) into v_texts
   from jsonb_array_elements(v_opts) with ordinality x(elem,ord);
   v_qorder:=v_qorder||to_jsonb(v_q.id);
   v_map:=v_map||jsonb_build_object(v_q.id::text,v_ids);
   v_questions:=v_questions||jsonb_build_array(jsonb_build_object(
      'id',v_q.id,'topic',v_q.topic,'prompt',v_q.prompt,'options',v_texts));
 end loop;
 v_token:=encode(gen_random_bytes(32),'hex');
 insert into public.exam_attempts(participant_id,token_hash,question_order,option_order)
 values(v_p.id,encode(digest(v_token,'sha256'),'hex'),v_qorder,v_map) returning * into v_a;
 return jsonb_build_object(
   'token',v_token,
   'participant',jsonb_build_object('full_name',v_p.full_name,'class_name',v_p.class_name,'participant_no',v_p.participant_no),
   'attempt',jsonb_build_object('full_name',v_p.full_name,'class_name',v_p.class_name,'participant_no',v_p.participant_no,'id',v_a.id),
   'started_at',v_a.started_at,'deadline_at',v_a.deadline_at,'questions',v_questions
 );
end $$;

create or replace function public.student_save_answer(p_token text,p_question_id integer,p_display_index integer)
returns jsonb language plpgsql security definer set search_path=public,extensions
as $$
declare v_a public.exam_attempts; v_opts jsonb; v_choice text;
begin
 select * into v_a from public.exam_attempts
 where token_hash=encode(digest(p_token,'sha256'),'hex');
 if not found then raise exception 'Sesi peserta tidak valid.'; end if;
 if v_a.status<>'in_progress' or v_a.submitted_at is not null then raise exception 'Jawaban telah dikunci.'; end if;
 if now()>=v_a.deadline_at then raise exception 'Waktu ujian telah habis.'; end if;
 if p_display_index<0 or p_display_index>4 or not (v_a.option_order ? p_question_id::text) then
   raise exception 'Pilihan jawaban tidak valid.';
 end if;
 v_opts:=v_a.option_order->p_question_id::text;
 v_choice:=v_opts->>p_display_index;
 if not (v_a.question_order @> jsonb_build_array(p_question_id)) then raise exception 'Nomor soal tidak termasuk sesi ini.'; end if;
 insert into public.exam_answers(attempt_id,question_id,selected_option)
 values(v_a.id,p_question_id,v_choice)
 on conflict(attempt_id,question_id) do update
 set selected_option=excluded.selected_option,updated_at=now();
 return jsonb_build_object('saved',true);
end $$;

create or replace function public.student_get_answers(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions
as $$
declare v_a public.exam_attempts; v_result jsonb;
begin
 select * into v_a from public.exam_attempts where token_hash=encode(digest(p_token,'sha256'),'hex');
 if not found or v_a.status<>'in_progress' then raise exception 'Sesi aktif tidak ditemukan.'; end if;
 select coalesce(jsonb_object_agg(a.question_id::text,
   (select ord-1 from jsonb_array_elements(v_a.option_order->a.question_id::text) with ordinality x(val,ord)
    where x.val#>>'{}'=a.selected_option)), '{}'::jsonb)
 into v_result from public.exam_answers a where a.attempt_id=v_a.id and a.selected_option is not null;
 return jsonb_build_object('answers',v_result);
end $$;

create or replace function public.student_submit_exam(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions
as $$
declare v_a public.exam_attempts; v_correct int; v_wrong int; v_blank int; v_score int;
begin
 select * into v_a from public.exam_attempts where token_hash=encode(digest(p_token,'sha256'),'hex') for update;
 if not found then raise exception 'Sesi peserta tidak valid.'; end if;
 if v_a.status='submitted' then
   return jsonb_build_object('score',v_a.score,'correct_count',v_a.correct_count,'wrong_count',v_a.wrong_count,'unanswered_count',v_a.unanswered_count);
 end if;
 if now()<v_a.deadline_at and v_a.submitted_at is not null then raise exception 'Status pengumpulan tidak valid.'; end if;
 select count(*) filter(where a.selected_option=k.correct_option),
        count(*) filter(where a.selected_option is not null and a.selected_option<>k.correct_option),
        count(*) filter(where a.selected_option is null)
 into v_correct,v_wrong,v_blank
 from public.exam_questions q join public.answer_keys k on k.question_id=q.id
 left join public.exam_answers a on a.attempt_id=v_a.id and a.question_id=q.id;
 v_score:=v_correct*2;
 update public.exam_attempts set status='submitted',submitted_at=now(),correct_count=v_correct,
   wrong_count=v_wrong,unanswered_count=v_blank,score=v_score where id=v_a.id;
 return jsonb_build_object('score',v_score,'correct_count',v_correct,'wrong_count',v_wrong,'unanswered_count',v_blank);
end $$;

create or replace function public.student_session_status(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions
as $$
declare v_a public.exam_attempts;
begin
 select * into v_a from public.exam_attempts where token_hash=encode(digest(p_token,'sha256'),'hex');
 if not found then raise exception 'Sesi tidak ditemukan.'; end if;
 if v_a.status='submitted' then
  return jsonb_build_object('submitted',true,'result',jsonb_build_object('score',v_a.score,'correct_count',v_a.correct_count,'wrong_count',v_a.wrong_count,'unanswered_count',v_a.unanswered_count));
 end if;
 return jsonb_build_object('submitted',false,'deadline_at',v_a.deadline_at);
end $$;

-- Akun guru dibuat melalui Authentication > Users, lalu UUID-nya didaftarkan di profiles.
create or replace function public.admin_dashboard()
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare v_rows jsonb; v_total int; v_done int; v_avg numeric; v_high int; v_low int;
 v_not int; v_progress int; v_ch jsonb;
begin
 if not public.is_admin() then raise exception 'Akses hanya untuk admin terdaftar.'; end if;
 select count(*) into v_total from public.participants;
 select count(*) into v_done from public.exam_attempts where status='submitted';
 select coalesce(round(avg(score)::numeric,2),0) into v_avg from public.exam_attempts where status='submitted';
 select coalesce(max(score),0),coalesce(min(score),0) into v_high,v_low from public.exam_attempts where status='submitted';
 select count(*) into v_not from public.participants p where not exists(select 1 from public.exam_attempts a where a.participant_id=p.id);
 select count(*) into v_progress from public.exam_attempts where status='in_progress';
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'full_name',p.full_name,'class_name',p.class_name,'participant_no',p.participant_no,
  'correct_count',a.correct_count,'wrong_count',a.wrong_count,'unanswered_count',a.unanswered_count,
  'score',a.score,'status',case when a.status='submitted' then 'Selesai' when a.id is not null then 'Sedang mengerjakan' else 'Belum mulai' end,
  'started_at',a.started_at,'submitted_at',a.submitted_at
 ) order by a.score desc nulls last,p.class_name,p.full_name),'[]'::jsonb)
 into v_rows from public.participants p left join public.exam_attempts a on a.participant_id=p.id;
 select jsonb_build_object(
  'high',count(*) filter(where score between 86 and 100),
  'mid',count(*) filter(where score between 70 and 85),
  'low',count(*) filter(where score between 0 and 69))
 into v_ch from public.exam_attempts where status='submitted';
 return jsonb_build_object('rows',v_rows,'total',v_total,'completed',v_done,'average',v_avg,
 'highest',v_high,'lowest',v_low,'not_started',v_not,'in_progress',v_progress,'categories',v_ch);
end $$;

create or replace function public.admin_create_participant(p_name text,p_class text,p_no text,p_pin text)
returns jsonb language plpgsql security definer set search_path=public,extensions
as $$
declare v_id uuid;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 if length(trim(p_name))<2 or length(trim(p_class))<1 or length(trim(p_no))<1 or p_pin !~ '^[0-9]{4,8}$' then
  raise exception 'Data peserta/PIN tidak valid.';
 end if;
 insert into public.participants(full_name,class_name,participant_no,pin_hash,exam_year)
 values(trim(p_name),trim(p_class),upper(trim(p_no)),crypt(p_pin,gen_salt('bf')),'2026/2027') returning id into v_id;
 return jsonb_build_object('created',true,'id',v_id);
end $$;

create or replace function public.admin_update_participant(p_id uuid,p_name text,p_class text,p_no text,p_pin text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions
as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 update public.participants set full_name=trim(p_name),class_name=trim(p_class),participant_no=upper(trim(p_no)),
   pin_hash=case when coalesce(p_pin,'')='' then pin_hash else crypt(p_pin,gen_salt('bf')) end
 where id=p_id;
 if not found then raise exception 'Peserta tidak ditemukan.'; end if;
 return jsonb_build_object('updated',true);
end $$;

create or replace function public.admin_delete_participant(p_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 delete from public.participants where id=p_id;
 if not found then raise exception 'Peserta tidak ditemukan.'; end if;
 return jsonb_build_object('deleted',true);
end $$;

revoke all on function public.is_admin() from public,anon,authenticated;
revoke all on function public.student_start_exam(text,text) from public,authenticated;
revoke all on function public.student_save_answer(text,integer,integer) from public,authenticated;
revoke all on function public.student_get_answers(text) from public,authenticated;
revoke all on function public.student_submit_exam(text) from public,authenticated;
revoke all on function public.student_session_status(text) from public,authenticated;
revoke all on function public.admin_dashboard() from public,anon;
revoke all on function public.admin_create_participant(text,text,text,text) from public,anon;
revoke all on function public.admin_update_participant(uuid,text,text,text,text) from public,anon;
revoke all on function public.admin_delete_participant(uuid) from public,anon;
grant execute on function public.student_start_exam(text,text) to anon,authenticated;
grant execute on function public.student_save_answer(text,integer,integer) to anon,authenticated;
grant execute on function public.student_get_answers(text) to anon,authenticated;
grant execute on function public.student_submit_exam(text) to anon,authenticated;
grant execute on function public.student_session_status(text) to anon,authenticated;
grant execute on function public.admin_dashboard() to authenticated;
grant execute on function public.admin_create_participant(text,text,text,text) to authenticated;
grant execute on function public.admin_update_participant(uuid,text,text,text,text) to authenticated;
grant execute on function public.admin_delete_participant(uuid) to authenticated;
