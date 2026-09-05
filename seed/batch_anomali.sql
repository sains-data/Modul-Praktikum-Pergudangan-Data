-- =============================================================================
-- Batch beranomali untuk Modul 10
-- Dijalankan pada: nusamart_oltp (port 5433)
--
--   docker compose exec -T postgres_source \
--     psql -U praktikum -d nusamart_oltp -f /seed/batch_anomali.sql
--
-- Menambahkan satu hari transaksi baru (2026-01-15) yang memuat anomali
-- terkendali. SELURUHNYA lolos constraint basis data, sehingga pipeline
-- Modul 7 memuatnya tanpa galat, dbt membangunnya tanpa galat, dan dashboard
-- Modul 9 menampilkan angka yang tampak wajar.
--
-- Itulah persoalannya, dan itulah yang harus ditemukan mahasiswa.
--
-- PERINGATAN UNTUK ASISTEN
-- Berkas ini menjelaskan seluruh anomali yang ditanam. JANGAN dibagikan ke
-- mahasiswa sebelum checkpoint Modul 10 selesai -- menemukannya adalah
-- pekerjaan Bagian A.
-- =============================================================================

SET search_path TO nusamart, public;

\set tanggal_batch '2026-01-15'

BEGIN;

-- -----------------------------------------------------------------------------
-- Titik awal penomoran, supaya skrip dapat dijalankan berulang tanpa bentrok.
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE awal AS
SELECT COALESCE(MAX(transaksi_id), 0)      AS trx,
       (SELECT COALESCE(MAX(transaksi_item_id), 0) FROM transaksi_item) AS item
FROM   transaksi;

-- =============================================================================
-- ANOMALI 1 -- COMPLETENESS: satu toko tidak mengirim apa pun
--
-- Toko 7 biasanya mengirim ratusan transaksi per hari. Pada batch ini ia tidak
-- mengirim satu baris pun.
--
-- Ini anomali yang PALING SULIT ditemukan: ketiadaan tidak menghasilkan baris,
-- sehingga luput dari seluruh pemeriksaan atas isi tabel. Ia hanya terlihat
-- dengan membandingkan terhadap daftar toko yang SEHARUSNYA mengirim.
--
-- Tidak ada perintah di sini -- justru ketiadaannya yang menjadi anomali.
-- Transaksi di bawah dibangkitkan untuk toko 1..6 dan 8..40 saja.
-- =============================================================================

INSERT INTO transaksi (transaksi_id, nomor_struk, toko_id, pelanggan_id,
                       pegawai_id, waktu_transaksi, metode_bayar,
                       total_bayar, status)
SELECT (SELECT trx FROM awal) + g,
       'ST' || LPAD((90000 + g)::TEXT, 8, '0'),
       CASE WHEN g % 39 < 6 THEN (g % 39) + 1        -- toko 1..6
            ELSE (g % 39) + 2 END,                   -- toko 8..40, toko 7 DILEWATI
       CASE WHEN random() < 0.4 THEN NULL
            ELSE (random() * 59999)::INT + 1 END,
       (random() * 1199)::INT + 1,
       TIMESTAMP :'tanggal_batch' + (random() * INTERVAL '14 hours')
                                  + INTERVAL '7 hours',
       (ARRAY['Tunai','Kartu Debit','QRIS','E-Wallet'])[(random() * 3)::INT + 1],
       0,
       'SELESAI'
FROM   generate_series(1, 4000) g;

-- =============================================================================
-- Baris struk normal, sebagai latar belakang yang wajar.
-- =============================================================================
INSERT INTO transaksi_item (transaksi_item_id, transaksi_id, produk_id,
                            kuantitas, harga_satuan, diskon, subtotal)
SELECT (SELECT item FROM awal) + row_number() OVER (),
       t.transaksi_id,
       (random() * 179999)::INT + 1,
       k.kuantitas,
       k.harga,
       0,
       ROUND(k.kuantitas * k.harga, 2)
FROM   transaksi t
CROSS  JOIN LATERAL (
         SELECT (random() * 3)::INT + 1        AS kuantitas,
                ROUND((random() * 200000 + 2000)::NUMERIC, 2) AS harga
       ) k
WHERE  t.waktu_transaksi::DATE = DATE :'tanggal_batch'
  AND  t.transaksi_id > (SELECT trx FROM awal);

-- =============================================================================
-- ANOMALI 2 -- CONSISTENCY: subtotal tidak sama dengan hitungannya
--
-- Sekitar 40 baris subtotalnya digelembungkan. Ketiga kolom sumbernya
-- sendiri-sendiri masuk akal: kuantitas positif, harga positif, diskon nol.
-- Yang salah adalah HUBUNGAN di antara ketiganya -- dan tidak ada constraint
-- yang dapat menangkapnya.
-- =============================================================================
UPDATE transaksi_item ti
SET    subtotal = ROUND(ti.subtotal * 1.25, 2)
FROM   transaksi t
WHERE  t.transaksi_id = ti.transaksi_id
  AND  t.waktu_transaksi::DATE = DATE :'tanggal_batch'
  AND  ti.transaksi_item_id % 97 = 0;

