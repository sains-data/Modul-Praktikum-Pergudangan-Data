-- =============================================================================
-- Modul 04 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-04/check.sql
--
-- Skrip mencetak satu baris per butir dengan status LULUS atau GAGAL.
-- Butir B4 sampai B7 memeriksa hal yang membedakan modul ini: grain periodic
-- snapshot, ketiadaan measure pada factless fact, dan keutuhan dimensi bersama.
-- =============================================================================

\pset border 2
\pset title 'Modul 04 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. Ketiga tabel fakta ada.
diharapkan (nama) AS (
  VALUES ('fakta_penjualan'), ('fakta_persediaan_harian'),
         ('fakta_cakupan_promosi')
),
hilang AS (
  SELECT nama FROM diharapkan
  EXCEPT
  SELECT table_name FROM information_schema.tables
  WHERE  table_schema = 'public' AND table_type = 'BASE TABLE'
),
b1 AS (
  SELECT 'B1  Tiga tabel fakta ada' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   hilang
),

-- B2. fakta_penjualan menunjuk junk dimension Modul 3.
b2 AS (
  SELECT 'B2  fakta_penjualan menunjuk dim_transaksi_flag' AS butir,
         COUNT(*) >= 1 AS lulus,
         CASE WHEN COUNT(*) >= 1 THEN 'foreign key terpasang'
              ELSE 'flag_key belum dihubungkan' END AS detail
  FROM   information_schema.referential_constraints rc
  JOIN   information_schema.table_constraints tc
         ON tc.constraint_name = rc.constraint_name
  JOIN   information_schema.constraint_column_usage ccu
         ON ccu.constraint_name = rc.unique_constraint_name
  WHERE  tc.table_name = 'fakta_penjualan'
    AND  ccu.table_name = 'dim_transaksi_flag'
),

-- B3. Setiap fakta memiliki foreign key ke dimensi bersama.
b3 AS (
  SELECT 'B3  Setiap fakta menunjuk dimensi bersama' AS butir,
         MIN(jml) >= 2 AS lulus,
         string_agg(nama || '=' || jml, ', ' ORDER BY nama) AS detail
  FROM ( SELECT tc.table_name AS nama, COUNT(*) AS jml
         FROM   information_schema.table_constraints tc
         WHERE  tc.table_schema = 'public'
           AND  tc.constraint_type = 'FOREIGN KEY'
           AND  tc.table_name IN ('fakta_penjualan', 'fakta_persediaan_harian',
                                  'fakta_cakupan_promosi')
         GROUP  BY tc.table_name ) x
),

-- B4. Periodic snapshot dijaga grainnya oleh primary key gabungan.
b4 AS (
  SELECT 'B4  Periodic snapshot punya PK gabungan' AS butir,
         COUNT(*) = 3 AS lulus,
         COUNT(*) || ' kolom pada primary key (diharapkan 3)' AS detail
  FROM   information_schema.key_column_usage kcu
  JOIN   information_schema.table_constraints tc
         ON tc.constraint_name = kcu.constraint_name
  WHERE  tc.table_schema = 'public'
    AND  tc.table_name   = 'fakta_persediaan_harian'
    AND  tc.constraint_type = 'PRIMARY KEY'
),

-- B5. Grain periodic snapshot benar-benar unik pada datanya.
b5 AS (
  SELECT 'B5  Grain persediaan unik pada data' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' kombinasi hari-produk-toko ganda' AS detail
  FROM ( SELECT tanggal_key, produk_key, toko_key
         FROM   fakta_persediaan_harian
         GROUP  BY tanggal_key, produk_key, toko_key
         HAVING COUNT(*) > 1 ) x
),

-- B6. Factless fact benar-benar tanpa measure: seluruh kolomnya kunci dimensi.
b6 AS (
  SELECT 'B6  Factless fact tanpa kolom measure' AS butir,
         COUNT(*) FILTER (WHERE column_name NOT LIKE '%\_key') = 0 AS lulus,
         COALESCE('kolom bukan kunci: ' ||
                  string_agg(column_name, ', ')
                  FILTER (WHERE column_name NOT LIKE '%\_key'),
                  'seluruh kolom adalah kunci dimensi') AS detail
  FROM   information_schema.columns
  WHERE  table_schema = 'public' AND table_name = 'fakta_cakupan_promosi'
),

