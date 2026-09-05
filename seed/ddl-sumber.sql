-- =============================================================================
-- Skema sistem operasional NusaMart -- sumber utama
-- Dijalankan pada: nusamart_oltp, schema nusamart
--
-- Dipakai oleh generate_nusamart.py. Dapat juga dijalankan manual:
--
--   docker compose exec -T postgres_source \
--     psql -U praktikum -d nusamart_oltp -f /seed/ddl-sumber.sql
--
-- CATATAN RANCANGAN
--
-- Skema ini sengaja dibuat "seperti sistem operasional sungguhan", bukan
-- seperti gudang data: ternormalisasi, hemat redundansi, dan menimpa nilai
-- lama ketika ada perubahan. Sebagian kelonggarannya juga disengaja dan
-- menjadi bahan temuan pada Modul 1:
--
--   * nomor_struk TIDAK unik secara global, hanya per toko
--   * pelanggan_id boleh NULL (pembeli tanpa kartu anggota)
--   * kategori mengacu pada dirinya sendiri, dan hierarkinya tidak seragam
--   * tidak ada CHECK pada kuantitas, harga, maupun diskon
--
-- Constraint yang longgar itu BUKAN kelalaian. Bila sumber sudah menolak data
-- buruk, tidak ada yang tersisa untuk ditemukan pada profiling Modul 1 dan
-- tidak ada yang perlu dikarantina pada Modul 10.
-- =============================================================================

DROP SCHEMA IF EXISTS nusamart CASCADE;
CREATE SCHEMA nusamart;
SET search_path TO nusamart;

-- -----------------------------------------------------------------------------
-- Master
-- -----------------------------------------------------------------------------
CREATE TABLE toko (
  toko_id       INTEGER      PRIMARY KEY,
  kode_toko     VARCHAR(15)  NOT NULL UNIQUE,
  nama_toko     VARCHAR(100) NOT NULL,
  alamat        TEXT,
  kota          VARCHAR(60),
  provinsi      VARCHAR(60),
  tipe_toko     VARCHAR(30),
  luas_m2       NUMERIC(10,2),
  tanggal_buka  DATE
);

-- Mengacu pada dirinya sendiri. Kedalaman hierarki TIDAK seragam, dan ada
-- kategori yatim -- bahan Latihan 1.1.
CREATE TABLE kategori (
  kategori_id        INTEGER     PRIMARY KEY,
  kode_kategori      VARCHAR(20) NOT NULL,
  nama_kategori      VARCHAR(60) NOT NULL,
  induk_kategori_id  INTEGER      -- sengaja TANPA foreign key
);

