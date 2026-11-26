# MinIO â€” S3-compatible object storage

Penyimpanan objek yang kompatibel dengan API Amazon S3, dijalankan sendiri di host ini.
Bisa dipakai oleh SDK S3 apa pun (boto3, aws-sdk, `@aws-sdk/client-s3`, Laravel Storage,
dan lain-lain) hanya dengan mengganti endpoint-nya.

## Isi folder

| File | Keterangan |
|---|---|
| `docker-compose.yml` | Service `minio` + service `init` sekali jalan |
| `.env` | Kredensial asli. **Jangan di-commit ke git.** Mode 600 |
| `.env.example` | Contoh untuk dibagikan, tanpa password asli |

## Kenapa image-nya `bitnamilegacy`, bukan `minio/minio`

MinIO sudah menutup distribusi publiknya. Per pengecekan terakhir:

| Sumber | Status |
|---|---|
| Docker Hub `minio/minio` | `404` â€” repo tidak ada lagi |
| `quay.io/minio/minio` | `401 Requires authentication`, termasuk tag `latest` |
| `dl.min.io` (binary) | `410 Gone` untuk semua versi |

Selain itu, sejak rilis **`RELEASE.2025-05-24T17-08-30Z`** MinIO memangkas web console-nya:
catatan rilis menyebut *"Embedded UI Console is now deprecated and moved to object-browser"*.
Versi setelah itu hanya menyisakan browser objek â€” manajemen user, policy, dan monitoring
hilang dari UI.

`bitnamilegacy/minio:2025.4.22` berisi **`RELEASE.2025-04-22T22-12-26Z`**, yaitu rilis
terakhir sebelum perubahan itu, jadi console-nya masih lengkap. Bitnami memindahkan semua
image komunitasnya ke namespace `bitnamilegacy` pada 2025 dan membekukannya di sana.

**Konsekuensinya: image ini tidak lagi menerima pembaruan keamanan.** Wajar untuk jaringan
internal atau Tailscale, tapi jangan dipakai jangka panjang untuk yang menghadap internet.
Lihat bagian "Kalau butuh yang terus diperbarui" di bawah.

## Catatan konvensi Bitnami

Image Bitnami berbeda dari image MinIO resmi:

- Jalan sebagai user **non-root UID 1001**
- Data di **`/bitnami/minio/data`**, bukan `/data`
- **Tidak perlu `command:`** â€” entrypoint-nya sendiri yang menjalankan server
- Mendukung `MINIO_DEFAULT_BUCKETS` untuk membuat bucket otomatis saat start

## Menjalankan

User `embed` belum masuk grup `docker`, jadi perlu `sudo`:

```bash
cd /s3
sudo docker compose up -d
sudo docker compose logs init      # pastikan bucket & user aplikasi terbuat
```

## Cara mengakses

| Jalur | Alamat |
|---|---|
| Tailscale | `100.111.178.48` â€” paling aman, hanya perangkat di tailnet |
| LAN | `172.16.83.240` |
| Internet | `103.135.24.89` â€” IP keluar, host di belakang NAT, perlu port forwarding |

- **Web console:** `http://100.111.178.48:9001` â€” login dengan `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
- **S3 API:** `http://100.111.178.48:9000` â€” dipakai aplikasi dan SDK

Lihat kredensial:

```bash
cat /s3/.env
```

Kalau alamat aksesnya berubah, sesuaikan `MINIO_SERVER_URL` dan `MINIO_CONSOLE_URL` di `.env`
lalu `sudo docker compose up -d`, supaya presigned URL yang dibuat console tetap benar.

## Konfigurasi di sisi aplikasi

```
endpoint         = http://100.111.178.48:9000
region           = us-east-1     # MinIO mengabaikan nilainya, tapi SDK sering mewajibkan
access_key       = app           # dari APP_ACCESS_KEY, bukan root
secret_key       = <APP_SECRET_KEY di .env>
bucket           = uploads
force_path_style = true          # WAJIB â€” MinIO tidak memakai virtual-host style
```

Contoh boto3:

