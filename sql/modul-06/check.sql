-- =============================================================================
-- Modul 06 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434), dataset ukuran SEDANG
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-06/check.sql
--
-- Skrip mencetak satu baris per butir dengan status LULUS atau GAGAL.
-- Butir B1 memeriksa hal yang paling sering terlewat: dataset yang dipakai
-- masih berukuran kecil, sehingga seluruh pengukuran modul ini tidak bermakna.
-- =============================================================================

\pset border 2
\pset title 'Modul 06 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. Dataset berukuran sedang, bukan kecil. Pada 100 ribu baris, sequential
--     scan memang menang dan pruning tidak memperlihatkan apa pun.
b1 AS (
  SELECT 'B1  Dataset berukuran sedang' AS butir,
         COUNT(*) >= 1000000 AS lulus,
         COUNT(*) || ' baris fakta (diharapkan >= 1 juta)' AS detail
  FROM   gudang.fakta_penjualan
),

-- B2. Tabel fakta benar-benar berpartisi menurut rentang.
b2 AS (
  SELECT 'B2  fakta_penjualan berpartisi RANGE' AS butir,
         COUNT(*) = 1 AS lulus,
         COALESCE(MAX(CASE partstrat WHEN 'r' THEN 'RANGE'
                                     WHEN 'l' THEN 'LIST'
                                     WHEN 'h' THEN 'HASH' END),
                  'tabel belum berpartisi') AS detail
  FROM ( SELECT p.partstrat
         FROM   pg_partitioned_table p
         JOIN   pg_class c ON c.oid = p.partrelid
         JOIN   pg_namespace n ON n.oid = c.relnamespace
         WHERE  n.nspname = 'gudang' AND c.relname = 'fakta_penjualan' ) x
),

-- B3. Jumlah partisi bulanan memadai.
partisi AS (
  SELECT c.relname, c.oid
  FROM   pg_class c
  JOIN   pg_inherits i ON i.inhrelid = c.oid
  JOIN   pg_class p ON p.oid = i.inhparent
  JOIN   pg_namespace n ON n.oid = p.relnamespace
  WHERE  n.nspname = 'gudang' AND p.relname = 'fakta_penjualan'
),
b3 AS (
  SELECT 'B3  Partisi bulanan terbentuk' AS butir,
         COUNT(*) >= 12 AS lulus,
         COUNT(*) || ' partisi' AS detail
  FROM   partisi
),

-- B4. Partisi DEFAULT ada. Tanpanya, baris unknown Modul 5 (tanggal_key = -1)
--     membuat pemindahan data gagal.
b4 AS (
  SELECT 'B4  Partisi DEFAULT penampung ada' AS butir,
         COUNT(*) >= 1 AS lulus,
         CASE WHEN COUNT(*) >= 1 THEN 'ada'
              ELSE 'belum ada -- baris tanggal_key = -1 tidak punya tempat'
         END AS detail
  FROM   pg_class c
  JOIN   pg_inherits i ON i.inhrelid = c.oid
  JOIN   pg_class p ON p.oid = i.inhparent
  WHERE  p.relname = 'fakta_penjualan'
    AND  pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT'
),

-- B5. Pemindahan tidak kehilangan baris. Dibandingkan terhadap tabel lama bila
--     masih disimpan sebagai cadangan.
b5 AS (
  SELECT 'B5  Pemindahan tidak kehilangan baris' AS butir,
         CASE WHEN NOT ada_lama THEN TRUE
              ELSE selisih = 0 END AS lulus,
         CASE WHEN NOT ada_lama
              THEN 'tabel cadangan sudah dihapus, tidak dapat dibandingkan'
              ELSE 'selisih ' || selisih || ' baris' END AS detail
  FROM ( SELECT EXISTS (SELECT 1 FROM information_schema.tables
                        WHERE table_schema = 'gudang'
                          AND table_name = 'fakta_penjualan_lama') AS ada_lama,
                COALESCE((SELECT COUNT(*) FROM gudang.fakta_penjualan)
                       - (SELECT COUNT(*) FROM gudang.fakta_penjualan_lama), 0)
                AS selisih ) x
),

-- B6. Aggregate table dan materialized view ada pada schema mart.
objek (nama, jenis) AS (
  VALUES ('agg_penjualan_bulanan', 'r'), ('mv_penjualan_bulanan', 'm')
),
objek_hilang AS (
  SELECT o.nama FROM objek o
  WHERE  NOT EXISTS (SELECT 1 FROM pg_class c
                     JOIN pg_namespace n ON n.oid = c.relnamespace
                     WHERE n.nspname = 'mart' AND c.relname = o.nama
                       AND c.relkind = o.jenis)
),
b6 AS (
  SELECT 'B6  Aggregate table dan MV ada di mart' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'keduanya ada') AS detail
  FROM   objek_hilang
),

