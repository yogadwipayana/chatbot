# Postgres (pgvector) + pgweb

Stack Docker Compose berisi **PostgreSQL 16 dengan extension pgvector** dan **pgweb**,
antarmuka web untuk menjelajah database (mirip phpMyAdmin, tapi untuk Postgres).
Keduanya dibuka ke jaringan supaya bisa diakses dari komputer lain.

## Isi folder

| File | Keterangan |
|---|---|
| `docker-compose.yml` | Definisi kedua service |
| `.env` | Kredensial asli. **Jangan di-commit ke git.** Mode 600 |
| `.env.example` | Contoh isi `.env` untuk dibagikan |
| `initdb/` | Opsional. File `.sql`/`.sh` di sini jalan otomatis saat database pertama kali dibuat |

## Menjalankan

User `embed` belum masuk grup `docker`, jadi perlu `sudo`:

```bash
cd /postgres
sudo docker compose up -d
sudo docker compose ps
```

Supaya tidak perlu `sudo` lagi (harus logoutâ€“login setelahnya):

```bash
sudo usermod -aG docker embed
```

## Cara mengakses

Host ini punya beberapa alamat:

| Jalur | Alamat | Catatan |
|---|---|---|
| Tailscale | `100.111.178.48` | Paling aman. Hanya perangkat di tailnet yang bisa masuk |
| LAN | `172.16.83.240` | Untuk komputer di jaringan lokal yang sama |
| Internet | `103.135.24.89` | Ini IP keluar. Host ada di belakang NAT, jadi perlu port forwarding di router dulu |

**pgweb** â€” buka di browser:

```
http://100.111.178.48:5050
```

Akan muncul kotak login (HTTP basic auth). Isi dengan `PGWEB_AUTH_USER` dan
`PGWEB_AUTH_PASS` dari `.env`.

**Postgres langsung** â€” dari psql, DBeaver, TablePlus, atau aplikasi:

```bash
psql "postgres://app:PASSWORD@100.111.178.48:5432/appdb"
```

Lihat password:

```bash
cat /postgres/.env
```

## Perintah sehari-hari

```bash
cd /postgres

sudo docker compose ps                 # status & health
sudo docker compose logs -f pgweb      # log pgweb
sudo docker compose logs -f db         # log postgres
sudo docker compose restart pgweb      # restart satu service
sudo docker compose pull && sudo docker compose up -d   # update image

# psql di dalam container
sudo docker compose exec db psql -U app -d appdb

sudo docker compose down               # stop, data tetap aman di volume
sudo docker compose down -v            # stop + HAPUS SEMUA DATA
```

## Backup & restore

```bash
# Backup (format custom, terkompresi)
sudo docker compose exec -T db pg_dump -U app -Fc appdb > appdb-$(date +%F).dump

# Restore ke database kosong
cat appdb-2026-09-26.dump | sudo docker compose exec -T db pg_restore -U app -d appdb --clean
```

## pgvector

Image dipatok ke tag `0.8.6-pg16`, yaitu **pgvector 0.8.6 di atas Postgres 16** â€” versi
extension yang sama dengan Postgres di server 43.157.204.85, jadi dump dari sana pasti cocok.
Tag `pg16` tanpa nomor versi sengaja dihindari karena ikut berubah saat pgvector rilis baru.

Extension tinggal diaktifkan sekali per database:

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE items (
  id        bigserial PRIMARY KEY,
  embedding vector(384)
);

-- Index untuk pencarian kemiripan
CREATE INDEX ON items USING hnsw (embedding vector_l2_ops);

-- Cari 5 tetangga terdekat
SELECT id FROM items ORDER BY embedding <-> '[0.1, 0.2, ...]' LIMIT 5;
```

Operator jarak: `<->` (L2), `<=>` (cosine), `<#>` (inner product).

## Keamanan â€” penting

1. **Tidak ada HTTPS.** Login pgweb dan isi query lewat jaringan sebagai teks biasa.
   Untuk jalur publik, taruh di belakang reverse proxy ber-TLS (Caddy/nginx) atau
   Cloudflare Tunnel. Lewat Tailscale sudah terenkripsi, jadi relatif aman.

2. **Port 5432 yang terbuka ke internet akan dipindai dan dibrute-force.** Password di
   `.env` dibuat acak 36 karakter â€” jangan diganti dengan yang mudah ditebak.

3. **Docker menembus ufw.** Aturan `ufw deny` tidak berlaku untuk port yang
   dipublikasikan Docker. Untuk membatasi ke IP tertentu, pakai chain `DOCKER-USER`:

   ```bash
   # izinkan hanya dari subnet Tailscale
   sudo iptables -I DOCKER-USER -p tcp --dport 5432 ! -s 100.64.0.0/10 -j DROP
   sudo iptables -I DOCKER-USER -p tcp --dport 5050 ! -s 100.64.0.0/10 -j DROP

   # simpan agar bertahan setelah reboot
   sudo apt install -y iptables-persistent && sudo netfilter-persistent save
   ```

4. **Mode lihat-saja** untuk pgweb, kalau tidak perlu mengubah data. Tambahkan di
   service `pgweb`:

   ```yaml
   command: ["--readonly", "--bind=0.0.0.0", "--listen=8081"]
   ```

5. **Tidak perlu akses Postgres dari luar?** Hapus blok `ports:` pada service `db`.
   pgweb tetap jalan karena memakai jaringan internal docker.

## Troubleshooting

| Masalah | Penyebab & solusi |
|---|---|
| `port is already allocated` | Port 5432/5050 dipakai proses lain. Cek `sudo ss -ltnp \| grep 5432`, lalu ubah sisi kiri pemetaan port, misal `"15432:5432"` |
| pgweb tidak mau start | Ia menunggu `db` sehat. Cek `sudo docker compose ps` dan `sudo docker compose logs db` |
| Password diubah tapi tidak berlaku | Password database hanya dibuat saat volume pertama kali diisi. Mengubah `.env` setelah itu tidak mengubah password lama. Ubah lewat SQL: `ALTER USER app PASSWORD '...';` |
| Ingin mulai dari nol | `sudo docker compose down -v` lalu `up -d`. Semua data hilang |
| Koneksi dari luar timeout | Cek dari host dulu: `curl -I http://localhost:5050`. Kalau di host jalan tapi dari luar tidak, berarti firewall, aturan `DOCKER-USER`, atau NAT/port forwarding |
