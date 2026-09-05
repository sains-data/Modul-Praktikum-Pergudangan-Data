-- =============================================================================
-- Modul 01 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_oltp (port 5433)
--
--   docker compose exec postgres_source \
--     psql -U praktikum -d nusamart_oltp -f /sql/modul-01/check.sql
--
-- Skrip mencetak satu baris per butir dengan status LULUS atau GAGAL. Asisten
-- hanya perlu menangani butir yang GAGAL.
--
-- Cakupan: butir yang dapat diperiksa dari basis data. Butir yang menyangkut
-- isi dokumen -- kalimat grain, lima temuan kualitas data, dan empat pertanyaan
-- bisnis -- diperiksa manual oleh asisten memakai checklist pada naskah modul.
-- =============================================================================

\pset border 2
\pset title 'Modul 01 -- Hasil pemeriksaan checkpoint'

SET search_path TO nusamart, public;

WITH
-- 1. Schema sumber ada.
b1 AS (
  SELECT 'B1  Schema nusamart tersedia' AS butir,
         COUNT(*) = 1 AS lulus,
         'ditemukan ' || COUNT(*) || ' schema' AS detail
  FROM   information_schema.schemata
  WHERE  schema_name = 'nusamart'
),

-- 2. Seluruh tabel yang diharapkan terpulihkan.
diharapkan (nama) AS (
  VALUES ('toko'), ('kategori'), ('produk'), ('pelanggan'), ('pegawai'),
         ('transaksi'), ('transaksi_item'), ('promosi'), ('promosi_produk'),
         ('persediaan_harian'), ('retur'), ('retur_item')
),
ada AS (
  SELECT table_name AS nama
  FROM   information_schema.tables
  WHERE  table_schema = 'nusamart' AND table_type = 'BASE TABLE'
),
hilang AS (
  SELECT nama FROM diharapkan
  EXCEPT
  SELECT nama FROM ada
),
b2 AS (
  SELECT 'B2  Dua belas tabel sumber terpulihkan' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('tabel hilang: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   hilang
),

-- 3. Tidak ada tabel yang kosong.
jumlah AS (
  SELECT d.nama,
         (xpath('/row/c/text()',
                query_to_xml(format('SELECT COUNT(*) AS c FROM nusamart.%I',
                                    d.nama), false, true, '')))[1]::text::bigint
         AS baris
  FROM   diharapkan d
  WHERE  EXISTS (SELECT 1 FROM ada a WHERE a.nama = d.nama)
),
b3 AS (
  SELECT 'B3  Tidak ada tabel sumber yang kosong' AS butir,
         COUNT(*) FILTER (WHERE baris = 0) = 0 AS lulus,
         COALESCE('kosong: ' || string_agg(nama, ', ') FILTER (WHERE baris = 0),
                  'seluruh tabel terisi') AS detail
  FROM   jumlah
),

-- 4. Volume masuk akal untuk dataset ukuran kecil (>= 100.000 baris fakta).
b4 AS (
  SELECT 'B4  Volume transaksi_item sesuai dataset kecil' AS butir,
         COALESCE(MAX(baris), 0) >= 100000 AS lulus,
         COALESCE(MAX(baris), 0) || ' baris (diharapkan >= 100.000)' AS detail
  FROM   jumlah WHERE nama = 'transaksi_item'
),

-- 5. Basis data gudang dapat dijangkau dan masih kosong.
--    Diperiksa terpisah pada nusamart_dw; lihat catatan di kaki skrip.
b5 AS (
  SELECT 'B5  Relasi transaksi -> transaksi_item utuh' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris item tanpa kepala struk' AS detail
  FROM      transaksi_item ti
  LEFT JOIN transaksi t ON t.transaksi_id = ti.transaksi_id
  WHERE     t.transaksi_id IS NULL
),

-- 6. Anomali yang sengaja ditanam memang masih ada -- bila hilang, mahasiswa
--    mengubah data mentah, dan itu melanggar aturan praktikum.
b6 AS (
  SELECT 'B6  Data mentah tidak diubah (anomali bawaan utuh)' AS butir,
         COUNT(*) > 0 AS lulus,
         COUNT(*) || ' baris anomali masih ada (diharapkan > 0)' AS detail
  FROM   transaksi_item
  WHERE  kuantitas <= 0 OR diskon < 0 OR harga_satuan <= 0
)

SELECT butir,
       CASE WHEN lulus THEN 'LULUS' ELSE 'GAGAL' END AS status,
       detail
FROM (
  SELECT * FROM b1 UNION ALL SELECT * FROM b2 UNION ALL SELECT * FROM b3
  UNION ALL SELECT * FROM b4 UNION ALL SELECT * FROM b5
  UNION ALL SELECT * FROM b6
) hasil
ORDER BY butir;

-- -----------------------------------------------------------------------------
-- Butir tambahan yang dijalankan pada basis data gudang (port 5434):
--
--   psql -U praktikum -d nusamart_dw -c "SELECT current_database(), version();"
--
-- Cukup memberi keluaran; pada Modul 1 basis data gudang memang masih kosong.
-- -----------------------------------------------------------------------------
