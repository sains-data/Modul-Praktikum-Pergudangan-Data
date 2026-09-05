-- =============================================================================
-- Uji singular: subtotal harus sama dengan kuantitas x harga - diskon.
--
-- Anomali jenis ini LOLOS seluruh constraint basis data, karena ketiga
-- kolomnya sendiri-sendiri masuk akal: kuantitas positif, harga positif,
-- diskon tidak negatif. Yang salah adalah hubungan di antara ketiganya.
--
-- Inilah alasan constraint tidak dapat menggantikan pengujian data.
--
-- Dimensi kualitas : consistency
-- Tingkat keparahan: error -- angka laporan langsung salah
-- =============================================================================
SELECT transaksi_id,
       kuantitas,
       harga_satuan,
       diskon,
       subtotal,
       ROUND(kuantitas * harga_satuan - diskon, 2) AS seharusnya,
       ROUND(subtotal - (kuantitas * harga_satuan - diskon), 2) AS selisih
FROM   {{ ref('fct_penjualan') }}
WHERE  ROUND(kuantitas * harga_satuan - diskon, 2) <> ROUND(subtotal, 2)
