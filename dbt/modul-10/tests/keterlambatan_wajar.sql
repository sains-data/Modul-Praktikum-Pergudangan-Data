-- =============================================================================
-- Uji singular: selisih antara tanggal transaksi dan tanggal pemuatan tidak
-- boleh melampaui ambang yang disepakati.
--
-- Sebagian keterlambatan memang wajar dan sudah ditangani Modul 7 -- sumber
-- ketiga mengirim tiga hari terlambat. Yang dicari adalah ekor yang JAUH lebih
-- panjang daripada biasanya.
--
-- Dimensi kualitas : timeliness
-- Tingkat keparahan: warn -- data terlambat tetap sah dan tetap dimuat,
--                    tetapi perlu diketahui karena laporan periode lalu
--                    dapat berubah setelah diterbitkan
--
-- Ambang 7 hari dipilih sebagai dua kali lipat keterlambatan yang diketahui
-- (3 hari), memberi ruang bagi hari libur tanpa membiarkan keterlambatan
-- sungguhan lolos. Sesuaikan bila pola sumber Anda berbeda.
-- =============================================================================
{% set ambang_hari = 7 %}

SELECT f.transaksi_id,
       dt.tanggal          AS tanggal_transaksi,
       a.waktu_muat::DATE  AS tanggal_muat,
       a.waktu_muat::DATE - dt.tanggal AS terlambat_hari,
       a.sumber
FROM   {{ ref('fct_penjualan') }} f
JOIN   {{ ref('dim_tanggal') }}  dt ON dt.tanggal_key = f.tanggal_key
JOIN   {{ ref('dim_audit') }}    a  ON a.audit_key    = f.audit_key
WHERE  f.tanggal_key <> -1
  AND  a.waktu_muat IS NOT NULL
  AND  a.waktu_muat::DATE - dt.tanggal > {{ ambang_hari }}
