-- =============================================================================
-- Modul 10 -- Profiling batch beranomali
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-10/01-profiling.sql
--
-- Profiling Modul 1 dikerjakan untuk MEMAHAMI sumber. Profiling di sini
-- dikerjakan untuk MENEMUKAN yang tidak diharapkan -- dan keduanya memakai
-- pemeriksaan yang sama.
--
-- Perbedaannya pada pembanding: sekarang ada profil batch sebelumnya, sehingga
-- yang dicari bukan hanya nilai yang mustahil, melainkan juga nilai yang
-- BERUBAH TANPA SEBAB.
-- =============================================================================

-- =============================================================================
-- 1. PERBANDINGAN ANTARBATCH
--
-- Anomali jenis "menyimpang" hanya terlihat di sini. Kolom yang berubah
-- drastis dari batch sebelumnya adalah calon anomali, meskipun setiap nilainya
-- sendiri masuk akal.
-- =============================================================================
SELECT batch_id,
       COUNT(*)                        AS baris,
       COUNT(DISTINCT toko_id)         AS toko_mengirim,
       COUNT(DISTINCT produk_id)       AS produk_terjual,
       ROUND(AVG(harga_satuan), 2)     AS rata_harga,
       ROUND(AVG(kuantitas), 3)        AS rata_kuantitas,
       ROUND(SUM(subtotal), 2)         AS total_nilai,
       MIN(waktu_transaksi)::DATE      AS transaksi_terlama,
       MAX(waktu_transaksi)::DATE      AS transaksi_terbaru
FROM   staging.penjualan_gabungan
GROUP  BY batch_id
ORDER  BY batch_id;

-- =============================================================================
-- 2. COMPLETENESS -- adakah yang hilang?
-- =============================================================================

-- Proporsi baris fakta yang menunjuk baris unknown. Angka ini bukan kegagalan;
-- ia ukuran seberapa banyak data yang tidak dapat dipetakan.
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE produk_key    = -1)
             / NULLIF(COUNT(*), 0), 3) AS produk_unknown_persen,
       ROUND(100.0 * COUNT(*) FILTER (WHERE toko_key      = -1)
             / NULLIF(COUNT(*), 0), 3) AS toko_unknown_persen,
       ROUND(100.0 * COUNT(*) FILTER (WHERE pelanggan_key = -1)
             / NULLIF(COUNT(*), 0), 3) AS pelanggan_unknown_persen,
       COUNT(*)                        AS total_baris
FROM   gudang.fakta_penjualan;

-- -----------------------------------------------------------------------------
-- ANOMALI YANG PALING SULIT DITEMUKAN.
--
-- Toko yang tidak mengirim data sama sekali tidak menghasilkan satu baris pun,
-- sehingga LUPUT dari seluruh pemeriksaan atas isi tabel. Ia hanya terlihat
-- dengan membandingkan terhadap daftar toko yang SEHARUSNYA mengirim.
--
-- Inilah alasan rekonsiliasi jumlah baris tidak dapat digantikan oleh uji apa
-- pun atas isi tabel.
-- -----------------------------------------------------------------------------
SELECT t.toko_id, t.kode_toko, t.nama_toko, t.provinsi,
       COALESCE(b.baris_batch_ini, 0) AS baris_batch_ini,
       COALESCE(l.rata_baris_lalu, 0) AS rata_baris_batch_lalu
FROM   gudang.dim_toko t
LEFT JOIN ( SELECT toko_id, COUNT(*) AS baris_batch_ini
            FROM   staging.penjualan_gabungan
            WHERE  batch_id = (SELECT MAX(batch_id)
                               FROM staging.penjualan_gabungan)
            GROUP  BY toko_id ) b ON b.toko_id = t.toko_id
LEFT JOIN ( SELECT toko_id, ROUND(AVG(jml), 0) AS rata_baris_lalu
            FROM ( SELECT toko_id, batch_id, COUNT(*) AS jml
                   FROM   staging.penjualan_gabungan
                   WHERE  batch_id < (SELECT MAX(batch_id)
                                      FROM staging.penjualan_gabungan)
                   GROUP  BY toko_id, batch_id ) x
            GROUP  BY toko_id ) l ON l.toko_id = t.toko_id
WHERE  t.toko_id <> -1
  AND  COALESCE(b.baris_batch_ini, 0) = 0
  AND  COALESCE(l.rata_baris_lalu, 0) > 0
ORDER  BY rata_baris_batch_lalu DESC;

-- =============================================================================
-- 3. UNIQUENESS -- adakah yang kembar?
-- =============================================================================

-- Struk yang sama terkirim dari dua sumber berbeda. Kunci gudang tetap unik,
-- sehingga constraint tidak menolaknya -- tetapi transaksinya terhitung dua
-- kali.
SELECT toko_key, nomor_struk, COUNT(*) AS jumlah_kemunculan,
       COUNT(DISTINCT transaksi_id) AS transaksi_berbeda
