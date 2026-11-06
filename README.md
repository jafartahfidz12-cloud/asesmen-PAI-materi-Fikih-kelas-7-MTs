# ASESMEN FIKIH ONLINE 2026 — MTs Raudlatul Ulum VI

Aplikasi web ujian Fikih dengan PIN peserta, 50 soal pilihan ganda, timer server 90 menit, pengacakan soal dan opsi, autosave server-side, penilaian server-side, hasil pribadi, serta dashboard guru.

## Teknologi
- Frontend: HTML, CSS, JavaScript ES Modules.
- Database/backend: Supabase PostgreSQL + RPC SQL `SECURITY DEFINER`.
- Admin: Supabase Auth email/password dan daftar izin `profiles.role='admin'`.
- Hosting: Vercel atau Netlify.
- Tidak memakai Edge Functions atau service-role key di browser.

## File proyek
- `index.html`: halaman utama.
- `src/app.js`: aplikasi siswa/admin.
- `src/style.css`: desain responsif.
- `src/config.js`: URL dan anon key Supabase.
- `src/questions.js`: bank soal contoh untuk referensi/penelaahan.
- `supabase/schema.sql`: tabel, RLS, fungsi PIN, autosave, submit, penilaian, dan dashboard.
- `supabase/seed.sql`: 50 soal dan kunci jawaban.\n- `supabase/verify.sql`: pemeriksaan jumlah soal dan distribusi materi.

## 1. Buat project Supabase
1. Buka https://supabase.com/dashboard lalu buat project.
2. Pilih region terdekat yang tersedia (misalnya Singapore bila tersedia).
3. Simpan database password secara pribadi.
4. Buka **SQL Editor → New query**.
5. Jalankan seluruh `supabase/schema.sql` terlebih dahulu.
6. Jalankan seluruh `supabase/seed.sql` setelah schema sukses.
7. Jalankan `supabase/verify.sql` untuk memastikan jumlah soal 50 dan masing-masing materi berisi 10 soal.\n8. Pastikan tidak ada error. Di Table Editor akan terlihat tabel `participants`, `exam_questions`, `answer_keys`, `exam_attempts`, `exam_answers`, dan `profiles`.

## 2. Buat akun admin/guru
1. Supabase → **Authentication → Users → Add user**.
2. Buat email dan password kuat milik guru.
3. Salin UUID user dari daftar Users.
4. Kembali ke SQL Editor, jalankan (ganti UUID):
   ```sql
   insert into public.profiles(id, role, display_name)
   values ('UUID-AKUN-GURU', 'admin', 'Admin Fikih')
   on conflict (id) do update set role='admin', display_name='Admin Fikih';
   ```
5. Login ke aplikasi dengan email/password tersebut melalui tombol **Masuk Admin/Guru**.

Jangan bagikan akun admin kepada siswa. Gunakan MFA pada akun admin bila tersedia.

## 3. Isi peserta dan PIN
Setelah login admin, gunakan tombol **+ Tambah peserta** pada dashboard. Isi nama, kelas, nomor peserta, dan PIN 4–8 angka. Berikan nomor peserta dan PIN secara pribadi kepada siswa.

Contoh PIN hanya untuk uji coba. Buat PIN berbeda dan tidak mudah ditebak untuk setiap peserta. PIN disimpan dalam bentuk hash bcrypt, bukan teks biasa.

Untuk import banyak peserta sekaligus, jalankan contoh SQL berikut di SQL Editor (ganti data dan PIN):
```sql
insert into public.participants(full_name,class_name,participant_no,pin_hash,exam_year)
values
('Ahmad Fauzi','VII A','FIKIH001',crypt('482913',gen_salt('bf')),'2026/2027'),
('Siti Aminah','VII A','FIKIH002',crypt('731825',gen_salt('bf')),'2026/2027');
```
Jangan gunakan PIN contoh di atas untuk ujian sebenarnya.

## 4. Konfigurasi frontend
Buka `src/config.js`, ganti:
```js
export const SUPABASE_URL = "https://PROJECT_REF.supabase.co";
export const SUPABASE_ANON_KEY = "ISI_SUPABASE_ANON_PUBLIC_KEY";
```
Ambil nilainya dari Supabase **Project Settings → API**:
- Project URL.
- anon/public atau publishable key.

Anon/publishable key memang boleh ada di frontend. **Jangan pernah menaruh `service_role` key, secret key, atau database password dalam source code, GitHub, maupun file frontend.**

## 5. Upload ke GitHub
1. Buat repository baru bernama `asesmen-fikih-online-2026`.
2. Pilih Private agar bank soal dan file konfigurasi tidak tersebar tanpa perlu (kunci tetap dilindungi database/RPC).
3. Upload isi folder proyek ini sehingga `index.html` ada di root repository, bukan di subfolder bertingkat.
4. Commit perubahan.
5. Pastikan struktur repository:
   ```text
   index.html
   README.md
   src/
     app.js
     config.js
     questions.js
     style.css
   supabase/
     schema.sql
     seed.sql
   ```

