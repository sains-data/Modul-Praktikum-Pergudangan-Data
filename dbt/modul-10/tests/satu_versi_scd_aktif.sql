-- =============================================================================
-- Uji singular: satu produk hanya boleh punya SATU versi aktif.
--
-- LOGIKA TERBALIK. Uji singular adalah query yang MENGEMBALIKAN BARIS YANG
-- MELANGGAR aturan. Uji dinyatakan lulus bila query ini tidak mengembalikan
-- baris apa pun.
--
-- Yang ditulis bukan "buktikan aturannya benar", melainkan "tunjukkan yang
-- melanggarnya".
--
-- Dimensi kualitas : uniqueness
-- Tingkat keparahan: error -- dua versi aktif membuat join dimensi
--                    menggandakan seluruh baris fakta produk itu
-- =============================================================================
SELECT produk_id,
       COUNT(*)                          AS jumlah_versi_aktif,
       string_agg(produk_key::TEXT, ', ') AS kunci_yang_bentrok
FROM   {{ ref('dim_produk') }}
WHERE  baris_kini
GROUP  BY produk_id
HAVING COUNT(*) > 1
