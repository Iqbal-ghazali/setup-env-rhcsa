#!/bin/bash
# =============================================================================
# setup-containerfile.sh
# Setup HTTP server untuk serve Containerfile di Controller Node
# Lab RHCSA EX200
#
# Controller : Rocky Linux 9
# IP Lab     : 172.24.10.100 (eth1)
# Hostname   : utility.example.com
#
# Soal Q9:
#   - Buat container image dari:
#     http://utility.example.com/container/Containerfile
#   - Named 'monitor' dengan user athena
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
CONTAINER_DIR="/var/www/html/container"
CONTAINERFILE_URL="http://${CONTROLLER_IP}/container/Containerfile"

# =============================================================================
step "STEP 1 — Pastikan httpd terinstall & aktif"
# =============================================================================
info "Cek httpd..."
if ! rpm -q httpd &>/dev/null; then
    info "httpd belum terinstall, install sekarang..."
    dnf install -y httpd || die "Gagal install httpd."
fi

systemctl enable --now httpd
systemctl is-active --quiet httpd || die "httpd tidak aktif. Cek: journalctl -xe"
ok "httpd aktif."

# =============================================================================
step "STEP 2 — Buat direktori /container"
# =============================================================================
info "Buat direktori ${CONTAINER_DIR}..."
mkdir -p "${CONTAINER_DIR}"
ok "Direktori siap."

# =============================================================================
step "STEP 3 — Buat Containerfile"
# =============================================================================
# Containerfile ini sesuai konteks soal Q9 & Q10:
# - Base image: ubi8 (Red Hat Universal Base Image)
# - Install logwatch untuk monitoring (sesuai nama image 'monitor')
# - Buat user athena
# - Expose direktori /opt/incoming & /opt/outgoing untuk volume mapping Q10
info "Tulis Containerfile ke ${CONTAINER_DIR}/Containerfile..."

cat > "${CONTAINER_DIR}/Containerfile" << 'EOF'
FROM ubi8/ubi:latest

# Install package yang dibutuhkan
RUN yum install -y logwatch && \
    yum clean all

# Buat user athena
RUN useradd -ms /bin/bash athena

# Buat direktori untuk volume mapping (Q10)
RUN mkdir -p /opt/incoming /opt/outgoing && \
    chown athena:athena /opt/incoming /opt/outgoing

# Set user
USER athena

# Working directory
WORKDIR /home/athena

CMD ["/bin/bash"]
EOF

ok "Containerfile ditulis."
info "Isi Containerfile:"
echo "---"
cat "${CONTAINER_DIR}/Containerfile"
echo "---"

# =============================================================================
step "STEP 4 — Set permission & SELinux context"
# =============================================================================
chown -R apache:apache "${CONTAINER_DIR}"
chmod -R 755 "${CONTAINER_DIR}"

semanage fcontext -a -t httpd_sys_content_t "${CONTAINER_DIR}(/.*)?" 2>/dev/null \
    || semanage fcontext -m -t httpd_sys_content_t "${CONTAINER_DIR}(/.*)?" 2>/dev/null \
    || warn "semanage gagal, coba restorecon saja..."
restorecon -Rv "${CONTAINER_DIR}" > /dev/null 2>&1
ok "Permission & SELinux context OK."

# =============================================================================
step "STEP 5 — Verifikasi Containerfile bisa diakses via HTTP"
# =============================================================================
sleep 1
info "Test akses: ${CONTAINERFILE_URL}"
if curl -sf "${CONTAINERFILE_URL}" > /dev/null; then
    ok "Containerfile bisa diakses via HTTP ✓"
else
    warn "Containerfile tidak bisa diakses! Cek httpd & SELinux."
    warn "Debug: curl -v ${CONTAINERFILE_URL}"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║         CONTAINERFILE SERVER — SETUP SELESAI ✓              ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  URL : ${CYAN}${CONTAINERFILE_URL}${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Jawaban Q9 di node1:"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# Login sebagai user athena${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}su - athena${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# Download Containerfile${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}curl -O http://utility.example.com/container/Containerfile${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# Build image bernama 'monitor'${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}podman build -t monitor .${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# Verifikasi${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}podman images${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Jawaban Q10 di node1 (rootless container + systemd):"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# Buat direktori volume di host${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}mkdir -p /opt/files /opt/processed${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# Jalankan container ascii2pdf${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}podman run -d --name ascii2pdf \\${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}  -v /opt/files:/opt/incoming:Z \\${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}  -v /opt/processed:/opt/outgoing:Z \\${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}  monitor${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}# Generate systemd service${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}mkdir -p ~/.config/systemd/user${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}podman generate systemd --name ascii2pdf --files --new${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}mv container-ascii2pdf.service ~/.config/systemd/user/${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}systemctl --user daemon-reload${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}systemctl --user enable --now container-ascii2pdf.service${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}loginctl enable-linger athena${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
