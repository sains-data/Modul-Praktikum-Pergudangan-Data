#!/usr/bin/env python3
"""Pembangkit data NusaMart untuk praktikum Pergudangan Data (SD25-31007).

    python seed/generate_nusamart.py --ukuran kecil  --seed 42
    python seed/generate_nusamart.py --ukuran sedang --seed 42
    python seed/generate_nusamart.py --ukuran sedang --seed 42 --sumber-tambahan

Membangkitkan sistem operasional NusaMart beserta ANOMALI YANG DITANAM SENGAJA.
Daftar lengkap anomali ada pada seed/README.md -- berkas itu untuk ASISTEN,
bukan untuk mahasiswa. Menemukan anomali adalah pekerjaan Modul 1 dan Modul 10.

Nilai --seed HARUS SAMA untuk seluruh kelas. Tanpa itu, angka hasil profiling
setiap mahasiswa berbeda dan tidak dapat dibandingkan saat checkpoint.

Pemuatan memakai COPY FROM STDIN, bukan INSERT: lima juta baris lewat INSERT
memakan waktu berjam-jam, lewat COPY beberapa menit.
"""

from __future__ import annotations

import argparse
import io
import os
import random
import sys
from datetime import date, datetime, timedelta

try:
    import psycopg2
except ImportError:
    sys.exit("psycopg2 belum terpasang. Jalankan: pip install -r requirements.txt")

try:
    from faker import Faker
except ImportError:
    sys.exit("Faker belum terpasang. Jalankan: pip install -r requirements.txt")


# =============================================================================
# Parameter ukuran
#
# Dimensi (240 toko, 180.000 produk) TETAP di seluruh ukuran; yang berjenjang
# hanya volume fakta. Ini disengaja: 180 ribu produk dengan 100 ribu baris
# penjualan berarti sebagian besar produk tidak pernah terjual -- ekor panjang
# yang realistis pada ritel, sekaligus yang membuat pertanyaan "produk mana
# yang dipromosikan tetapi tidak terjual" (Modul 4) menjadi menarik.
#
# CAKUPAN PERSEDIAAN DIBATASI. Bila seluruh kombinasi dicatat, 180.000 produk
# x 240 toko x 365 hari menghasilkan 15,8 MILIAR baris -- mustahil untuk
# praktikum. Generator hanya mencatat sebagian toko, sebagian produk, dan
# sebagian hari. Mahasiswa menghitung angka teoretis itu sendiri pada
# Latihan 4.2, dan perbedaannya justru menjadi bahan diskusi.
# =============================================================================
UKURAN = {
    "kecil": {
        "item_fakta": 100_000,
        "hari": 730,               # 2024-01-01 .. 2025-12-31
        "persediaan_toko": 20,
        "persediaan_produk": 100,
        "persediaan_hari": 60,
    },
    "sedang": {
        "item_fakta": 5_000_000,
        "hari": 730,
        "persediaan_toko": 60,
        "persediaan_produk": 300,
        "persediaan_hari": 180,
    },
    "besar": {
        "item_fakta": 50_000_000,
        "hari": 1095,
        "persediaan_toko": 120,
        "persediaan_produk": 500,
        "persediaan_hari": 365,
    },
}

JUMLAH_TOKO = 240
JUMLAH_PRODUK = 180_000
JUMLAH_PELANGGAN = 60_000
JUMLAH_PEGAWAI = 1_200
JUMLAH_PROMOSI = 24
TANGGAL_MULAI = date(2024, 1, 1)

PROVINSI = [
    ("Lampung", ["Bandar Lampung", "Metro", "Pringsewu", "Kotabumi"]),
    ("Sumatera Selatan", ["Palembang", "Prabumulih", "Lubuklinggau"]),
    ("Banten", ["Serang", "Cilegon", "Tangerang"]),
    ("Jawa Barat", ["Bandung", "Bekasi", "Bogor", "Cirebon"]),
    ("DKI Jakarta", ["Jakarta Pusat", "Jakarta Timur", "Jakarta Barat"]),
    ("Jawa Tengah", ["Semarang", "Solo", "Magelang"]),
    ("Jawa Timur", ["Surabaya", "Malang", "Kediri"]),
]

