-- =============================================================================
-- Modul 10 -- Rekonsiliasi sumber lawan gudang
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw \
--     -v tanggal_batch="'2024-06-15'" -v tanggal_key=20240615 \
--     -f /sql/modul-10/02-reconciliation.sql
--
-- Rekonsiliasi lintas basis data mungkin dilakukan berkat postgres_fdw yang
-- dipasang pada Modul 7. Sebelum itu, pemeriksaan semacam ini harus dikerjakan
-- manual dengan menyandingkan dua keluaran query.
--
-- EMPAT besaran diperiksa, dan keempatnya diperlukan karena masing-masing buta
-- terhadap yang lain:
--
--   jumlah baris    -> baris hilang atau kembar saat pemuatan
--   transaksi unik  -> baris kembar yang MENGGANTIKAN, bukan menambah
--   total kuantitas -> kesalahan measure yang tidak mengubah jumlah baris
--   total nilai     -> kesalahan konversi satuan atau pembulatan
--
-- Selisih TIDAK HARUS NOL. Yang wajib adalah setiap selisih dapat dijelaskan,
-- dan jumlah seluruh penjelasan sama persis dengan selisihnya.
-- =============================================================================

\set ON_ERROR_STOP on

-- =============================================================================
-- 1. Empat besaran, sumber lawan gudang
-- =============================================================================
WITH sumber AS (
  SELECT COUNT(*)                       AS baris,
         COUNT(DISTINCT t.transaksi_id) AS transaksi_unik,
         COALESCE(SUM(ti.kuantitas), 0) AS kuantitas,
         COALESCE(SUM(ti.subtotal), 0)  AS nilai
  FROM   src_oltp.transaksi_item ti
  JOIN   src_oltp.transaksi t ON t.transaksi_id = ti.transaksi_id
  WHERE  t.status <> 'BATAL'
    AND  t.waktu_transaksi::DATE = :tanggal_batch::DATE
),
gudang AS (
  SELECT COUNT(*)                     AS baris,
         COUNT(DISTINCT transaksi_id) AS transaksi_unik,
         COALESCE(SUM(kuantitas), 0)  AS kuantitas,
         COALESCE(SUM(subtotal), 0)   AS nilai
  FROM   gudang.fakta_penjualan
  WHERE  tanggal_key = :tanggal_key
)
SELECT 'baris'           AS besaran,
       s.baris           AS di_sumber,
       g.baris           AS di_gudang,
       s.baris - g.baris AS selisih
FROM   sumber s, gudang g
UNION ALL
SELECT 'transaksi_unik', s.transaksi_unik, g.transaksi_unik,
       s.transaksi_unik - g.transaksi_unik FROM sumber s, gudang g
UNION ALL
SELECT 'kuantitas', s.kuantitas, g.kuantitas,
       s.kuantitas - g.kuantitas           FROM sumber s, gudang g
UNION ALL
SELECT 'nilai', s.nilai, g.nilai,
       s.nilai - g.nilai                   FROM sumber s, gudang g;

-- =============================================================================
-- 2. Calon penjelasan selisih
--
-- Periksa berurutan. Jumlah keempatnya harus menutup selisih jumlah baris
-- secara TEPAT. Selisih yang "kira-kira sesuai" tidak memenuhi syarat: bila
-- 47 baris tidak cocok dan penjelasan hanya mencakup 39, sisanya adalah
-- kegagalan yang belum ditemukan -- bukan pembulatan.
-- =============================================================================
SELECT 'baris terkarantina' AS penjelasan,
       COUNT(*)             AS jumlah
FROM   gudang.karantina_penjualan
WHERE  (baris_asli->>'waktu_transaksi')::DATE = :tanggal_batch::DATE

UNION ALL

SELECT 'transaksi batal disaring',
       COUNT(*)
FROM   src_oltp.transaksi_item ti
JOIN   src_oltp.transaksi t ON t.transaksi_id = ti.transaksi_id
WHERE  t.status = 'BATAL'
  AND  t.waktu_transaksi::DATE = :tanggal_batch::DATE

UNION ALL

SELECT 'ada di sumber, belum di staging',
       COUNT(*)
FROM   src_oltp.transaksi_item ti
JOIN   src_oltp.transaksi t ON t.transaksi_id = ti.transaksi_id
WHERE  t.status <> 'BATAL'
  AND  t.waktu_transaksi::DATE = :tanggal_batch::DATE
  AND  NOT EXISTS (SELECT 1 FROM staging.penjualan_gabungan s
                   WHERE s.transaksi_id = t.transaksi_id
                     AND s.produk_id    = ti.produk_id)

UNION ALL

SELECT 'ada di staging, tidak masuk fakta',
       COUNT(*)
FROM   staging.penjualan_gabungan s
WHERE  s.waktu_transaksi::DATE = :tanggal_batch::DATE
  AND  s.status <> 'BATAL'
  AND  NOT EXISTS (SELECT 1 FROM gudang.fakta_penjualan f
                   WHERE f.transaksi_id = s.transaksi_id)

ORDER BY 1;

-- =============================================================================
-- 3. Rekonsiliasi per toko
--
-- Selisih total yang kecil dapat menyembunyikan dua selisih besar yang saling
-- meniadakan. Rincian per toko memperlihatkannya.
-- =============================================================================
WITH sumber AS (
  SELECT t.toko_id, COUNT(*) AS baris, SUM(ti.subtotal) AS nilai
  FROM   src_oltp.transaksi_item ti
  JOIN   src_oltp.transaksi t ON t.transaksi_id = ti.transaksi_id
  WHERE  t.status <> 'BATAL'
    AND  t.waktu_transaksi::DATE = :tanggal_batch::DATE
  GROUP  BY t.toko_id
),
gudang AS (
  SELECT dt.toko_id, COUNT(*) AS baris, SUM(f.subtotal) AS nilai
  FROM   gudang.fakta_penjualan f
  JOIN   gudang.dim_toko dt ON dt.toko_key = f.toko_key
  WHERE  f.tanggal_key = :tanggal_key
  GROUP  BY dt.toko_id
)
SELECT COALESCE(s.toko_id, g.toko_id)                  AS toko_id,
       COALESCE(s.baris, 0)                            AS baris_sumber,
       COALESCE(g.baris, 0)                            AS baris_gudang,
       COALESCE(s.baris, 0) - COALESCE(g.baris, 0)     AS selisih_baris,
       COALESCE(s.nilai, 0) - COALESCE(g.nilai, 0)     AS selisih_nilai
FROM       sumber s
FULL OUTER JOIN gudang g ON g.toko_id = s.toko_id
WHERE  COALESCE(s.baris, 0) <> COALESCE(g.baris, 0)
    OR COALESCE(s.nilai, 0) <> COALESCE(g.nilai, 0)
ORDER  BY ABS(COALESCE(s.baris, 0) - COALESCE(g.baris, 0)) DESC;
