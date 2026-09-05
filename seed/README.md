# Data Praktikum — Berkas untuk Asisten

> **JANGAN DIBAGIKAN KE MAHASISWA.**
> Berkas ini memuat daftar lengkap anomali yang ditanam sengaja. Menemukannya
> adalah pekerjaan Modul 1 (profiling) dan Modul 10 (kualitas data).

## Isi direktori

| Berkas | Guna |
|---|---|
| `init-source/`, `init-dw/` | Dijalankan otomatis saat container pertama kali dibuat |
| `ddl-sumber.sql` | Skema sistem operasional NusaMart |
| `generate_nusamart.py` | Pembangkit sumber utama, tiga ukuran |
| `generate_sumber_tambahan.py` | Pembangkit sumber kedua dan ketiga (Modul 7) |
| `batch_anomali.sql` | Batch beranomali untuk Modul 10 |
| `buat-snapshot.sh` | Membuat `snapshot-modul-NN.sql` |
| `unduh-northwind.sh` | Menyiapkan pembanding Modul 6 |

## Menyiapkan dari nol

```bash
cp .env.example .env          # isi kata sandinya
docker compose up -d postgres_source postgres_dw
pip install -r requirements.txt

# Modul 1–5
python seed/generate_nusamart.py --ukuran kecil --seed 42

# Modul 6–8 (wajib sebelum Modul 6)
python seed/generate_nusamart.py --ukuran sedang --seed 42

# Modul 7 ke atas
python seed/generate_sumber_tambahan.py --ukuran sedang --seed 42

# Modul 6
./seed/unduh-northwind.sh

# Modul 10, sesudah pipeline Modul 7 berjalan
docker compose exec -T postgres_source \
  psql -U praktikum -d nusamart_oltp -f /seed/batch_anomali.sql
```

**Nilai `--seed` harus sama untuk seluruh kelas.** Tanpa itu, angka hasil
profiling setiap mahasiswa berbeda dan tidak dapat dibandingkan saat
checkpoint.

### Perkiraan waktu dan ruang

| Ukuran | Baris struk | Waktu | Ruang |
|---|---:|---|---|
| `kecil` | 100 ribu | ~1 menit | ~150 MB |
| `sedang` | 5 juta | ~8–15 menit | ~2 GB |
| `besar` | 50 juta | ~1,5–2 jam | ~18 GB |

Ukuran `besar` bersifat opsional dan tidak dipakai modul mana pun. Ia
disediakan bagi mahasiswa yang ingin melihat partisi dan agregat Modul 6
benar-benar berbeda.

---

## Anomali yang ditanam pada sumber utama

Ditemukan mahasiswa pada **Modul 1 Bagian C**. Persentase bersifat perkiraan;
angka pastinya bergantung pada `--seed`.

| # | Anomali | Kadar | Ditemukan lewat | Berbuah di |
|---|---|---|---|---|
| 1 | `nomor_struk` unik hanya per toko | seluruh baris | `COUNT(*)` vs `COUNT(DISTINCT)` | Modul 2: degenerate dimension |
| 2 | `pelanggan_id` `NULL` | ~40% | proporsi NULL | Modul 3: junk dimension; Modul 5: baris unknown |
| 3 | Transaksi berstatus `BATAL` | ~2% | sebaran `status` | Modul 2: penyaringan saat pemuatan |
| 4 | Kuantitas tidak positif | ~0,04% | `kuantitas <= 0` | Modul 5: `CHECK` gagal dipasang |
| 5 | Diskon negatif | ~0,04% | `diskon < 0` | Modul 5 |
| 6 | Harga satuan nol | ~0,03% | `harga_satuan <= 0` | Modul 5 |
| 7 | Subtotal tidak konsisten | ~0,06% | aritmetika subtotal | Modul 10: custom test |
| 8 | Produk berkategori yatim | ~0,2% | `LEFT JOIN` ke `kategori` | Modul 2: `LEFT JOIN` wajib |
| 9 | Produk tanpa kategori | ~0,2% | `kategori_id IS NULL` | Modul 9: `GROUPING` vs `COALESCE` |
| 10 | Kategori menunjuk induk tak ada | 1 baris | `WITH RECURSIVE` | Modul 1: Latihan 1.1 |
| 11 | `berat_gram` kosong | ~3% | proporsi NULL | Modul 7: standardisasi satuan |
| 12 | Tanggal lahir di masa depan | ~0,1% | `> CURRENT_DATE` | Modul 1: rentang nilai |
| 13 | Tanggal lahir sebelum 1920 | ~0,1% | `< '1920-01-01'` | Modul 1 |

