-- =============================================================================
-- Inisialisasi container postgres_source.
--
-- Dijalankan OTOMATIS oleh image PostgreSQL, hanya saat volume pertama kali
-- dibuat. Untuk menjalankannya ulang:  docker compose down -v && docker compose up -d
--
-- Membuat tiga basis data selain nusamart_oltp (yang sudah dibuat oleh
-- POSTGRES_DB), beserta ekstensi yang diperlukan masing-masing.
-- =============================================================================

CREATE DATABASE nusamart_barat;
CREATE DATABASE nusamart_timur;
CREATE DATABASE northwind;

COMMENT ON DATABASE nusamart_barat IS
  'Sumber kedua, hasil akuisisi. Nama kolom berbahasa Inggris, berat dalam '
  'kilogram, kode kategori sendiri. Dipakai mulai Modul 7.';
COMMENT ON DATABASE nusamart_timur IS
  'Sumber ketiga, wilayah timur. Ejaan pelanggan tidak konsisten, transaksi '
  'sampai terlambat tiga hari. Dipakai mulai Modul 7.';
COMMENT ON DATABASE northwind IS
  'Basis data pembanding pada Modul 6. Diisi oleh seed/unduh-northwind.sh.';

-- Schema nusamart pada basis data utama.
\connect nusamart_oltp
CREATE SCHEMA IF NOT EXISTS nusamart;
COMMENT ON SCHEMA nusamart IS
  'Sistem operasional NusaMart. Data mentah -- TIDAK BOLEH DIUBAH oleh '
  'mahasiswa (lihat Aturan Reproduksibilitas pada panduan persiapan).';
