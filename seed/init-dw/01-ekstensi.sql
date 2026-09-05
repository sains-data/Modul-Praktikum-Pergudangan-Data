-- =============================================================================
-- Inisialisasi container postgres_dw.
--
-- Ekstensi diaktifkan di muka agar mahasiswa tidak terhalang hak akses saat
-- modul yang memerlukannya tiba. Naskah modul tetap meminta mereka
-- menjalankan CREATE EXTENSION sendiri sebagai pre-lab -- perintah itu aman
-- diulang karena memakai IF NOT EXISTS.
--
--   btree_gist          Modul 3   exclusion constraint penjaga versi SCD-2
--   postgres_fdw        Modul 7   membaca basis data sumber lain langsung
--   tablefunc           Modul 9   crosstab untuk pivot (opsional)
--   pg_stat_statements  proyek    pemantauan query operasional
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE EXTENSION IF NOT EXISTS tablefunc;

-- pg_stat_statements memerlukan shared_preload_libraries; bila belum diatur,
-- perintah ini gagal tanpa menghentikan inisialisasi.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_stat_statements dilewati: %', SQLERRM;
END $$;
