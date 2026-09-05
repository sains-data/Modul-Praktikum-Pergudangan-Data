-- =============================================================================
-- Modul 03 -- Skenario perubahan produk untuk menguji SCD Type 2
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-03/01-skenario-perubahan.sql
--
-- Skrip menyiapkan tiga keadaan berurutan bagi SATU produk terpilih:
--
--   versi 1  sampai 2024-03-01   keadaan awal
--   versi 2  2024-03-01          harga naik            -> Type 2
--   versi 3  2024-08-15          kategori dipindah     -> Type 2
--
-- Produk dipilih berdasarkan sku, bukan produk_id, sehingga produk yang sama
-- terpilih di seluruh kelas meskipun surrogate key setiap mahasiswa berbeda.
--
-- CATATAN: skrip ini hanya MENYIAPKAN data perubahan. Pemuatannya ke dimensi
-- adalah pekerjaan mahasiswa pada Bagian C.2 -- di situlah SCD-2 dipelajari.
-- =============================================================================

DROP TABLE IF EXISTS staging_produk_perubahan;

CREATE TABLE staging_produk_perubahan (
  batch          SMALLINT     NOT NULL,   -- urutan pemuatan, satu batch sekali
  produk_id      INTEGER      NOT NULL,
  sku            VARCHAR(20)  NOT NULL,
  nama_produk    VARCHAR(150) NOT NULL,
  merek          VARCHAR(60),
  kategori       VARCHAR(60),
  sub_kategori   VARCHAR(60),
  satuan         VARCHAR(15),
  berat_gram     NUMERIC(10,2),
  harga_jual     NUMERIC(12,2),
  berlaku_sejak  DATE         NOT NULL,
  catatan        TEXT
);

COMMENT ON TABLE staging_produk_perubahan IS
  'Perubahan atribut produk beserta tanggal berlakunya. Satu baris = satu '
  'versi baru yang harus dibentuk oleh pemuatan SCD-2.';
COMMENT ON COLUMN staging_produk_perubahan.batch IS
  'Pemuatan dijalankan SATU BATCH SEKALI, urut menaik. Memuat dua perubahan '
  'atas produk yang sama dalam satu jalan akan menghasilkan dua baris kini '
  'dan ditolak oleh indeks parsial uq_dim_produk_kini.';

-- -----------------------------------------------------------------------------
-- Produk skenario. Diambil dari baris kini dim_produk agar seluruh atribut
-- lain tersalin apa adanya; hanya atribut yang disebut yang berubah.
-- -----------------------------------------------------------------------------
WITH terpilih AS (
  SELECT *
  FROM   dim_produk
  WHERE  baris_kini
    AND  sku = (SELECT MIN(sku) FROM dim_produk WHERE baris_kini)
  LIMIT  1
)
INSERT INTO staging_produk_perubahan (
  batch, produk_id, sku, nama_produk, merek, kategori, sub_kategori,
  satuan, berat_gram, harga_jual, berlaku_sejak, catatan)

-- Perubahan 1: harga naik 12 persen sejak 1 Maret 2024.
SELECT 1, t.produk_id, t.sku, t.nama_produk, t.merek, t.kategori, t.sub_kategori,
       t.satuan, t.berat_gram,
       ROUND(t.harga_jual * 1.12, 2),
       DATE '2024-03-01',
       'Penyesuaian harga triwulan pertama'
FROM   terpilih t

UNION ALL

-- Perubahan 2: kategori dipindah, harga tetap seperti hasil perubahan 1.
SELECT 2, t.produk_id, t.sku, t.nama_produk, t.merek,
       'Makanan dan Minuman', 'Minuman Siap Saji',
       t.satuan, t.berat_gram,
       ROUND(t.harga_jual * 1.12, 2),
       DATE '2024-08-15',
       'Penataan ulang kategori oleh bagian pemasaran'
FROM   terpilih t;

-- -----------------------------------------------------------------------------
-- Produk yang terpilih. CATAT produk_id ini: ia dipakai berulang kali pada
-- Bagian C.3, Bagian D, dan latihan mandiri.
-- -----------------------------------------------------------------------------
SELECT DISTINCT produk_id, sku, nama_produk
FROM   staging_produk_perubahan;

SELECT batch, berlaku_sejak, kategori, harga_jual, catatan
FROM   staging_produk_perubahan
ORDER  BY batch;
