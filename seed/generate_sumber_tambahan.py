#!/usr/bin/env python3
"""Pembangkit sumber kedua dan ketiga NusaMart -- dipakai mulai Modul 7.

    python seed/generate_sumber_tambahan.py --ukuran kecil --seed 42

Kedua sumber ini SENGAJA TIDAK SEPAKAT dengan sumber utama. Ketidaksepakatan
itu bukan kelalaian: menemukannya adalah pekerjaan Bagian B Modul 7, dan
menyatukannya adalah pekerjaan Bagian C.

KONFLIK YANG DITANAM
--------------------

nusamart_barat (hasil akuisisi, sistemnya berbahasa Inggris)

  penamaan    tabel  produk        -> item
                     pelanggan     -> customer
                     kategori      -> item_category
                     transaksi     -> sales_header
                     transaksi_item-> sales_line
              kolom  produk_id     -> item_code   (TEKS, bukan integer)
                     nama_produk   -> item_name
                     berat_gram    -> weight_kg
  satuan      berat dalam KILOGRAM, bukan gram -- selisihnya seribu kali
  pengodean   kategori BEV, SNK, HHD (lawan MNM, MKN, RTG)
  identitas   sebagian pelanggan sama dengan sumber utama, ejaan berbeda

nusamart_timur (wilayah timur, sistemnya berbahasa Indonesia)

  pengodean   kategori DRK, FOD
  representasi nama pelanggan HURUF BESAR SEMUA, dengan gelar dan tanda baca
  identitas   sebagian pelanggan sama dengan sumber utama dan barat
  timeliness  transaksi dicatat tiga hari SESUDAH kejadian; sebagian bahkan
              sepuluh hari -- ekor yang menjadi bahan uji timeliness Modul 10

Daftar lengkap beserta jumlah barisnya ada pada seed/README.md, untuk ASISTEN.
"""

from __future__ import annotations

import argparse
import os
import random
import sys
from datetime import date, datetime, timedelta

try:
    import psycopg2
    from faker import Faker
except ImportError:
    sys.exit("Jalankan: pip install -r requirements.txt")

from generate_nusamart import (
    METODE_BAYAR, PROVINSI, TANGGAL_MULAI, UKURAN,
    PenulisCopy, log, salin,
)

# Sumber tambahan berukuran jauh lebih kecil daripada sumber utama: keduanya
# wilayah tambahan, bukan pengganti. Yang penting bukan volumenya, melainkan
# ketidaksepakatannya.
NISBAH = 0.12

PETA_KATEGORI_BARAT = {
    "BEV": "Beverages", "SNK": "Snacks", "HHD": "Household",
    "PCR": "Personal Care", "ELC": "Electronics",
}
PETA_KATEGORI_TIMUR = {
    "DRK": "Minuman", "FOD": "Makanan", "HSE": "Rumah Tangga",
}

GELAR = ["Bapak ", "Ibu ", "Bpk. ", "H. ", "Hj. ", "Drs. ", ""]


# =============================================================================
# Nama yang sama, tertulis berbeda
# =============================================================================

def variasi_nama(nama: str, gaya: str, rnd) -> str:
    """Menulis ulang satu nama sehingga TIDAK sama persis, tetapi orang yang sama.

    Inilah bahan object identification Modul 7. Variasinya sengaja dibuat
    beragam: sebagian mudah dikenali (huruf besar), sebagian sulit (spasi
    disisipkan di tengah nama).
    """
    if gaya == "barat":
        pilihan = rnd.random()
        if pilihan < 0.35:
            return nama.title()
        if pilihan < 0.60:
            # Nama tengah disingkat: "Siti Nurhaliza Dewi" -> "Siti N. Dewi"
            bagian = nama.split()
            if len(bagian) >= 3:
                return f"{bagian[0]} {bagian[1][0]}. {bagian[-1]}"
            return nama
        if pilihan < 0.80:
            return nama.replace("  ", " ").strip() + "."
        return nama
    # gaya timur: huruf besar semua, kadang bergelar, kadang berspasi ganda
    hasil = nama.upper()
    if rnd.random() < 0.4:
        hasil = rnd.choice(GELAR).upper() + hasil
    if rnd.random() < 0.25:
        # Spasi disisipkan: "NURHALIZA" -> "NUR HALIZA"
        bagian = hasil.split()
        if bagian and len(bagian[-1]) > 6:
            kata = bagian[-1]
            bagian[-1] = kata[:3] + " " + kata[3:]
            hasil = " ".join(bagian)
    return hasil


