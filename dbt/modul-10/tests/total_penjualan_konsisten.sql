-- =============================================================================
-- Uji singular: total pada mart harus sama dengan total pada fakta.
--
-- Selisih berarti salah satu dari dua hal: mart belum disegarkan setelah fakta
-- berubah -- risiko yang disebut pada Modul 6 -- atau agregasinya keliru.
--
-- Dimensi kualitas : consistency
-- Tingkat keparahan: error -- seluruh angka dashboard bertumpu pada mart
-- =============================================================================
WITH fakta AS (
    SELECT ROUND(SUM(subtotal), 2) AS total
    FROM   {{ ref('fct_penjualan') }}
),
mart AS (
    SELECT ROUND(SUM(nilai_penjualan), 2) AS total
    FROM   {{ ref('agg_penjualan_bulanan') }}
)
SELECT fakta.total        AS total_fakta,
       mart.total         AS total_mart,
       fakta.total - mart.total AS selisih
FROM   fakta, mart
WHERE  fakta.total <> mart.total
