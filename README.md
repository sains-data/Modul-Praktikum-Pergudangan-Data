# Modul Praktikum Pergudangan Data

Direktori ini memuat naskah dan artefak pendukung untuk sepuluh modul praktikum
Pergudangan Data. Naskah dikompilasi dari `main.tex` menjadi
`modul-praktikum-pergudangan-data.pdf`.

## Menyiapkan lingkungan

```bash
cp .env.example .env              # isi kata sandinya
docker compose up -d postgres_source postgres_dw
pip install -r requirements.txt
python seed/generate_nusamart.py --ukuran kecil --seed 42
```

Petunjuk lengkap penyiapan data, termasuk daftar anomali yang ditanam, ada pada
`seed/README.md` — **berkas itu untuk asisten, bukan untuk mahasiswa.**

Mengompilasi naskah:

```bash
latexmk -pdf -outdir=tmp main.tex
```

## Organisasi direktori

- `main.tex`, `config/`: naskah utama, tema, dan sampul TikZ.
- `section/`: naskah LaTeX untuk bagian awal, sepuluh modul, dan daftar pustaka.
- `docker-compose.yml`: tiga layanan — `postgres_source` (5433),
  `postgres_dw` (5434), dan `superset` (8088).
- `seed/`: skema sumber, pembangkit data, batch beranomali, dan skrip snapshot.
- `assets/`: gambar, diagram, dan tangkapan layar yang digunakan oleh naskah.
- `data/`: petunjuk penyimpanan data sumber, staging, dan keluaran warehouse.
- `sql/`: skrip SQL per modul.
- `dbt/`: placeholder model dan custom data tests untuk modul berbasis dbt.
- `etl/`: kode, konfigurasi contoh, dan dokumentasi pipeline ETL.
- `notebooks/`: notebook eksplorasi, OLAP, atau pemeriksaan kualitas data.
- `templates/`: templat laporan, kamus data, dan dokumen desain.
- `rubrik/`: rubrik serta checklist penilaian praktikum.

## Konvensi

- Gunakan penomoran dua digit: `modul-01` sampai `modul-10`.
- Simpan data asli sebagai read-only di `data/raw/` dan hasil proses di
  `data/processed/`.
- Berkas berisi kredensial harus menggunakan nama `.env` dan tidak boleh masuk
  version control.
- Artefak besar atau data yang dapat dibuat ulang tidak disimpan ke repository.

Modul 10 membahas jaminan kualitas data melalui profiling, pengujian otomatis,
penanganan data gagal, dan rekonsiliasi source--warehouse pada kasus NusaMart.