-- B7. Tidak ada baris fakta yang menunjuk versi dimensi di luar masa
--     berlakunya. Diperiksa untuk ketiga fakta sekaligus.
salah_versi AS (
  SELECT COUNT(*) AS jml FROM (
    SELECT 1 FROM fakta_penjualan f
    JOIN   dim_produk  dp ON dp.produk_key  = f.produk_key
    JOIN   dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
    WHERE  dt.tanggal < dp.mulai_berlaku OR dt.tanggal >= dp.selesai_berlaku
    UNION ALL
    SELECT 1 FROM fakta_persediaan_harian p
    JOIN   dim_produk  dp ON dp.produk_key  = p.produk_key
    JOIN   dim_tanggal dt ON dt.tanggal_key = p.tanggal_key
    WHERE  dt.tanggal < dp.mulai_berlaku OR dt.tanggal >= dp.selesai_berlaku
    UNION ALL
    SELECT 1 FROM fakta_cakupan_promosi c
    JOIN   dim_produk  dp ON dp.produk_key  = c.produk_key
    JOIN   dim_tanggal dt ON dt.tanggal_key = c.tanggal_key
    WHERE  dt.tanggal < dp.mulai_berlaku OR dt.tanggal >= dp.selesai_berlaku
  ) x
),
b7 AS (
  SELECT 'B7  Fakta menunjuk versi dimensi yang berlaku' AS butir,
         jml = 0 AS lulus,
         jml || ' baris menunjuk versi di luar masa berlakunya' AS detail
  FROM   salah_versi
),

-- B8. Tidak ada foreign key fakta yang NULL.
b8 AS (
  SELECT 'B8  Tidak ada kunci dimensi yang NULL' AS butir,
         jml = 0 AS lulus,
         jml || ' baris dengan kunci dimensi NULL' AS detail
  FROM ( SELECT (SELECT COUNT(*) FROM fakta_penjualan
                 WHERE tanggal_key IS NULL OR produk_key IS NULL
                    OR toko_key IS NULL OR flag_key IS NULL)
              + (SELECT COUNT(*) FROM fakta_persediaan_harian
                 WHERE tanggal_key IS NULL OR produk_key IS NULL
                    OR toko_key IS NULL)
              + (SELECT COUNT(*) FROM fakta_cakupan_promosi
                 WHERE tanggal_key IS NULL OR produk_key IS NULL
                    OR promosi_key IS NULL) AS jml ) x
)

SELECT butir,
       CASE WHEN lulus THEN 'LULUS' ELSE 'GAGAL' END AS status,
       detail
FROM (
  SELECT * FROM b1 UNION ALL SELECT * FROM b2 UNION ALL SELECT * FROM b3
  UNION ALL SELECT * FROM b4 UNION ALL SELECT * FROM b5
  UNION ALL SELECT * FROM b6 UNION ALL SELECT * FROM b7
  UNION ALL SELECT * FROM b8
) hasil
ORDER BY butir;

-- -----------------------------------------------------------------------------
-- Peragaan penggandaan measure, dibaca asisten bersama mahasiswa.
--
-- Kolom "saldo_via_join" dihitung dengan men-join dua fakta pada tingkat
-- detail; kolom "saldo_sebenarnya" dihitung langsung dari satu fakta.
-- Selisihnya adalah akibat penggandaan, dan itulah alasan drill-across ada.
-- -----------------------------------------------------------------------------
SELECT (SELECT ROUND(SUM(p.saldo_akhir), 2)
        FROM   fakta_penjualan f
        JOIN   fakta_persediaan_harian p
               ON  p.tanggal_key = f.tanggal_key
               AND p.produk_key  = f.produk_key
               AND p.toko_key    = f.toko_key)      AS saldo_via_join,
       (SELECT ROUND(SUM(saldo_akhir), 2)
        FROM   fakta_persediaan_harian)             AS saldo_sebenarnya;

-- Jumlah baris setiap fakta. Periodic snapshot yang padat lazimnya lebih besar
-- daripada transaction fact yang jarang.
SELECT 'fakta_penjualan'         AS tabel, COUNT(*) FROM fakta_penjualan
UNION ALL
SELECT 'fakta_persediaan_harian', COUNT(*) FROM fakta_persediaan_harian
UNION ALL
SELECT 'fakta_cakupan_promosi',   COUNT(*) FROM fakta_cakupan_promosi
ORDER BY 1;

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten secara manual:
--
--   B9   grain.md memuat tiga pernyataan grain, jenis fakta, dan alasannya.
--   B10  drill-across.sql mengagregasi setiap fakta lebih dahulu, memakai AVG
--        untuk measure semi-aditif, dan menyandingkan dengan FULL OUTER JOIN.
--   B11  catatan-additivity.md memuat perbandingan SUM lawan AVG beserta
--        rasionya.
-- -----------------------------------------------------------------------------