TIPE_TOKO = ["Minimarket", "Supermarket", "Hypermarket", "Grosir"]
METODE_BAYAR = ["Tunai", "Kartu Debit", "Kartu Kredit", "QRIS", "E-Wallet"]
SATUAN = ["pcs", "pak", "botol", "kaleng", "sachet", "kg", "liter"]

# Hierarki kategori. Kedalaman SENGAJA tidak seragam: sebagian kategori punya
# induk, sebagian tidak, dan satu menunjuk induk yang tidak ada.
KATEGORI_INDUK = [
    (1, "MKN", "Makanan"),
    (2, "MNM", "Minuman"),
    (3, "RTG", "Rumah Tangga"),
    (4, "PRW", "Perawatan Diri"),
    (5, "ELK", "Elektronik"),
]
KATEGORI_ANAK = [
    (11, "MKN-RIN", "Makanan Ringan", 1),
    (12, "MKN-BEK", "Makanan Beku", 1),
    (13, "MKN-POK", "Bahan Pokok", 1),
    (21, "MNM-SJI", "Minuman Siap Saji", 2),
    (22, "MNM-SRB", "Minuman Serbuk", 2),
    (31, "RTG-BRS", "Pembersih", 3),
    (32, "RTG-DPR", "Peralatan Dapur", 3),
    (41, "PRW-MND", "Perlengkapan Mandi", 4),
    (42, "PRW-KOS", "Kosmetik", 4),
    (51, "ELK-KCL", "Elektronik Kecil", 5),
]


def log(pesan: str) -> None:
    print(f"[{datetime.now():%H:%M:%S}] {pesan}", flush=True)


class PenulisCopy(io.RawIOBase):
    """Menyalurkan iterator baris menjadi aliran TSV untuk COPY FROM STDIN.

    Data tidak pernah ditampung seluruhnya di memori: PostgreSQL menarik baris
    sesuai kebutuhannya. Inilah yang membuat lima juta baris dapat dimuat tanpa
    membebani RAM.
    """

    def __init__(self, baris_iter):
        self.iter = baris_iter
        self.sisa = b""

    def readable(self) -> bool:
        return True

    def readinto(self, b) -> int:
        if not self.sisa:
            try:
                baris = next(self.iter)
            except StopIteration:
                return 0
            self.sisa = ("\t".join(_tsv(n) for n in baris) + "\n").encode("utf-8")
        n = min(len(b), len(self.sisa))
        b[:n] = self.sisa[:n]
        self.sisa = self.sisa[n:]
        return n


def _tsv(nilai) -> str:
    """Format satu nilai untuk COPY teks. None menjadi \\N."""
    if nilai is None:
        return r"\N"
    if isinstance(nilai, bool):
        return "t" if nilai else "f"
    s = str(nilai)
    return s.replace("\\", "\\\\").replace("\t", " ").replace("\n", " ")


def salin(cur, tabel: str, kolom: list[str], baris_iter, nama: str) -> int:
    jumlah = _Penghitung()
    cur.copy_expert(
        f"COPY {tabel} ({', '.join(kolom)}) FROM STDIN",
        PenulisCopy(jumlah.bungkus(baris_iter)),
    )
    log(f"  {nama:<24} {jumlah.n:>12,} baris")
    return jumlah.n


class _Penghitung:
    def __init__(self):
        self.n = 0

    def bungkus(self, it):
        for baris in it:
            self.n += 1
            yield baris


# =============================================================================
# Pembangkit master
# =============================================================================

def buat_toko(fake, rnd):
    for i in range(1, JUMLAH_TOKO + 1):
        prov, kota_list = rnd.choice(PROVINSI)
        yield (
            i,
            f"TK{i:04d}",
            f"NusaMart {rnd.choice(kota_list)} {i}",
            fake.street_address(),
            rnd.choice(kota_list),
            prov,
            rnd.choice(TIPE_TOKO),
            round(rnd.uniform(80, 3500), 2),
            TANGGAL_MULAI - timedelta(days=rnd.randint(200, 4000)),
        )


