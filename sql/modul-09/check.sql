-- =============================================================================
-- Modul 09 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-09/check.sql
--
-- Sebagian besar butir modul ini berada di luar basis data: dashboard, chart,
-- filter, dan penilaian pertanyaan Modul 1. Skrip ini memeriksa yang berada di
-- dalam basis data, dan menyediakan angka acuan yang dipakai asisten untuk
-- memvalidasi angka pada dashboard.
-- =============================================================================

\pset border 2
\pset title 'Modul 09 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. Schema mart terisi dan dapat dibaca Superset.
b1 AS (
  SELECT 'B1  Schema mart memuat objek siap saji' AS butir,
         COUNT(*) >= 1 AS lulus,
         COUNT(*) || ' view atau tabel pada mart' AS detail
  FROM   information_schema.tables
  WHERE  table_schema = 'mart'
),

-- B2. View drill-across untuk chart keempat ada.
b2 AS (
  SELECT 'B2  View drill-across tersedia' AS butir,
         COUNT(*) = 1 AS lulus,
         CASE WHEN COUNT(*) = 1 THEN 'ada'
              ELSE 'v_penjualan_lawan_persediaan belum dibuat' END AS detail
  FROM   information_schema.views
  WHERE  table_schema = 'mart'
    AND  table_name = 'v_penjualan_lawan_persediaan'
),

-- B3. Superset memerlukan pengguna basis data yang dapat membaca mart.
--     Hak baca yang kurang adalah penyebab "permission denied" yang sering
--     disalahartikan sebagai galat koneksi.
b3 AS (
  SELECT 'B3  Hak baca schema mart tersedia' AS butir,
         has_schema_privilege(CURRENT_USER, 'mart', 'USAGE') AS lulus,
         CASE WHEN has_schema_privilege(CURRENT_USER, 'mart', 'USAGE')
              THEN 'USAGE tersedia untuk ' || CURRENT_USER
              ELSE 'USAGE belum diberikan' END AS detail
),

-- B4. Sanity check subtotal: total ROLLUP harus sama dengan agregasi biasa.
--     Bila berbeda, biasanya ada baris fakta yang tidak menemukan pasangan
--     dimensi dan terbuang oleh INNER JOIN pada salah satu query.
b4 AS (
  SELECT 'B4  Total ROLLUP sama dengan total biasa' AS butir,
         selisih = 0 AS lulus,
         'selisih ' || selisih AS detail
  FROM ( SELECT
           (SELECT COALESCE(SUM(subtotal), 0) FROM gudang.fakta_penjualan)
         - (SELECT COALESCE(SUM(nilai), 0) FROM (
              SELECT SUM(f.subtotal) AS nilai,
                     GROUPING(dtk.provinsi) AS g
              FROM   gudang.fakta_penjualan f
              JOIN   gudang.dim_toko dtk ON dtk.toko_key = f.toko_key
              GROUP  BY ROLLUP (dtk.provinsi)
              HAVING GROUPING(dtk.provinsi) = 1) r)
           AS selisih ) x
),

-- B5. Angka mart sama dengan angka fakta. Mart yang belum disegarkan setelah
--     fakta berubah adalah sumber selisih dashboard yang paling sering --
--     risiko yang sudah disebut pada Modul 6.
b5 AS (
  SELECT 'B5  Angka mart sesuai dengan fakta' AS butir,
         selisih = 0 AS lulus,
         'selisih ' || selisih || ' -- mart mungkin perlu disegarkan' AS detail
  FROM ( SELECT
           (SELECT COALESCE(SUM(nilai_penjualan), 0)
            FROM   mart.v_penjualan_bulanan)
         - (SELECT COALESCE(SUM(subtotal), 0) FROM gudang.fakta_penjualan)
           AS selisih ) x
)

SELECT butir,
       CASE WHEN lulus THEN 'LULUS' ELSE 'GAGAL' END AS status,
       detail
FROM (
  SELECT * FROM b1 UNION ALL SELECT * FROM b2 UNION ALL SELECT * FROM b3
  UNION ALL SELECT * FROM b4 UNION ALL SELECT * FROM b5
) hasil
ORDER BY butir;