# =============================================================================
# Sumber kedua: nusamart_barat
# =============================================================================

DDL_BARAT = """
DROP TABLE IF EXISTS sales_line, sales_header, item, item_category, customer;

CREATE TABLE item_category (
  category_id    INTEGER PRIMARY KEY,
  category_code  VARCHAR(10) NOT NULL,
  category_name  VARCHAR(60) NOT NULL
);

CREATE TABLE item (
  item_code    VARCHAR(20)  PRIMARY KEY,   -- TEKS, bukan integer
  item_name    VARCHAR(150) NOT NULL,
  category_id  INTEGER,
  brand        VARCHAR(60),
  unit         VARCHAR(15),
  weight_kg    NUMERIC(10,4),              -- KILOGRAM, bukan gram
  unit_price   NUMERIC(12,2),
  is_active    BOOLEAN
);

CREATE TABLE customer (
  cust_id    INTEGER PRIMARY KEY,
  cust_name  VARCHAR(120) NOT NULL,
  city       VARCHAR(60),
  join_date  DATE
);

CREATE TABLE sales_header (
  sales_id     BIGINT PRIMARY KEY,
  receipt_no   VARCHAR(25) NOT NULL,
  store_id     INTEGER     NOT NULL,
  cust_id      INTEGER,
  sales_ts     TIMESTAMP   NOT NULL,
  payment      VARCHAR(30),
  total_amount NUMERIC(14,2),
  sales_status VARCHAR(20) NOT NULL
);

CREATE TABLE sales_line (
  line_id     BIGINT PRIMARY KEY,
  sales_id    BIGINT NOT NULL REFERENCES sales_header(sales_id),
  item_code   VARCHAR(20) NOT NULL,
  qty         NUMERIC(10,3),
  unit_price  NUMERIC(12,2),
  disc_amount NUMERIC(12,2),
  line_total  NUMERIC(14,2)
);
"""


def bangkitkan_barat(konf, seed, nama_bersama):
    rnd = random.Random(seed + 1)
    fake = Faker("id_ID")
    Faker.seed(seed + 1)

    n_item = 4_000
    n_cust = 3_000
    n_line = max(2_000, int(konf["item_fakta"] * NISBAH))

    conn = _koneksi("nusamart_barat")
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute(DDL_BARAT)

            salin(cur, "item_category",
                  ["category_id", "category_code", "category_name"],
                  ((i + 1, k, v) for i, (k, v) in enumerate(PETA_KATEGORI_BARAT.items())),
                  "item_category")

            def item():
                for i in range(1, n_item + 1):
                    yield (
                        f"ITM-{i:06d}",
                        f"{fake.word().capitalize()} {fake.word().capitalize()}",
                        rnd.randint(1, len(PETA_KATEGORI_BARAT)),
                        fake.company().split()[0],
                        rnd.choice(["pcs", "box", "btl"]),
                        # KILOGRAM: nilainya seribu kali lebih kecil daripada gram
                        round(rnd.uniform(0.005, 5.0), 4),
                        round(rnd.uniform(1_500, 320_000), 2),
                        rnd.random() > 0.05,
                    )

            salin(cur, "item",
                  ["item_code", "item_name", "category_id", "brand", "unit",
                   "weight_kg", "unit_price", "is_active"],
                  item(), "item")

            def customer():
                for i in range(1, n_cust + 1):
                    # Sebagian pelanggan adalah orang yang SAMA dengan sumber
                    # utama, hanya ditulis berbeda.
                    if i <= len(nama_bersama):
                        nama = variasi_nama(nama_bersama[i - 1][0], "barat", rnd)
                        kota = nama_bersama[i - 1][1]
                    else:
                        nama = fake.name()
                        kota = rnd.choice(rnd.choice(PROVINSI)[1])
                    yield (i, nama, kota,
                           TANGGAL_MULAI - timedelta(days=rnd.randint(0, 2000)))

            salin(cur, "customer", ["cust_id", "cust_name", "city", "join_date"],
                  customer(), "customer")

            baris_line: list[tuple] = []

            def header():
                sales_id = 0
                line_id = 0
                dibuat = 0
                while dibuat < n_line:
                    sales_id += 1
                    waktu = datetime.combine(
                        TANGGAL_MULAI + timedelta(days=rnd.randint(0, konf["hari"] - 1)),
                        datetime.min.time()) + timedelta(hours=rnd.randint(8, 20))
                    total = 0.0
                    for _ in range(rnd.randint(1, 5)):
                        line_id += 1
                        dibuat += 1
                        qty = float(rnd.randint(1, 6))
                        harga = round(rnd.uniform(1_500, 320_000), 2)
                        disc = round(harga * qty * rnd.choice([0, 0, 0.05]), 2)
                        tot = round(qty * harga - disc, 2)
                        total += tot
                        baris_line.append(
                            (line_id, sales_id, f"ITM-{rnd.randint(1, n_item):06d}",
                             qty, harga, disc, tot))
                    yield (sales_id, f"RC{sales_id:08d}",
                           rnd.randint(1, 240),
                           None if rnd.random() < 0.35 else rnd.randint(1, n_cust),
                           waktu, rnd.choice(METODE_BAYAR), round(total, 2),
                           "CANCELLED" if rnd.random() < 0.02 else "DONE")

            salin(cur, "sales_header",
                  ["sales_id", "receipt_no", "store_id", "cust_id", "sales_ts",
                   "payment", "total_amount", "sales_status"],
                  header(), "sales_header")

            salin(cur, "sales_line",
                  ["line_id", "sales_id", "item_code", "qty", "unit_price",
                   "disc_amount", "line_total"],
                  iter(baris_line), "sales_line")

            cur.execute("ANALYZE")
        conn.commit()
    finally:
        conn.close()