**Anomali 8 dan 9 patut diperhatikan.** Keduanya menghasilkan `kategori`
bernilai `NULL` pada dimensi, dan itulah yang membuat peragaan `GROUPING` pada
Modul 9 bekerja — baris subtotal dan baris data sama-sama berlabel kosong bila
`COALESCE` dipakai tanpa `GROUPING`.

---

## Konflik yang ditanam antarsumber

Ditemukan mahasiswa pada **Modul 7 Bagian B**. Minimal lima harus dilaporkan.

### `nusamart_barat` — hasil akuisisi

| Jenis | Wujud |
|---|---|
| Penamaan (tabel) | `produk`→`item`, `pelanggan`→`customer`, `kategori`→`item_category`, `transaksi`→`sales_header`, `transaksi_item`→`sales_line` |
| Penamaan (kolom) | `produk_id`→`item_code`, `nama_produk`→`item_name`, `berat_gram`→`weight_kg` |
| Tipe | `item_code` bertipe **TEKS** (`ITM-000123`), bukan integer |
| **Satuan** | Berat dalam **kilogram**, bukan gram — rata-ratanya berselisih ~1000× |
| Pengodean | Kategori `BEV`, `SNK`, `HHD`, `PCR`, `ELC` |
| Status | `DONE`/`CANCELLED`, bukan `SELESAI`/`BATAL` |

### `nusamart_timur` — wilayah timur

| Jenis | Wujud |
|---|---|
| Pengodean | Kategori `DRK`, `FOD`, `HSE` |
| Representasi | Nama pelanggan **HURUF BESAR**, sebagian bergelar, sebagian berspasi sisipan |
| **Timeliness** | Kolom `dicatat_pada` = `waktu` + 3 hari; ~1% terlambat 10 hari |

### Identitas lintas sumber

**1.200 pelanggan pertama** dari `nusamart_oltp` muncul kembali di kedua sumber
lain dengan ejaan berbeda. Inilah jawaban benar yang dapat diperiksa untuk
*object identification* Modul 7.

Variasi yang dipakai:

| Sumber | Contoh transformasi |
|---|---|
| barat | `Siti Nurhaliza Dewi` → `Siti N. Dewi` (nama tengah disingkat) |
| barat | `siti nurhaliza` → `Siti Nurhaliza` (kapitalisasi berubah) |
| timur | `Siti Nurhaliza` → `IBU SITI NURHALIZA` (gelar + huruf besar) |
| timur | `Siti Nurhaliza` → `SITI NUR HALIZA` (spasi disisipkan) |

Varian terakhir paling sulit: kemiripan `difflib` untuk `siti nurhaliza`
lawan `siti nur haliza` sekitar 0,97 — jadi tertangkap ambang 0,88. Varian
nama-tengah-disingkat skornya jauh lebih rendah dan **sengaja** jatuh di zona
ragu, sehingga masuk `tinjau-manual.csv`. Mahasiswa yang berkas ragunya kosong
hampir pasti memakai ambang terlalu longgar.

---

## Anomali batch Modul 10