-- =============================================================================
-- ANOMALI 3 -- VALIDITY: harga satuan seribu kali lipat
--
-- Sekitar 15 baris harganya naik seribu kali. Nilainya TETAP bilangan positif,
-- sehingga lolos CHECK harga_satuan > 0 yang dipasang pada Modul 5. Hanya
-- terlihat sebagai pencilan terhadap sebaran harga produk itu sendiri.
-- =============================================================================
UPDATE transaksi_item ti
SET    harga_satuan = ti.harga_satuan * 1000,
       subtotal     = ROUND(ti.kuantitas * ti.harga_satuan * 1000, 2)
FROM   transaksi t
WHERE  t.transaksi_id = ti.transaksi_id
  AND  t.waktu_transaksi::DATE = DATE :'tanggal_batch'
  AND  ti.transaksi_item_id % 263 = 0;

-- =============================================================================
-- ANOMALI 4 -- UNIQUENESS: satu struk terkirim dua kali
--
-- Lima puluh transaksi disalin dengan transaksi_id baru tetapi nomor_struk,
-- toko, waktu, dan isi yang SAMA PERSIS. Kunci gudang tetap unik, sehingga
-- tidak ada constraint yang menolaknya -- tetapi nilainya terhitung dua kali.
-- =============================================================================
CREATE TEMP TABLE ganda AS
SELECT transaksi_id
FROM   transaksi
WHERE  waktu_transaksi::DATE = DATE :'tanggal_batch'
ORDER  BY transaksi_id
LIMIT  50;

INSERT INTO transaksi (transaksi_id, nomor_struk, toko_id, pelanggan_id,
                       pegawai_id, waktu_transaksi, metode_bayar,
                       total_bayar, status)
SELECT t.transaksi_id + 500000, t.nomor_struk, t.toko_id, t.pelanggan_id,
       t.pegawai_id, t.waktu_transaksi, t.metode_bayar, t.total_bayar, t.status
FROM   transaksi t JOIN ganda g ON g.transaksi_id = t.transaksi_id;

INSERT INTO transaksi_item (transaksi_item_id, transaksi_id, produk_id,
                            kuantitas, harga_satuan, diskon, subtotal)
SELECT ti.transaksi_item_id + 5000000, ti.transaksi_id + 500000, ti.produk_id,
       ti.kuantitas, ti.harga_satuan, ti.diskon, ti.subtotal
FROM   transaksi_item ti JOIN ganda g ON g.transaksi_id = ti.transaksi_id;

-- =============================================================================
-- ANOMALI 5 -- TIMELINESS: sebagian transaksi bertanggal jauh sebelumnya
--
-- Seratus transaksi dicatat pada batch ini, tetapi terjadi sepuluh sampai dua
-- puluh hari sebelumnya. Tanggalnya SAH, sehingga tidak ada yang menolaknya --
-- tetapi laporan periode yang sudah diterbitkan akan berubah setelah baris ini
-- masuk.
-- =============================================================================
UPDATE transaksi
SET    waktu_transaksi = waktu_transaksi - (10 + (transaksi_id % 11)) * INTERVAL '1 day'
WHERE  waktu_transaksi::DATE = DATE :'tanggal_batch'
  AND  transaksi_id % 41 = 0;

-- -----------------------------------------------------------------------------
-- Menyelaraskan total_bayar pada kepala struk. Dikerjakan TERAKHIR supaya
-- anomali consistency tetap tersembunyi di tingkat baris struk, bukan langsung
-- terlihat sebagai selisih pada kepala struk.
-- -----------------------------------------------------------------------------
UPDATE transaksi t
SET    total_bayar = s.jumlah
FROM ( SELECT transaksi_id, ROUND(SUM(subtotal), 2) AS jumlah
       FROM   transaksi_item GROUP BY transaksi_id ) s
WHERE  s.transaksi_id = t.transaksi_id
  AND  t.waktu_transaksi::DATE >= DATE :'tanggal_batch' - 25;

COMMIT;

-- =============================================================================
-- Ringkasan untuk asisten. JANGAN ditampilkan ke mahasiswa.
-- =============================================================================
\echo ''
\echo '=== RINGKASAN ANOMALI YANG DITANAM (untuk asisten) ==='

SELECT 'completeness: toko tidak mengirim' AS anomali,
       COUNT(*) FILTER (WHERE toko_id = 7) AS jumlah_baris,
       '0 diharapkan; toko 7 sengaja dilewati' AS catatan
FROM   transaksi WHERE waktu_transaksi::DATE = DATE :'tanggal_batch'
UNION ALL
SELECT 'consistency: subtotal tidak cocok',
       COUNT(*), 'lolos seluruh constraint'
FROM   transaksi_item ti JOIN transaksi t USING (transaksi_id)
WHERE  t.waktu_transaksi::DATE >= DATE :'tanggal_batch' - 25
  AND  ROUND(ti.kuantitas * ti.harga_satuan - ti.diskon, 2) <> ROUND(ti.subtotal, 2)
UNION ALL
SELECT 'uniqueness: struk ganda',
       COUNT(*), 'nomor_struk sama, transaksi_id berbeda'
FROM ( SELECT toko_id, nomor_struk FROM transaksi
       WHERE waktu_transaksi::DATE >= DATE :'tanggal_batch' - 25
       GROUP BY toko_id, nomor_struk HAVING COUNT(*) > 1 ) x
UNION ALL
SELECT 'timeliness: transaksi bertanggal mundur',
       COUNT(*), 'tanggalnya sah, tetapi mengubah laporan periode lalu'
FROM   transaksi
WHERE  waktu_transaksi::DATE BETWEEN DATE :'tanggal_batch' - 25
                                 AND DATE :'tanggal_batch' - 1;