# =============================================================================
# Sumber ketiga: nusamart_timur
# =============================================================================

DDL_TIMUR = """
DROP TABLE IF EXISTS transaksi_baris, transaksi, produk, kategori, pelanggan;

CREATE TABLE kategori (
  kategori_id    INTEGER PRIMARY KEY,
  kode           VARCHAR(10) NOT NULL,
  nama           VARCHAR(60) NOT NULL
);

CREATE TABLE produk (
  produk_id    INTEGER PRIMARY KEY,
  nama         VARCHAR(150) NOT NULL,
  kategori_id  INTEGER,
  berat_gram   NUMERIC(10,2),
  harga        NUMERIC(12,2)
);

CREATE TABLE pelanggan (
  pelanggan_id  INTEGER PRIMARY KEY,
  nama          VARCHAR(140) NOT NULL,   -- HURUF BESAR, kadang bergelar
  kota          VARCHAR(60),
  terdaftar     DATE
);

CREATE TABLE transaksi (
  transaksi_id  BIGINT PRIMARY KEY,
  no_struk      VARCHAR(25) NOT NULL,
  toko_id       INTEGER     NOT NULL,
  pelanggan_id  INTEGER,
  waktu         TIMESTAMP   NOT NULL,   -- saat transaksi TERJADI
  dicatat_pada  TIMESTAMP   NOT NULL,   -- saat transaksi SAMPAI ke sistem
  bayar         VARCHAR(30),
  total         NUMERIC(14,2),
  status        VARCHAR(20) NOT NULL
);

CREATE TABLE transaksi_baris (
  baris_id      BIGINT PRIMARY KEY,
  transaksi_id  BIGINT NOT NULL REFERENCES transaksi(transaksi_id),
  produk_id     INTEGER NOT NULL,
  jumlah        NUMERIC(10,3),
  harga         NUMERIC(12,2),
  potongan      NUMERIC(12,2),
  total_baris   NUMERIC(14,2)
);
"""


