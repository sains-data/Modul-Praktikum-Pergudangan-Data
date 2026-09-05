-- =============================================================================
-- Modul 04 -- Tabel staging untuk persediaan dan promosi
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-04/01-staging-persediaan.sql
--
-- Melanjutkan pola Modul 2: staging menyalin sumber apa adanya, pembersihan
-- dan pemetaan kunci terjadi saat pemuatan fakta.
-- =============================================================================

DROP TABLE IF EXISTS staging_persediaan;
DROP TABLE IF EXISTS staging_promosi_produk;
DROP TABLE IF EXISTS staging_promosi;

-- Grain sumber: satu produk di satu toko pada satu hari.
CREATE TABLE staging_persediaan (
  tanggal      DATE,
  toko_id      INTEGER,
  produk_id    INTEGER,
  saldo_awal   NUMERIC(12,2),
  masuk        NUMERIC(12,2),
  keluar       NUMERIC(12,2),
  saldo_akhir  NUMERIC(12,2)
);

CREATE TABLE staging_promosi (
  promosi_id    INTEGER,
  kode_promo    VARCHAR(20),
  nama_promosi  VARCHAR(120),
  tipe_promosi  VARCHAR(40),
  mulai         DATE,
  selesai       DATE
);

CREATE TABLE staging_promosi_produk (
  promosi_id  INTEGER,
  produk_id   INTEGER
);

-- =============================================================================
-- Pemindahan dari sumber. Jalankan dari shell:
--
--   SRC="docker compose exec -T postgres_source psql -U praktikum -d nusamart_oltp"
--   DW="docker compose exec -T postgres_dw     psql -U praktikum -d nusamart_dw"
--
--   $SRC -c "COPY (SELECT tanggal, toko_id, produk_id, saldo_awal, masuk,
--                         keluar, saldo_akhir
--                  FROM nusamart.persediaan_harian) TO STDOUT WITH CSV" \
--   | $DW -c "COPY staging_persediaan FROM STDIN WITH CSV"
--
--   $SRC -c "COPY (SELECT promosi_id, kode_promo, nama_promosi, tipe,
--                         mulai, selesai
--                  FROM nusamart.promosi) TO STDOUT WITH CSV" \
--   | $DW -c "COPY staging_promosi FROM STDIN WITH CSV"
--
--   $SRC -c "COPY (SELECT promosi_id, produk_id
--                  FROM nusamart.promosi_produk) TO STDOUT WITH CSV" \
--   | $DW -c "COPY staging_promosi_produk FROM STDIN WITH CSV"
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Pemeriksaan grain sumber SEBELUM memuat fakta.
--
-- Periodic snapshot memakai primary key gabungan (tanggal, produk, toko).
-- Bila sumber memuat lebih dari satu baris untuk kombinasi itu, pemuatan akan
-- ditolak -- dan lebih baik mengetahuinya sekarang daripada di tengah INSERT.
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS kombinasi_ganda
FROM ( SELECT tanggal, toko_id, produk_id
       FROM   staging_persediaan
       GROUP  BY tanggal, toko_id, produk_id
       HAVING COUNT(*) > 1 ) x;

-- Perkiraan ukuran factless fact sebelum dimuat: jumlah produk per promosi
-- dikalikan lama promosi. Angka ini menentukan apakah pemuatan perlu dibatasi
-- lebih ketat daripada satu tahun.
SELECT sp.kode_promo,
       COUNT(DISTINCT spp.produk_id)              AS jumlah_produk,
       (sp.selesai - sp.mulai + 1)                AS lama_hari,
       COUNT(DISTINCT spp.produk_id) * (sp.selesai - sp.mulai + 1)
                                                  AS perkiraan_baris
FROM   staging_promosi sp
JOIN   staging_promosi_produk spp ON spp.promosi_id = sp.promosi_id
WHERE  EXTRACT(YEAR FROM sp.mulai) = 2024
GROUP  BY sp.kode_promo, sp.mulai, sp.selesai
ORDER  BY perkiraan_baris DESC;

-- Rentang tanggal persediaan, untuk memastikan dim_tanggal mencakupnya.
SELECT MIN(tanggal) AS mulai, MAX(tanggal) AS selesai,
       COUNT(DISTINCT tanggal) AS jumlah_hari,
       COUNT(DISTINCT produk_id) AS jumlah_produk,
       COUNT(DISTINCT toko_id)   AS jumlah_toko
FROM   staging_persediaan;