Ditanam oleh `batch_anomali.sql` pada tanggal **2026-01-15**. Seluruhnya
**lolos setiap constraint** yang dipasang pada Modul 5 — pipeline memuatnya
tanpa galat dan dashboard menampilkan angka yang tampak wajar.

| # | Dimensi | Anomali | Kadar | Kenapa lolos |
|---|---|---|---|---|
| 1 | Completeness | Toko 7 tidak mengirim apa pun | 0 baris | Ketiadaan tidak menghasilkan baris |
| 2 | Consistency | Subtotal digelembungkan 25% | ~40 baris | Ketiga kolomnya sendiri-sendiri wajar |
| 3 | Validity | Harga satuan ×1000 | ~15 baris | Tetap bilangan positif |
| 4 | Uniqueness | Struk disalin dengan id baru | 50 struk | Kunci gudang tetap unik |
| 5 | Timeliness | Transaksi bertanggal mundur 10–20 hari | ~100 baris | Tanggalnya sah |

**Anomali 1 paling jarang ditemukan.** Bila sampai menit ke-60 belum ada yang
menemukannya, beri petunjuk berupa pertanyaan — bukan jawaban:

> *"Berapa toko yang mengirim data pada batch ini, dan berapa yang mengirim
> pada batch sebelumnya?"*

---

## Cakupan yang sengaja dibatasi

### Persediaan harian

Bila seluruh kombinasi dicatat, 180.000 produk × 240 toko × 365 hari
menghasilkan **15,8 miliar baris** — mustahil untuk praktikum. Generator hanya
mencatat sebagian:

| Ukuran | Toko | Produk | Hari | Baris |
|---|---:|---:|---:|---:|
| kecil | 20 | 100 | 60 | 120 ribu |
| sedang | 60 | 300 | 180 | 3,2 juta |
| besar | 120 | 500 | 365 | 21,9 juta |

Pembatasan ini **memperkuat**, bukan melemahkan, Latihan 4.2 — mahasiswa
menghitung angka teoretisnya sendiri, lalu membandingkannya dengan yang ada.
Selisih itu justru bahan diskusinya.

### Dimensi tetap di seluruh ukuran

240 toko dan 180.000 produk tidak berubah antarukuran; yang berjenjang hanya
volume fakta. Konsekuensinya sebagian besar produk tidak pernah terjual — ekor
panjang yang realistis pada ritel, sekaligus yang membuat pertanyaan *"produk
mana yang dipromosikan tetapi tidak terjual"* pada Modul 4 memiliki jawaban.

---

## Snapshot per modul

Snapshot **tidak disertakan** di repositori: isinya adalah hasil kerja modul
itu sendiri, sehingga hanya dapat dibuat setelah solusi acuan dikerjakan.

```bash
# 1. Kerjakan modul N pada solusi acuan sampai check.sql seluruhnya LULUS
# 2. Buat snapshotnya
./seed/buat-snapshot.sh 03
# 3. Bagikan seed/snapshot/snapshot-modul-03.sql ke mahasiswa
```

Yang perlu disiapkan sebelum semester berjalan:

- [ ] `snapshot-modul-01.sql` … `snapshot-modul-04.sql` (dataset kecil)
- [ ] `snapshot-modul-05.sql` dan `snapshot-modul-05-sedang.sql`
- [ ] `snapshot-modul-06.sql` … `snapshot-modul-09.sql` (dataset sedang)

---

## Daftar periksa sebelum minggu ke-3

- [ ] `docker compose up` diuji pada **Windows, macOS, dan Linux**
- [ ] Dataset `kecil` dan `sedang` dibangkitkan dengan seed yang sama
- [ ] Sumber kedua dan ketiga dibangkitkan
- [ ] Northwind dipulihkan
- [ ] Seluruh `sql/modul-*/check.sql` dijalankan pada solusi acuan dan **lulus**
- [ ] Snapshot sepuluh modul dibuat
- [ ] Berkas ini **tidak** ikut dibagikan ke mahasiswa
