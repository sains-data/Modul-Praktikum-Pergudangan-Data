-- CONTOH LENGKAP.
{{ config(materialized='view') }}

WITH sumber AS (
    SELECT * FROM {{ source('nusamart', 'produk_gabungan') }}
)

SELECT produk_id,
       sku,
       nama_produk,
       merek,
       kode_kategori   AS kategori,
       berat_gram,
       mulai_berlaku,
       selesai_berlaku,
       baris_kini,
       sumber          AS sistem_asal
FROM   sumber