def buat_kategori(rnd):
    for kid, kode, nama in KATEGORI_INDUK:
        yield (kid, kode, nama, None)
    for kid, kode, nama, induk in KATEGORI_ANAK:
        yield (kid, kode, nama, induk)
    # ANOMALI: kategori yang menunjuk induk tidak ada -- bahan Latihan 1.1.
    yield (99, "XXX-YTM", "Kategori Yatim", 8888)


def buat_produk(fake, rnd):
    kategori_valid = [k[0] for k in KATEGORI_ANAK]
    for i in range(1, JUMLAH_PRODUK + 1):
        harga_pokok = round(rnd.uniform(1_000, 250_000), 2)
        harga_jual = round(harga_pokok * rnd.uniform(1.08, 1.65), 2)

        # ANOMALI: sebagian kecil produk menunjuk kategori yatim atau NULL.
        u = rnd.random()
        if u < 0.002:
            kategori = 99
        elif u < 0.004:
            kategori = None
        else:
            kategori = rnd.choice(kategori_valid)

        # ANOMALI: sebagian berat tidak tercatat.
        berat = None if rnd.random() < 0.03 else round(rnd.uniform(5, 5_000), 2)

        yield (
            i,
            f"SKU{i:07d}",
            f"{fake.word().capitalize()} {fake.word().capitalize()} {rnd.choice(['250g','500ml','1kg','isi 12','refill'])}",
            kategori,
            fake.company().split()[0],
            rnd.choice(SATUAN),
            berat,
            harga_jual,
            harga_pokok,
            rnd.random() > 0.06,
        )


def buat_pelanggan(fake, rnd):
    hari_ini = date.today()
    for i in range(1, JUMLAH_PELANGGAN + 1):
        # ANOMALI: tanggal lahir mustahil pada sebagian kecil baris.
        u = rnd.random()
        if u < 0.001:
            lahir = hari_ini + timedelta(days=rnd.randint(30, 900))   # masa depan
        elif u < 0.002:
            lahir = date(1890, 1, 1) + timedelta(days=rnd.randint(0, 3000))
        elif u < 0.05:
            lahir = None
        else:
            lahir = fake.date_of_birth(minimum_age=17, maximum_age=75)

        prov, kota_list = rnd.choice(PROVINSI)
        yield (
            i,
            f"MB{i:07d}",
            fake.name(),
            rnd.choice(["L", "P"]),
            lahir,
            rnd.choice(kota_list),
            TANGGAL_MULAI - timedelta(days=rnd.randint(0, 2500)),
            rnd.choice(["Reguler", "Silver", "Gold", "Platinum"]),
        )


def buat_pegawai(fake, rnd):
    for i in range(1, JUMLAH_PEGAWAI + 1):
        yield (
            i,
            fake.name(),
            rnd.randint(1, JUMLAH_TOKO),
            rnd.choice(["Kasir", "Supervisor", "Kepala Toko"]),
            TANGGAL_MULAI - timedelta(days=rnd.randint(30, 2000)),
        )


def buat_promosi(rnd, hari):
    for i in range(1, JUMLAH_PROMOSI + 1):
        mulai = TANGGAL_MULAI + timedelta(days=rnd.randint(0, max(1, hari - 40)))
        yield (
            i,
            f"PRM{i:04d}",
            f"Promo {rnd.choice(['Awal Bulan','Gajian','Akhir Pekan','Ramadan','Tahun Baru','Cuci Gudang'])} {i}",
            rnd.choice(["Diskon Persen", "Potongan Langsung", "Beli 1 Gratis 1"]),
            mulai,
            mulai + timedelta(days=rnd.randint(7, 30)),
        )


def buat_promosi_produk(rnd):
    """Produk yang tercakup setiap promosi.

    Jumlahnya dibatasi agar factless fact Modul 4 tidak membengkak: baris
    factless = produk per promosi x lama promosi.
    """
    for promosi_id in range(1, JUMLAH_PROMOSI + 1):
        dipilih = rnd.sample(range(1, JUMLAH_PRODUK + 1), rnd.randint(80, 250))
        for produk_id in dipilih:
            yield (promosi_id, produk_id)


# =============================================================================
# Pembangkit transaksi
# =============================================================================

