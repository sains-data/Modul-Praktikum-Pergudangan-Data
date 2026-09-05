-- =============================================================================
-- Modul 08 -- Skrip pemeriksa checkpoint
-- Dijalankan pada: nusamart_dw (port 5434), sesudah `dbt build`
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-08/check.sql
--
-- Sebagian butir modul ini diperiksa dari keluaran dbt, bukan dari basis data:
-- `dbt debug`, `dbt build`, dan keutuhan graf lineage. Skrip ini memeriksa
-- jejak yang ditinggalkan dbt DI DALAM basis data.
--
-- Butir B5 adalah kriteria lulus utama: angka versi dbt harus sama dengan
-- angka gudang bikinan tangan. Keduanya membangun hal yang sama dengan cara
-- berbeda, sehingga selisih apa pun berarti salah satunya keliru.
-- =============================================================================

\pset border 2
\pset title 'Modul 08 -- Hasil pemeriksaan checkpoint'

WITH
-- B1. Schema keluaran dbt ada.
b1 AS (
  SELECT 'B1  Schema dbt_mart ada' AS butir,
         COUNT(*) = 1 AS lulus,
         CASE WHEN COUNT(*) = 1 THEN 'ada'
              ELSE 'belum ada -- dbt run belum pernah berhasil' END AS detail
  FROM   information_schema.schemata
  WHERE  schema_name = 'dbt_mart'
),

-- B2. Model yang diminta sudah terbangun, termasuk dua yang dikosongkan pada
--     kerangka.
model_diharapkan (nama) AS (
  VALUES ('dim_produk'), ('dim_toko'), ('dim_audit'), ('fct_penjualan')
),
model_hilang AS (
  SELECT nama FROM model_diharapkan
  EXCEPT
  SELECT table_name FROM information_schema.tables
  WHERE  table_schema = 'dbt_mart'
),
b2 AS (
  SELECT 'B2  Seluruh model mart terbangun' AS butir,
         COUNT(*) = 0 AS lulus,
         COALESCE('belum terbangun: ' || string_agg(nama, ', ' ORDER BY nama),
                  'lengkap') AS detail
  FROM   model_hilang
),

-- B3. Model staging terbangun sebagai VIEW, bukan TABLE. Materialization yang
--     keliru menandakan config belum ditetapkan.
b3 AS (
  SELECT 'B3  Model staging berupa view' AS butir,
         COUNT(*) FILTER (WHERE table_type <> 'VIEW') = 0 AS lulus,
         COUNT(*) FILTER (WHERE table_type = 'VIEW') || ' view, ' ||
         COUNT(*) FILTER (WHERE table_type <> 'VIEW') || ' bukan view' AS detail
  FROM   information_schema.tables
  WHERE  table_schema = 'dbt_staging' AND table_name LIKE 'stg\_%'
),

-- B4. Audit dimension terisi dan setiap baris fakta memiliki audit_key.
b4 AS (
  SELECT 'B4  Setiap baris fakta punya audit_key' AS butir,
         jml = 0 AS lulus,
         jml || ' baris fakta tanpa audit_key' AS detail
  FROM ( SELECT COUNT(*) AS jml FROM dbt_mart.fct_penjualan
         WHERE audit_key IS NULL ) x
),

-- B5. Angka versi dbt sama dengan gudang bikinan tangan.
--     KRITERIA LULUS UTAMA.
b5 AS (
  SELECT 'B5  Angka dbt sama dengan gudang manual' AS butir,
         COALESCE(selisih, 1) = 0 AS lulus,
         'selisih ' || COALESCE(selisih::TEXT, 'tidak dapat dihitung') AS detail
  FROM ( SELECT (SELECT COALESCE(SUM(subtotal), 0) FROM dbt_mart.fct_penjualan)
              - (SELECT COALESCE(SUM(subtotal), 0) FROM gudang.fakta_penjualan)
              AS selisih ) x
),

-- B6. Jumlah baris kedua jalur juga sama. Total yang sama dengan jumlah baris
--     berbeda menandakan penyaringan yang tidak konsisten.
b6 AS (
  SELECT 'B6  Jumlah baris kedua jalur sama' AS butir,
         selisih = 0 AS lulus,
         'dbt ' || a || ' lawan manual ' || b || ', selisih ' || selisih
         AS detail
  FROM ( SELECT (SELECT COUNT(*) FROM dbt_mart.fct_penjualan)   AS a,
                (SELECT COUNT(*) FROM gudang.fakta_penjualan)   AS b,
                (SELECT COUNT(*) FROM dbt_mart.fct_penjualan)
              - (SELECT COUNT(*) FROM gudang.fakta_penjualan)   AS selisih ) x
),

