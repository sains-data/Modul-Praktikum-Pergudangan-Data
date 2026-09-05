-- =============================================================================
-- Modul 02 -- Tabel staging penampung salinan sumber
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-02/01-staging.sql
--
-- Tabel staging menyalin sumber APA ADANYA: tanpa surrogate key, tanpa
-- perbaikan, dan tanpa penyaringan. Pembersihan dan pemetaan kunci terjadi saat
-- pemuatan dimensi dan fakta.
--
-- Pemisahan ini yang membuat pemuatan dapat diulang tanpa menyentuh basis data
-- sumber kembali -- dan pada Modul 5 seluruh tabel ini pindah ke schema
-- "staging" tersendiri.
-- =============================================================================

DROP TABLE IF EXISTS staging_penjualan;
DROP TABLE IF EXISTS staging_produk;
DROP TABLE IF EXISTS staging_kategori;
DROP TABLE IF EXISTS staging_toko;

-- -----------------------------------------------------------------------------
-- Tipe kolom sengaja dibuat longgar. Tugas staging adalah menampung, bukan
-- menolak; baris bermasalah harus sampai ke sini agar dapat dihitung dan
-- dijelaskan, bukan gagal diam-diam saat impor.
-- -----------------------------------------------------------------------------
CREATE TABLE staging_toko (
  toko_id       INTEGER,
  kode_toko     VARCHAR(15),
  nama_toko     VARCHAR(100),
  alamat        TEXT,
  kota          VARCHAR(60),
  provinsi      VARCHAR(60),
  tipe_toko     VARCHAR(30),
  luas_m2       NUMERIC(10,2),
  tanggal_buka  DATE
);

CREATE TABLE staging_kategori (
  kategori_id        INTEGER,
  kode_kategori      VARCHAR(20),
  nama_kategori      VARCHAR(60),
  induk_kategori_id  INTEGER
);

CREATE TABLE staging_produk (
  produk_id     INTEGER,
  sku           VARCHAR(20),
  nama_produk   VARCHAR(150),
  kategori_id   INTEGER,
  merek         VARCHAR(60),
  satuan        VARCHAR(15),
  berat_gram    NUMERIC(10,2),
  harga_jual    NUMERIC(12,2),
  harga_pokok   NUMERIC(12,2),
  aktif         BOOLEAN
);

-- Hasil join transaksi dengan transaksi_item pada sumber. Satu baris di sini
-- berpadanan satu lawan satu dengan satu baris struk.
CREATE TABLE staging_penjualan (
  transaksi_id     BIGINT,
  nomor_struk      VARCHAR(25),
  toko_id          INTEGER,
  pelanggan_id     INTEGER,      -- boleh NULL: pembeli tanpa kartu anggota
  waktu_transaksi  TIMESTAMP,
  metode_bayar     VARCHAR(30),
  status           VARCHAR(20),
  produk_id        INTEGER,
  kuantitas        NUMERIC(10,2),
  harga_satuan     NUMERIC(12,2),
  diskon           NUMERIC(12,2),
  subtotal         NUMERIC(14,2)
);

-- =============================================================================
-- Pemindahan data dari sumber ke staging.
--
-- Perintah COPY ... TO STDOUT disalurkan langsung ke COPY ... FROM STDIN
-- sehingga data tidak singgah sebagai berkas. Opsi -T diperlukan agar Docker
-- tidak mengalokasikan terminal, yang akan merusak aliran data.
--
-- Jalankan dari shell, bukan dari psql:
--
--   SRC="docker compose exec -T postgres_source psql -U praktikum -d nusamart_oltp"
--   DW="docker compose exec -T postgres_dw     psql -U praktikum -d nusamart_dw"
--
--   $SRC -c "COPY (SELECT toko_id, kode_toko, nama_toko, alamat, kota,
--                         provinsi, tipe_toko, luas_m2, tanggal_buka
--                  FROM nusamart.toko) TO STDOUT WITH CSV" \
--   | $DW -c "COPY staging_toko FROM STDIN WITH CSV"
--
--   $SRC -c "COPY (SELECT kategori_id, kode_kategori, nama_kategori,
--                         induk_kategori_id
--                  FROM nusamart.kategori) TO STDOUT WITH CSV" \
--   | $DW -c "COPY staging_kategori FROM STDIN WITH CSV"
--
--   $SRC -c "COPY (SELECT produk_id, sku, nama_produk, kategori_id, merek,
--                         satuan, berat_gram, harga_jual, harga_pokok, aktif
--                  FROM nusamart.produk) TO STDOUT WITH CSV" \
--   | $DW -c "COPY staging_produk FROM STDIN WITH CSV"
--
--   $SRC -c "COPY (SELECT t.transaksi_id, t.nomor_struk, t.toko_id,
--                         t.pelanggan_id, t.waktu_transaksi, t.metode_bayar,
--                         t.status, ti.produk_id, ti.kuantitas,
--                         ti.harga_satuan, ti.diskon, ti.subtotal
--                  FROM nusamart.transaksi t
--                  JOIN nusamart.transaksi_item ti
--                    ON ti.transaksi_id = t.transaksi_id) TO STDOUT WITH CSV" \
--   | $DW -c "COPY staging_penjualan FROM STDIN WITH CSV"
--
-- Perhatikan: penyaringan status TIDAK dilakukan di sini. Baris berstatus BATAL
-- tetap masuk staging agar jumlahnya dapat dihitung, dan disaring saat pemuatan
-- fakta. Menyaring terlalu awal menghilangkan bukti yang diperlukan untuk
-- menjelaskan selisih rekonsiliasi.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Verifikasi setelah impor. Bandingkan dengan angka COUNT(*) pada sumber.
-- -----------------------------------------------------------------------------
SELECT 'staging_toko'      AS tabel, COUNT(*) AS baris FROM staging_toko
UNION ALL
SELECT 'staging_kategori',  COUNT(*) FROM staging_kategori
UNION ALL
SELECT 'staging_produk',    COUNT(*) FROM staging_produk
UNION ALL
SELECT 'staging_penjualan', COUNT(*) FROM staging_penjualan
ORDER BY tabel;

-- Rincian status pada staging. Angka BATAL di sini menjelaskan selisih antara
-- jumlah baris staging dan jumlah baris fakta.
SELECT status, COUNT(*) AS jumlah
FROM   staging_penjualan
GROUP  BY status
ORDER  BY jumlah DESC;
