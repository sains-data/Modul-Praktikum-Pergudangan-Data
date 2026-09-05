-- =============================================================================
-- Modul 07 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-07/check.sql
--
-- Butir B4 dan B5 adalah kriteria lulus utama modul: satu pelanggan dari dua
-- sumber menjadi satu baris dimensi, dan tidak ada foreign key fakta yang NULL.
-- =============================================================================

\pset border 2
\pset title 'Modul 07 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. Ketiga sumber terhubung lewat postgres_fdw.
server_diharapkan (nama) AS (
  VALUES ('src_oltp'), ('src_barat'), ('src_timur')
),
server_hilang AS (
  SELECT nama FROM server_diharapkan
  EXCEPT
  SELECT srvname FROM pg_foreign_server
),
b1 AS (
  SELECT 'B1  Tiga sumber terhubung lewat FDW' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('belum terhubung: ' || string_agg(nama, ', ' ORDER BY nama),
                  'ketiganya terhubung') AS detail
  FROM   server_hilang
),

-- B2. Satuan berat sudah seragam.
--     Konflik satuan terlihat dari sebaran nilai, bukan dari nama kolom:
--     rata-rata yang berselisih sekitar seribu kali adalah tandanya.
b2 AS (
  SELECT 'B2  Satuan berat sudah seragam' AS butir,
         COALESCE(MAX(rasio), 0) < 100 AS lulus,
         'rasio rata-rata berat antar sumber: ' ||
         COALESCE(ROUND(MAX(rasio), 1)::TEXT, 'tidak dapat dihitung') AS detail
  FROM ( SELECT MAX(rata) / NULLIF(MIN(rata), 0) AS rasio
         FROM ( SELECT sumber_asal, AVG(berat_gram) AS rata
                FROM   gudang.dim_produk
                WHERE  baris_kini AND berat_gram > 0
                GROUP  BY sumber_asal ) s ) r
),

-- B3. Kode kategori sudah terstandardisasi: tidak ada lagi kode khas sumber
--     kedua dan ketiga yang lolos ke dimensi.
b3 AS (
  SELECT 'B3  Kode kategori terstandardisasi' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('kode belum dipetakan: ' ||
                  string_agg(DISTINCT kategori, ', '),
                  'seluruh kode sudah baku') AS detail
  FROM   gudang.dim_produk
  WHERE  baris_kini
    AND  kategori IN ('BEV', 'SNK', 'HHD', 'DRK', 'FOD')
),

-- B4. Pelanggan yang sama dari dua sumber menjadi SATU baris dimensi.
--     Diperiksa dari sisi keunikan: satu pelanggan_id hanya boleh punya satu
--     baris kini, sebagaimana SCD-2 Modul 3.
b4 AS (
  SELECT 'B4  Satu pelanggan = satu baris dimensi kini' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' pelanggan_id punya lebih dari satu baris kini' AS detail
  FROM ( SELECT pelanggan_id FROM gudang.dim_pelanggan WHERE baris_kini
         GROUP BY pelanggan_id HAVING COUNT(*) > 1 ) x
),

-- B5. Tidak ada foreign key fakta yang NULL. Seluruhnya menunjuk dimensi
--     atau baris unknown.
b5 AS (
  SELECT 'B5  Tidak ada kunci dimensi fakta yang NULL' AS butir,
         jml = 0 AS lulus,
         jml || ' baris fakta dengan kunci NULL' AS detail
  FROM ( SELECT COUNT(*) AS jml FROM gudang.fakta_penjualan
         WHERE tanggal_key IS NULL OR produk_key IS NULL
            OR toko_key IS NULL OR pelanggan_key IS NULL ) x
),

-- B6. Transaksi menunjuk versi dimensi yang berlaku saat transaksi terjadi.
--     Bila pencarian kunci memakai baris_kini, transaksi yang datang terlambat
--     akan menunjuk harga hari ini dan butir ini gagal.
b6 AS (
  SELECT 'B6  Fakta menunjuk versi yang berlaku saat transaksi' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris menunjuk versi di luar masa berlakunya' AS detail
  FROM   gudang.fakta_penjualan f
  JOIN   gudang.dim_tanggal   dt ON dt.tanggal_key   = f.tanggal_key
  JOIN   gudang.dim_pelanggan dp ON dp.pelanggan_key = f.pelanggan_key
  WHERE  f.pelanggan_key <> -1
    AND  (dt.tanggal < dp.mulai_berlaku OR dt.tanggal >= dp.selesai_berlaku)
),