-- B7. Keduanya menghasilkan angka yang sama. Bila berbeda, salah satunya belum
--     disegarkan setelah fakta berubah -- risiko yang dibahas pada Konsep Dasar.
b7 AS (
  SELECT 'B7  Agregat dan MV menghasilkan angka sama' AS butir,
         COALESCE(selisih, -1) = 0 AS lulus,
         CASE WHEN selisih IS NULL
              THEN 'tidak dapat dibandingkan, salah satu objek belum ada'
              ELSE selisih || ' baris berbeda' END AS detail
  FROM ( SELECT (SELECT COUNT(*) FROM (
                   SELECT tahun_bulan, kategori, provinsi, nilai_penjualan
                   FROM   mart.agg_penjualan_bulanan
                   EXCEPT
                   SELECT tahun_bulan, kategori, provinsi, nilai_penjualan
                   FROM   mart.mv_penjualan_bulanan) d) AS selisih ) x
),

-- B8. Statistik perencana mutakhir untuk dataset sedang. Statistik dari
--     dataset kecil membuat perencana memilih rencana yang keliru.
b8 AS (
  SELECT 'B8  Statistik mutakhir untuk dataset sedang' AS butir,
         COALESCE(MAX(n_live_tup), 0) >= 1000000 AS lulus,
         'perencana mengira ada ' || COALESCE(MAX(n_live_tup), 0) || ' baris'
         AS detail
  FROM   pg_stat_user_tables
  WHERE  schemaname = 'gudang' AND relname = 'fakta_penjualan'
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

-- =============================================================================
-- Peragaan pruning, dibaca asisten bersama mahasiswa.
--
-- Rencana pertama menyaring lewat dim_tanggal saja: seluruh partisi dibaca.
-- Rencana kedua menambahkan predikat atas kunci partisi: hanya enam partisi
-- yang tersisa. Kedua query menghasilkan angka yang SAMA -- yang berbeda hanya
-- berapa banyak data yang harus dibaca untuk memperolehnya.
-- =============================================================================

\echo '--- TANPA predikat kunci partisi: pruning TIDAK terjadi ---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT dp.kategori, dt.tahun_bulan, SUM(f.subtotal)
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
JOIN   gudang.dim_produk  dp ON dp.produk_key  = f.produk_key
JOIN   gudang.dim_toko   dtk ON dtk.toko_key   = f.toko_key
WHERE  dtk.provinsi = 'Lampung'
  AND  dt.tanggal BETWEEN DATE '2024-01-01' AND DATE '2024-06-30'
GROUP  BY 1, 2;

\echo '--- DENGAN predikat kunci partisi: pruning terjadi ---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT dp.kategori, dt.tahun_bulan, SUM(f.subtotal)
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
JOIN   gudang.dim_produk  dp ON dp.produk_key  = f.produk_key
JOIN   gudang.dim_toko   dtk ON dtk.toko_key   = f.toko_key
WHERE  dtk.provinsi = 'Lampung'
  AND  f.tanggal_key BETWEEN 20240101 AND 20240630
  AND  dt.tanggal BETWEEN DATE '2024-01-01' AND DATE '2024-06-30'
GROUP  BY 1, 2;

-- -----------------------------------------------------------------------------
-- Ruang yang dibayar setiap tindakan.
-- -----------------------------------------------------------------------------
SELECT 'fakta_penjualan (seluruh partisi)' AS objek,
       pg_size_pretty(pg_total_relation_size('gudang.fakta_penjualan')) AS ukuran
UNION ALL
SELECT 'mart.agg_penjualan_bulanan',
       pg_size_pretty(pg_total_relation_size('mart.agg_penjualan_bulanan'))
UNION ALL
SELECT 'mart.mv_penjualan_bulanan',
       pg_size_pretty(pg_total_relation_size('mart.mv_penjualan_bulanan'));

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten secara manual:
--
--   B9   catatan-optimisasi.md memuat DUA keluaran EXPLAIN berdampingan
--        sebagai bukti pruning, bukan sekadar pernyataan bahwa pruning terjadi.
--   B10  Tabel sebelum-sesudah memuat kolom HALAMAN, bukan hanya detik, dan
--        menyebutkan eksekusi keberapa setiap angka diambil.
--   B11  Setiap tindakan disertai keterangan apa yang dibeli dan apa yang
--        dibayar -- ruang, waktu pemuatan, atau kesegaran data.
--   B12  Perbandingan Northwind membahas BENTUK query (jumlah join, kedalaman
--        rantai), bukan waktu eksekusi.
-- -----------------------------------------------------------------------------
