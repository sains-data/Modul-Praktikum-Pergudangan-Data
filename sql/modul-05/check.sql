-- =============================================================================
-- Modul 05 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-05/check.sql
--
-- Skrip mencetak satu baris per butir dengan status LULUS atau GAGAL.
-- Butir B3 sampai B5 adalah kriteria lulus utama modul: tidak boleh ada
-- foreign key fakta yang NULL.
-- =============================================================================

\pset border 2
\pset title 'Modul 05 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. Ketiga schema ada.
schema_diharapkan (nama) AS (
  VALUES ('staging'), ('gudang'), ('mart')
),
schema_hilang AS (
  SELECT nama FROM schema_diharapkan
  EXCEPT
  SELECT schema_name FROM information_schema.schemata
),
b1 AS (
  SELECT 'B1  Schema staging, gudang, mart ada' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   schema_hilang
),

-- B2. Tidak ada lagi tabel gudang data yang tertinggal di public.
b2 AS (
  SELECT 'B2  public bersih dari tabel gudang data' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('masih di public: ' ||
                  string_agg(table_name, ', ' ORDER BY table_name),
                  'bersih') AS detail
  FROM   information_schema.tables
  WHERE  table_schema = 'public' AND table_type = 'BASE TABLE'
    AND  (table_name LIKE 'dim\_%' OR table_name LIKE 'fakta\_%'
       OR table_name LIKE 'staging\_%')
),

-- B3. Setiap dimensi memiliki baris unknown berkunci -1.
unknown_ada AS (
  SELECT 'dim_tanggal' AS dimensi,
         EXISTS (SELECT 1 FROM gudang.dim_tanggal WHERE tanggal_key = -1) AS ada
  UNION ALL
  SELECT 'dim_produk',
         EXISTS (SELECT 1 FROM gudang.dim_produk WHERE produk_key = -1)
  UNION ALL
  SELECT 'dim_toko',
         EXISTS (SELECT 1 FROM gudang.dim_toko WHERE toko_key = -1)
  UNION ALL
  SELECT 'dim_transaksi_flag',
         EXISTS (SELECT 1 FROM gudang.dim_transaksi_flag WHERE flag_key = -1)
  UNION ALL
  SELECT 'dim_promosi',
         EXISTS (SELECT 1 FROM gudang.dim_promosi WHERE promosi_key = -1)
),
b3 AS (
  SELECT 'B3  Setiap dimensi punya baris unknown' AS butir,
         COUNT(*) FILTER (WHERE NOT ada) = 0 AS lulus,
         COALESCE('belum ada pada: ' ||
                  string_agg(dimensi, ', ') FILTER (WHERE NOT ada),
                  'lengkap pada lima dimensi') AS detail
  FROM   unknown_ada
),

-- B4. Tidak ada foreign key fakta yang NULL. Ini kriteria lulus utama modul.
b4 AS (
  SELECT 'B4  Tidak ada kunci dimensi fakta yang NULL' AS butir,
         jml = 0 AS lulus,
         jml || ' baris fakta dengan kunci dimensi NULL' AS detail
  FROM ( SELECT (SELECT COUNT(*) FROM gudang.fakta_penjualan
                 WHERE tanggal_key IS NULL OR produk_key IS NULL
                    OR toko_key IS NULL OR flag_key IS NULL)
              + (SELECT COUNT(*) FROM gudang.fakta_persediaan_harian
                 WHERE tanggal_key IS NULL OR produk_key IS NULL
                    OR toko_key IS NULL)
              + (SELECT COUNT(*) FROM gudang.fakta_cakupan_promosi
                 WHERE tanggal_key IS NULL OR produk_key IS NULL
                    OR promosi_key IS NULL) AS jml ) x
),

-- B5. Kolom kunci dimensi pada fakta sudah dideklarasikan NOT NULL, sehingga
--     kesalahan pemuatan berikutnya ditolak, bukan sekadar dibersihkan sekali.
b5 AS (
  SELECT 'B5  Kunci dimensi fakta dideklarasikan NOT NULL' AS butir,
         COUNT(*) FILTER (WHERE is_nullable = 'YES') = 0 AS lulus,
         COALESCE('masih nullable: ' ||
                  string_agg(table_name || '.' || column_name, ', ')
                  FILTER (WHERE is_nullable = 'YES'),
                  'seluruhnya NOT NULL') AS detail
  FROM   information_schema.columns
  WHERE  table_schema = 'gudang'
    AND  table_name LIKE 'fakta\_%'
    AND  column_name LIKE '%\_key'
),

