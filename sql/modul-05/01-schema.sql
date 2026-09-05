-- =============================================================================
-- Modul 05 -- Penataan schema staging, gudang, dan mart
-- Dijalankan pada: nusamart_dw (port 5434)
--
--   docker compose exec -T postgres_dw \
--     psql -U praktikum -d nusamart_dw -f /sql/modul-05/01-schema.sql
--
-- ALTER TABLE ... SET SCHEMA hanya mengubah katalog, tidak memindahkan satu
-- byte pun data. Karena itu perintah ini selesai seketika bahkan pada tabel
-- berisi jutaan baris.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS gudang;
CREATE SCHEMA IF NOT EXISTS mart;

COMMENT ON SCHEMA staging IS
  'Salinan sumber apa adanya. Boleh kotor. Hanya dibaca proses ETL.';
COMMENT ON SCHEMA gudang IS
  'Dimensi dan fakta yang sudah bersih. Dibaca analis dan proses mart.';
COMMENT ON SCHEMA mart IS
  'Agregat dan view siap saji. Dibaca dashboard dan pengguna akhir.';

-- -----------------------------------------------------------------------------
-- Pemindahan objek. Blok berikut memindahkan setiap tabel ke schema yang
-- sesuai berdasarkan awalan namanya, sehingga tidak perlu disebut satu per
-- satu -- dan tetap benar meskipun sebagian tabel belum atau sudah dipindah.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  t   RECORD;
  tuj TEXT;
BEGIN
  FOR t IN
    SELECT table_name
    FROM   information_schema.tables
    WHERE  table_schema = 'public' AND table_type = 'BASE TABLE'
    ORDER  BY table_name
  LOOP
    tuj := CASE
             WHEN t.table_name LIKE 'staging\_%' THEN 'staging'
             WHEN t.table_name LIKE 'dim\_%'     THEN 'gudang'
             WHEN t.table_name LIKE 'fakta\_%'   THEN 'gudang'
             ELSE NULL
           END;

    IF tuj IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I SET SCHEMA %I', t.table_name, tuj);
      RAISE NOTICE 'dipindah: public.% -> %.%', t.table_name, tuj, t.table_name;
    ELSE
      RAISE NOTICE 'DILEWATI (tidak dikenali): public.%', t.table_name;
    END IF;
  END LOOP;
END $$;

-- View role-playing Modul 3 ikut berpindah ke gudang.
DO $$
DECLARE v RECORD;
BEGIN
  FOR v IN
    SELECT table_name FROM information_schema.views
    WHERE  table_schema = 'public' AND table_name LIKE 'dim\_%'
  LOOP
    EXECUTE format('ALTER VIEW public.%I SET SCHEMA gudang', v.table_name);
    RAISE NOTICE 'view dipindah: public.% -> gudang.%', v.table_name, v.table_name;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- Kenyamanan selama sesi laboratorium.
--
-- PERINGATAN: pada skrip yang dikumpulkan, tulis nama lengkap objek. Skrip
-- yang bergantung pada search_path tidak reproduktif di lingkungan orang lain.
-- -----------------------------------------------------------------------------
SET search_path TO gudang, staging, mart, public;

-- -----------------------------------------------------------------------------
-- Verifikasi. Setelah pemindahan, schema public seharusnya tidak lagi memuat
-- tabel gudang data.
-- -----------------------------------------------------------------------------
SELECT table_schema, COUNT(*) AS jumlah_tabel,
       string_agg(table_name, ', ' ORDER BY table_name) AS daftar
FROM   information_schema.tables
WHERE  table_schema IN ('public', 'staging', 'gudang', 'mart')
  AND  table_type = 'BASE TABLE'
GROUP  BY table_schema
ORDER  BY table_schema;
