-- =============================================================================
-- Modul 09 -- Contoh query OLAP
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-09/01-query-olap.sql
--
-- Berkas ini contoh, bukan jawaban. Mahasiswa menulis query-olap.sql sendiri
-- untuk pertanyaan bisnisnya masing-masing.
-- =============================================================================

-- =============================================================================
-- 1. ROLLUP -- subtotal menurut hierarki, dari kanan ke kiri.
--
-- ROLLUP(provinsi, kota) menghasilkan TIGA tingkat: per kota, per provinsi,
-- dan total keseluruhan. Urutan kolomnya diandaikan hierarki -- karena itu
-- ROLLUP(kota, provinsi) menghasilkan kelompok yang tidak bermakna.
-- =============================================================================
SELECT CASE WHEN GROUPING(dtk.provinsi) = 1 THEN 'SELURUH INDONESIA'
            ELSE COALESCE(dtk.provinsi, 'Tidak Diketahui') END AS provinsi,
       CASE WHEN GROUPING(dtk.kota) = 1 THEN 'Seluruh provinsi'
            ELSE COALESCE(dtk.kota, 'Tidak Diketahui') END      AS kota,
       SUM(f.subtotal)                             AS nilai_penjualan,
       COUNT(*)                                    AS baris_fakta,
       GROUPING(dtk.provinsi) + GROUPING(dtk.kota) AS tingkat
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_toko    dtk ON dtk.toko_key   = f.toko_key
JOIN   gudang.dim_tanggal dt  ON dt.tanggal_key = f.tanggal_key
WHERE  dt.tahun = 2024
GROUP  BY ROLLUP (dtk.provinsi, dtk.kota)
ORDER  BY tingkat, provinsi, kota;

-- -----------------------------------------------------------------------------
-- PERAGAAN: yang terjadi bila GROUPING tidak dipakai.
--
-- Jalankan query berikut, lalu bandingkan dengan yang di atas. Baris subtotal
-- dan baris data yang provinsinya memang kosong sama-sama berlabel
-- "Tidak Diketahui" -- dua baris berlabel sama dengan arti yang sama sekali
-- berbeda. Laporan semacam ini lebih buruk daripada laporan yang gagal dibuat.
-- -----------------------------------------------------------------------------
SELECT COALESCE(dtk.provinsi, 'Tidak Diketahui') AS provinsi,
       COALESCE(dtk.kota, 'Tidak Diketahui')     AS kota,
       SUM(f.subtotal) AS nilai_penjualan
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_toko    dtk ON dtk.toko_key   = f.toko_key
JOIN   gudang.dim_tanggal dt  ON dt.tanggal_key = f.tanggal_key
WHERE  dt.tahun = 2024
GROUP  BY ROLLUP (dtk.provinsi, dtk.kota)
ORDER  BY 1, 2;

-- =============================================================================
-- 2. ROLLUP lawan CUBE lawan GROUPING SETS
--
-- Untuk n kolom:
--   ROLLUP        -> n + 1 tingkat
--   CUBE          -> 2^n tingkat
--   GROUPING SETS -> persis yang disebut
--
-- Bandingkan jumlah barisnya, lalu putuskan apakah tingkat tambahan CUBE
-- memang diperlukan laporan Anda. Tingkat yang tidak dipakai tetap harus
-- dihitung.
-- =============================================================================
WITH dasar AS (
  SELECT dp.kategori, dt.tahun_bulan, f.subtotal
  FROM   gudang.fakta_penjualan f
  JOIN   gudang.dim_produk  dp ON dp.produk_key  = f.produk_key
  JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
  WHERE  dt.tahun = 2024
)
SELECT 'ROLLUP' AS konstruksi, COUNT(*) AS jumlah_baris FROM (
  SELECT kategori, tahun_bulan FROM dasar
  GROUP BY ROLLUP (kategori, tahun_bulan)) a
UNION ALL
SELECT 'CUBE', COUNT(*) FROM (
  SELECT kategori, tahun_bulan FROM dasar
  GROUP BY CUBE (kategori, tahun_bulan)) b
UNION ALL
SELECT 'GROUPING SETS', COUNT(*) FROM (
  SELECT kategori, tahun_bulan FROM dasar
  GROUP BY GROUPING SETS ((kategori, tahun_bulan), ())) c;

-- =============================================================================
-- 3. Window function
--
-- GROUP BY meringkas beberapa baris menjadi satu. Window function menghitung
-- nilai agregat TANPA meringkas: setiap baris tetap ada dan memperoleh kolom
-- tambahan yang dihitung dari sekelompok baris di sekitarnya.
-- =============================================================================

-- 3a. Peringkat produk di dalam kategorinya, beserta pangsanya.
--
-- Perhatikan SUM(SUM(...)) OVER (...). Bentuk bertumpuk ini benar dan bukan
-- salah ketik: agregat bagian dalam dihitung lebih dahulu oleh GROUP BY, lalu
-- window function bekerja atas hasil agregat itu.
SELECT dp.kategori,
       dp.nama_produk,
       SUM(f.subtotal) AS nilai,
       RANK() OVER (PARTITION BY dp.kategori
                    ORDER BY SUM(f.subtotal) DESC) AS peringkat,
       ROUND(100.0 * SUM(f.subtotal)
             / SUM(SUM(f.subtotal)) OVER (PARTITION BY dp.kategori), 2)
         AS pangsa_kategori_persen
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_produk  dp ON dp.produk_key  = f.produk_key
JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
WHERE  dt.tahun = 2024
GROUP  BY dp.kategori, dp.nama_produk
ORDER  BY dp.kategori, peringkat
LIMIT  50;