-- B7. Tabel audit terisi untuk seluruh sumber.
b7 AS (
  SELECT 'B7  audit_muat terisi untuk tiga sumber' AS butir,
         COUNT(DISTINCT sumber) >= 3 AS lulus,
         COUNT(DISTINCT batch_id) || ' batch, ' ||
         COUNT(DISTINCT sumber) || ' sumber tercatat' AS detail
  FROM   gudang.audit_muat
),

-- B8. Tidak ada versi dimensi kembar -- bukti pipeline idempoten.
--     Dua versi dengan rentang berlaku identik berarti pipeline dijalankan
--     dua kali tanpa perbandingan atribut yang benar.
b8 AS (
  SELECT 'B8  Tidak ada versi dimensi kembar' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' pasangan versi kembar' AS detail
  FROM ( SELECT pelanggan_id, mulai_berlaku
         FROM   gudang.dim_pelanggan
         GROUP  BY pelanggan_id, mulai_berlaku
         HAVING COUNT(*) > 1 ) x
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
-- Bahan pembacaan bersama asisten
-- =============================================================================

-- Hasil object identification: berapa catatan sumber menyatu menjadi berapa
-- pelanggan master. Pelanggan yang muncul di lebih dari satu sumber adalah
-- bukti langsung bahwa identifikasi bekerja.
SELECT COUNT(DISTINCT pelanggan_id) AS pelanggan_master,
       COUNT(*)                     AS baris_dimensi,
       COUNT(*) FILTER (WHERE versi > 1) AS baris_versi_lanjutan
FROM   gudang.dim_pelanggan
WHERE  pelanggan_id <> -1;

-- Berapa baris fakta yang menunjuk baris unknown. Angka ini bukan kegagalan;
-- ia laporan berapa data yang tidak dapat dipetakan, dan wajib dijelaskan.
SELECT COUNT(*) FILTER (WHERE produk_key    = -1) AS produk_unknown,
       COUNT(*) FILTER (WHERE toko_key      = -1) AS toko_unknown,
       COUNT(*) FILTER (WHERE pelanggan_key = -1) AS pelanggan_unknown,
       COUNT(*)                                   AS total_baris
FROM   gudang.fakta_penjualan;

-- Isi tabel audit. Selisih antara baris_dibaca dan baris_dimuat WAJIB dapat
-- dijelaskan pada log-muat.md.
SELECT batch_id, tahap, sumber, baris_dibaca, baris_dimuat,
       baris_dibaca - baris_dimuat AS selisih,
       baris_unknown
FROM   gudang.audit_muat
ORDER  BY batch_id, tahap, sumber;

-- Bukti idempotensi: jumlah baris per batch. Menjalankan pipeline dua kali
-- untuk tanggal yang sama harus menghasilkan angka yang sama, bukan dua kali
-- lipat.
SELECT batch_id, SUM(baris_dimuat) AS total_dimuat
FROM   gudang.audit_muat
WHERE  tahap = 'load_fakta'
GROUP  BY batch_id
ORDER  BY batch_id;

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten secara manual:
--
--   B9   laporan-konflik.md memuat sekurang-kurangnya lima konflik, masing-
--        masing disertai jenisnya, bukti berupa ANGKA, dan aturan penyelesaian.
--   B10  tinjau-manual.csv ada dan tidak kosong. Pipeline yang tidak pernah
--        ragu hampir pasti ambangnya terlalu longgar.
--   B11  Aturan transformasi ditulis sebagai data (dict), bukan sebagai
--        rangkaian percabangan if yang tersebar.
--   B12  .env TIDAK ikut ter-commit; yang ada hanya .env.example tanpa
--        kredensial sebenarnya.
-- -----------------------------------------------------------------------------