-- B6. Constraint CHECK terpasang pada tabel fakta.
b6 AS (
  SELECT 'B6  Constraint CHECK terpasang pada fakta' AS butir,
         COUNT(*) >= 2 AS lulus,
         COUNT(*) || ' constraint CHECK pada fakta_penjualan' AS detail
  FROM   pg_constraint c
  JOIN   pg_class t ON t.oid = c.conrelid
  JOIN   pg_namespace n ON n.oid = t.relnamespace
  WHERE  n.nspname = 'gudang' AND t.relname = 'fakta_penjualan'
    AND  c.contype = 'c'
),

-- B7. Indeks terpasang pada tabel fakta terbesar.
b7 AS (
  SELECT 'B7  Indeks terpasang pada fakta_penjualan' AS butir,
         COUNT(*) >= 1 AS lulus,
         COUNT(*) || ' indeks non-constraint' AS detail
  FROM   pg_indexes
  WHERE  schemaname = 'gudang' AND tablename = 'fakta_penjualan'
    AND  indexname NOT LIKE '%\_pkey'
),

-- B8. Statistik perencana mutakhir. Tanpa ANALYZE, seluruh pengukuran EXPLAIN
--     mahasiswa menyesatkan dan perbandingan sebelum-sesudah tidak sahih.
b8 AS (
  SELECT 'B8  Statistik perencana sudah dimutakhirkan' AS butir,
         COUNT(*) FILTER (WHERE last_analyze IS NULL
                            AND last_autoanalyze IS NULL) = 0 AS lulus,
         COALESCE('belum di-ANALYZE: ' ||
                  string_agg(relname, ', ') FILTER (WHERE last_analyze IS NULL
                                              AND last_autoanalyze IS NULL),
                  'seluruh tabel gudang sudah') AS detail
  FROM   pg_stat_user_tables
  WHERE  schemaname = 'gudang'
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
-- Lebar baris sebenarnya, untuk dibandingkan dengan hitungan tangan mahasiswa
-- pada kamus-tipe-data.md. Selisih beberapa persen wajar; selisih puluhan
-- persen berarti padding terlewat atau NUMERIC diperkirakan sebagai lebar
-- tetap padahal ukurannya bergantung nilai.
-- -----------------------------------------------------------------------------
SELECT MIN(pg_column_size(f.*))            AS byte_terkecil,
       ROUND(AVG(pg_column_size(f.*)), 1)  AS byte_rata_rata,
       MAX(pg_column_size(f.*))            AS byte_terbesar,
       COUNT(*)                            AS jumlah_baris
FROM   gudang.fakta_penjualan f;

-- Ukuran objek sebenarnya, heap dan indeks dipisah.
SELECT relname AS tabel,
       pg_size_pretty(pg_relation_size(c.oid))       AS heap,
       pg_size_pretty(pg_indexes_size(c.oid))        AS indeks,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'gudang' AND c.relkind = 'r'
ORDER  BY pg_total_relation_size(c.oid) DESC;

-- Pemakaian indeks. Indeks ber-idx_scan nol adalah pemborosan murni: ia
-- memakan ruang dan memperlambat pemuatan tanpa memberi apa pun.
SELECT indexrelname AS indeks,
       idx_scan     AS kali_dipakai,
       pg_size_pretty(pg_relation_size(indexrelid)) AS ukuran
FROM   pg_stat_user_indexes
WHERE  schemaname = 'gudang'
ORDER  BY idx_scan, indexrelname;

-- Berapa baris fakta yang benar-benar memakai baris unknown. Angka ini bukan
-- kegagalan; ia laporan berapa data yang tidak dapat dipetakan, dan wajib
-- dijelaskan pada laporan mahasiswa.
SELECT COUNT(*) FILTER (WHERE produk_key  = -1) AS produk_tidak_diketahui,
       COUNT(*) FILTER (WHERE toko_key    = -1) AS toko_tidak_diketahui,
       COUNT(*) FILTER (WHERE tanggal_key = -1) AS tanggal_tidak_diketahui,
       COUNT(*)                                 AS total_baris
FROM   gudang.fakta_penjualan;

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten secara manual:
--
--   B9   kamus-tipe-data.md memuat perhitungan lebar baris beserta header
--        tuple, line pointer, alignment, dan padding -- bukan sekadar jumlah
--        ukuran kolom.
--   B10  catatan-explain.md membandingkan shared hit dan shared read
--        (halaman), bukan hanya Execution Time, dan menyebutkan bahwa eksekusi
--        kedua membaca dari cache.
--   B11  Setiap perubahan tipe data disertai alasan, dan perubahan satuan uang
--        didukung query yang membuktikan tidak ada nilai berpecahan.
-- -----------------------------------------------------------------------------
