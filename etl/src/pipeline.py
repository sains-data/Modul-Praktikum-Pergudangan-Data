"""Modul 07 -- orkestrasi pipeline ETL multi-sumber.

Kerangka setengah jadi. Mahasiswa melengkapi bagian bertanda TODO.

    python etl/src/pipeline.py --batch 2024-06-15
    python etl/src/pipeline.py --batch 2024-06-15   # jalan kedua: idempoten

Batas tanggung jawab tiap tahap dijaga dengan tegas:

    extract    menyalin sumber APA ADANYA ke staging
    transform  menstandardisasi satuan, kode, format, dan identitas
    load       memuat dimensi SCD-2 dan fakta

Godaan terbesar adalah membersihkan data pada tahap ekstraksi. Jangan. Begitu
data rusak tidak pernah sampai ke staging, kemampuan menghitung berapa banyak
yang rusak ikut hilang, dan rekonsiliasi Modul 10 tidak lagi mungkin.
"""

from __future__ import annotations

import argparse
import csv
import logging
import os
from contextlib import contextmanager
from datetime import date, datetime
from pathlib import Path

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

from transform import identifikasi_pelanggan, standardisasi

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s %(message)s",
)
log = logging.getLogger("pipeline")

SUMBER = ["oltp", "barat", "timur"]


# =============================================================================
# Koneksi
# =============================================================================

def koneksi_gudang():
    """Kredensial dibaca dari .env, tidak pernah ditulis di dalam kode."""
    return psycopg2.connect(
        host=os.environ["DW_HOST"],
        port=os.environ["DW_PORT"],
        dbname=os.environ["DW_NAME"],
        user=os.environ["DW_USER"],
        password=os.environ["DW_PASSWORD"],
    )


@contextmanager
def transaksi(conn):
    """Satu blok kerja: commit bila selesai, rollback bila gagal."""
    try:
        yield conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        conn.commit()
    except Exception:
        conn.rollback()
        raise


# =============================================================================
# Audit
# =============================================================================

def mulai_batch(conn, tanggal_batch: date) -> int:
    """Buat batch_id baru dan catat waktu mulainya."""
    with transaksi(conn) as cur:
        cur.execute(
            "SELECT COALESCE(MAX(batch_id), 0) + 1 AS id FROM gudang.audit_muat"
        )
        batch_id = cur.fetchone()["id"]
    log.info("batch %s dimulai untuk tanggal %s", batch_id, tanggal_batch)
    return batch_id


def catat_audit(conn, batch_id, tahap, sumber, dibaca, dimuat, unknown=0):
    with transaksi(conn) as cur:
        cur.execute(
            """
            INSERT INTO gudang.audit_muat (batch_id, tahap, sumber,
                   baris_dibaca, baris_dimuat, baris_unknown, mulai, selesai)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (batch_id, tahap, sumber) DO UPDATE
              SET baris_dibaca  = EXCLUDED.baris_dibaca,
                  baris_dimuat  = EXCLUDED.baris_dimuat,
                  baris_unknown = EXCLUDED.baris_unknown,
                  selesai       = EXCLUDED.selesai
            """,
            (batch_id, tahap, sumber, dibaca, dimuat, unknown,
             datetime.now(), datetime.now()),
        )
    selisih = dibaca - dimuat
    if selisih:
        # Selisih bukan kegagalan, tetapi WAJIB dapat dijelaskan.
        log.warning("%s/%s: %s baris tidak dimuat -- jelaskan pada log-muat.md",
                    tahap, sumber, selisih)


# =============================================================================
# Extract
# =============================================================================

# Nama tabel dan kolom berbeda di setiap sumber. Perbedaan itu diselesaikan
# di sini, sekali, dengan query per sumber -- bukan dengan percabangan yang
# tersebar di seluruh pipeline.
SQL_EKSTRAK = {
    "oltp": """
        SELECT p.produk_id::TEXT AS id_sumber, p.sku, p.nama_produk AS nama,
               p.berat_gram AS berat, k.kode_kategori
        FROM   src_oltp.produk p
        LEFT JOIN src_oltp.kategori k ON k.kategori_id = p.kategori_id
    """,
    "barat": """
        SELECT i.item_code AS id_sumber, i.item_code AS sku,
               i.item_name AS nama, i.weight_kg AS berat,
               c.category_code AS kode_kategori
        FROM   src_barat.item i
        LEFT JOIN src_barat.item_category c ON c.category_id = i.category_id
    """,
    # TODO: lengkapi untuk sumber timur, sesuai temuan Bagian B.1
    "timur": """
        SELECT ...
    """,
}


