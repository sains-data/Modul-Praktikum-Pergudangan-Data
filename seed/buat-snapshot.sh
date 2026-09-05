#!/usr/bin/env bash
# =============================================================================
# Pembuat snapshot keadaan akhir setiap modul.
#
#   ./seed/buat-snapshot.sh 03           # snapshot sesudah Modul 3
#   ./seed/buat-snapshot.sh 05 sedang    # varian dataset sedang
#
# Snapshot adalah dump keadaan gudang data SESUDAH modul tertentu selesai
# dikerjakan dengan benar. Mahasiswa yang tertinggal memulihkannya, lalu
# mengikuti modul berikutnya tanpa harus mengejar dari awal.
#
# ALUR KERJA ASISTEN
#
#   1. Kerjakan modul N pada solusi acuan sampai check.sql seluruhnya LULUS.
#   2. Jalankan skrip ini untuk membuat snapshot-modul-NN.sql.
#   3. Bagikan berkas hasilnya ke mahasiswa.
#
# Snapshot TIDAK dapat dibangkitkan tanpa langkah pertama: isinya adalah hasil
# kerja modul itu sendiri. Karena itu berkasnya tidak disertakan di repositori,
# hanya skrip pembuatnya.
# =============================================================================
set -euo pipefail

MODUL="${1:?Pemakaian: $0 <nomor-modul: 01..10> [ukuran]}"
UKURAN="${2:-kecil}"

DW_USER="${DW_USER:-praktikum}"
KELUARAN_DIR="${KELUARAN_DIR:-seed/snapshot}"

if [[ "$UKURAN" == "kecil" ]]; then
  NAMA="snapshot-modul-${MODUL}.sql"
else
  NAMA="snapshot-modul-${MODUL}-${UKURAN}.sql"
fi

mkdir -p "$KELUARAN_DIR"

echo "Membuat $NAMA dari nusamart_dw ..."

# --clean --if-exists : snapshot dapat dipulihkan di atas basis data yang sudah
#                       berisi, tanpa perlu dibuang lebih dahulu
# --no-owner --no-acl : agar dapat dipulihkan oleh pengguna mana pun
docker compose exec -T postgres_dw \
  pg_dump -U "$DW_USER" -d nusamart_dw \
          --clean --if-exists --no-owner --no-acl \
  > "${KELUARAN_DIR}/${NAMA}"

BARIS=$(wc -l < "${KELUARAN_DIR}/${NAMA}")
UKURAN_BERKAS=$(du -h "${KELUARAN_DIR}/${NAMA}" | cut -f1)

echo "Selesai: ${KELUARAN_DIR}/${NAMA}  (${BARIS} baris, ${UKURAN_BERKAS})"
echo
echo "Mahasiswa memulihkannya dengan:"
echo "  docker compose exec -T postgres_dw \\"
echo "    psql -U ${DW_USER} -d nusamart_dw -f /seed/snapshot/${NAMA}"
