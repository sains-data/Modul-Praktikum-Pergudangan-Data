-- =============================================================================
-- Modul 03 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-03/check.sql
--
-- Skrip mencetak satu baris per butir dengan status LULUS atau GAGAL.
-- Butir B5 sampai B8 adalah inti modul: keutuhan histori dimensi.
-- =============================================================================

\pset border 2
\pset title 'Modul 03 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. Ekstensi btree_gist aktif.
b1 AS (
  SELECT 'B1  Ekstensi btree_gist aktif' AS butir,
         COUNT(*) = 1 AS lulus,
         COALESCE(MAX('versi ' || extversion), 'belum diaktifkan') AS detail
  FROM   pg_extension WHERE extname = 'btree_gist'
),

-- B2. Kolom histori SCD-2 ada.
kolom (nama) AS (
  VALUES ('mulai_berlaku'), ('selesai_berlaku'), ('baris_kini'), ('harga_jual')
),
kolom_hilang AS (
  SELECT nama FROM kolom
  EXCEPT
  SELECT column_name FROM information_schema.columns
  WHERE  table_schema = 'public' AND table_name = 'dim_produk'
),
b2 AS (
  SELECT 'B2  dim_produk memiliki kolom histori' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('kolom hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   kolom_hilang
),

-- B3. Constraint UNIQUE lama pada produk_id sudah dihapus dan digantikan
--     indeks parsial. Constraint Modul 2 kini justru menghalangi versi kedua.
b3 AS (
  SELECT 'B3  UNIQUE lama diganti indeks parsial' AS butir,
         NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                     WHERE table_schema = 'public'
                       AND table_name   = 'dim_produk'
                       AND constraint_type = 'UNIQUE'
                       AND constraint_name = 'dim_produk_produk_id_key')
         AND EXISTS (SELECT 1 FROM pg_indexes
                     WHERE schemaname = 'public'
                       AND tablename  = 'dim_produk'
                       AND indexdef ILIKE '%WHERE baris_kini%')
         AS lulus,
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.table_constraints
                           WHERE table_schema = 'public'
                             AND table_name   = 'dim_produk'
                             AND constraint_name = 'dim_produk_produk_id_key')
              THEN 'constraint UNIQUE lama masih terpasang'
              ELSE 'indeks parsial terpasang' END AS detail
),

-- B4. Exclusion constraint terpasang.
b4 AS (
  SELECT 'B4  Exclusion constraint rentang terpasang' AS butir,
         COUNT(*) >= 1 AS lulus,
         COUNT(*) || ' exclusion constraint pada dim_produk' AS detail
  FROM   pg_constraint c
  JOIN   pg_class t ON t.oid = c.conrelid
  WHERE  t.relname = 'dim_produk' AND c.contype = 'x'
),

-- B5. Tidak ada produk dengan lebih dari satu baris kini.
b5 AS (
  SELECT 'B5  Satu baris kini per produk' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' produk memiliki lebih dari satu baris kini' AS detail
  FROM ( SELECT produk_id FROM dim_produk WHERE baris_kini
         GROUP BY produk_id HAVING COUNT(*) > 1 ) x
),

-- B6. Tidak ada irisan rentang antarversi satu produk.
--     Constraint B4 seharusnya sudah mencegahnya; pemeriksaan ini menangkap
--     kasus data yang masuk SEBELUM constraint dipasang.
b6 AS (
  SELECT 'B6  Tidak ada irisan rentang antarversi' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' pasangan versi beririsan' AS detail
  FROM   dim_produk a
  JOIN   dim_produk b
         ON  b.produk_id  = a.produk_id
         AND b.produk_key > a.produk_key
         AND daterange(a.mulai_berlaku, a.selesai_berlaku, '[)')
          && daterange(b.mulai_berlaku, b.selesai_berlaku, '[)')
),