def buat_transaksi_dan_item(rnd, konf, kumpul_item):
    """Membangkitkan kepala struk. Baris struknya dikumpulkan ke kumpul_item.

    Kedua tabel dibangkitkan dalam satu jalan karena total_bayar pada kepala
    struk harus konsisten dengan jumlah baris struknya -- kecuali pada baris
    yang sengaja dibuat tidak konsisten.
    """
    hari = konf["hari"]
    target_item = konf["item_fakta"]
    transaksi_id = 0
    item_id = 0
    dibuat_item = 0
    # nomor_struk hanya unik PER TOKO -- pencacah per toko, bukan global.
    pencacah_struk = {t: 0 for t in range(1, JUMLAH_TOKO + 1)}

    while dibuat_item < target_item:
        transaksi_id += 1
        toko_id = rnd.randint(1, JUMLAH_TOKO)
        pencacah_struk[toko_id] += 1

        hari_ke = rnd.randint(0, hari - 1)
        waktu = datetime.combine(
            TANGGAL_MULAI + timedelta(days=hari_ke),
            datetime.min.time(),
        ) + timedelta(hours=rnd.randint(7, 21), minutes=rnd.randint(0, 59))

        # ANOMALI: 40 persen transaksi tanpa kartu anggota (pelanggan_id NULL).
        # Ini FAKTA BISNIS yang sah, bukan kerusakan data.
        pelanggan_id = None if rnd.random() < 0.40 else rnd.randint(1, JUMLAH_PELANGGAN)

        # ANOMALI: sebagian transaksi berstatus BATAL dan tetap tersimpan.
        u = rnd.random()
        status = "BATAL" if u < 0.02 else ("PENDING" if u < 0.025 else "SELESAI")

        jumlah_baris = rnd.choices([1, 2, 3, 4, 5, 8, 12], [30, 25, 18, 12, 8, 5, 2])[0]
        total = 0.0
        for _ in range(jumlah_baris):
            item_id += 1
            dibuat_item += 1
            produk_id = rnd.randint(1, JUMLAH_PRODUK)
            kuantitas = float(rnd.choices([1, 2, 3, 6, 12], [55, 25, 12, 6, 2])[0])
            harga = round(rnd.uniform(1_500, 320_000), 2)
            diskon = round(harga * kuantitas * rnd.choice([0, 0, 0, 0.05, 0.1]), 2)

            # --- anomali tingkat baris struk ---------------------------------
            v = rnd.random()
            if v < 0.0004:
                kuantitas = -kuantitas          # kuantitas tidak positif
            elif v < 0.0008:
                diskon = -abs(diskon) - 500     # diskon negatif
            elif v < 0.0011:
                harga = 0                       # harga tidak positif

            subtotal = round(kuantitas * harga - diskon, 2)

            # ANOMALI consistency: subtotal tidak sama dengan hitungannya.
            # Ketiga kolom sumbernya sendiri-sendiri masuk akal, sehingga
            # tidak ada constraint yang dapat menangkapnya -- bahan Modul 10.
            if rnd.random() < 0.0006:
                subtotal = round(subtotal * rnd.uniform(1.05, 1.4), 2)

            total += subtotal
            kumpul_item.append(
                (item_id, transaksi_id, produk_id, kuantitas, harga, diskon, subtotal)
            )

        yield (
            transaksi_id,
            f"ST{pencacah_struk[toko_id]:08d}",   # unik hanya per toko
            toko_id,
            pelanggan_id,
            rnd.randint(1, JUMLAH_PEGAWAI),
            waktu,
            rnd.choice(METODE_BAYAR),
            round(total, 2),
            status,
        )


def buat_persediaan(rnd, konf):
    """Periodic snapshot harian. Cakupan dibatasi -- lihat catatan UKURAN."""
    toko = rnd.sample(range(1, JUMLAH_TOKO + 1), konf["persediaan_toko"])
    produk = rnd.sample(range(1, JUMLAH_PRODUK + 1), konf["persediaan_produk"])
    for t in toko:
        for p in produk:
            saldo = float(rnd.randint(10, 400))
            for d in range(konf["persediaan_hari"]):
                tanggal = TANGGAL_MULAI + timedelta(days=d)
                masuk = float(rnd.randint(0, 60)) if rnd.random() < 0.25 else 0.0
                keluar = float(min(saldo + masuk, rnd.randint(0, 25)))
                akhir = saldo + masuk - keluar
                yield (tanggal, t, p, saldo, masuk, keluar, akhir)
                saldo = akhir


