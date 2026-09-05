"""Modul 07 -- standardisasi dan object identification.

Kerangka setengah jadi. Mahasiswa melengkapi bagian bertanda TODO.

Prinsip yang dipegang berkas ini:

1.  Aturan transformasi ditulis sebagai DATA (dict), bukan sebagai rangkaian
    percabangan if. Aturan yang berupa data dapat dicetak, diperiksa, diuji,
    dan didokumentasikan sebagai metadata pada Modul 8. Aturan yang tersembunyi
    di dalam percabangan hanya dapat dibaca oleh yang menulisnya.

2.  Fungsi di sini TIDAK menyentuh basis data. Ia menerima dan mengembalikan
    data, sehingga dapat diuji tanpa PostgreSQL yang menyala.
"""

from __future__ import annotations

import re
from collections import defaultdict
from difflib import SequenceMatcher

# =============================================================================
# Aturan standardisasi
# =============================================================================

# Faktor pengali menuju satuan baku, yaitu GRAM.
#
# Konflik satuan tidak terlihat dari nama kolom; ia terlihat dari sebaran
# nilai. Rata-rata yang berselisih sekitar seribu kali adalah tandanya.
KONVERSI_BERAT: dict[str, float] = {
    "oltp": 1.0,        # sudah gram
    "barat": 1000.0,    # kilogram -> gram
    "timur": 1.0,
}

# Pemetaan kode kategori setiap sumber ke kode baku milik sumber utama.
# Kunci berupa pasangan (sumber, kode_asal) supaya kode yang sama pada dua
# sumber berbeda tetap dapat dipetakan ke tujuan yang berbeda.
PETA_KATEGORI: dict[tuple[str, str], str] = {
    ("barat", "BEV"): "MNM",
    ("barat", "SNK"): "MKN",
    ("barat", "HHD"): "RTG",
    ("timur", "DRK"): "MNM",
    ("timur", "FOD"): "MKN",
    # TODO: lengkapi dari temuan Bagian B.2 pada laporan-konflik.md
}

# Nilai yang secara bisnis berarti "kosong", tetapi ditulis berbeda-beda.
NILAI_KOSONG = {"", "-", "n/a", "na", "null", "none", "tidak ada", "?"}


def standardisasi_berat(baris: dict) -> float | None:
    """Kembalikan berat dalam gram, apa pun satuan sumbernya."""
    berat = baris.get("berat")
    if berat is None:
        return None
    faktor = KONVERSI_BERAT.get(baris["sumber"])
    if faktor is None:
        # Sumber tak dikenal lebih baik gagal keras daripada diam-diam salah.
        raise ValueError(f"faktor berat belum ditetapkan: {baris['sumber']!r}")
    return float(berat) * faktor


def standardisasi_kategori(baris: dict) -> str:
    """Petakan kode kategori sumber ke kode baku; biarkan bila sudah baku."""
    asal = (baris.get("kode_kategori") or "").strip().upper()
    return PETA_KATEGORI.get((baris["sumber"], asal), asal)


def bersihkan_teks(nilai: str | None) -> str | None:
    """Rapatkan spasi dan seragamkan nilai yang berarti kosong."""
    if nilai is None:
        return None
    rapat = " ".join(str(nilai).split())
    return None if rapat.lower() in NILAI_KOSONG else rapat


def standardisasi(catatan: list[dict]) -> list[dict]:
    """Terapkan seluruh aturan standardisasi pada satu batch catatan."""
    hasil = []
    for baris in catatan:
        baru = dict(baris)
        baru["berat_gram"] = standardisasi_berat(baris)
        baru["kode_kategori"] = standardisasi_kategori(baris)
        baru["nama"] = bersihkan_teks(baris.get("nama"))
        baru["kota"] = bersihkan_teks(baris.get("kota"))
        # TODO: tambahkan standardisasi format tanggal dan zona waktu
        #       (lihat Latihan 7.1 pada naskah modul)
        hasil.append(baru)
    return hasil


# =============================================================================
# Object identification
# =============================================================================

GELAR = {"bapak", "ibu", "bpk", "sdr", "sdri", "h", "hj", "drs", "ir", "st"}