-- B7. Baris unknown ada pada dimensi versi dbt. Tanpanya, uji relationships
--     akan gagal untuk setiap baris fakta yang kuncinya -1.
b7 AS (
  SELECT 'B7  Baris unknown ada pada dimensi dbt' AS butir,
         COUNT(*) FILTER (WHERE NOT ada) = 0 AS lulus,
         COALESCE('belum ada pada: ' ||
                  string_agg(dimensi, ', ') FILTER (WHERE NOT ada),
                  'lengkap') AS detail
  FROM ( SELECT 'dim_produk' AS dimensi,
                EXISTS (SELECT 1 FROM dbt_mart.dim_produk
                        WHERE produk_key = -1) AS ada
         UNION ALL
         SELECT 'dim_toko',
                EXISTS (SELECT 1 FROM dbt_mart.dim_toko WHERE toko_key = -1)
         UNION ALL
         SELECT 'dim_audit',
                EXISTS (SELECT 1 FROM dbt_mart.dim_audit WHERE audit_key = -1)
       ) u
),

-- B8. Fakta menunjuk versi dimensi yang berlaku saat transaksi terjadi.
--     Bila pencarian kunci memakai baris_kini, butir ini gagal.
b8 AS (
  SELECT 'B8  Fakta menunjuk versi yang berlaku' AS butir,
         COUNT(*) = 0 AS lulus,
         COUNT(*) || ' baris menunjuk versi di luar masa berlakunya' AS detail
  FROM   dbt_mart.fct_penjualan f
  JOIN   dbt_mart.dim_produk p ON p.produk_key = f.produk_key
  WHERE  f.produk_key <> -1
    AND  (f.tanggal_transaksi <  p.mulai_berlaku
       OR f.tanggal_transaksi >= p.selesai_berlaku)
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

-- Isi audit dimension. Kolom status_mutu yang bernilai 'ada selisih' bukan
-- kegagalan; ia laporan bahwa batch tersebut tidak memuat seluruh baris yang
-- dibacanya, dan selisih itu wajib dijelaskan.
SELECT audit_key, batch_id, sumber, waktu_muat,
       baris_dibaca, baris_dimuat, baris_unknown, status_mutu
FROM   dbt_mart.dim_audit
ORDER  BY audit_key;

-- Penelusuran satu angka lewat audit dimension: batch mana yang menyumbang
-- berapa. Inilah bentuk konkret dari pertanyaan "baris ini masuk kapan, dari
-- jalan pipeline yang mana" pada tugas individu.
SELECT a.batch_id, a.sumber, a.waktu_muat,
       COUNT(*)           AS baris_fakta,
       SUM(f.subtotal)    AS nilai_penjualan
FROM   dbt_mart.fct_penjualan f
JOIN   dbt_mart.dim_audit a ON a.audit_key = f.audit_key
GROUP  BY a.batch_id, a.sumber, a.waktu_muat
ORDER  BY a.batch_id, a.sumber;

-- Perbandingan dua jalur pembangunan, dirinci per bulan supaya selisih dapat
-- dilacak ke periode tertentu, bukan hanya diketahui totalnya.
SELECT COALESCE(d.bln, g.bln)                       AS tahun_bulan,
       d.nilai                                      AS versi_dbt,
       g.nilai                                      AS versi_tangan,
       COALESCE(d.nilai, 0) - COALESCE(g.nilai, 0)  AS selisih
FROM ( SELECT to_char(tanggal_transaksi, 'YYYYMM')::INT AS bln,
              SUM(subtotal) AS nilai
       FROM   dbt_mart.fct_penjualan GROUP BY 1 ) d
FULL OUTER JOIN
     ( SELECT dt.tahun_bulan AS bln, SUM(f.subtotal) AS nilai
       FROM   gudang.fakta_penjualan f
       JOIN   gudang.dim_tanggal dt ON dt.tanggal_key = f.tanggal_key
       GROUP  BY 1 ) g
  ON g.bln = d.bln
WHERE COALESCE(d.nilai, 0) <> COALESCE(g.nilai, 0)
ORDER BY 1;

-- -----------------------------------------------------------------------------
-- Butir yang diperiksa asisten dari keluaran dbt, bukan dari basis data:
--
--   B9   `dbt debug` seluruhnya OK.
--   B10  `dbt build` berjalan tanpa galat.
--   B11  Seluruh model memakai source() atau ref(); tidak ada nama tabel yang
--        ditulis langsung. Periksa dengan:
--            grep -rn "FROM \(staging\|dbt_mart\)\." models/
--        Model yang lolos grep ini akan muncul TERPUTUS pada graf lineage
--        meskipun build-nya berhasil -- graf yang bohong lebih berbahaya
--        daripada tidak ada graf sama sekali.
--   B12  lineage.png memperlihatkan jalur utuh dari source sampai
--        fct_penjualan, tanpa simpul yang menggantung.
--   B13  Empat generic test terpasang dan hasilnya dilaporkan.
--   B14  profiles.yml TIDAK ada di dalam repositori; yang ada hanya
--        profiles.yml.example tanpa kredensial.
-- -----------------------------------------------------------------------------
