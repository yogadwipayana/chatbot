# Chatbot

Repository induk untuk project chatbot. Kode aplikasi ada di tiga repository terpisah yang di-clone ke dalam folder ini.

| Folder    | Repository                                                            |
| --------- | --------------------------------------------------------------------- |
| `api/`    | [chatbot-api](https://github.com/yogadwipayana/chatbot-api)       |
| `client/` | [chatbot-client](https://github.com/yogadwipayana/chatbot-client) |
| `admin/`  | [chatbot-admin](https://github.com/yogadwipayana/chatbot-admin)   |

## Langkah Setup

### 1. Clone repository

Clone repository ini, lalu clone ketiga repository aplikasi ke dalamnya:

```bash
git clone https://github.com/yogadwipayana/chatbot-api.git api
git clone https://github.com/yogadwipayana/chatbot-client.git client
git clone https://github.com/yogadwipayana/chatbot-admin.git admin
```

### 2. Siapkan file `.env`

Buat semua file `.env` dari `.env.example` masing-masing:

```bash
cp api/.env.example api/.env
cp client/.env.example client/.env
cp admin/.env.example admin/.env
```

Lalu file env untuk service Docker di root:

```bash
cp pg.env.example pg.env
cp s3.env.example s3.env
cp model.env.example model.env
```

Setelah itu isi nilainya sesuai environment.

### 3. Jalankan Docker

Jalankan secara berurutan:

```bash
docker compose -f pg-docker-compose.yml --env-file pg.env up -d         # a. PostgreSQL + pgvector
docker compose -f s3-docker-compose.yml --env-file s3.env up -d         # b. MinIO (S3)
docker compose -f model-docker-compose.yml --env-file model.env up -d   # c. Model (9router, headroom, embedding)
docker compose up -d --build                                            # d. api + admin + client
```
