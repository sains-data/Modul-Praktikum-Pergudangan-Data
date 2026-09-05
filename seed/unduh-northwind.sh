#!/usr/bin/env bash
# =============================================================================
# Penyiap basis data Northwind -- pembanding pada Modul 6.
#
#   ./seed/unduh-northwind.sh
#
# Northwind adalah basis data contoh yang ternormalisasi -- bentuk yang sama
# dengan sumber NusaMart sebelum dimodelkan secara dimensional. Modul 6
# memakainya untuk membandingkan BENTUK query, bukan waktu eksekusi: berapa
# join yang diperlukan, dan seberapa dalam rantai join sampai mencapai nama
# kategori.
#
# Skrip mengunduh sekali lalu menyimpannya di seed/northwind.sql. Jalankan di
# rumah, bukan di laboratorium -- jaringan kelas tidak perlu menanggung seluruh
# mahasiswa mengunduh serentak.
# =============================================================================
set -euo pipefail

SRC_USER="${SRC_USER:-praktikum}"
BERKAS="seed/northwind.sql"
URL="${NORTHWIND_URL:-https://raw.githubusercontent.com/pthom/northwind_psql/master/northwind.sql}"

if [[ -f "$BERKAS" ]]; then
  echo "Berkas $BERKAS sudah ada, pengunduhan dilewati."
else
  echo "Mengunduh Northwind dari:"
  echo "  $URL"
  echo
  read -r -p "Lanjutkan pengunduhan? [y/N] " jawab
  [[ "$jawab" =~ ^[Yy]$ ]] || { echo "Dibatalkan."; exit 1; }

  curl -fSL "$URL" -o "$BERKAS"
  echo "Tersimpan sebagai $BERKAS"
fi

echo "Memulihkan ke basis data northwind ..."
docker compose exec -T postgres_source \
  psql -U "$SRC_USER" -d northwind -v ON_ERROR_STOP=1 -f "/seed/$(basename "$BERKAS")"

echo
echo "Verifikasi:"
docker compose exec -T postgres_source \
  psql -U "$SRC_USER" -d northwind -c "
    SELECT table_name, (xpath('/row/c/text()',
             query_to_xml(format('SELECT COUNT(*) AS c FROM %I', table_name),
                          false, true, '')))[1]::text::bigint AS baris
    FROM   information_schema.tables
    WHERE  table_schema = 'public' AND table_type = 'BASE TABLE'
    ORDER  BY baris DESC LIMIT 10;"
