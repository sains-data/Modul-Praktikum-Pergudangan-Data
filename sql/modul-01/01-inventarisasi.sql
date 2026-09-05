-- =============================================================================
-- Modul 01 -- Inventarisasi dan profiling basis data operasional NusaMart
-- Dijalankan pada: nusamart_oltp (port 5433), schema nusamart
--
-- Skrip ini adalah kerangka kerja Bagian C. Mahasiswa menjalankannya per blok,
-- membaca hasilnya, lalu memindahkan temuan ke inventaris-sumber.md.
-- Menjalankan seluruh berkas sekaligus tanpa membaca hasilnya tidak memenuhi
-- tujuan modul.
-- =============================================================================

SET search_path TO nusamart, public;

-- -----------------------------------------------------------------------------
-- 1. VOLUME -- jumlah baris sebenarnya untuk seluruh tabel sekaligus.
--    Angka pada panel statistik DBeaver berasal dari pg_class.reltuples dan
--    hanya berupa perkiraan; yang dipakai pada laporan adalah angka di bawah.
-- -----------------------------------------------------------------------------
SELECT table_name,
       (xpath('/row/c/text()',
              query_to_xml(format('SELECT COUNT(*) AS c FROM nusamart.%I',
                                  table_name),
                           false, true, '')))[1]::text::bigint AS jumlah_baris
FROM   information_schema.tables
WHERE  table_schema = 'nusamart'
  AND  table_type   = 'BASE TABLE'
ORDER  BY jumlah_baris DESC;

-- Pembanding: perkiraan dari katalog. Bandingkan dengan hasil di atas dan
-- catat selisihnya -- inilah alasan perkiraan tidak dipakai untuk rekonsiliasi.
SELECT relname AS tabel, reltuples::bigint AS perkiraan_baris
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'nusamart' AND c.relkind = 'r'
ORDER  BY perkiraan_baris DESC;

-- -----------------------------------------------------------------------------
-- 2. STRUKTUR -- kolom, tipe data, dan keterisian yang dideklarasikan.
-- -----------------------------------------------------------------------------
SELECT table_name, ordinal_position, column_name, data_type,
       character_maximum_length AS panjang, numeric_precision AS presisi,
       numeric_scale AS skala, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'nusamart'
ORDER  BY table_name, ordinal_position;

-- Kunci primer dan kunci asing yang benar-benar terpasang sebagai constraint.
SELECT tc.table_name, tc.constraint_type, tc.constraint_name,
       kcu.column_name,
       ccu.table_name  AS acuan_tabel,
       ccu.column_name AS acuan_kolom
FROM   information_schema.table_constraints tc
JOIN   information_schema.key_column_usage kcu
       ON kcu.constraint_name = tc.constraint_name
      AND kcu.table_schema    = tc.table_schema
LEFT  JOIN information_schema.constraint_column_usage ccu
       ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema    = tc.table_schema
WHERE  tc.table_schema = 'nusamart'
  AND  tc.constraint_type IN ('PRIMARY KEY', 'FOREIGN KEY')
ORDER  BY tc.table_name, tc.constraint_type DESC;

-- -----------------------------------------------------------------------------
-- 3. KEUNIKAN KUNCI -- menguji dugaan, bukan mempercayai nama kolom.
--    Kunci yang dideklarasikan belum tentu kunci bisnis yang dipakai orang.
-- -----------------------------------------------------------------------------
SELECT COUNT(*)                    AS baris,
       COUNT(DISTINCT nomor_struk) AS struk_unik,
       COUNT(*) - COUNT(DISTINCT nomor_struk) AS selisih
FROM   transaksi;

-- Bila selisih di atas tidak nol: apakah keunikan berlaku per toko?
SELECT COUNT(*) AS kombinasi_ganda
FROM (
  SELECT toko_id, nomor_struk
  FROM   transaksi
  GROUP  BY toko_id, nomor_struk
  HAVING COUNT(*) > 1
) t;

-- Apakah SKU produk unik?
SELECT COUNT(*) AS baris, COUNT(DISTINCT sku) AS sku_unik
FROM   produk;

-- Apakah satu produk dapat muncul dua kali pada satu struk?
SELECT COUNT(*) AS struk_dengan_produk_ganda
FROM (
  SELECT transaksi_id, produk_id
  FROM   transaksi_item
  GROUP  BY transaksi_id, produk_id
  HAVING COUNT(*) > 1
) t;

-- -----------------------------------------------------------------------------
-- 4. KELENGKAPAN -- proporsi NULL pada kolom yang akan menjadi foreign key.
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE pelanggan_id IS NULL) AS tanpa_pelanggan,
       ROUND(100.0 * COUNT(*) FILTER (WHERE pelanggan_id IS NULL)
             / NULLIF(COUNT(*), 0), 2)              AS persen_tanpa_pelanggan,
       COUNT(*) FILTER (WHERE pegawai_id IS NULL)   AS tanpa_kasir,
       COUNT(*) FILTER (WHERE toko_id IS NULL)      AS tanpa_toko
FROM   transaksi;

SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE kategori_id IS NULL) AS tanpa_kategori,
       COUNT(*) FILTER (WHERE berat_gram IS NULL)  AS tanpa_berat,
       COUNT(*) FILTER (WHERE merek IS NULL
                           OR btrim(merek) = '')   AS merek_kosong
FROM   produk;

