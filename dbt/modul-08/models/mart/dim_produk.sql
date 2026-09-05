-- =============================================================================
-- CONTOH LENGKAP -- dimensi SCD-2 versi dbt.
--
-- Perhatikan ref(), bukan nama tabel. Inilah satu-satunya cara dbt mengetahui
-- bahwa model ini harus dibangun SESUDAH stg_produk.
--
-- Baris unknown ditambahkan di sini, bukan lewat INSERT terpisah, supaya
-- model tetap dapat dibangun ulang dari nol kapan saja.
-- =============================================================================
{{ config(materialized='table') }}

WITH produk AS (
    SELECT * FROM {{ ref('stg_produk') }}
),

bernomor AS (
    SELECT ROW_NUMBER() OVER (ORDER BY produk_id, mulai_berlaku) AS produk_key,
           produk_id, sku, nama_produk, merek, kategori, berat_gram,
           mulai_berlaku, selesai_berlaku, baris_kini, sistem_asal
    FROM   produk
),

unknown AS (
    -- Baris unknown Modul 5: fakta tanpa pasangan menunjuk ke sini, bukan NULL.
    SELECT -1                     AS produk_key,
           -1                     AS produk_id,
           'TIDAK-DIKETAHUI'      AS sku,
           'Tidak Diketahui'      AS nama_produk,
           'Tidak Diketahui'      AS merek,
           'Tidak Diketahui'      AS kategori,
           NULL::NUMERIC          AS berat_gram,
           DATE '1900-01-01'      AS mulai_berlaku,
           DATE '9999-12-31'      AS selesai_berlaku,
           TRUE                   AS baris_kini,
           'sistem'               AS sistem_asal
)

SELECT * FROM bernomor
UNION ALL
SELECT * FROM unknown