def buat_retur(rnd, jumlah_transaksi):
    """Accumulating snapshot: tonggak terisi bertahap, sebagian masih kosong."""
    n = max(1, jumlah_transaksi // 500)
    for i in range(1, n + 1):
        transaksi_id = rnd.randint(1, jumlah_transaksi)
        ajukan = TANGGAL_MULAI + timedelta(days=rnd.randint(0, 700))
        tahap = rnd.choices([1, 2, 3, 4], [10, 20, 25, 45])[0]
        setuju = ajukan + timedelta(days=rnd.randint(1, 5)) if tahap >= 2 else None
        terima = setuju + timedelta(days=rnd.randint(1, 7)) if tahap >= 3 and setuju else None
        dana = terima + timedelta(days=rnd.randint(1, 14)) if tahap >= 4 and terima else None
        status = ["Diajukan", "Disetujui", "Barang Diterima", "Selesai"][tahap - 1]
        yield (i, transaksi_id, ajukan, setuju, terima, dana,
               rnd.choice(["Rusak", "Salah Beli", "Kedaluwarsa", "Tidak Sesuai"]),
               status)


def buat_retur_item(rnd, jumlah_retur):
    for retur_id in range(1, jumlah_retur + 1):
        for produk_id in rnd.sample(range(1, JUMLAH_PRODUK + 1), rnd.randint(1, 3)):
            yield (retur_id, produk_id, float(rnd.randint(1, 4)))


# =============================================================================
# Orkestrasi
# =============================================================================

def koneksi(dbname: str):
    return psycopg2.connect(
        host=os.environ.get("SRC_HOST", "localhost"),
        port=os.environ.get("SRC_PORT", "5433"),
        dbname=dbname,
        user=os.environ.get("SRC_USER", "praktikum"),
        password=os.environ.get("SRC_PASSWORD", ""),
    )


def jalankan_ddl(cur, berkas: str) -> None:
    with open(berkas, encoding="utf-8") as f:
        isi = f.read()
    # Baris \connect hanya bermakna bagi psql; dilewati saat dijalankan dari sini.
    isi = "\n".join(b for b in isi.splitlines() if not b.startswith("\\"))
    cur.execute(isi)


def bangkitkan(ukuran: str, seed: int, ddl: str) -> None:
    konf = UKURAN[ukuran]
    rnd = random.Random(seed)
    fake = Faker("id_ID")
    Faker.seed(seed)

    log(f"Ukuran '{ukuran}', seed {seed}")
    log(f"Target baris struk: {konf['item_fakta']:,}")
    if ukuran == "besar":
        log("PERINGATAN: ukuran 'besar' memerlukan puluhan menit dan beberapa GB disk.")

    conn = koneksi("nusamart_oltp")
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            log("Membuat skema ...")
            jalankan_ddl(cur, ddl)
            cur.execute("SET search_path TO nusamart")

            log("Memuat master ...")
            salin(cur, "toko",
                  ["toko_id", "kode_toko", "nama_toko", "alamat", "kota",
                   "provinsi", "tipe_toko", "luas_m2", "tanggal_buka"],
                  buat_toko(fake, rnd), "toko")

            salin(cur, "kategori",
                  ["kategori_id", "kode_kategori", "nama_kategori",
                   "induk_kategori_id"],
                  buat_kategori(rnd), "kategori")

            salin(cur, "produk",
                  ["produk_id", "sku", "nama_produk", "kategori_id", "merek",
                   "satuan", "berat_gram", "harga_jual", "harga_pokok", "aktif"],
                  buat_produk(fake, rnd), "produk")

            salin(cur, "pelanggan",
                  ["pelanggan_id", "kode_member", "nama", "jenis_kelamin",
                   "tanggal_lahir", "kota", "tanggal_daftar", "segmen"],
                  buat_pelanggan(fake, rnd), "pelanggan")

            salin(cur, "pegawai",
                  ["pegawai_id", "nama", "toko_id", "peran", "tanggal_masuk"],
                  buat_pegawai(fake, rnd), "pegawai")

            salin(cur, "promosi",
                  ["promosi_id", "kode_promo", "nama_promosi", "tipe",
                   "mulai", "selesai"],
                  buat_promosi(rnd, konf["hari"]), "promosi")

            salin(cur, "promosi_produk", ["promosi_id", "produk_id"],
                  buat_promosi_produk(rnd), "promosi_produk")

            log("Memuat transaksi ...")
            # Baris struk dikumpulkan saat kepala struk dibangkitkan, lalu
            # dimuat sesudahnya -- foreign key transaksi_item menuntut kepala
            # struknya sudah ada.
            kumpul_item: list[tuple] = []
            n_trx = salin(cur, "transaksi",
                          ["transaksi_id", "nomor_struk", "toko_id",
                           "pelanggan_id", "pegawai_id", "waktu_transaksi",
                           "metode_bayar", "total_bayar", "status"],
                          buat_transaksi_dan_item(rnd, konf, kumpul_item),
                          "transaksi")

            salin(cur, "transaksi_item",
                  ["transaksi_item_id", "transaksi_id", "produk_id",
                   "kuantitas", "harga_satuan", "diskon", "subtotal"],
                  iter(kumpul_item), "transaksi_item")
            kumpul_item.clear()

            log("Memuat persediaan dan retur ...")
            salin(cur, "persediaan_harian",
                  ["tanggal", "toko_id", "produk_id", "saldo_awal", "masuk",
                   "keluar", "saldo_akhir"],
                  buat_persediaan(rnd, konf), "persediaan_harian")

            n_retur = salin(cur, "retur",
                            ["retur_id", "transaksi_id", "tanggal_pengajuan",
                             "tanggal_disetujui", "tanggal_barang_diterima",
                             "tanggal_dana_kembali", "alasan", "status"],
                            buat_retur(rnd, n_trx), "retur")

            salin(cur, "retur_item", ["retur_id", "produk_id", "kuantitas"],
                  buat_retur_item(rnd, n_retur), "retur_item")

            log("Menjalankan ANALYZE ...")
            cur.execute("ANALYZE")

        conn.commit()
        log("Selesai. Ringkasan:")
        ringkasan(conn)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def ringkasan(conn) -> None:
    with conn.cursor() as cur:
        cur.execute("""
            SELECT table_name,
                   (xpath('/row/c/text()',
                          query_to_xml(format('SELECT COUNT(*) AS c FROM nusamart.%I',
                                              table_name), false, true, ''))
                   )[1]::text::bigint AS baris
            FROM   information_schema.tables
            WHERE  table_schema = 'nusamart' AND table_type = 'BASE TABLE'
            ORDER  BY baris DESC
        """)
        for nama, baris in cur.fetchall():
            print(f"    {nama:<24} {baris:>12,}")


def main() -> None:
    p = argparse.ArgumentParser(
        description="Pembangkit data operasional NusaMart",
        epilog="Nilai --seed harus SAMA untuk seluruh kelas.",
    )
    p.add_argument("--ukuran", choices=list(UKURAN), default="kecil",
                   help="kecil (Modul 1-5), sedang (Modul 6-8), besar (opsional)")
    p.add_argument("--seed", type=int, default=42,
                   help="penentu keacakan; samakan untuk seluruh kelas")
    p.add_argument("--ddl", default=os.path.join(os.path.dirname(__file__),
                                                 "ddl-sumber.sql"))
    p.add_argument("--sumber-tambahan", action="store_true",
                   help="bangkitkan juga nusamart_barat dan nusamart_timur "
                        "(diperlukan mulai Modul 7)")
    a = p.parse_args()

    bangkitkan(a.ukuran, a.seed, a.ddl)

    if a.sumber_tambahan:
        from generate_sumber_tambahan import bangkitkan_sumber_tambahan
        bangkitkan_sumber_tambahan(a.ukuran, a.seed)


if __name__ == "__main__":
    main()
