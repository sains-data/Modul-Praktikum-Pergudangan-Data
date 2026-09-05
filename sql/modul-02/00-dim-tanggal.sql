-- =============================================================================
-- Modul 02 -- Pembangkit dimensi tanggal
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-02/00-dim-tanggal.sql
--
-- Dimensi tanggal adalah satu-satunya dimensi yang dibangkitkan, bukan diambil
-- dari sumber: tidak ada sistem operasional yang menyimpan tabel kalender.
--
-- Kunci memakai bentuk YYYYMMDD. Ini pengecualian yang diterima atas aturan
-- "surrogate key tanpa makna": bentuknya memudahkan debugging dan memungkinkan
-- partisi menurut rentang kunci pada Modul 6, tanpa kehilangan sifatnya sebagai
-- bilangan bulat sempit.
-- =============================================================================

DROP TABLE IF EXISTS dim_tanggal CASCADE;

CREATE TABLE dim_tanggal (
  tanggal_key    INTEGER     PRIMARY KEY,
  tanggal        DATE        NOT NULL UNIQUE,
  hari           SMALLINT    NOT NULL,
  nama_hari      VARCHAR(10) NOT NULL,
  minggu_ke      SMALLINT    NOT NULL,
  bulan          SMALLINT    NOT NULL,
  nama_bulan     VARCHAR(12) NOT NULL,
  kuartal        SMALLINT    NOT NULL,
  tahun          SMALLINT    NOT NULL,
  tahun_bulan    INTEGER     NOT NULL,   -- YYYYMM, untuk pengurutan kronologis
  hari_ke_tahun  SMALLINT    NOT NULL,
  akhir_pekan    BOOLEAN     NOT NULL
);

COMMENT ON TABLE  dim_tanggal IS
  'Kalender harian 2020-2029. Satu baris mewakili satu hari.';
COMMENT ON COLUMN dim_tanggal.tanggal_key IS
  'Kunci berbentuk YYYYMMDD.';
COMMENT ON COLUMN dim_tanggal.tahun_bulan IS
  'YYYYMM. Dipakai untuk mengurutkan bulan lintas tahun secara benar.';

INSERT INTO dim_tanggal (
  tanggal_key, tanggal, hari, nama_hari, minggu_ke, bulan, nama_bulan,
  kuartal, tahun, tahun_bulan, hari_ke_tahun, akhir_pekan)
SELECT TO_CHAR(d, 'YYYYMMDD')::INTEGER,
       d::DATE,
       EXTRACT(DAY     FROM d),
       TO_CHAR(d, 'TMDay'),          -- TM mengikuti setelan lc_time basis data
       EXTRACT(WEEK    FROM d),
       EXTRACT(MONTH   FROM d),
       TO_CHAR(d, 'TMMonth'),
       EXTRACT(QUARTER FROM d),
       EXTRACT(YEAR    FROM d),
       TO_CHAR(d, 'YYYYMM')::INTEGER,
       EXTRACT(DOY     FROM d),
       EXTRACT(ISODOW  FROM d) IN (6, 7)   -- ISO: 6 Sabtu, 7 Minggu
FROM   generate_series(DATE '2020-01-01',
                       DATE '2029-12-31',
                       INTERVAL '1 day') d;

-- -----------------------------------------------------------------------------
-- Verifikasi. Sepuluh tahun 2020-2029 memuat 3.653 hari karena 2020, 2024, dan
-- 2028 adalah tahun kabisat. Bila hasilnya 3.650, rentangnya keliru.
-- -----------------------------------------------------------------------------
SELECT COUNT(*)     AS jumlah_hari,
       MIN(tanggal) AS mulai,
       MAX(tanggal) AS selesai,
       COUNT(*) FILTER (WHERE akhir_pekan) AS jumlah_akhir_pekan,
       COUNT(DISTINCT tahun) AS jumlah_tahun
FROM   dim_tanggal;