def bangkitkan_timur(konf, seed, nama_bersama):
    rnd = random.Random(seed + 2)
    fake = Faker("id_ID")
    Faker.seed(seed + 2)

    n_produk = 3_000
    n_pel = 2_500
    n_baris = max(2_000, int(konf["item_fakta"] * NISBAH * 0.7))

    conn = _koneksi("nusamart_timur")
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute(DDL_TIMUR)

            salin(cur, "kategori", ["kategori_id", "kode", "nama"],
                  ((i + 1, k, v) for i, (k, v) in enumerate(PETA_KATEGORI_TIMUR.items())),
                  "kategori")

            salin(cur, "produk",
                  ["produk_id", "nama", "kategori_id", "berat_gram", "harga"],
                  ((i,
                    f"{fake.word().capitalize()} {fake.word().capitalize()}",
                    rnd.randint(1, len(PETA_KATEGORI_TIMUR)),
                    round(rnd.uniform(5, 5_000), 2),
                    round(rnd.uniform(1_500, 320_000), 2))
                   for i in range(1, n_produk + 1)),
                  "produk")

            def pelanggan():
                for i in range(1, n_pel + 1):
                    if i <= len(nama_bersama):
                        nama = variasi_nama(nama_bersama[i - 1][0], "timur", rnd)
                        kota = nama_bersama[i - 1][1]
                    else:
                        nama = fake.name().upper()
                        kota = rnd.choice(rnd.choice(PROVINSI)[1])
                    yield (i, nama, kota,
                           TANGGAL_MULAI - timedelta(days=rnd.randint(0, 2000)))

            salin(cur, "pelanggan",
                  ["pelanggan_id", "nama", "kota", "terdaftar"],
                  pelanggan(), "pelanggan")

            baris: list[tuple] = []

            def transaksi():
                trx = 0
                bid = 0
                dibuat = 0
                while dibuat < n_baris:
                    trx += 1
                    terjadi = datetime.combine(
                        TANGGAL_MULAI + timedelta(days=rnd.randint(0, konf["hari"] - 1)),
                        datetime.min.time()) + timedelta(hours=rnd.randint(8, 20))

                    # TIMELINESS: dicatat tiga hari sesudah kejadian. Sebagian
                    # kecil jauh lebih terlambat -- ekor inilah yang dicari
                    # oleh uji timeliness Modul 10.
                    lambat = 10 if rnd.random() < 0.01 else 3
                    dicatat = terjadi + timedelta(days=lambat,
                                                  hours=rnd.randint(0, 12))

                    total = 0.0
                    for _ in range(rnd.randint(1, 4)):
                        bid += 1
                        dibuat += 1
                        jml = float(rnd.randint(1, 5))
                        harga = round(rnd.uniform(1_500, 320_000), 2)
                        pot = round(harga * jml * rnd.choice([0, 0, 0.08]), 2)
                        tot = round(jml * harga - pot, 2)
                        total += tot
                        baris.append((bid, trx, rnd.randint(1, n_produk),
                                      jml, harga, pot, tot))
                    yield (trx, f"TR{trx:08d}", rnd.randint(1, 240),
                           None if rnd.random() < 0.30 else rnd.randint(1, n_pel),
                           terjadi, dicatat, rnd.choice(METODE_BAYAR),
                           round(total, 2),
                           "BATAL" if rnd.random() < 0.02 else "SELESAI")

            salin(cur, "transaksi",
                  ["transaksi_id", "no_struk", "toko_id", "pelanggan_id",
                   "waktu", "dicatat_pada", "bayar", "total", "status"],
                  transaksi(), "transaksi")

            salin(cur, "transaksi_baris",
                  ["baris_id", "transaksi_id", "produk_id", "jumlah", "harga",
                   "potongan", "total_baris"],
                  iter(baris), "transaksi_baris")

            cur.execute("ANALYZE")
        conn.commit()
    finally:
        conn.close()


# =============================================================================

def _koneksi(dbname: str):
    return psycopg2.connect(
        host=os.environ.get("SRC_HOST", "localhost"),
        port=os.environ.get("SRC_PORT", "5433"),
        dbname=dbname,
        user=os.environ.get("SRC_USER", "praktikum"),
        password=os.environ.get("SRC_PASSWORD", ""),
    )


def ambil_nama_bersama(jumlah: int = 1_200):
    """Ambil sebagian pelanggan sumber utama untuk ditulis ulang secara berbeda.

    Inilah yang membuat object identification Modul 7 memiliki jawaban benar
    yang dapat diperiksa: pasangan ini memang orang yang sama.
    """
    conn = _koneksi("nusamart_oltp")
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT nama, kota FROM nusamart.pelanggan
                WHERE nama IS NOT NULL ORDER BY pelanggan_id LIMIT %s
            """, (jumlah,))
            return cur.fetchall()
    finally:
        conn.close()


def bangkitkan_sumber_tambahan(ukuran: str, seed: int) -> None:
    konf = UKURAN[ukuran]
    log("Mengambil nama pelanggan bersama dari sumber utama ...")
    nama_bersama = ambil_nama_bersama()
    log(f"  {len(nama_bersama)} pelanggan akan muncul di lebih dari satu sumber")

    log("Membangkitkan nusamart_barat (berat KILOGRAM, kolom Inggris) ...")
    bangkitkan_barat(konf, seed, nama_bersama)

    log("Membangkitkan nusamart_timur (nama HURUF BESAR, catatan terlambat) ...")
    bangkitkan_timur(konf, seed, nama_bersama)

    log("Sumber tambahan selesai.")


def main() -> None:
    p = argparse.ArgumentParser(description="Pembangkit sumber kedua dan ketiga")
    p.add_argument("--ukuran", choices=list(UKURAN), default="kecil")
    p.add_argument("--seed", type=int, default=42)
    a = p.parse_args()
    bangkitkan_sumber_tambahan(a.ukuran, a.seed)


if __name__ == "__main__":
    main()