```python
import boto3
s3 = boto3.client(
    "s3",
    endpoint_url="http://100.111.178.48:9000",
    aws_access_key_id="app",
    aws_secret_access_key="...",
    region_name="us-east-1",
)
s3.upload_file("file.pdf", "uploads", "file.pdf")
```

## Perintah sehari-hari

```bash
cd /s3

sudo docker compose ps
sudo docker compose logs -f minio
sudo docker compose restart minio
sudo docker compose down             # stop, data aman di volume
sudo docker compose down -v          # stop + HAPUS SEMUA OBJEK

# AWS CLI dari host mana pun
aws --endpoint-url http://100.111.178.48:9000 s3 ls
aws --endpoint-url http://100.111.178.48:9000 s3 cp file.pdf s3://uploads/
aws --endpoint-url http://100.111.178.48:9000 s3 sync ./folder s3://uploads/folder

# mc lewat container init (sekali pakai)
sudo docker compose run --rm --entrypoint sh init -c \
  "mc --config-dir /tmp/.mc alias set local http://minio:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD && \
   mc --config-dir /tmp/.mc ls local/uploads"
```

## Backup

Isi bucket ada di volume docker `s3_minio-data`.

```bash
# Cara paling sederhana: mirror ke folder lokal
aws --endpoint-url http://100.111.178.48:9000 s3 sync s3://uploads ./backup-uploads

# Atau salin seluruh volume
sudo docker run --rm -v s3_minio-data:/data -v "$PWD":/backup alpine \
  tar czf /backup/minio-data-$(date +%F).tar.gz -C /data .
```

## Keamanan

1. **Tidak ada HTTPS.** Kredensial dan isi objek lewat jaringan sebagai teks biasa. Lewat
   Tailscale sudah terenkripsi. Untuk jalur publik, pasang reverse proxy ber-TLS.

2. **Jangan pakai kredensial root di aplikasi.** Service `init` sudah membuat user `app`
   dengan policy `readwrite`. Untuk lebih ketat, buat policy JSON yang membatasi ke satu bucket.

3. **Docker menembus ufw.** Untuk membatasi akses hanya dari subnet Tailscale:

   ```bash
   sudo iptables -I DOCKER-USER -p tcp --dport 9000 ! -s 100.64.0.0/10 -j DROP
   sudo iptables -I DOCKER-USER -p tcp --dport 9001 ! -s 100.64.0.0/10 -j DROP
   sudo apt install -y iptables-persistent && sudo netfilter-persistent save
   ```

4. **Image beku, tanpa patch keamanan.** Jangan menaruh port 9000/9001 langsung di internet.

## Kalau butuh yang terus diperbarui

| Pilihan | Catatan |
|---|---|
| `chainguard/minio:latest` | MinIO versi kini, masih dirawat dan bebas di-pull. Console sudah versi pangkas, administrasi lewat `mc`. Tier gratis hanya menyediakan tag `latest` |
| Garage (`dxflrs/garage`) | Ringan (Rust), S3-compatible, tanpa masalah distribusi. Perlu `garage.toml` dan `garage layout assign` sekali di awal |
| SeaweedFS (`chrislusf/seaweedfs`) | S3-compatible, kuat untuk jumlah file sangat banyak |
| MinIO resmi | Perlu akun: `docker login quay.io` lalu tag resmi bisa dipakai lagi |

## Troubleshooting

| Masalah | Penyebab & solusi |
|---|---|
| `port is already allocated` | Port 9000/9001 dipakai proses lain. Ubah sisi kiri pemetaan port, misal `"19000:9000"` |
| Container `init` gagal | Ia menunggu minio sehat. Cek `sudo docker compose logs minio` |
| `SignatureDoesNotMatch` | Hampir selalu karena `force_path_style` belum diaktifkan di SDK |
| Console bisa login tapi link download salah alamat | `MINIO_SERVER_URL` di `.env` belum sesuai alamat yang kamu pakai |
| Ganti password di `.env` tidak berlaku | Password root hanya dibaca saat start. Jalankan `sudo docker compose up -d` agar container dibuat ulang. Untuk user `app`, ubah lewat `mc admin user` |
| Mulai dari nol | `sudo docker compose down -v` lalu `up -d`. Semua objek hilang |
