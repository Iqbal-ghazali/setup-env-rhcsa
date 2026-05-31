#!/bin/bash
# =============================================================================
# rhcsa-localrepo-v4.sh
# Setup Local YUM Repository untuk Lab RHCSA EX200
# Controller : Rocky Linux 9
# IP Lab     : 172.24.10.100 (eth1)
#
# URL repo (sesuai format soal RHCSA Q2):
#   http://172.24.10.100/rhel9/x86_64/dvd/BaseOS
#   http://172.24.10.100/rhel9/x86_64/dvd/AppStream
#
# Di node1/node2 cukup:
#   dnf config-manager --add-repo http://172.24.10.100/rhel9/x86_64/dvd/BaseOS
#   dnf config-manager --add-repo http://172.24.10.100/rhel9/x86_64/dvd/AppStream
#   echo gpgcheck=0 >> /etc/yum.repos.d/*BaseOS*
#   echo gpgcheck=0 >> /etc/yum.repos.d/*AppStream*
#   dnf clean all && dnf makecache
#
# Pembelajaran dari iterasi sebelumnya:
# [1] JANGAN pakai --disablerepo/--enablerepo saat dnf download
#     httpd ada di AppStream, bukan BaseOS — dnf gagal resolve kalau dibatasi
# [2] JANGAN set -euo pipefail — script mati terlalu dini saat warning kecil
# [3] SELALU validasi RPM count > 0 sebelum lanjut ke createrepo
# [4] JANGAN hardcode nama repo upstream — auto-detect dari dnf repolist
# [5] Download semua ke satu staging dir, copy ke BaseOS & AppStream
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

# =============================================================================
# GUARD
# =============================================================================
[[ $EUID -ne 0 ]] && die "Script harus dijalankan sebagai root."

# =============================================================================
# KONFIGURASI
# =============================================================================
CONTROLLER_IP="172.24.10.100"

# URL path sesuai format soal RHCSA Q2
REPO_ROOT="/var/www/html/rhel9/x86_64/dvd"
BASEOS_DIR="${REPO_ROOT}/BaseOS"
APPSTREAM_DIR="${REPO_ROOT}/AppStream"
STAGING_DIR="/var/tmp/rhcsa-repo-staging"

BASEOS_URL="http://${CONTROLLER_IP}/rhel9/x86_64/dvd/BaseOS"
APPSTREAM_URL="http://${CONTROLLER_IP}/rhel9/x86_64/dvd/AppStream"

# =============================================================================
# PACKAGE LIST — tidak dibedakan BaseOS/AppStream
# Pembelajaran [1]: biarkan dnf resolve sendiri dari semua repo aktif
# =============================================================================
PACKAGES=(
    # Web server (Q3)
    httpd httpd-tools mod_ssl
    # NFS & AutoFS (Q8)
    nfs-utils autofs
    # NTP (Q7)
    chrony
    # System tuning (Q20)
    tuned
    # Storage & LVM (Q17, Q18, Q19)
    lvm2 parted gdisk
    # Dictionary (Q13)
    words
    # Firewall
    firewalld
    # SELinux (Q3)
    policycoreutils policycoreutils-python-utils
    selinux-policy selinux-policy-targeted
    setroubleshoot-server setools-console
    # Container (Q9, Q10)
    podman container-selinux containers-common
    crun fuse-overlayfs slirp4netns
    # Utilities
    bash-completion vim-enhanced vim-minimal
    tree wget curl rsync tar bzip2 xz zip unzip
    bind-utils net-tools iproute
    less psmisc man-pages dracut grub2-tools
)

# =============================================================================
step "STEP 1 — Install tools yang dibutuhkan"
# =============================================================================
info "Install: httpd createrepo_c yum-utils firewalld policycoreutils-python-utils"
dnf install -y httpd createrepo_c yum-utils firewalld policycoreutils-python-utils
[[ $? -ne 0 ]] && die "Gagal install tools. Cek koneksi internet."
ok "Tools siap."

# =============================================================================
step "STEP 2 — Bersihkan & buat ulang direktori"
# =============================================================================
info "Hapus direktori lama..."
rm -rf "${REPO_ROOT}"
rm -rf "${STAGING_DIR}"

info "Buat struktur direktori baru..."
mkdir -p "${BASEOS_DIR}/Packages"
mkdir -p "${APPSTREAM_DIR}/Packages"
mkdir -p "${STAGING_DIR}"
ok "Direktori siap."

# =============================================================================
step "STEP 3 — Cek koneksi internet"
# =============================================================================
curl -sf --max-time 10 "https://dl.rockylinux.org/" > /dev/null \
    || die "Tidak bisa akses internet!"
ok "Koneksi internet OK."

# =============================================================================
step "STEP 4 — Refresh metadata upstream"
# =============================================================================
info "dnf clean + makecache..."
dnf clean metadata > /dev/null 2>&1
dnf makecache > /dev/null 2>&1 || warn "makecache ada warning, lanjut..."
info "Repo upstream aktif:"
dnf repolist --enabled
ok "Metadata siap."