-- 3b. Perbandingan terhadap bulan sebelumnya.
--     NULLIF menjaga agar pembagian oleh nol menghasilkan NULL, bukan galat.
SELECT tahun_bulan, kategori, nilai_penjualan,
       LAG(nilai_penjualan) OVER (PARTITION BY kategori
                                  ORDER BY tahun_bulan) AS bulan_lalu,
       ROUND(100.0 * (nilai_penjualan
             - LAG(nilai_penjualan) OVER (PARTITION BY kategori
                                          ORDER BY tahun_bulan))
             / NULLIF(LAG(nilai_penjualan) OVER (PARTITION BY kategori
                                                 ORDER BY tahun_bulan), 0), 2)
         AS pertumbuhan_persen
FROM   mart.v_penjualan_bulanan
ORDER  BY kategori, tahun_bulan;

-- 3c. Total berjalan sepanjang tahun.
SELECT tahun_bulan, kategori, nilai_penjualan,
       SUM(nilai_penjualan) OVER (PARTITION BY kategori, tahun
                                  ORDER BY tahun_bulan
                                  ROWS UNBOUNDED PRECEDING) AS total_berjalan
FROM   mart.v_penjualan_bulanan
ORDER  BY kategori, tahun_bulan;

-- 3d. Rata-rata bergerak tiga bulan, untuk meredam fluktuasi.
SELECT tahun_bulan, kategori, nilai_penjualan,
       ROUND(AVG(nilai_penjualan) OVER (PARTITION BY kategori
                                        ORDER BY tahun_bulan
                                        ROWS BETWEEN 2 PRECEDING
                                                 AND CURRENT ROW), 2)
         AS rata_tiga_bulan
FROM   mart.v_penjualan_bulanan
ORDER  BY kategori, tahun_bulan;

-- =============================================================================
-- 4. Dataset untuk chart keempat: drill-across penjualan dan persediaan.
--
-- Ini dataset virtual Superset. Perhatikan bahwa kedua fakta diagregasi
-- TERPISAH lebih dahulu, lalu disandingkan lewat atribut dimensi -- aturan
-- Modul 4 yang tetap berlaku sampai lapisan tampilan.
--
-- Measure semi-aditif memakai AVG, bukan SUM.
-- =============================================================================
CREATE OR REPLACE VIEW mart.v_penjualan_lawan_persediaan AS
WITH penjualan AS (
  SELECT dt.tahun_bulan, dp.kategori, dtk.provinsi,
         SUM(f.kuantitas) AS unit_terjual,
         SUM(f.subtotal)  AS nilai_penjualan
  FROM   gudang.fakta_penjualan f
  JOIN   gudang.dim_tanggal dt  ON dt.tanggal_key = f.tanggal_key
  JOIN   gudang.dim_produk  dp  ON dp.produk_key  = f.produk_key
  JOIN   gudang.dim_toko    dtk ON dtk.toko_key   = f.toko_key
  GROUP  BY 1, 2, 3
),
persediaan AS (
  SELECT dt.tahun_bulan, dp.kategori, dtk.provinsi,
         ROUND(AVG(p.saldo_akhir), 2) AS rata_saldo   -- AVG, bukan SUM
  FROM   gudang.fakta_persediaan_harian p
  JOIN   gudang.dim_tanggal dt  ON dt.tanggal_key = p.tanggal_key
  JOIN   gudang.dim_produk  dp  ON dp.produk_key  = p.produk_key
  JOIN   gudang.dim_toko    dtk ON dtk.toko_key   = p.toko_key
  GROUP  BY 1, 2, 3
)
SELECT COALESCE(j.tahun_bulan, s.tahun_bulan) AS tahun_bulan,
       COALESCE(j.kategori,    s.kategori)    AS kategori,
       COALESCE(j.provinsi,    s.provinsi)    AS provinsi,
       j.unit_terjual,
       j.nilai_penjualan,
       s.rata_saldo,
       ROUND(j.unit_terjual / NULLIF(s.rata_saldo, 0), 2) AS perputaran
FROM       penjualan  j
FULL OUTER JOIN persediaan s
       ON  s.tahun_bulan = j.tahun_bulan
       AND s.kategori    = j.kategori
       AND s.provinsi    = j.provinsi;

COMMENT ON VIEW mart.v_penjualan_lawan_persediaan IS
  'Drill-across penjualan dan persediaan lewat dimensi bersama. Baris dengan '
  'unit_terjual NULL berarti ada stok tanpa penjualan; baris dengan '
  'rata_saldo NULL berarti ada penjualan tanpa catatan persediaan -- yang '
  'kedua ini temuan kualitas data yang layak dilaporkan.';