## 6. Deploy dengan Vercel
1. Buka https://vercel.com dan login.
2. Klik **Add New → Project**.
3. Import repository GitHub.
4. Framework Preset: **Other**.
5. Build Command: kosongkan.
6. Output Directory: `.` (root).
7. Klik **Deploy**.
8. Setelah deploy sukses, salin URL HTTPS Vercel.
9. Supabase → **Authentication → URL Configuration**: masukkan URL Vercel ke Site URL dan Redirect URLs jika akan digunakan untuk admin auth. (Untuk domain statis, tambahkan URL domain utama.)

## 7. Cara penggunaan
**Guru**
- Login dari tombol Masuk Admin/Guru.
- Tambahkan peserta dan PIN.
- Pantau jumlah peserta, status, rata-rata, nilai tertinggi/terendah, kategori, dan daftar hasil.
- Cari peserta, edit identitas/PIN, hapus peserta (penghapusan menghapus attempt/riwayat peserta tersebut), cetak atau ekspor CSV.

**Siswa**
- Masuk dengan nomor peserta dan PIN.
- Sistem memulai timer berdasarkan waktu server (90 menit).
- Soal dan opsi diacak untuk setiap attempt.
- Setiap jawaban dikirim langsung ke server ketika dipilih.
- Siswa dapat menandai soal, berpindah soal, dan meninjau sebelum submit.
- Setelah submit, siswa hanya melihat identitas sendiri, nilai, jumlah benar/salah/kosong, bintang, dan motivasi.
- Nomor peserta hanya dapat memulai satu attempt.

## 8. Keamanan yang diterapkan
- RLS aktif di seluruh tabel.
- Hak akses langsung ke tabel dicabut dari `anon` dan `authenticated`.
- Kunci jawaban berada di `answer_keys`, tanpa policy baca untuk browser.
- PIN disimpan sebagai hash bcrypt.
- Sesi ujian memakai token acak 256-bit; database hanya menyimpan SHA-256 token.
- Fungsi RPC memvalidasi token, status attempt, waktu server, dan opsi jawaban.
- Koreksi nilai dilakukan di PostgreSQL, bukan di JavaScript.
- Dashboard memeriksa `profiles.role='admin'`.
- Submit bersifat idempoten: pengiriman ulang tidak membuat nilai kedua.
- Satu peserta hanya memiliki satu attempt.

## 9. Batasan dan langkah sebelum ujian resmi
- Source project ini belum terhubung ke Supabase sekolah dan belum dideploy. URL/key harus diisi oleh pemilik project.
- Kumpulan 50 soal merupakan draf. Guru Fikih harus memeriksa ketepatan materi, kunci, tingkat kesulitan, dan kesesuaian buku/kurikulum sebelum digunakan.
- Jika browser/perangkat tertutup, sesi bisa dipulihkan pada browser/perangkat yang sama selama localStorage tidak dihapus. Jawaban yang sudah tersimpan di server akan dimuat ulang. Jangan gunakan mode incognito atau hapus data situs saat ujian.
- Jika siswa pindah perangkat atau kehilangan token sesi, admin perlu melakukan prosedur khusus. Jangan hapus attempt sembarangan karena akan mengizinkan attempt baru.
- CORS/RPC berjalan melalui Supabase client. Batasi penggunaan domain dan aktifkan perlindungan tambahan/rate limiting bila ujian diikuti sangat banyak peserta.
- Uji terlebih dahulu dengan akun peserta dan admin percobaan: login PIN salah/benar, soal acak, autosave, refresh halaman, timer, submit ganda, siswa tidak bisa membaca kunci, admin bisa melihat rekap, dan ekspor CSV.
- Pertimbangkan kebijakan privasi, persetujuan wali, retensi data, serta pendampingan siswa sebelum pengumpulan data anak.

## 10. Mengganti logo
Saat ini halaman menampilkan placeholder logo. Untuk mengganti:
1. Tambahkan file logo resmi ke folder `assets`, misalnya `assets/logo-pesantren.png`.
2. Pada template landing di `src/app.js`, ganti elemen `<div class="logo-slot">...</div>` menjadi:
   ```html
   <div class="logo-slot"><img src="./assets/logo-pesantren.png" alt="Logo pesantren"></div>
   ```
3. Tambahkan CSS:
   ```css
   .logo-slot img { width:100%; height:100%; object-fit:contain; padding:8px; }
   ```
4. Commit dan tunggu Vercel melakukan deployment ulang.

## Troubleshooting singkat
- **Konfigurasi belum diisi**: periksa `src/config.js`, URL harus berakhiran `.supabase.co`, key adalah anon/publishable.
- **Bank soal belum lengkap**: jalankan `seed.sql` setelah `schema.sql`; pastikan 50 baris di `exam_questions` dan 50 baris di `answer_keys`.
- **Akses admin ditolak**: pastikan UUID akun Auth telah dimasukkan ke `profiles` dengan role `admin`.
- **PIN salah**: pastikan nomor peserta benar dan PIN sesuai yang dibuat guru.
- **Tidak dapat memulai lagi**: satu nomor peserta hanya mendapat satu attempt; hubungi guru untuk memeriksa status.
