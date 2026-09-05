-- =============================================================================
-- CONTOH LENGKAP -- audit dimension.
--
-- Tabel audit_muat Modul 7 mencatat JALANNYA pipeline. Dimensi ini melangkah
-- lebih jauh: ia dihubungkan ke setiap baris fakta, sehingga pertanyaan
-- "baris ini dimuat kapan, dari sumber mana, oleh pipeline versi berapa?"
-- dijawab dengan satu join.
--
-- Kegunaannya terasa ketika sesuatu salah: bila pipeline versi tertentu
-- ternyata cacat, dimensi ini menjawab dengan tepat baris fakta mana yang
-- perlu dimuat ulang. Tanpanya, satu-satunya pilihan aman adalah memuat ulang
-- semuanya.
-- =============================================================================
{{ config(materialized='table') }}

WITH ringkas AS (
    SELECT batch_id,
           sumber,
           MIN(mulai)         AS waktu_muat,
           SUM(baris_dibaca)  AS baris_dibaca,
           SUM(baris_dimuat)  AS baris_dimuat,
           SUM(baris_unknown) AS baris_unknown
    FROM   {{ source('nusamart', 'audit_muat') }}
    GROUP  BY batch_id, sumber
)

SELECT ROW_NUMBER() OVER (ORDER BY batch_id, sumber) AS audit_key,
       batch_id,
       sumber,
       waktu_muat,
       baris_dibaca,
       baris_dimuat,
       baris_unknown,
       CASE WHEN baris_dibaca = baris_dimuat THEN 'lengkap'
            WHEN baris_dimuat = 0            THEN 'gagal'
            ELSE 'ada selisih'
       END AS status_mutu
FROM   ringkas

UNION ALL

SELECT -1, -1, 'sistem', NULL::TIMESTAMP, 0, 0, 0, 'tidak diketahui'