-- B7. Tidak ada celah antarversi: versi berikutnya mulai tepat saat versi
--     sebelumnya berakhir. Celah membuat query tanggal tertentu tidak
--     mengembalikan baris apa pun.
b7 AS (
  SELECT 'B7  Tidak ada celah antarversi' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' celah ditemukan' AS detail
  FROM ( SELECT produk_id, selesai_berlaku,
                LEAD(mulai_berlaku) OVER (PARTITION BY produk_id
                                          ORDER BY mulai_berlaku) AS berikutnya
         FROM   dim_produk ) x
  WHERE  berikutnya IS NOT NULL AND berikutnya <> selesai_berlaku
),

-- B8. Produk skenario memiliki tepat tiga versi.
b8 AS (
  SELECT 'B8  Produk skenario memiliki tiga versi' AS butir,
         COALESCE(MAX(jml), 0) = 3 AS lulus,
         COALESCE(MAX(jml), 0) || ' versi (diharapkan 3)' AS detail
  FROM ( SELECT COUNT(*) AS jml
         FROM   dim_produk
         WHERE  produk_id IN (SELECT DISTINCT produk_id
                              FROM staging_produk_perubahan)
         GROUP  BY produk_id ) x
),

-- B9. Fakta menunjuk versi yang berlaku saat transaksi, bukan versi kini.
--     Bila join pemuatan memakai baris_kini, seluruh baris fakta akan menunjuk
--     versi terakhir dan pemeriksaan ini gagal.
b9 AS (
  SELECT 'B9  Fakta menunjuk versi yang berlaku' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris fakta menunjuk versi di luar masa berlakunya'
         AS detail
  FROM   fakta_penjualan f
  JOIN   dim_produk  dp ON dp.produk_key  = f.produk_key
  JOIN   dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
  WHERE  dt.tanggal < dp.mulai_berlaku OR dt.tanggal >= dp.selesai_berlaku
),

-- B10. Dimensi khusus ada beserta kedua view perannya.
objek (nama, jenis) AS (
  VALUES ('dim_transaksi_flag', 'BASE TABLE'), ('dim_promosi', 'BASE TABLE'),
         ('dim_tanggal_mulai', 'VIEW'),        ('dim_tanggal_selesai', 'VIEW')
),
objek_hilang AS (
  SELECT nama FROM objek
  EXCEPT
  SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'
),
b10 AS (
  SELECT 'B10 Junk dimension dan role-playing view ada' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   objek_hilang
)

SELECT butir,
       CASE WHEN lulus THEN 'LULUS' ELSE 'GAGAL' END AS status,
       detail
FROM (
  SELECT * FROM b1 UNION ALL SELECT * FROM b2 UNION ALL SELECT * FROM b3
  UNION ALL SELECT * FROM b4 UNION ALL SELECT * FROM b5
  UNION ALL SELECT * FROM b6 UNION ALL SELECT * FROM b7
  UNION ALL SELECT * FROM b8 UNION ALL SELECT * FROM b9
  UNION ALL SELECT * FROM b10
) hasil
ORDER BY butir;

-- -----------------------------------------------------------------------------
-- Riwayat produk skenario. Asisten membaca keluaran ini bersama mahasiswa:
-- selesai_berlaku setiap versi harus sama persis dengan mulai_berlaku versi
-- sesudahnya, dan hanya baris terakhir yang baris_kini-nya benar.
-- -----------------------------------------------------------------------------
SELECT produk_key, produk_id, versi, harga_jual, kategori,
       mulai_berlaku, selesai_berlaku, baris_kini
FROM   dim_produk
WHERE  produk_id IN (SELECT DISTINCT produk_id FROM staging_produk_perubahan)
ORDER  BY produk_id, mulai_berlaku;

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten secara manual:
--
--   B11  kebijakan-scd.md memuat tipe SCD dan alasan untuk setiap atribut.
--   B12  bukti-constraint.md memuat salinan pesan galat penolakan irisan.
--   B13  Query harga pada tanggal tertentu memakai rentang berlaku, bukan
--        baris_kini.
-- -----------------------------------------------------------------------------