# Ambang keputusan. Di atas AMBANG: satu orang. Di bawah AMBANG - ZONA_RAGU:
# dua orang. Di antaranya: ditinjau manusia.
#
# Ambang yang terlalu longgar menggabungkan dua orang berbeda menjadi satu --
# seluruh transaksi mereka bercampur, dan kesalahan ini nyaris mustahil
# ditemukan kembali. Ambang yang terlalu ketat membiarkan satu orang tercatat
# dua kali -- kesalahan yang lebih mudah ditemukan dan diperbaiki.
#
# Bila ragu, pilih yang terlalu ketat.
AMBANG = 0.88
ZONA_RAGU = 0.08


def normalkan_nama(nama: str) -> str:
    """Huruf kecil, tanpa tanda baca, tanpa gelar, spasi dirapatkan."""
    hanya_huruf = re.sub(r"[^a-z ]", " ", nama.lower())
    kata = [k for k in hanya_huruf.split() if k not in GELAR]
    return " ".join(kata)


def kemiripan(a: str, b: str) -> float:
    return SequenceMatcher(None, a, b).ratio()


def identifikasi_pelanggan(catatan: list[dict]) -> tuple[dict, list[dict]]:
    """Tetapkan satu master id bagi catatan pelanggan yang sama.

    Mengembalikan (peta, ragu):
      peta -- {(sumber, id_sumber): pelanggan_master_id}
      ragu -- daftar pasangan yang skornya di zona ragu, untuk ditinjau manusia

    Blocking dilakukan menurut kota. Ini mempercepat proses secara drastis --
    tanpa blocking, 100 ribu pelanggan menuntut sekitar lima miliar
    perbandingan -- tetapi juga berarti pelanggan yang sama dengan kota berbeda
    TIDAK AKAN PERNAH dibandingkan. Keterbatasan ini disengaja dan wajib
    dicatat pada laporan, bukan disembunyikan.
    """
    blok: dict[str | None, list[dict]] = defaultdict(list)
    for c in catatan:
        blok[c.get("kota")].append(c)

    peta: dict[tuple[str, str], int] = {}
    ragu: list[dict] = []
    master_berikutnya = 1

    for kota, kelompok in blok.items():
        wakil: list[tuple[str, int]] = []   # (nama_normal, master_id)

        for c in kelompok:
            nama_normal = normalkan_nama(c["nama"] or "")
            if not nama_normal:
                continue

            skor, mid = max(
                ((kemiripan(nama_normal, wn), m) for wn, m in wakil),
                default=(0.0, None),
            )
            kunci = (c["sumber"], c["id_sumber"])

            if skor >= AMBANG:
                peta[kunci] = mid
            elif skor >= AMBANG - ZONA_RAGU:
                # Tidak diputuskan mesin. Sementara diperlakukan sebagai orang
                # baru, lalu dilaporkan untuk ditinjau.
                peta[kunci] = master_berikutnya
                ragu.append({
                    "sumber": c["sumber"], "id_sumber": c["id_sumber"],
                    "nama": c["nama"], "kota": kota,
                    "skor": round(skor, 4), "calon_master_id": mid,
                })
                wakil.append((nama_normal, master_berikutnya))
                master_berikutnya += 1
            else:
                peta[kunci] = master_berikutnya
                wakil.append((nama_normal, master_berikutnya))
                master_berikutnya += 1

    return peta, ragu


# =============================================================================
# Survivorship
# =============================================================================

# Nilai mana yang menang ketika dua sumber tidak sepakat tentang orang yang
# sama. Aturan ini HARUS ditulis, bukan diputuskan diam-diam oleh urutan
# pemrosesan.
URUTAN_KEPERCAYAAN = ["oltp", "barat", "timur"]


def pilih_nilai_bertahan(calon: list[dict], kolom: str):
    """Nilai dari sumber paling tepercaya yang tidak kosong."""
    for sumber in URUTAN_KEPERCAYAAN:
        for c in calon:
            if c["sumber"] == sumber and c.get(kolom) is not None:
                return c[kolom]
    return None
