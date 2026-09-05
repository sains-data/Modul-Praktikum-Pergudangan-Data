# Modul Praktikum Pergudangan Data

Direktori ini memuat naskah dan artefak pendukung untuk sepuluh modul praktikum
Pergudangan Data.

## Menyiapkan lingkungan

```bash
cp .env.example .env              # isi kata sandinya
docker compose up -d postgres_source postgres_dw
pip install -r requirements.txt
python seed/generate_nusamart.py --ukuran kecil --seed 42
```

Petunjuk lengkap penyiapan data, termasuk daftar anomali yang ditanam, ada pada
`seed/README.md` — **berkas itu untuk asisten, bukan untuk mahasiswa.**


## Organisasi direktori


- `docker-compose.yml`: tiga layanan — `postgres_source` (5433),
  `postgres_dw` (5434), dan `superset` (8088).
- `seed/`: skema sumber, pembangkit data, batch beranomali, dan skrip snapshot.
- `data/`: petunjuk penyimpanan data sumber, staging, dan keluaran warehouse.
- `sql/`: skrip SQL per modul.
- `dbt/`: placeholder model dan custom data tests untuk modul berbasis dbt.
- `etl/`: kode, konfigurasi contoh, dan dokumentasi pipeline ETL.
- `notebooks/`: notebook eksplorasi, OLAP, atau pemeriksaan kualitas data.
- `templates/`: templat laporan, kamus data, dan dokumen desain.

