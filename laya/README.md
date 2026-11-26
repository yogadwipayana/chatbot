# Laya — server keputusan lokal (pengganti JEV)

[Laya](https://github.com/NandhaKishorM/laya) adalah model keputusan *open-weight*
(Apache 2.0) dari Convai Innovations. Model ini tidak menghasilkan teks: ia menjawab
pertanyaan bertipe (`choice`, `score`, `noul`) beserta probabilitasnya dalam satu
forward pass. `laya-serve` menyediakan `POST /v1/systemone` dengan format request dan
response yang sama dengan TypeSafe JEV, jadi gate chatbot bisa diarahkan ke sini hanya
lewat env.

Compose ini hanya memuat checkpoint **`laya-multilingual`** (mmBERT-base, 322M, konteks
1.024 token), karena pesan mahasiswa berbahasa Indonesia.

| File | Isi |
|---|---|
| `docker-compose.yml` | Service `laya` (container `laya-decision`), volume `laya-data`, jaringan `laya-network`. Berdiri sendiri: tidak bergantung pada compose lain |
| `.env.example` | Template `.env`: `LAYA_API_KEY` wajib, sisanya opsional |
| `README.md` | Dokumen ini |

## Status (2026-09-30)

**Belum pernah di-build atau dijalankan di host ini.** Risiko terbesar: CPU host
(`QEMU Virtual CPU version 2.5+`) **tidak punya AVX/AVX2/FMA**, hanya sampai SSE4.2.
Container `headroom` di `/9router` sudah mati dengan exit code 132 (*Illegal
instruction*) karena hal ini. Torch bisa bernasib sama, jadi jalankan langkah 1 dulu.

## 1. Tes torch di CPU ini (wajib, sebelum build)

Tes murah (unduhan ±200 MB, tidak meninggalkan container):

```bash
sudo docker run --rm python:3.11-slim-bookworm sh -c '
  pip install -q torch==2.14.0 --index-url https://download.pytorch.org/whl/cpu &&
  python -c "import torch; print(torch.__version__, torch.backends.cpu.get_cpu_capability());
x = torch.randn(256, 256); print(float((x @ x).sum()))"'
echo "exit=$?"
sudo docker image rm python:3.11-slim-bookworm
```

- `exit=0` dan tercetak `DEFAULT` → torch jalan (tanpa kernel AVX, jadi lebih lambat
  dari angka vendor). Lanjut ke langkah 2.
- `exit=132` → torch tidak didukung CPU ini. **Berhenti di sini**; Laya tidak bisa
  jalan di host ini.

## 2. Setup

```bash
cd /laya
sudo cp .env.example .env
sudo chmod 600 .env
openssl rand -hex 32          # salin hasilnya
sudo nano .env                # isi LAYA_API_KEY=<hasil di atas>

sudo docker compose build     # build dari github.com/NandhaKishorM/laya @ LAYA_GIT_REF
sudo docker compose up -d
sudo docker compose logs -f   # tunggu sampai uvicorn listen; unduh bobot pertama kali
```

Disk: image ±1,5 GB + bobot ±1,3 GB + cache build. Sisa disk host saat ditulis hanya
±4,8 GB (84%). Setelah build selesai:

```bash
sudo docker builder prune -f
df -h /
```

Kalau langkah build gagal di `check_torch.py` dengan `Illegal instruction`, artinya
sama dengan exit 132 di langkah 1.

## 3. Cek

```bash
sudo docker compose ps                       # harus (healthy)
curl -s localhost:8001/health                # {"status":"ok","loaded":[...],...}
sudo docker stats --no-stream laya-decision  # pemakaian RAM nyata
```

Contoh request, bentuknya sama dengan yang dikirim gate chatbot:

```bash
KEY=$(sudo grep '^LAYA_API_KEY=' /laya/.env | cut -d= -f2)
curl -s localhost:8001/v1/systemone \
  -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"multilingual",
       "state":{"body":"cara bayar UKT lewat VA"},
       "questions":{"topik":{"type":"choice","instructions":"Topik pesan?",
         "criteria":{"akademik":"kuliah, UKT, KRS, jadwal","lain":"di luar urusan kampus"}}}}'
```

Tanpa header `Authorization` → 401. `/health` memang tidak memakai auth.

Jika container restart terus dengan exit 137 (OOM), naikkan `LAYA_MEM_LIMIT` di `.env`
(misalnya `3584m`), lalu `sudo docker compose up -d`.

## 4. Sambungkan ke chatbot-api

Tidak perlu mengubah kode; `app/rag/gate.py` sudah membaca env berikut. Tambahkan di
`/chatbot/api/.env`:

```
JEV_URL=http://127.0.0.1:8001/v1/systemone
JEV_MODEL=multilingual
JEV_API_KEY=<sama dengan LAYA_API_KEY>
```

Lalu buat ulang container api (restart saja tidak membaca ulang `env_file`):

```bash
cd /chatbot && sudo docker compose up -d api
```

- `JEV_MODEL=multilingual` wajib. Tanpa itu Laya memilih checkpoint sendiri, dan teks
  Indonesia (huruf Latin) bisa jatuh ke checkpoint Inggris.
- chatbot-api memakai `network_mode: host`, jadi `127.0.0.1:8001` terjangkau.
- **Kembali ke JEV:** hapus tiga baris di atas, lalu `sudo docker compose up -d api`
  lagi. Default-nya kembali ke `<BASE_URL>/systemone` lewat gateway.
- **Kalibrasi ulang dulu.** `JEV_BLOCK_THRESHOLD=0.7` dan `JEV_OUT_OF_SCOPE_THRESHOLD=0.9`
  dikalibrasi untuk JEV. Uji ulang dengan 64 pesan berlabel (`jev.md` §8) sebelum
  dipakai mahasiswa.
- Server melayani request **satu per satu** (satu worker + lock). Chat yang bersamaan
  mengantre dan bisa melewati `JEV_TIMEOUT_SECONDS`; gate akan *fail-open*.

## Operasional

```bash
cd /laya
sudo docker compose logs --tail 100          # log
sudo docker compose restart                  # restart (env tidak dibaca ulang)
sudo docker compose up -d                    # terapkan perubahan .env
```

**Ganti versi Laya:** ubah `LAYA_GIT_REF` di `.env` (tag atau commit SHA; daftar tag:
`git ls-remote --tags https://github.com/NandhaKishorM/laya.git`), lalu
`sudo docker compose build && sudo docker compose up -d && sudo docker builder prune -f`.

**Mode offline:** setelah bobot ada di volume `laya-data`, isi `HF_HUB_OFFLINE=1` di
`.env` lalu `sudo docker compose up -d`, supaya restart tidak bergantung pada HF Hub.

**Copot total:**

```bash
cd /laya
sudo docker compose down
sudo docker volume rm laya-data
sudo docker image rm laya-serve:local
sudo docker builder prune -f
```

Setelah itu kembalikan `/chatbot/api/.env` seperti semula (lihat langkah 4).

## Kenapa konfigurasinya begini

| Setelan | Alasan |
|---|---|
| Build dari git, bukan `image:` | Upstream tidak menerbitkan image di registry |
| `LAYA_MODELS=multilingual`, `LAYA_MAX_LOADED=1` | Hanya satu checkpoint di RAM; checkpoint Inggris (421M) tidak ikut dimuat |
| `LAYA_CPU_AMP` kosong | Inferensi float32; bf16 di CPU tanpa AVX hanya emulasi dan lambat |
| `127.0.0.1:8001` | Host `:8000` dipakai chatbot-api; loopback agar tidak terbuka ke LAN 172.16.83.0/24 atau Tailscale (ufw tidak aktif) |
| `mem_limit` = `memswap_limit` | OOM tetap di dalam container, tidak mematikan pg/9router/api seperti kasus bge-reranker (2026-09-29) |
| `cpus`/`LAYA_THREADS` = 4 | Host 10 vCPU dipakai bersama pg, e5, api |
| Jaringan sendiri (`laya-network`), bukan `pandu-network` | Berdiri sendiri: bisa `up`/`down` tanpa `/9router`. chatbot-api menjangkau Laya lewat `127.0.0.1:8001`, jadi jaringan bersama tidak diperlukan |
| `LAYA_API_KEY` wajib | Port loopback tetap bisa diakses semua proses di host, termasuk container `network_mode: host` |

Angka dari vendor (belum diverifikasi di sini): ±33 ms per request di GPU T4, 193–464 ms
di CPU dengan AVX. Blog pembanding dari pihak JEV melaporkan hasil sebaliknya (JEV 74,4
vs Laya 54,4), jadi andalkan hasil kalibrasi sendiri.

Referensi: repo [NandhaKishorM/laya](https://github.com/NandhaKishorM/laya)
(`compose.http.yaml`, `Dockerfile`, `laya/serve.py`), model
[convaiinnovations/laya](https://huggingface.co/convaiinnovations/laya).
