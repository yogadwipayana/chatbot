# Reranker (TEI)

Layanan reranker untuk chatbot di `/chatbot`. Dijalankan dengan Text
Embeddings Inference versi CPU, sama seperti `e5-embedding` di `/9router`.
`docker-compose.yml` berisi dua model; **jalankan satu saja**.

| Service | Container | Port host | Model |
|---|---|---|---|
| `gte` | `gte-reranker` | 8081 | `Alibaba-NLP/gte-multilingual-reranker-base` (0,3B) |
| `bge` | `bge-reranker` | 8082 | `BAAI/bge-reranker-v2-m3` (0,6B) |

Mulailah dengan `gte`. CPU server ini (QEMU) tidak punya AVX/AVX2, hanya
sampai SSE4.2, jadi `bge` yang dua kali lebih besar kemungkinan melewati batas
`RERANK_TIMEOUT_SECONDS=10` di API.

## Status

Chatbot **belum** bisa memakai layanan ini. API mengirim format Cohere
(`documents`, jawaban `results`), sedangkan TEI memakai `texts`. Perlu adapter
di `api/app/rag/reranker.py` lebih dulu. Sampai adapter itu ada, biarkan
`RERANK_PROVIDER=none` di `/chatbot/api/.env`. Panduan sisi API ada di
`api/docs/rerank.md` di repo.

## Syarat

Project ini berdiri sendiri: jaringannya `rerank-network`, tidak bergantung
pada `/9router`. Yang perlu diperiksa hanya ruang disk. Model diunduh dari
huggingface.co saat container pertama kali start: gte ±1,2 GB, bge ±2,3 GB.
Disk server sempit, cek dulu `df -h /`.

## Menjalankan satu model

```bash
cd /rerank
sudo cp .env.example .env
openssl rand -hex 24              # buat kunci acak
sudo nano .env                    # isi GTE_API_KEY (dan/atau BGE_API_KEY)
sudo docker compose up -d gte
sudo docker compose logs -f gte   # tunggu baris "Ready", lalu Ctrl+C
```

Selalu sebut nama service. `sudo docker compose up -d` tanpa nama service
menyalakan **kedua** model sekaligus.

Kalau log gte menunjukkan model tidak didukung: dokumentasi TEI tidak menyebut
apakah arsitektur GTE jalan di image CPU. Pakai `bge` sebagai gantinya.

### Uji

```bash
KEY=$(sudo grep '^GTE_API_KEY=' /rerank/.env | cut -d= -f2)
time curl -s localhost:8081/rerank \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"query":"Apa saja jenis beasiswa?","texts":["Beasiswa Prestasi Internal diberikan kepada mahasiswa berprestasi.","Jadwal wisuda semester ganjil diumumkan bulan Juli."]}'
```

Jawabannya berisi `index` dan `score` (0–1) per teks; teks beasiswa harus
mendapat skor jauh lebih tinggi. Untuk bge, ganti port ke 8082 dan kuncinya ke
`BGE_API_KEY`.

`time` menunjukkan lamanya. Chatbot mengirim 20 potongan (masing-masing sampai
900 karakter) per pertanyaan, jadi sebelum dipakai uji juga dengan 20 teks
sepanjang itu dan pastikan hasilnya jauh di bawah 10 detik.

## Ganti model

Contoh gte → bge (untuk arah sebaliknya, tukar namanya):

```bash
cd /rerank
sudo docker compose rm -sf gte      # hentikan DAN hapus container lama
sudo docker compose up -d bge
sudo docker compose logs -f bge     # tunggu "Ready"
sudo docker compose ps              # pastikan hanya bge yang jalan
```

Pakai `rm -sf`, bukan `stop`. Dengan `restart: always`, container yang hanya
di-`stop` akan menyala lagi ketika Docker atau server restart, sehingga kedua
model jalan bersamaan.

Kalau disk penuh, hapus bobot model lama. Bobot itu diunduh ulang bila model
dipakai lagi.

```bash
sudo docker volume rm gte-data
```

Setelah chatbot terhubung (adapter sudah ada), sesuaikan juga
`/chatbot/api/.env`:

- `RERANK_BASE_URL=http://localhost:8082` (8081 untuk gte). API memakai
  jaringan host, jadi `localhost` langsung sampai ke port ini.
- `RERANK_API_KEY` diisi kunci model yang baru.
- `RERANK_MODEL` diisi nama model yang baru.
- `RERANK_THRESHOLD` dikosongkan lalu dikalibrasi ulang. Skala skor tiap model
  berbeda, jadi ambang untuk gte tidak berlaku untuk bge.

Lalu buat ulang container API supaya `.env` terbaca (`restart` saja tidak
cukup):

```bash
cd /chatbot && sudo docker compose up -d api
```

## Memakai model lain

Ganti `MODEL_ID` dan `SERVED_MODEL_NAME` di salah satu service, lalu jalankan
`sudo docker compose up -d <service>`. Compose membuat ulang container karena
konfigurasinya berubah.

- TEI hanya mendukung reranker berarsitektur XLM-RoBERTa, GTE, ModernBERT, dan
  CamemBERT. Reranker berbasis LLM seperti Qwen3-Reranker tidak jalan di sini.
- Pilih model multilingual, karena dokumen chatbot berbahasa Indonesia.
- Bobot model lama tetap tersimpan di volume. Hapus dengan
  `docker volume rm` bila tidak dipakai lagi.

## Perintah lain

| Keperluan | Perintah |
|---|---|
| Status | `sudo docker compose ps` |
| Log terakhir | `sudo docker compose logs --tail 50 gte` |
| Pemakaian CPU/RAM | `sudo docker stats --no-stream gte-reranker` |
| Matikan semua | `sudo docker compose down` (volume dan bobot model tetap) |
