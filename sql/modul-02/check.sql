-- =============================================================================
-- Modul 02 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-02/check.sql
--
-- Skrip mencetak satu baris per butir dengan status LULUS atau GAGAL.
--
-- Cakupan: struktur skema dan konsistensi internal gudang. Butir rekonsiliasi
-- lintas basis data -- angka star query lawan angka sumber -- diperiksa manual
-- oleh asisten dari berkas rekonsiliasi.md mahasiswa, karena psql tidak dapat
-- menjangkau dua basis data sekaligus sebelum postgres_fdw diaktifkan (Modul 7).
-- =============================================================================

\pset border 2
\pset title 'Modul 02 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. Keempat tabel skema bintang ada.
diharapkan (nama) AS (
  VALUES ('dim_tanggal'), ('dim_produk'), ('dim_toko'), ('fakta_penjualan')
),
ada AS (
  SELECT table_name AS nama
  FROM   information_schema.tables
  WHERE  table_schema = 'public' AND table_type = 'BASE TABLE'
),
hilang AS (
  SELECT nama FROM diharapkan EXCEPT SELECT nama FROM ada
),
b1 AS (
  SELECT 'B1  Empat tabel skema bintang ada' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('tabel hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   hilang
),

-- B2. dim_tanggal memuat sepuluh tahun penuh, termasuk hari kabisat.
b2 AS (
  SELECT 'B2  dim_tanggal memuat 3.653 hari' AS butir,
         COUNT(*) = 3653 AS lulus,
         COUNT(*) || ' baris (diharapkan 3.653 untuk 2020-2029)' AS detail
  FROM   dim_tanggal
),

-- B3. Kalender memuat atribut, bukan hanya kolom tanggal.
atribut (nama) AS (
  VALUES ('nama_hari'), ('bulan'), ('nama_bulan'), ('kuartal'), ('tahun'),
         ('tahun_bulan'), ('akhir_pekan')
),
atribut_hilang AS (
  SELECT nama FROM atribut
  EXCEPT
  SELECT column_name FROM information_schema.columns
  WHERE  table_schema = 'public' AND table_name = 'dim_tanggal'
),
b3 AS (
  SELECT 'B3  dim_tanggal memuat atribut kalender' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('kolom hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   atribut_hilang
),

-- B4. Surrogate key terpisah dari natural key pada kedua dimensi.
b4 AS (
  SELECT 'B4  Surrogate key terpisah dari natural key' AS butir,
         COUNT(*) = 4 AS lulus,
         'ditemukan ' || COUNT(*) || ' dari 4 kolom yang diharapkan' AS detail
  FROM   information_schema.columns
  WHERE  table_schema = 'public'
    AND  (   (table_name = 'dim_produk' AND column_name IN ('produk_key','produk_id'))
          OR (table_name = 'dim_toko'   AND column_name IN ('toko_key','toko_id')))
),

-- B5. Tabel fakta memiliki foreign key ke ketiga dimensi.
b5 AS (
  SELECT 'B5  Fakta memiliki tiga foreign key dimensi' AS butir,
         COUNT(*) >= 3 AS lulus,
         COUNT(*) || ' foreign key pada fakta_penjualan' AS detail
  FROM   information_schema.table_constraints
  WHERE  table_schema = 'public'
    AND  table_name   = 'fakta_penjualan'
    AND  constraint_type = 'FOREIGN KEY'
),

-- B6. Tidak ada foreign key fakta yang NULL.
b6 AS (
  SELECT 'B6  Tidak ada foreign key fakta yang NULL' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris dengan kunci dimensi NULL' AS detail
  FROM   fakta_penjualan
  WHERE  tanggal_key IS NULL OR produk_key IS NULL OR toko_key IS NULL
),

-- B7. Jumlah baris fakta sesuai staging setelah penyaringan status.
--     Inilah pemeriksaan rekonsiliasi pertama: grain fakta berpadanan satu
--     lawan satu dengan baris struk yang tidak dibatalkan.
b7 AS (
  SELECT 'B7  Jumlah baris fakta sesuai staging' AS butir,
         (SELECT COUNT(*) FROM fakta_penjualan)
         = (SELECT COUNT(*) FROM staging_penjualan WHERE status <> 'BATAL')
         AS lulus,
         'fakta ' || (SELECT COUNT(*) FROM fakta_penjualan)
         || ' lawan staging ' ||
         (SELECT COUNT(*) FROM staging_penjualan WHERE status <> 'BATAL')
         AS detail
),

-- B8. Nilai penjualan gudang sama dengan nilai pada staging.
b8 AS (
  SELECT 'B8  Total nilai penjualan sesuai staging' AS butir,
         ROUND((SELECT COALESCE(SUM(subtotal), 0) FROM fakta_penjualan), 2)
         = ROUND((SELECT COALESCE(SUM(subtotal), 0) FROM staging_penjualan
                  WHERE status <> 'BATAL'), 2) AS lulus,
         'selisih ' ||
         ROUND((SELECT COALESCE(SUM(subtotal), 0) FROM fakta_penjualan)
             - (SELECT COALESCE(SUM(subtotal), 0) FROM staging_penjualan
                WHERE status <> 'BATAL'), 2) AS detail
),

-- B9. Natural key dimensi benar-benar unik. Bila tidak, join ke dimensi akan
--     menggandakan baris fakta dan seluruh agregat menjadi terlalu besar.
b9 AS (
  SELECT 'B9  Natural key dimensi unik' AS butir,
         (SELECT COUNT(*) FROM (SELECT produk_id FROM dim_produk
                                GROUP BY produk_id HAVING COUNT(*) > 1) x)
       + (SELECT COUNT(*) FROM (SELECT toko_id FROM dim_toko
                                GROUP BY toko_id HAVING COUNT(*) > 1) y) = 0
         AS lulus,
         'produk ganda ' ||
         (SELECT COUNT(*) FROM (SELECT produk_id FROM dim_produk
                                GROUP BY produk_id HAVING COUNT(*) > 1) x)
         || ', toko ganda ' ||
         (SELECT COUNT(*) FROM (SELECT toko_id FROM dim_toko
                                GROUP BY toko_id HAVING COUNT(*) > 1) y)
         AS detail
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

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten secara manual:
--
--   B10  Angka ketiga star query sama persis dengan angka dari sumber
--        (berkas rekonsiliasi.md).
--   B11  Pernyataan grain tertulis sebagai komentar pada baris awal ddl.sql.
--   B12  ddl.sql, load.sql, dan query.sql dapat dijalankan berurutan pada
--        basis data kosong tanpa penyuntingan manual.
-- -----------------------------------------------------------------------------