-- -----------------------------------------------------------------------------
-- 5. RENTANG NILAI DAN KARDINALITAS.
--    Nilai ekstrem hampir selalu menandai anomali, bukan transaksi luar biasa.
-- -----------------------------------------------------------------------------
SELECT MIN(waktu_transaksi) AS paling_awal,
       MAX(waktu_transaksi) AS paling_akhir,
       COUNT(DISTINCT DATE(waktu_transaksi)) AS jumlah_hari
FROM   transaksi;

SELECT status, COUNT(*) AS jumlah,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS persen
FROM   transaksi
GROUP  BY status
ORDER  BY jumlah DESC;

SELECT metode_bayar, COUNT(*) AS jumlah
FROM   transaksi
GROUP  BY metode_bayar
ORDER  BY jumlah DESC;

-- Kolom berkardinalitas rendah adalah kandidat atribut dimensi.
SELECT COUNT(DISTINCT provinsi)   AS provinsi,
       COUNT(DISTINCT kota)       AS kota,
       COUNT(DISTINCT tipe_toko)  AS tipe_toko,
       COUNT(*)                   AS jumlah_toko
FROM   toko;

SELECT MIN(tanggal_lahir) AS lahir_paling_awal,
       MAX(tanggal_lahir) AS lahir_paling_akhir,
       COUNT(*) FILTER (WHERE tanggal_lahir > CURRENT_DATE) AS lahir_di_masa_depan,
       COUNT(*) FILTER (WHERE tanggal_lahir < DATE '1920-01-01') AS lahir_mustahil
FROM   pelanggan;

-- -----------------------------------------------------------------------------
-- 6. INTEGRITAS RELASI DAN KONSISTENSI ARITMETIKA.
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS item_tanpa_produk
FROM      transaksi_item ti
LEFT JOIN produk p ON p.produk_id = ti.produk_id
WHERE     p.produk_id IS NULL;

SELECT COUNT(*) AS item_tanpa_kepala_struk
FROM      transaksi_item ti
LEFT JOIN transaksi t ON t.transaksi_id = ti.transaksi_id
WHERE     t.transaksi_id IS NULL;

SELECT COUNT(*) AS produk_kategori_yatim
FROM      produk p
LEFT JOIN kategori k ON k.kategori_id = p.kategori_id
WHERE     p.kategori_id IS NOT NULL AND k.kategori_id IS NULL;

-- Apakah subtotal baris konsisten dengan kuantitas, harga, dan diskon?
SELECT COUNT(*) AS subtotal_tidak_cocok
FROM   transaksi_item
WHERE  ROUND(kuantitas * harga_satuan - diskon, 2) <> ROUND(subtotal, 2);

-- Apakah total pada kepala struk sama dengan jumlah barisnya?
SELECT COUNT(*) AS total_struk_tidak_cocok
FROM (
  SELECT t.transaksi_id, t.total_bayar, SUM(ti.subtotal) AS jumlah_item
  FROM   transaksi t
  JOIN   transaksi_item ti ON ti.transaksi_id = t.transaksi_id
  GROUP  BY t.transaksi_id, t.total_bayar
  HAVING ROUND(t.total_bayar, 2) <> ROUND(SUM(ti.subtotal), 2)
) t;

-- Nilai yang tidak masuk akal secara bisnis.
SELECT COUNT(*) FILTER (WHERE kuantitas <= 0)    AS kuantitas_tidak_positif,
       COUNT(*) FILTER (WHERE diskon < 0)        AS diskon_negatif,
       COUNT(*) FILTER (WHERE harga_satuan <= 0) AS harga_tidak_positif,
       COUNT(*) FILTER (WHERE diskon > kuantitas * harga_satuan)
                                                 AS diskon_melebihi_nilai
FROM   transaksi_item;

-- -----------------------------------------------------------------------------
-- 7. LATIHAN: hierarki kategori yang mengacu pada dirinya sendiri.
-- -----------------------------------------------------------------------------
WITH RECURSIVE jalur AS (
  SELECT kategori_id, nama_kategori, induk_kategori_id,
         1 AS kedalaman,
         ARRAY[kategori_id] AS lintasan
  FROM   kategori
  WHERE  induk_kategori_id IS NULL

  UNION ALL

  SELECT k.kategori_id, k.nama_kategori, k.induk_kategori_id,
         j.kedalaman + 1,
         j.lintasan || k.kategori_id
  FROM   kategori k
  JOIN   jalur j ON j.kategori_id = k.induk_kategori_id
  WHERE  NOT k.kategori_id = ANY (j.lintasan)   -- menahan lingkaran acuan
)
SELECT MAX(kedalaman) AS kedalaman_maksimum,
       COUNT(*)       AS kategori_terjangkau
FROM   jalur;

-- Kategori yang tidak terjangkau dari akar mana pun: yatim atau bagian
-- dari lingkaran acuan.
WITH RECURSIVE jalur AS (
  SELECT kategori_id, ARRAY[kategori_id] AS lintasan
  FROM   kategori WHERE induk_kategori_id IS NULL
  UNION ALL
  SELECT k.kategori_id, j.lintasan || k.kategori_id
  FROM   kategori k
  JOIN   jalur j ON j.kategori_id = k.induk_kategori_id
  WHERE  NOT k.kategori_id = ANY (j.lintasan)
)
SELECT k.kategori_id, k.nama_kategori, k.induk_kategori_id
FROM   kategori k
WHERE  k.kategori_id NOT IN (SELECT kategori_id FROM jalur)
ORDER  BY k.kategori_id;