def ekstrak_semua_sumber(conn, batch_id) -> list[dict]:
    """Salin ketiga sumber ke staging apa adanya, lalu kembalikan isinya."""
    semua = []
    for sumber in SUMBER:
        with transaksi(conn) as cur:
            cur.execute(SQL_EKSTRAK[sumber])
            baris = cur.fetchall()
        for b in baris:
            b = dict(b)
            b["sumber"] = sumber
            semua.append(b)
        catat_audit(conn, batch_id, "extract", sumber, len(baris), len(baris))
        log.info("extract %-6s: %s baris", sumber, len(baris))
    return semua


# =============================================================================
# Load
# =============================================================================

def muat_fakta(conn, batch_id, tanggal_batch):
    """Muat fakta untuk satu batch.

    IDEMPOTENSI: batch yang sama dihapus lebih dahulu sebelum dimuat ulang.
    Tanpa langkah ini, menjalankan pipeline dua kali melipatgandakan measure.

    KETERLAMBATAN: pencarian dimensi memakai rentang tanggal TRANSAKSI, bukan
    baris_kini. Transaksi yang datang terlambat tiga hari tetap menunjuk versi
    dimensi yang berlaku saat ia terjadi.

    UNKNOWN: LEFT JOIN dengan COALESCE(..., -1). Baris tanpa pasangan dimensi
    tetap masuk dan menunjuk baris unknown -- bukan dibuang, bukan NULL.
    """
    with transaksi(conn) as cur:
        cur.execute(
            "DELETE FROM gudang.fakta_penjualan WHERE tanggal_key = %s",
            (int(tanggal_batch.strftime("%Y%m%d")),),
        )
        dihapus = cur.rowcount
        log.info("hapus-lalu-muat: %s baris batch lama dihapus", dihapus)

        # TODO: lengkapi INSERT ... SELECT sesuai naskah modul Bagian D.2
        cur.execute("SELECT 0 AS dimuat")
        dimuat = cur.fetchone()["dimuat"]

    catat_audit(conn, batch_id, "load_fakta", "gabungan", dimuat, dimuat)


# =============================================================================
# Orkestrasi
# =============================================================================

def jalankan(tanggal_batch: date, keluaran: Path) -> None:
    conn = koneksi_gudang()
    try:
        batch_id = mulai_batch(conn, tanggal_batch)

        mentah = ekstrak_semua_sumber(conn, batch_id)
        bersih = standardisasi(mentah)

        peta, ragu = identifikasi_pelanggan(bersih)
        log.info("identifikasi: %s catatan -> %s pelanggan master",
                 len(peta), len(set(peta.values())))

        # Pipeline yang tidak pernah ragu hampir pasti ambangnya terlalu
        # longgar. Jumlah baris berkas ini adalah bagian dari laporan.
        if ragu:
            keluaran.parent.mkdir(parents=True, exist_ok=True)
            with keluaran.open("w", newline="", encoding="utf-8") as f:
                w = csv.DictWriter(f, fieldnames=list(ragu[0].keys()))
                w.writeheader()
                w.writerows(ragu)
            log.warning("%s pasangan di zona ragu -> %s", len(ragu), keluaran)

        # TODO: muat_dimensi(conn, batch_id, bersih, peta)  -- SCD-2
        muat_fakta(conn, batch_id, tanggal_batch)

        log.info("batch %s selesai", batch_id)
    finally:
        conn.close()


def main() -> None:
    p = argparse.ArgumentParser(description="Pipeline ETL NusaMart multi-sumber")
    p.add_argument("--batch", required=True,
                   help="tanggal batch, format YYYY-MM-DD")
    p.add_argument("--tinjau", default="modul-07-etl/tinjau-manual.csv",
                   help="berkas keluaran pasangan yang perlu ditinjau manusia")
    a = p.parse_args()
    jalankan(date.fromisoformat(a.batch), Path(a.tinjau))


if __name__ == "__main__":
    main()
