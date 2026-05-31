#!/bin/bash
# =============================================================================
# setup-container-registry.sh
# Setup Container Registry di Controller Node untuk Lab RHCSA EX200
#
# Controller : Rocky Linux 9
# IP Lab     : 172.24.10.100 (eth1)
# Hostname   : registry.lab.example.com
#
# Soal Q9:
#   - Login ke registry.lab.example.com
#   - Credentials: admin / redhat321
#
# Pakai HTTP (insecure) — node tidak perlu copy cert, langsung bisa login
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

CONTROLLER_IP="172.24.10.100"
REGISTRY_HOSTNAME="registry.lab.example.com"
REGISTRY_PORT="5000"
REGISTRY_USER="admin"
REGISTRY_PASS="redhat321"
REGISTRY_DIR="/opt/registry"

# =============================================================================
step "STEP 1 — Install podman & httpd-tools"
# =============================================================================
info "Install podman & httpd-tools..."
dnf install -y podman httpd-tools
[[ $? -ne 0 ]] && die "Gagal install podman/httpd-tools."
ok "podman & httpd-tools terinstall."

# =============================================================================
step "STEP 2 — Buat struktur direktori registry"
# =============================================================================
info "Buat direktori registry..."
rm -rf "${REGISTRY_DIR}"
mkdir -p "${REGISTRY_DIR}"/{data,auth}
ok "Direktori registry siap: ${REGISTRY_DIR}"

# =============================================================================
step "STEP 3 — Buat credentials (htpasswd)"
# =============================================================================
info "Generate htpasswd untuk user ${REGISTRY_USER}..."
htpasswd -Bbn "${REGISTRY_USER}" "${REGISTRY_PASS}" > "${REGISTRY_DIR}/auth/htpasswd"
[[ $? -ne 0 ]] && die "Gagal generate htpasswd."
ok "Credentials dibuat."

# =============================================================================
step "STEP 4 — Pull image registry:2"
# =============================================================================
info "Pull docker.io/library/registry:2..."
podman pull docker.io/library/registry:2
[[ $? -ne 0 ]] && die "Gagal pull registry image. Cek koneksi internet."
ok "Image registry:2 siap."

# =============================================================================
step "STEP 5 — Jalankan container registry (HTTP/insecure)"
# =============================================================================
info "Stop & hapus container lama jika ada..."
podman rm -f registry-lab 2>/dev/null || true

info "Jalankan container registry tanpa TLS (HTTP)..."
podman run -d \
    --name registry-lab \
    -p ${REGISTRY_PORT}:5000 \
    -v "${REGISTRY_DIR}/data:/var/lib/registry:z" \
    -v "${REGISTRY_DIR}/auth:/auth:z" \
    -e REGISTRY_AUTH=htpasswd \
    -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    docker.io/library/registry:2

[[ $? -ne 0 ]] && die "Gagal menjalankan container registry."
ok "Container registry-lab berjalan di port ${REGISTRY_PORT} (HTTP)."

# =============================================================================
step "STEP 6 — Konfigurasi podman insecure registry di CONTROLLER"
# =============================================================================
info "Tambahkan insecure registry di controller..."
mkdir -p /etc/containers
cat > /etc/containers/registries.conf.d/rhcsa-lab.conf << EOF
[[registry]]
location = "${REGISTRY_HOSTNAME}:${REGISTRY_PORT}"
insecure = true

[[registry]]
location = "${CONTROLLER_IP}:${REGISTRY_PORT}"
insecure = true
EOF
ok "Insecure registry dikonfigurasi di controller."

# =============================================================================
step "STEP 7 — Buat systemd service supaya registry auto-start"
# =============================================================================
info "Buat systemd service untuk registry..."
cat > /etc/systemd/system/registry-lab.service << EOF
[Unit]
Description=RHCSA Lab Container Registry
Wants=network-online.target
After=network-online.target

[Service]
Restart=always
ExecStart=/usr/bin/podman start -a registry-lab
ExecStop=/usr/bin/podman stop -t 10 registry-lab

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable registry-lab.service
ok "Systemd service registry-lab dibuat & enabled."

# =============================================================================
step "STEP 8 — Tambahkan /etc/hosts entry di controller"
# =============================================================================
if ! grep -q "${REGISTRY_HOSTNAME}" /etc/hosts; then
    echo "${CONTROLLER_IP} ${REGISTRY_HOSTNAME}" >> /etc/hosts
    ok "Entry ${REGISTRY_HOSTNAME} ditambahkan ke /etc/hosts controller."
else
    ok "Entry ${REGISTRY_HOSTNAME} sudah ada."
fi

# =============================================================================
step "STEP 9 — Buka firewall port registry"
# =============================================================================
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=${REGISTRY_PORT}/tcp
    firewall-cmd --reload
    ok "Firewall: port ${REGISTRY_PORT}/tcp dibuka."
else
    warn "firewalld tidak aktif — skip."
fi

# =============================================================================
step "STEP 10 — Verifikasi registry dari controller"
# =============================================================================
sleep 3
info "Test login dari controller..."
podman login \
    --username "${REGISTRY_USER}" \
    --password "${REGISTRY_PASS}" \
    --tls-verify=false \
    "${REGISTRY_HOSTNAME}:${REGISTRY_PORT}" \
    && ok "Login ke registry berhasil ✓" \
    || warn "Login gagal. Tunggu beberapa detik & coba lagi."

info "Test catalog API..."
curl -sf -u "${REGISTRY_USER}:${REGISTRY_PASS}" \
    "http://${REGISTRY_HOSTNAME}:${REGISTRY_PORT}/v2/_catalog" \
    && echo "" || warn "Catalog API tidak respond."

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║        CONTAINER REGISTRY — SETUP SELESAI ✓                 ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Registry : ${CYAN}${REGISTRY_HOSTNAME}:${REGISTRY_PORT}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Mode     : HTTP (insecure — tidak perlu cert)"
echo -e "${BOLD}${GREEN}║${NC}  Username : ${REGISTRY_USER}"
echo -e "${BOLD}${GREEN}║${NC}  Password : ${REGISTRY_PASS}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Setup di node1 / node2 — cukup 3 langkah:"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# 1. Tambah hosts mapping${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}echo '${CONTROLLER_IP} ${REGISTRY_HOSTNAME}' >> /etc/hosts${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# 2. Tambah insecure registry di node${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}cat > /etc/containers/registries.conf.d/rhcsa-lab.conf << 'EOF'${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}[[registry]]${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}location = \"${REGISTRY_HOSTNAME}:${REGISTRY_PORT}\"${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}insecure = true${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}EOF${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# 3. Login (Q9)${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}podman login ${REGISTRY_HOSTNAME}:${REGISTRY_PORT}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}  Username: ${REGISTRY_USER}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}  Password: ${REGISTRY_PASS}${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