-- =============================================================================
-- Angka acuan untuk memvalidasi dashboard.
--
-- Asisten membandingkan angka pada chart mahasiswa dengan keluaran di bawah.
-- Bila berbeda, sebabnya hampir selalu salah satu dari tiga hal: cache
-- Superset yang belum dikosongkan, filter yang tidak sama, atau mart yang
-- belum disegarkan.
-- =============================================================================

\echo '--- Acuan chart 1: total nilai penjualan per tahun ---'
SELECT dt.tahun,
       SUM(f.subtotal) AS nilai_penjualan,
       COUNT(*)        AS baris_fakta
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
GROUP  BY dt.tahun
ORDER  BY dt.tahun;

\echo '--- Acuan chart 2: nilai penjualan per kategori per bulan (10 teratas) ---'
SELECT dt.tahun_bulan, dp.kategori, SUM(f.subtotal) AS nilai_penjualan
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
JOIN   gudang.dim_produk  dp ON dp.produk_key  = f.produk_key
GROUP  BY 1, 2
ORDER  BY nilai_penjualan DESC
LIMIT  10;

\echo '--- Acuan chart 3: sepuluh produk teratas per provinsi ---'
SELECT dtk.provinsi, dp.nama_produk, SUM(f.subtotal) AS nilai_penjualan
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_toko   dtk ON dtk.toko_key   = f.toko_key
JOIN   gudang.dim_produk dp  ON dp.produk_key  = f.produk_key
GROUP  BY 1, 2
ORDER  BY nilai_penjualan DESC
LIMIT  10;

-- Peragaan GROUPING: bandingkan kedua kolom label pada keluaran yang sama.
--
-- Kolom "label_benar" memakai GROUPING lebih dahulu; kolom "label_keliru"
-- hanya memakai COALESCE. Perhatikan baris mana yang berlabel sama pada kolom
-- kedua padahal artinya berbeda -- satu subtotal, satu data tanpa provinsi.
\echo '--- Peragaan GROUPING: subtotal lawan data kosong ---'
SELECT CASE WHEN GROUPING(dtk.provinsi) = 1 THEN 'SELURUH INDONESIA'
            ELSE COALESCE(dtk.provinsi, 'Tidak Diketahui') END AS label_benar,
       COALESCE(dtk.provinsi, 'Tidak Diketahui')               AS label_keliru,
       GROUPING(dtk.provinsi)                                  AS ini_subtotal,
       SUM(f.subtotal)                                         AS nilai
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_toko dtk ON dtk.toko_key = f.toko_key
GROUP  BY ROLLUP (dtk.provinsi)
ORDER  BY ini_subtotal, label_benar;

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten di luar basis data:
--
--   B6   query-olap.sql memuat ROLLUP, CUBE, GROUPING SETS, dan sekurang-
--        kurangnya dua window function.
--   B7   Baris subtotal dibedakan dengan GROUPING, bukan hanya COALESCE.
--   B8   catatan-explain-olap.md membandingkan HALAMAN, bukan hanya detik, dan
--        menunjukkan berapa kali tabel fakta dibaca oleh GROUPING SETS
--        dibandingkan UNION ALL.
--   B9   Dashboard memuat empat chart dan dua filter yang berfungsi; filter
--        provinsi mengubah SELURUH chart.
--   B10  Setiap chart memiliki deskripsi yang menyebut pertanyaan yang dijawab
--        dan fact table sumber angkanya.
--   B11  telusur-angka-dashboard.md menunjukkan satu angka cocok pada keempat
--        langkah: chart, dataset, mart, dan fakta.
--   B12  penilaian-pertanyaan-modul-1.md menilai keempat pertanyaan Modul 1
--        beserta alasannya. Pertanyaan yang TIDAK terjawab adalah hasil yang
--        sah dan harus disertai keterangan apa yang kurang.
--   B13  dashboard-nusamart.zip dikumpulkan -- ekspor, bukan tangkapan layar.
-- -----------------------------------------------------------------------------
