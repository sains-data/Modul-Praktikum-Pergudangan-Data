-- =============================================================================
-- CONTOH LENGKAP. Pakai berkas ini sebagai pola untuk stg_toko.
--
-- Perhatikan tiga hal:
--   1. config materialization -- view, karena staging murah dan harus segar
--   2. source(), bukan nama tabel langsung -- inilah yang membentuk lineage
--   3. penamaan kolom yang diseragamkan di lapis ini, sekali saja
-- =============================================================================
{{ config(materialized='view') }}

WITH sumber AS (
    SELECT * FROM {{ source('nusamart', 'penjualan_gabungan') }}
)

SELECT transaksi_id,
       nomor_struk,
       produk_id,
       toko_id,
       pelanggan_master_id     AS pelanggan_id,
       waktu_transaksi::DATE   AS tanggal_transaksi,
       kuantitas,
       harga_satuan,
       diskon,
       subtotal,
       sumber                  AS sistem_asal,
       batch_id
FROM   sumber
-- Penyaringan status dilakukan DI SINI, bukan saat ekstraksi. Baris BATAL
-- tetap sampai ke staging agar jumlahnya dapat dihitung saat rekonsiliasi.
WHERE  status <> 'BATAL'
