-- =============================================================================
-- Modul 10 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-10/check.sql
--
-- Butir B1 adalah kriteria lulus yang paling mudah dilanggar tanpa sadar:
-- data mentah tidak boleh diubah. Rekonsiliasi yang cocok karena sumbernya
-- disunting tidak membuktikan apa pun.
-- =============================================================================

\pset border 2
\pset title 'Modul 10 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. DATA MENTAH TIDAK DIUBAH. Anomali bawaan harus masih utuh di sumber.
--     Bila anomali hilang, seseorang memperbaikinya langsung di sumber --
--     dan itu melanggar aturan pokok modul ini.
b1 AS (
  SELECT 'B1  Data mentah tidak diubah' AS butir,
         COUNT(*) > 0 AS lulus,
         COUNT(*) || ' baris anomali masih utuh di sumber (diharapkan > 0)'
         AS detail
  FROM   src_oltp.transaksi_item ti
  WHERE  ROUND(ti.kuantitas * ti.harga_satuan - ti.diskon, 2)
         <> ROUND(ti.subtotal, 2)
),

-- B2. Tabel karantina ada beserta kolom yang menjelaskan sebabnya.
kolom_karantina (nama) AS (
  VALUES ('batch_id'), ('aturan'), ('alasan'), ('baris_asli')
),
kolom_hilang AS (
  SELECT nama FROM kolom_karantina
  EXCEPT
  SELECT column_name FROM information_schema.columns
  WHERE  table_schema = 'gudang' AND table_name = 'karantina_penjualan'
),
b2 AS (
  SELECT 'B2  Tabel karantina lengkap' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('kolom hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   kolom_hilang
),

-- B3. Karantina terisi. Batch beranomali seharusnya menghasilkan baris gagal;
--     karantina yang kosong berarti anomali tidak terdeteksi, atau baris
--     gagal dibuang alih-alih disisihkan.
b3 AS (
  SELECT 'B3  Karantina terisi dan beralasan' AS butir,
         COUNT(*) > 0 AND COUNT(*) FILTER (WHERE alasan IS NULL
                                             OR btrim(alasan) = '') = 0
         AS lulus,
         COUNT(*) || ' baris dikarantina, ' ||
         COUNT(DISTINCT aturan) || ' aturan berbeda' AS detail
  FROM   gudang.karantina_penjualan
),

-- B4. Fakta bersih dari baris yang terkarantina. Baris gagal tidak boleh
--     mencemari mart, tetapi juga tidak boleh hilang tanpa jejak.
b4 AS (
  SELECT 'B4  Baris terkarantina tidak masuk fakta' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris terkarantina masih ada di fakta' AS detail
  FROM   gudang.fakta_penjualan f
  WHERE  EXISTS (SELECT 1 FROM gudang.karantina_penjualan k
                 WHERE (k.baris_asli->>'transaksi_id') = f.transaksi_id::TEXT)
),

-- B5. Consistency: aritmetika subtotal pada fakta sudah bersih setelah
--     remediasi. Uji bertingkat error harus lulus.
b5 AS (
  SELECT 'B5  Aritmetika subtotal bersih di fakta' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris fakta tidak konsisten' AS detail
  FROM   gudang.fakta_penjualan
  WHERE  ROUND(kuantitas * harga_satuan - diskon, 2) <> ROUND(subtotal, 2)
),

-- B6. Uniqueness: satu produk hanya punya satu versi aktif.
b6 AS (
  SELECT 'B6  Satu versi aktif per produk' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' produk punya lebih dari satu versi aktif' AS detail
  FROM ( SELECT produk_id FROM gudang.dim_produk WHERE baris_kini
         GROUP BY produk_id HAVING COUNT(*) > 1 ) x
),

-- B7. Completeness terukur dan berada di bawah ambang.
b7 AS (
  SELECT 'B7  Baris unknown di bawah ambang 5 persen' AS butir,
         persen <= 5.0 AS lulus,
         persen || ' persen baris fakta menunjuk baris unknown' AS detail
  FROM ( SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE produk_key = -1
                                                  OR toko_key   = -1)
                      / NULLIF(COUNT(*), 0), 3) AS persen
         FROM   gudang.fakta_penjualan ) x
),

-- B8. Integrity: fakta menunjuk versi dimensi yang berlaku saat transaksi.
b8 AS (
  SELECT 'B8  Fakta menunjuk versi yang berlaku' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris menunjuk versi di luar masa berlakunya' AS detail
  FROM   gudang.fakta_penjualan f
  JOIN   gudang.dim_produk  dp ON dp.produk_key  = f.produk_key
  JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
  WHERE  f.produk_key <> -1
    AND  (dt.tanggal < dp.mulai_berlaku OR dt.tanggal >= dp.selesai_berlaku)
),

