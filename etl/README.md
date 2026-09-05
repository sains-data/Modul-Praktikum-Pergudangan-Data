# Pipeline ETL

Direktori ini disiapkan untuk kode ETL pada Modul 07. Struktur yang disarankan
setelah teknologi dipilih:

```text
etl/
├── config/        # konfigurasi contoh tanpa kredensial
├── src/           # extract, transform, load, dan utilitas
└── tests/         # pengujian transformasi dan kualitas data
```

Simpan nilai rahasia dalam `.env`, bukan dalam source code. Tambahkan
`requirements.txt`, `pyproject.toml`, atau manifest lain setelah runtime ETL
ditetapkan.

