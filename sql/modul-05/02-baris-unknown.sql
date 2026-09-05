-- =============================================================================
-- Modul 05 -- Baris unknown pada setiap dimensi
-- Dijalankan pada: nusamart_dw (port 5434), sesudah 01-schema.sql
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-05/02-baris-unknown.sql
--
-- Baris fakta yang tidak menemukan pasangan dimensi menunjuk baris ini, BUKAN
-- NULL. Kunci NULL menimbulkan tiga masalah sekaligus:
--
--   1. INNER JOIN ke dimensi membuang baris itu diam-diam, sehingga total
--      penjualan menyusut tanpa jejak;
--   2. constraint NOT NULL tidak dapat dipasang, sehingga kesalahan pemuatan
--      yang sebenarnya tidak lagi terdeteksi;
--   3. pengguna akhir tidak memperoleh keterangan apa pun -- "tidak ada baris"
--      berbeda maknanya dari "pembeli tanpa kartu anggota".
--
-- Klausa OVERRIDING SYSTEM VALUE diperlukan karena surrogate key dimensi
-- memakai GENERATED ALWAYS AS IDENTITY, yang secara asali menolak nilai yang
-- ditentukan sendiri.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- dim_tanggal -- kuncinya ditetapkan sendiri sejak Modul 2, jadi tanpa
-- OVERRIDING. Kolom tanggal tetap harus terisi karena NOT NULL UNIQUE.
-- -----------------------------------------------------------------------------
INSERT INTO gudang.dim_tanggal (
  tanggal_key, tanggal, hari, nama_hari, minggu_ke, bulan, nama_bulan,
  kuartal, tahun, tahun_bulan, hari_ke_tahun, akhir_pekan)
VALUES (-1, DATE '1900-01-01', 1, 'Tidak Diketahui', 1, 1, 'Tidak Diketahui',
        1, 1900, 190001, 1, FALSE)
ON CONFLICT (tanggal_key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- dim_produk -- sudah SCD-2 sejak Modul 3, jadi baris unknown pun memerlukan
-- rentang berlaku. Rentangnya dibuat selebar mungkin agar pencarian kunci
-- berbasis tanggal selalu menemukannya.
-- -----------------------------------------------------------------------------
INSERT INTO gudang.dim_produk (
  produk_key, produk_id, sku, nama_produk, merek, kategori, sub_kategori,
  satuan, mulai_berlaku, selesai_berlaku, baris_kini, versi)
OVERRIDING SYSTEM VALUE
VALUES (-1, -1, 'TIDAK-DIKETAHUI', 'Tidak Diketahui', 'Tidak Diketahui',
        'Tidak Diketahui', 'Tidak Diketahui', 'Tidak Diketahui',
        DATE '1900-01-01', DATE '9999-12-31', TRUE, 1)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- dim_toko
-- -----------------------------------------------------------------------------
INSERT INTO gudang.dim_toko (
  toko_key, toko_id, kode_toko, nama_toko, kota, provinsi, tipe_toko)
OVERRIDING SYSTEM VALUE
VALUES (-1, -1, 'TIDAK-DIKETAHUI', 'Tidak Diketahui', 'Tidak Diketahui',
        'Tidak Diketahui', 'Tidak Diketahui')
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- dim_transaksi_flag dan dim_promosi
-- -----------------------------------------------------------------------------
INSERT INTO gudang.dim_transaksi_flag (
  flag_key, metode_bayar, status, jenis_pembeli)
OVERRIDING SYSTEM VALUE
VALUES (-1, 'Tidak Diketahui', 'Tidak Diketahui', 'Tidak Diketahui')
ON CONFLICT DO NOTHING;

INSERT INTO gudang.dim_promosi (
  promosi_key, promosi_id, kode_promo, nama_promosi, tipe_promosi,
  tanggal_mulai_key, tanggal_selesai_key)
OVERRIDING SYSTEM VALUE
VALUES (-1, -1, 'TIDAK-DIKETAHUI', 'Tidak Diketahui', 'Tidak Diketahui', -1, -1)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Mengarahkan kunci NULL ke baris unknown, lalu memasang NOT NULL.
--
-- Urutannya wajib: arahkan dahulu, baru pasang constraint. Membalik urutan
-- membuat ALTER TABLE gagal dengan pesan "column contains null values".
-- =============================================================================
UPDATE gudang.fakta_penjualan SET produk_key  = -1 WHERE produk_key  IS NULL;
UPDATE gudang.fakta_penjualan SET toko_key    = -1 WHERE toko_key    IS NULL;
UPDATE gudang.fakta_penjualan SET tanggal_key = -1 WHERE tanggal_key IS NULL;
UPDATE gudang.fakta_penjualan SET flag_key    = -1 WHERE flag_key    IS NULL;

UPDATE gudang.fakta_persediaan_harian SET produk_key  = -1 WHERE produk_key  IS NULL;
UPDATE gudang.fakta_persediaan_harian SET toko_key    = -1 WHERE toko_key    IS NULL;
UPDATE gudang.fakta_persediaan_harian SET tanggal_key = -1 WHERE tanggal_key IS NULL;

ALTER TABLE gudang.fakta_penjualan
  ALTER COLUMN produk_key  SET NOT NULL,
  ALTER COLUMN toko_key    SET NOT NULL,
  ALTER COLUMN tanggal_key SET NOT NULL,
  ALTER COLUMN flag_key    SET NOT NULL;

-- -----------------------------------------------------------------------------
-- Verifikasi: setiap dimensi memiliki baris unknown, dan berapa banyak baris
-- fakta yang benar-benar memakainya. Angka terakhir ini bukan kegagalan --
-- ia adalah laporan berapa banyak data yang tidak dapat dipetakan, dan wajib
-- dijelaskan pada laporan.
-- -----------------------------------------------------------------------------
SELECT 'dim_tanggal'        AS dimensi,
       COUNT(*) FILTER (WHERE tanggal_key = -1) AS punya_unknown
FROM   gudang.dim_tanggal
UNION ALL
SELECT 'dim_produk',  COUNT(*) FILTER (WHERE produk_key  = -1) FROM gudang.dim_produk
UNION ALL
SELECT 'dim_toko',    COUNT(*) FILTER (WHERE toko_key    = -1) FROM gudang.dim_toko
UNION ALL
SELECT 'dim_promosi', COUNT(*) FILTER (WHERE promosi_key = -1) FROM gudang.dim_promosi
ORDER  BY dimensi;

SELECT COUNT(*) FILTER (WHERE produk_key  = -1) AS produk_tidak_diketahui,
       COUNT(*) FILTER (WHERE toko_key    = -1) AS toko_tidak_diketahui,
       COUNT(*) FILTER (WHERE tanggal_key = -1) AS tanggal_tidak_diketahui,
       COUNT(*)                                 AS total_baris
FROM   gudang.fakta_penjualan;