-- B9. Karantina bersifat idempoten: memuat ulang batch yang sama tidak
--     melipatgandakan barisnya.
b9 AS (
  SELECT 'B9  Karantina idempoten' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris terkarantina ganda pada batch yang sama' AS detail
  FROM ( SELECT batch_id, aturan, baris_asli->>'transaksi_id' AS trx
         FROM   gudang.karantina_penjualan
         GROUP  BY 1, 2, 3
         HAVING COUNT(*) > 1 ) x
)

SELECT butir,
       CASE WHEN lulus THEN 'LULUS' ELSE 'GAGAL' END AS status,
       detail
FROM (
  SELECT * FROM b1 UNION ALL SELECT * FROM b2 UNION ALL SELECT * FROM b3
  UNION ALL SELECT * FROM b4 UNION ALL SELECT * FROM b5
  UNION ALL SELECT * FROM b6 UNION ALL SELECT * FROM b7
  UNION ALL SELECT * FROM b8 UNION ALL SELECT * FROM b9
) hasil
ORDER BY butir;

-- =============================================================================
-- Scorecard kualitas data batch ini.
--
-- Setiap dimensi berupa ANGKA, bukan pernyataan ya-atau-tidak. Angka
-- memungkinkan penetapan ambang, perbandingan antarbatch, dan penilaian arah
-- -- tiga hal yang tidak mungkin dilakukan dengan penilaian "bagus" atau
-- "jelek".
-- =============================================================================
SELECT 'completeness' AS dimensi,
       'persen baris menunjuk unknown' AS ukuran,
       ROUND(100.0 * COUNT(*) FILTER (WHERE produk_key = -1 OR toko_key = -1)
             / NULLIF(COUNT(*), 0), 3) AS nilai,
       5.0 AS ambang
FROM   gudang.fakta_penjualan
UNION ALL
SELECT 'consistency', 'persen subtotal tidak cocok',
       ROUND(100.0 * COUNT(*) FILTER (
             WHERE ROUND(kuantitas * harga_satuan - diskon, 2)
                   <> ROUND(subtotal, 2)) / NULLIF(COUNT(*), 0), 3),
       0.0
FROM   gudang.fakta_penjualan
UNION ALL
SELECT 'validity', 'jumlah nilai mustahil',
       COUNT(*) FILTER (WHERE kuantitas <= 0 OR harga_satuan <= 0
                           OR diskon < 0),
       0.0
FROM   gudang.fakta_penjualan
UNION ALL
SELECT 'uniqueness', 'jumlah versi aktif ganda',
       (SELECT COUNT(*) FROM (SELECT produk_id FROM gudang.dim_produk
                              WHERE baris_kini GROUP BY produk_id
                              HAVING COUNT(*) > 1) x),
       0.0
ORDER BY dimensi;

-- Rincian karantina menurut aturan yang dilanggar. Angka ini menjadi salah
-- satu penjelasan sah bagi selisih rekonsiliasi.
SELECT aturan,
       COUNT(*)                              AS jumlah_baris,
       COUNT(*) FILTER (WHERE ditinjau)      AS sudah_ditinjau,
       MIN(ditemukan)                        AS pertama_ditemukan
FROM   gudang.karantina_penjualan
GROUP  BY aturan
ORDER  BY jumlah_baris DESC;

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten secara manual:
--
--   B10  temuan-anomali.md memuat sekurang-kurangnya LIMA anomali, masing-
--        masing disertai dimensi kualitas, jumlah baris, dan query pembuktinya.
--        Bandingkan dengan daftar anomali yang ditanam pada berkas asisten.
--        Anomali completeness -- satu toko yang tidak mengirim apa pun --
--        adalah yang paling jarang ditemukan.
--
--   B11  Proyek dbt memuat minimal DELAPAN uji: empat generic dan empat
--        custom, masing-masing dengan tingkat keparahan yang BERALASAN.
--        Uji yang seluruhnya bertingkat error tanpa alasan tidak memenuhi
--        syarat.
--
--   B12  `dbt test` dijalankan dan seluruh uji bertingkat error LULUS setelah
--        remediasi. Uji bertingkat warn boleh gagal, tetapi harus dilaporkan.
--
--   B13  laporan-kualitas.md memuat tabel rekonsiliasi empat besaran, dan
--        SETIAP selisih dijelaskan sampai jumlahnya TEPAT. Selisih yang
--        "kira-kira sesuai" tidak memenuhi syarat.
--
--   B14  scorecard-kualitas.md membandingkan DUA batch, bukan satu. Satu batch
--        hanya memberi potret; dua batch memberi arah.
-- -----------------------------------------------------------------------------
