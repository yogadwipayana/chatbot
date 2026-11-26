# Chatbot

Repository induk untuk project chatbot: konfigurasi Docker Compose untuk server, disusun persis seperti di server. Setiap folder di sini adalah satu folder di root server dan dijalankan dari folder itu.

| Folder      | Di server   | Isi                                                                  |
| ----------- | ----------- | -------------------------------------------------------------------- |
| `chatbot/`  | `/chatbot`  | api + admin + client (`docker-compose.yml`), skrip deploy `start.sh` |
| `postgres/` | `/postgres` | PostgreSQL 16 + pgvector (`pg`) dan pgweb                            |
| `s3/`       | `/s3`       | MinIO, penyimpanan dokumen yang diunggah                             |
| `9router/`  | `/9router`  | Gateway AI 9router + embedding multilingual-e5-small (TEI)           |
| `laya/`     | `/laya`     | Gerbang semantik Laya (`POST /v1/systemone`)                         |

`postgres/`, `s3/`, dan `laya/` punya `README.md` masing-masing. `start.txt` berisi perintah menjalankan versi dev di komputer lokal.

Kode aplikasi ada di tiga repository terpisah yang di-clone ke dalam `chatbot/`:

| Folder            | Repository                                                        |
| ----------------- | ----------------------------------------------------------------- |
| `chatbot/api/`    | [chatbot-api](https://github.com/yogadwipayana/chatbot-api)       |
| `chatbot/client/` | [chatbot-client](https://github.com/yogadwipayana/chatbot-client) |
| `chatbot/admin/`  | [chatbot-admin](https://github.com/yogadwipayana/chatbot-admin)   |

## Langkah Setup

### 1. Letakkan folder di root server

`chatbot/start.sh` dan `laya/docker-compose.yml` memakai path absolut (`/chatbot/...`, `/laya/...`), jadi setiap folder harus berada di root:

```bash
git clone https://github.com/yogadwipayana/chatbot.git ~/chatbot-gh
sudo cp -r ~/chatbot-gh/{chatbot,postgres,s3,9router,laya} /
```

Lalu clone ketiga repository aplikasi ke dalam `/chatbot`:

```bash
cd /chatbot
sudo git clone https://github.com/yogadwipayana/chatbot-api.git api
sudo git clone https://github.com/yogadwipayana/chatbot-client.git client
sudo git clone https://github.com/yogadwipayana/chatbot-admin.git admin
```

### 2. Siapkan file `.env`

Di setiap folder, salin `.env.example` menjadi `.env`, isi nilainya, lalu kunci aksesnya:

```bash
for d in /chatbot /postgres /s3 /9router /laya /chatbot/api /chatbot/client /chatbot/admin; do
    sudo cp "$d/.env.example" "$d/.env" && sudo chmod 600 "$d/.env"
done
```

Catatan:

- `/chatbot/.env` hanya berisi `RUN_MIGRATIONS`. Nilai `false` berarti migrasi dijalankan dari lokal (`alembic upgrade head`). Untuk instalasi baru, set `true` agar migrasi jalan saat container api start.
- `/chatbot/api/.env` di server memakai `ENVIRONMENT=production`, `DEBUG=false`, dan `DATABASE_URL` ke `localhost:5432` (api memakai `network_mode: host`).
- Jangan commit file `.env` apa pun. Repository ini publik, dan `.gitignore` sudah menolaknya.

### 3. Jalankan service secara berurutan

```bash
cd /postgres && sudo docker compose up -d                       # a. PostgreSQL + pgvector, pgweb
cd /s3       && sudo docker compose up -d                       # b. MinIO
cd /9router  && sudo docker compose up -d --no-deps 9router e5  # c. 9router + embedding
cd /laya     && sudo docker compose up -d --build               # d. Laya (lihat laya/README.md)
sudo bash /chatbot/start.sh                                     # e. api + admin + client
```

- (c) `--no-deps` sengaja dipakai supaya `headroom` tidak ikut jalan. CPU server ini tidak punya AVX, sehingga `headroom` crash dengan SIGILL (exit 132).
- (d) Laya butuh checkpoint di `/laya/models/laya-pandu-gerbang/` (sekitar 650 MB, tidak disimpan di git). `/laya/sajikan_laya.py` di-mount ke container.
- (e) `start.sh` menarik kode terbaru, membangun image satu per satu, lalu mengganti container dan memeriksa kesehatannya. Jika ada build yang gagal, skrip berhenti dan container lama tetap berjalan. Skrip yang sama dipakai untuk setiap deploy ulang.
