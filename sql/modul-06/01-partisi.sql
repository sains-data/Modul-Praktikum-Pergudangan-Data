-- =============================================================================
-- Modul 06 -- Memartisi fakta_penjualan menurut rentang bulan
-- Dijalankan pada: nusamart_dw (port 5434), dataset ukuran SEDANG
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-06/01-partisi.sql
--
-- Tabel yang sudah ada TIDAK dapat diubah menjadi tabel berpartisi. Yang
-- dilakukan adalah membuat tabel berpartisi baru, memindahkan datanya, lalu
-- menukar namanya.
--
-- Kunci partisi adalah tanggal_key. Bentuk YYYYMMDD yang dipilih pada Modul 2
-- terbayar di sini: ia bilangan bulat, sehingga batas partisi dapat dinyatakan
-- sebagai rentang bilangan yang terbaca manusia.
-- =============================================================================

\timing on

-- Jumlah baris sebelum pemindahan. Angka ini WAJIB sama sesudahnya.
SELECT COUNT(*) AS baris_sebelum,
       MIN(tanggal_key) AS kunci_terkecil,
       MAX(tanggal_key) AS kunci_terbesar
FROM   gudang.fakta_penjualan;

-- -----------------------------------------------------------------------------
-- 1. Tabel induk berpartisi.
--
-- INCLUDING DEFAULTS saja, bukan INCLUDING ALL: primary key pada tabel
-- berpartisi wajib memuat kunci partisi, sehingga constraint disalin manual
-- sesudah pemindahan.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS gudang.fakta_penjualan_p CASCADE;

CREATE TABLE gudang.fakta_penjualan_p (
  LIKE gudang.fakta_penjualan INCLUDING DEFAULTS
) PARTITION BY RANGE (tanggal_key);

-- -----------------------------------------------------------------------------
-- 2. Satu partisi per bulan, dibangkitkan otomatis dari rentang data yang ada.
--    Menulis 36 pernyataan CREATE TABLE dengan tangan mengundang salah ketik
--    pada batas rentang, dan batas yang keliru menyebabkan baris terlempar ke
--    partisi DEFAULT tanpa pesan apa pun.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  bulan   DATE;
  mulai   DATE := DATE '2020-01-01';
  selesai DATE := DATE '2027-01-01';
  nama    TEXT;
BEGIN
  bulan := mulai;
  WHILE bulan < selesai LOOP
    nama := format('fakta_penjualan_%s', to_char(bulan, 'YYYY_MM'));
    EXECUTE format(
      'CREATE TABLE gudang.%I PARTITION OF gudang.fakta_penjualan_p
         FOR VALUES FROM (%s) TO (%s)',
      nama,
      to_char(bulan, 'YYYYMMDD'),
      to_char(bulan + INTERVAL '1 month', 'YYYYMMDD'));
    bulan := bulan + INTERVAL '1 month';
  END LOOP;
  RAISE NOTICE 'partisi bulanan dibuat: % sampai %', mulai, selesai;
END $$;

-- -----------------------------------------------------------------------------
-- 3. Partisi penampung.
--
-- WAJIB ADA. Alasannya berasal dari Modul 5: baris fakta yang tanggalnya tidak
-- diketahui menunjuk tanggal_key = -1, dan nilai itu tidak masuk rentang bulan
-- mana pun. Tanpa partisi ini, pemindahan data gagal dengan pesan
-- "no partition of relation found for row".
-- -----------------------------------------------------------------------------
CREATE TABLE gudang.fakta_penjualan_lain
  PARTITION OF gudang.fakta_penjualan_p DEFAULT;

-- -----------------------------------------------------------------------------
-- 4. Pemindahan data.
-- -----------------------------------------------------------------------------
INSERT INTO gudang.fakta_penjualan_p
SELECT * FROM gudang.fakta_penjualan;

-- -----------------------------------------------------------------------------
-- 5. Penukaran nama. Tabel lama disimpan sebagai cadangan sampai verifikasi
--    selesai; hapus sendiri sesudah checkpoint.
-- -----------------------------------------------------------------------------
ALTER TABLE gudang.fakta_penjualan   RENAME TO fakta_penjualan_lama;
ALTER TABLE gudang.fakta_penjualan_p RENAME TO fakta_penjualan;

-- -----------------------------------------------------------------------------
-- 6. Constraint dan indeks pada tabel induk.
--    Indeks pada induk otomatis dibuat pada setiap partisi.
-- -----------------------------------------------------------------------------
ALTER TABLE gudang.fakta_penjualan
  ADD CONSTRAINT fk_fp_tanggal FOREIGN KEY (tanggal_key)
      REFERENCES gudang.dim_tanggal(tanggal_key),
  ADD CONSTRAINT fk_fp_produk  FOREIGN KEY (produk_key)
      REFERENCES gudang.dim_produk(produk_key),
  ADD CONSTRAINT fk_fp_toko    FOREIGN KEY (toko_key)
      REFERENCES gudang.dim_toko(toko_key),
  ADD CONSTRAINT fk_fp_flag    FOREIGN KEY (flag_key)
      REFERENCES gudang.dim_transaksi_flag(flag_key);

CREATE INDEX ix_fp_toko_tanggal
  ON gudang.fakta_penjualan (toko_key, tanggal_key);

ANALYZE gudang.fakta_penjualan;

\timing off

-- =============================================================================
-- Verifikasi
-- =============================================================================

-- Jumlah baris harus sama persis dengan angka sebelum pemindahan.
SELECT (SELECT COUNT(*) FROM gudang.fakta_penjualan)      AS baris_sesudah,
       (SELECT COUNT(*) FROM gudang.fakta_penjualan_lama) AS baris_sebelum,
       (SELECT COUNT(*) FROM gudang.fakta_penjualan)
     - (SELECT COUNT(*) FROM gudang.fakta_penjualan_lama) AS selisih;

-- Sebaran baris per partisi. Partisi DEFAULT yang berisi banyak baris adalah
-- tanda ada rentang tanggal yang belum dibuatkan partisinya -- periksa, jangan
-- diabaikan.
SELECT c.relname AS partisi,
       c.reltuples::BIGINT AS perkiraan_baris,
       pg_size_pretty(pg_relation_size(c.oid)) AS ukuran
FROM   pg_class c
JOIN   pg_inherits i ON i.inhrelid = c.oid
JOIN   pg_class p ON p.oid = i.inhparent
WHERE  p.relname = 'fakta_penjualan'
ORDER  BY c.relname;

-- Jumlah baris yang benar-benar mendarat di partisi penampung.
SELECT COUNT(*) AS baris_di_partisi_default
FROM   gudang.fakta_penjualan_lain;