CREATE TABLE produk (
  produk_id     INTEGER      PRIMARY KEY,
  sku           VARCHAR(20)  NOT NULL UNIQUE,
  nama_produk   VARCHAR(150) NOT NULL,
  kategori_id   INTEGER,     -- sengaja TANPA foreign key: ada yang yatim
  merek         VARCHAR(60),
  satuan        VARCHAR(15),
  berat_gram    NUMERIC(10,2),
  harga_jual    NUMERIC(12,2),
  harga_pokok   NUMERIC(12,2),
  aktif         BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE pelanggan (
  pelanggan_id   INTEGER      PRIMARY KEY,
  kode_member    VARCHAR(20)  NOT NULL,
  nama           VARCHAR(120) NOT NULL,
  jenis_kelamin  CHAR(1),
  tanggal_lahir  DATE,        -- memuat nilai mustahil
  kota           VARCHAR(60),
  tanggal_daftar DATE,
  segmen         VARCHAR(30)
);

CREATE TABLE pegawai (
  pegawai_id     INTEGER      PRIMARY KEY,
  nama           VARCHAR(120) NOT NULL,
  toko_id        INTEGER      REFERENCES toko(toko_id),
  peran          VARCHAR(30),
  tanggal_masuk  DATE
);

-- -----------------------------------------------------------------------------
-- Transaksi
-- -----------------------------------------------------------------------------
CREATE TABLE transaksi (
  transaksi_id     BIGINT      PRIMARY KEY,
  nomor_struk      VARCHAR(25) NOT NULL,   -- unik hanya PER TOKO
  toko_id          INTEGER     NOT NULL REFERENCES toko(toko_id),
  pelanggan_id     INTEGER     REFERENCES pelanggan(pelanggan_id),  -- boleh NULL
  pegawai_id       INTEGER     REFERENCES pegawai(pegawai_id),
  waktu_transaksi  TIMESTAMP   NOT NULL,
  metode_bayar     VARCHAR(30),
  total_bayar      NUMERIC(14,2),
  status           VARCHAR(20) NOT NULL    -- SELESAI, BATAL, PENDING
);

CREATE INDEX ix_transaksi_waktu ON transaksi (waktu_transaksi);
CREATE INDEX ix_transaksi_toko  ON transaksi (toko_id);

-- Grain: satu produk pada satu baris struk. Berpadanan satu lawan satu dengan
-- grain fakta penjualan yang dibangun mahasiswa pada Modul 2.
CREATE TABLE transaksi_item (
  transaksi_item_id BIGINT        PRIMARY KEY,
  transaksi_id      BIGINT        NOT NULL REFERENCES transaksi(transaksi_id),
  produk_id         INTEGER       NOT NULL,   -- sengaja TANPA foreign key
  kuantitas         NUMERIC(10,3),            -- sengaja TANPA CHECK > 0
  harga_satuan      NUMERIC(12,2),
  diskon            NUMERIC(12,2),
  subtotal          NUMERIC(14,2)
);

CREATE INDEX ix_item_transaksi ON transaksi_item (transaksi_id);
CREATE INDEX ix_item_produk    ON transaksi_item (produk_id);

-- -----------------------------------------------------------------------------
-- Promosi -- bahan factless fact pada Modul 4
-- -----------------------------------------------------------------------------
CREATE TABLE promosi (
  promosi_id    INTEGER      PRIMARY KEY,
  kode_promo    VARCHAR(20)  NOT NULL UNIQUE,
  nama_promosi  VARCHAR(120) NOT NULL,
  tipe          VARCHAR(40),
  mulai         DATE         NOT NULL,
  selesai       DATE         NOT NULL
);

CREATE TABLE promosi_produk (
  promosi_id  INTEGER NOT NULL REFERENCES promosi(promosi_id),
  produk_id   INTEGER NOT NULL,
  PRIMARY KEY (promosi_id, produk_id)
);

-- -----------------------------------------------------------------------------
-- Persediaan -- bahan periodic snapshot pada Modul 4
--
-- Grain sumber sudah sesuai grain fakta: satu produk di satu toko pada satu
-- hari. Cakupannya sengaja dibatasi pada sebagian toko dan produk; lihat
-- catatan pada seed/README.md.
-- -----------------------------------------------------------------------------
CREATE TABLE persediaan_harian (
  tanggal      DATE          NOT NULL,
  toko_id      INTEGER       NOT NULL REFERENCES toko(toko_id),
  produk_id    INTEGER       NOT NULL,
  saldo_awal   NUMERIC(12,2) NOT NULL,
  masuk        NUMERIC(12,2) NOT NULL,
  keluar       NUMERIC(12,2) NOT NULL,
  saldo_akhir  NUMERIC(12,2) NOT NULL,
  PRIMARY KEY (tanggal, toko_id, produk_id)
);

-- -----------------------------------------------------------------------------
-- Retur -- bahan accumulating snapshot, tugas Modul 4
-- -----------------------------------------------------------------------------
CREATE TABLE retur (
  retur_id                 INTEGER   PRIMARY KEY,
  transaksi_id             BIGINT    NOT NULL REFERENCES transaksi(transaksi_id),
  tanggal_pengajuan        DATE      NOT NULL,
  tanggal_disetujui        DATE,     -- tonggak yang terisi bertahap
  tanggal_barang_diterima  DATE,
  tanggal_dana_kembali     DATE,
  alasan                   VARCHAR(60),
  status                   VARCHAR(20) NOT NULL
);

CREATE TABLE retur_item (
  retur_id   INTEGER       NOT NULL REFERENCES retur(retur_id),
  produk_id  INTEGER       NOT NULL,
  kuantitas  NUMERIC(10,3) NOT NULL,
  PRIMARY KEY (retur_id, produk_id)
);
