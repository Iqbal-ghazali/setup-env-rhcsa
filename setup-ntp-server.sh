#!/bin/bash
# =============================================================================
# setup-ntp-server.sh
# Setup NTP Server di Controller Node untuk Lab RHCSA EX200
#
# Controller : Rocky Linux 9
# IP Lab     : 172.24.10.100 (eth1)
# Hostname   : utility.example.com
#
# Node1/Node2 sync NTP ke utility.example.com (Q7)
#
# Pembelajaran:
# [1] chrony versi baru tidak otomatis listen di port 123
#     harus eksplisit tambahkan 'port 123' di chrony.conf
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
step() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $*${NC}"
    echo -e "${BOLD}════════════════════════════════════════════${NC}"
}

[[ $EUID -ne 0 ]] && die "Jalankan sebagai root."

LAB_NETWORK="172.24.10.0/24"
CONTROLLER_IP="172.24.10.100"

# =============================================================================
step "STEP 1 — Install chrony"
# =============================================================================
info "Install chrony..."
dnf install -y chrony
[[ $? -ne 0 ]] && die "Gagal install chrony."
ok "chrony terinstall."

# =============================================================================
step "STEP 2 — Konfigurasi chrony sebagai NTP server"
# =============================================================================
info "Backup konfigurasi chrony lama..."
cp /etc/chrony.conf /etc/chrony.conf.bak

info "Tulis konfigurasi chrony baru..."
cat > /etc/chrony.conf << EOF
# =============================================================
# /etc/chrony.conf — RHCSA Lab NTP Server
# Controller: utility.example.com (${CONTROLLER_IP})
# =============================================================

# Sync dari upstream NTP public
pool 2.rocky.pool.ntp.org iburst

# Eksplisit listen di port 123 (wajib di chrony versi baru)
port 123

# Izinkan node di network lab untuk sync ke controller ini
allow ${LAB_NETWORK}

# Jika tidak ada upstream, gunakan local clock sebagai fallback
local stratum 10

# File untuk menyimpan drift
driftfile /var/lib/chrony/drift

# Log
logdir /var/log/chrony

# Makestep: langsung adjust jika offset > 1 detik (max 3x saat startup)
makestep 1.0 3

# RTC
rtcsync
EOF

ok "Konfigurasi chrony ditulis."

# =============================================================================
step "STEP 3 — Enable & start chronyd"
# =============================================================================
systemctl enable --now chronyd
systemctl restart chronyd
systemctl is-active --quiet chronyd || die "chronyd gagal start. Cek: journalctl -xe"
ok "chronyd aktif."

# =============================================================================
step "STEP 4 — Set hostname & /etc/hosts"
# =============================================================================
hostnamectl set-hostname utility.example.com
ok "Hostname di-set ke: utility.example.com"

if ! grep -q "utility.example.com" /etc/hosts; then
    echo "${CONTROLLER_IP} utility.example.com utility" >> /etc/hosts
    ok "Entry utility.example.com ditambahkan ke /etc/hosts."
else
    ok "Entry utility.example.com sudah ada di /etc/hosts."
fi

# =============================================================================
step "STEP 5 — Verifikasi port 123 listening"
# =============================================================================
sleep 2
info "Cek port 123 UDP..."
ss -ulnp | grep 123 && ok "Port 123 sudah listen." || warn "Port 123 belum listen!"

info "Status sumber NTP controller:"
chronyc sources -v 2>/dev/null | head -20

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║          NTP SERVER — SETUP SELESAI ✓                   ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  NTP Server : utility.example.com (${CONTROLLER_IP})"
echo -e "${BOLD}${GREEN}║${NC}  Port       : 123/udp"
echo -e "${BOLD}${GREEN}║${NC}  Allow      : ${LAB_NETWORK}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Setup di node1 / node2 (Q7):"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}echo '${CONTROLLER_IP} utility.example.com' >> /etc/hosts${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}vim /etc/chrony.conf${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}  -> tambah: server utility.example.com iburst${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}systemctl enable --now chronyd${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}chronyc sources -v${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