FROM   gudang.fakta_penjualan
GROUP  BY toko_key, nomor_struk
HAVING COUNT(*) > COUNT(DISTINCT transaksi_id)
    OR COUNT(DISTINCT transaksi_id) > 1
ORDER  BY jumlah_kemunculan DESC
LIMIT  20;

-- =============================================================================
-- 4. VALIDITY -- sesuaikah bentuknya?
-- =============================================================================

-- Nilai yang mustahil menurut aturan bisnis. Sebagian sudah ditolak constraint
-- Modul 5; yang tersisa di sini adalah yang LOLOS constraint karena secara
-- teknis sah.
SELECT COUNT(*) FILTER (WHERE kuantitas <= 0)        AS kuantitas_tidak_positif,
       COUNT(*) FILTER (WHERE harga_satuan <= 0)     AS harga_tidak_positif,
       COUNT(*) FILTER (WHERE diskon < 0)            AS diskon_negatif,
       COUNT(*) FILTER (WHERE diskon > kuantitas * harga_satuan)
                                                     AS diskon_melebihi_nilai
FROM   gudang.fakta_penjualan;

-- Harga yang menyimpang jauh dari kebiasaan produk itu sendiri. Nilainya tetap
-- bilangan positif, sehingga lolos seluruh constraint.
WITH statistik AS (
  SELECT produk_key,
         AVG(harga_satuan)    AS rata,
         STDDEV(harga_satuan) AS simpangan
  FROM   gudang.fakta_penjualan
  GROUP  BY produk_key
  HAVING COUNT(*) >= 30 AND STDDEV(harga_satuan) > 0
)
SELECT f.produk_key, dp.nama_produk, f.harga_satuan,
       ROUND(s.rata, 2) AS rata_harga_produk,
       ROUND(ABS(f.harga_satuan - s.rata) / s.simpangan, 1) AS jarak_simpangan
FROM   gudang.fakta_penjualan f
JOIN   statistik s ON s.produk_key = f.produk_key
JOIN   gudang.dim_produk dp ON dp.produk_key = f.produk_key
WHERE  ABS(f.harga_satuan - s.rata) > 5 * s.simpangan
ORDER  BY jarak_simpangan DESC
LIMIT  20;

-- =============================================================================
-- 5. CONSISTENCY -- cocokkah antarbagian?
-- =============================================================================

-- Aritmetika subtotal. Ketiga kolomnya sendiri-sendiri masuk akal, sehingga
-- tidak ada constraint yang dapat menangkapnya.
SELECT COUNT(*)                                        AS baris_tidak_konsisten,
       ROUND(100.0 * COUNT(*)
             / NULLIF((SELECT COUNT(*) FROM gudang.fakta_penjualan), 0), 3)
                                                       AS persen,
       ROUND(SUM(ABS(ROUND(kuantitas * harga_satuan - diskon, 2) - subtotal)), 2)
                                                       AS total_selisih
FROM   gudang.fakta_penjualan
WHERE  ROUND(kuantitas * harga_satuan - diskon, 2) <> ROUND(subtotal, 2);

-- =============================================================================
-- 6. INTEGRITY -- utuhkah relasinya?
-- =============================================================================
SELECT COUNT(*) AS fakta_tanpa_produk
FROM      gudang.fakta_penjualan f
LEFT JOIN gudang.dim_produk dp ON dp.produk_key = f.produk_key
WHERE     dp.produk_key IS NULL;

-- Fakta yang menunjuk versi dimensi di luar masa berlakunya.
SELECT COUNT(*) AS fakta_salah_versi
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_produk  dp ON dp.produk_key  = f.produk_key
JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
WHERE  f.produk_key <> -1
  AND  (dt.tanggal < dp.mulai_berlaku OR dt.tanggal >= dp.selesai_berlaku);

-- =============================================================================
-- 7. TIMELINESS -- cukup segarkah?
-- =============================================================================

-- Selisih hari antara transaksi terjadi dan baris itu dimuat. Sebagian
-- keterlambatan wajar dan sudah ditangani Modul 7; yang dicari adalah ekor
-- yang jauh lebih panjang daripada biasanya.
SELECT a.batch_id,
       MIN(a.waktu_muat::DATE - dt.tanggal) AS lag_tercepat_hari,
       ROUND(AVG(a.waktu_muat::DATE - dt.tanggal), 1) AS lag_rata_hari,
       MAX(a.waktu_muat::DATE - dt.tanggal) AS lag_terlama_hari,
       COUNT(*) FILTER (WHERE a.waktu_muat::DATE - dt.tanggal > 3)
                                            AS baris_lebih_dari_tiga_hari
FROM   gudang.fakta_penjualan f
JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
JOIN   dbt_mart.dim_audit a  ON a.audit_key   = f.audit_key
WHERE  f.tanggal_key <> -1
GROUP  BY a.batch_id
ORDER  BY a.batch_id;