# =============================================================================
step "STEP 5 — Download semua package + dependencies"
# =============================================================================
# Pembelajaran [1]: TIDAK pakai --disablerepo/--enablerepo
# Pembelajaran [4]: TIDAK hardcode nama repo
info "Download ${#PACKAGES[@]} package ke staging: ${STAGING_DIR}"
info "dnf resolve dari semua repo aktif..."
echo ""

dnf download \
    --resolve \
    --alldeps \
    --downloaddir="${STAGING_DIR}" \
    "${PACKAGES[@]}"

DOWNLOAD_EXIT=$?
RPM_COUNT=$(find "${STAGING_DIR}" -name "*.rpm" | wc -l)
info "RPM terdownload: ${RPM_COUNT}"

# Pembelajaran [3]: validasi sebelum lanjut
[[ $RPM_COUNT -eq 0 ]] && die "0 RPM terdownload (exit: ${DOWNLOAD_EXIT}). Cek error di atas."
[[ $DOWNLOAD_EXIT -ne 0 ]] && warn "Download exit ${DOWNLOAD_EXIT} tapi ${RPM_COUNT} RPM OK — lanjut."
ok "${RPM_COUNT} RPM berhasil didownload."

# =============================================================================
step "STEP 6 — Distribusi RPM ke BaseOS & AppStream"
# =============================================================================
# Pembelajaran [5]: copy semua ke kedua repo
info "Copy ke BaseOS/Packages..."
cp "${STAGING_DIR}"/*.rpm "${BASEOS_DIR}/Packages/"

info "Copy ke AppStream/Packages..."
cp "${STAGING_DIR}"/*.rpm "${APPSTREAM_DIR}/Packages/"

rm -rf "${STAGING_DIR}"
ok "RPM terdistribusi, staging dir dihapus."

# =============================================================================
step "STEP 7 — Generate repodata"
# =============================================================================
info "createrepo_c BaseOS..."
createrepo_c "${BASEOS_DIR}" || die "createrepo_c BaseOS gagal."
ok "BaseOS repodata OK."

info "createrepo_c AppStream..."
createrepo_c "${APPSTREAM_DIR}" || die "createrepo_c AppStream gagal."
ok "AppStream repodata OK."

# =============================================================================
step "STEP 8 — Konfigurasi httpd"
# =============================================================================
cat > /etc/httpd/conf.d/rhcsa-repo.conf << 'EOF'
<Directory "/var/www/html">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

chown -R apache:apache /var/www/html/rhel9
chmod -R 755 /var/www/html/rhel9

semanage fcontext -a -t httpd_sys_content_t "/var/www/html/rhel9(/.*)?" 2>/dev/null \
    || semanage fcontext -m -t httpd_sys_content_t "/var/www/html/rhel9(/.*)?" 2>/dev/null \
    || warn "semanage gagal, coba restorecon..."
restorecon -Rv /var/www/html/rhel9 > /dev/null 2>&1

systemctl enable --now httpd
systemctl is-active --quiet httpd || die "httpd gagal start! Cek: journalctl -xe"
ok "httpd aktif."

# =============================================================================
step "STEP 9 — Konfigurasi firewall"
# =============================================================================
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=http     > /dev/null
firewall-cmd --permanent --add-service=nfs      > /dev/null
firewall-cmd --permanent --add-service=mountd   > /dev/null
firewall-cmd --permanent --add-service=rpc-bind > /dev/null
firewall-cmd --reload > /dev/null
ok "Firewall: http, nfs, mountd, rpc-bind dibuka."

# =============================================================================
step "STEP 10 — Verifikasi repo accessible via HTTP"
# =============================================================================
sleep 1
curl -sf "${BASEOS_URL}/repodata/repomd.xml" > /dev/null \
    && ok  "BaseOS    OK ✓ — ${BASEOS_URL}" \
    || warn "BaseOS GAGAL diakses! Cek: curl -v ${BASEOS_URL}/repodata/repomd.xml"

curl -sf "${APPSTREAM_URL}/repodata/repomd.xml" > /dev/null \
    && ok  "AppStream OK ✓ — ${APPSTREAM_URL}" \
    || warn "AppStream GAGAL diakses! Cek: curl -v ${APPSTREAM_URL}/repodata/repomd.xml"

# =============================================================================
# SUMMARY
# =============================================================================
FINAL_RPM=$(find "${BASEOS_DIR}/Packages" -name "*.rpm" | wc -l)
TOTAL_SIZE=$(du -sh /var/www/html/rhel9 | cut -f1)

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║            RHCSA LOCAL REPO — SELESAI ✓                     ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Total RPM  : ${BOLD}${FINAL_RPM} package${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Disk usage : ${BOLD}${TOTAL_SIZE}${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${CYAN}${BASEOS_URL}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${CYAN}${APPSTREAM_URL}${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Setup di node1 / node2 — jalankan ini:${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}dnf config-manager --add-repo ${BASEOS_URL}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}dnf config-manager --add-repo ${APPSTREAM_URL}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}echo gpgcheck=0 >> /etc/yum.repos.d/*BaseOS*${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}echo gpgcheck=0 >> /etc/yum.repos.d/*AppStream*${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}dnf clean all && dnf makecache${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
