#!/usr/bin/env bash
# Deploy ulang chatbot (admin + api + client) dari kode terbaru di GitHub:
#
#   bash /chatbot/start.sh
#
# Urutannya sengaja: tarik kode -> build SEMUA image -> baru ganti container.
# Bila satu build gagal, skrip berhenti dan container lama tetap melayani.
# Versi lama menjalankan `down` lebih dulu lalu tetap lanjut walau build gagal,
# sehingga image lama terpakai lagi tanpa ada yang sadar.
set -euo pipefail

cd /chatbot

# Disk root host ini sempit: satu build Next.js memakan ~2,5GB sementara.
MIN_FREE_GB=3

bersihkan_cache() {
    sudo docker builder prune -af >/dev/null
}

cek_disk() {
    local free_gb
    free_gb=$(df --output=avail -BG / | tail -1 | tr -dc 0-9)
    if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
        echo "!! Disk tinggal ${free_gb}GB (< ${MIN_FREE_GB}GB); deploy dihentikan, container lama tetap berjalan." >&2
        exit 1
    fi
    echo "   disk kosong: ${free_gb}GB"
}

echo "== Tarik kode terbaru"
for repo in admin api client; do
    sudo git -C "/chatbot/$repo" pull --ff-only
done

# Build satu per satu: `compose build` untuk semua service membatalkan service
# lain begitu satu gagal. Diulang karena build client mengambil font dari Google
# Fonts dan DNS di host ini kadang lambat.
build() {
    local svc=$1 attempt
    for attempt in 1 2 3; do
        cek_disk
        echo "== Build $svc (percobaan $attempt/3)"
        if sudo docker compose build --pull "$svc"; then
            return 0
        fi
        bersihkan_cache
        sleep 15
    done
    echo "!! Build $svc gagal 3 kali; container lama tetap berjalan." >&2
    return 1
}

echo "== Bersihkan cache build dan image tak terpakai"
bersihkan_cache
sudo docker image prune -f >/dev/null
for svc in api admin client; do
    build "$svc"
    # Cache tidak dibutuhkan lagi setelah image jadi; lepaskan sebelum build berikutnya.
    bersihkan_cache
done

echo "== Ganti container"
sudo docker compose up -d --remove-orphans

echo "== Cek kesehatan"
sehat=
for _ in $(seq 1 45); do
    if curl -sf -m 3 -o /dev/null http://localhost:8000/health; then
        sehat=1
        break
    fi
    sleep 2
done
if [ -z "$sehat" ]; then
    echo "!! api tidak sehat setelah 90 detik:" >&2
    sudo docker compose logs --tail 40 api >&2
    exit 1
fi
for port in 3000 3001; do
    curl -sf -m 10 -o /dev/null "http://localhost:$port/" \
        || { echo "!! port $port tidak menjawab" >&2; exit 1; }
done
echo "api, admin, client sehat"

echo "== Hapus image versi lama"
sudo docker image prune -f >/dev/null
cek_disk
