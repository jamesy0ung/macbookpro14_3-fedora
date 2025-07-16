#!/usr/bin/env bash

set -euo pipefail
IFS=$' \t\n'

# --- Globals --------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/${SCRIPT_NAME%.sh}.log"

# colour helpers (fallback to plain when not a tty)
if [[ -t 1 ]]; then
  RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; BOLD="\e[1m"; RESET="\e[0m"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

msg()  { printf "%b\n" "$*" | tee -a "$LOG_FILE" ; }
say()  { msg "${GREEN}[OK]${RESET} $*" ; }
warn() { msg "${YELLOW}[Warn]${RESET} $*" ; }
fail() { msg "${RED}[Err]${RESET} $*" ; exit 1 ; }
run()  { msg "${BLUE}▶ $*${RESET}" ; "$@" ; }

need_root() {
  [[ $EUID -eq 0 ]] || fail "Please run with sudo or as root."
}

if command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
  PKG_Q="rpm -q"
  PKG_INSTALL=(dnf install -y)
  PKG_GROUP_INSTALL=(dnf groupinstall -y)
else
  fail "Only Fedora/RHEL‑like systems (dnf) are supported right now."
fi

need_pkg() {
  local pkg="$1"
  if ! $PKG_Q "$pkg" &>/dev/null; then
    run "${PKG_INSTALL[@]}" "$pkg"
  fi
}

need_kernel_dev() {
  # make sure headers/devel match running kernel
  local ver="$(uname -r)"
  need_pkg "kernel-devel-${ver}"
}

rebuild_initramfs() {
  run dracut -f --kver "$(uname -r)"
}

update_grub() {
  say "Regenerating GRUB configuration";
  if grub2-mkconfig -o /boot/grub2/grub.cfg &>>"$LOG_FILE"; then return; fi
  grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg &>>"$LOG_FILE" || warn "grub2-mkconfig could not run – check manually."
}

# ---- paths/URLs ----------------------------------------------------------
WIFI_FIRMWARE_SRC="brcmfmac43602-pcie.txt"
WIFI_FIRMWARE_DEST_DIR="/usr/lib/firmware/brcm"
APPLE_SET_OS_URL="https://github.com/0xbb/apple_set_os.efi/releases/download/v1/apple_set_os.efi"
APPLE_SET_OS_DEST_DIR="/boot/EFI/EFI/custom"
GRUB_CUSTOM_FILE="/etc/grub.d/40_custom"
INTEL_XORG_CONF="/etc/X11/xorg.conf.d/20-intel.conf"
AMD_MODPROBE_CONF="/etc/modprobe.d/amdgpu.conf"
TOUCHBAR_SRC_REPO="https://github.com/Heratiki/macbook12-spi-driver.git"
TOUCHBAR_SRC_BRANCH="kernel-6.12.10-fixes"
TOUCHBAR_SRC_DIR="/usr/src/applespi-0.1"
TOUCHBAR_MODULES_CONF="/etc/modules-load.d/applespi.conf"
AUDIO_SRC_REPO="https://github.com/davidjo/snd_hda_macbookpro.git"
AUDIO_SRC_DIR="/usr/src/snd_hda_macbookpro"
AUDIO_INSTALL_SCRIPT="install.cirrus.driver.sh"

GNOME_GROUP="workstation-product-environment"   # leaner than full workstation

# --- core helpers ---------------------------------------------------------
confirm() {
  [[ ${AUTO_YES:-0} -eq 1 ]] && return 0
  read -r -p "$1 [y/N] " ans
  [[ $ans =~ ^[Yy](es)?$ ]]
}

backup_file() {
  local f="$1"; [[ -e "$f" ]] || return 0
  cp -af "$f" "${f}.bak.$(date +%s)"
}

# -------------------------------------------------------------------------
setup_wifi() {
  msg "${BOLD}-- Wi‑Fi firmware --${RESET}"
  [[ -f "$WIFI_FIRMWARE_SRC" ]] || fail "Firmware source $WIFI_FIRMWARE_SRC not present beside the script."
  mkdir -p "$WIFI_FIRMWARE_DEST_DIR"
  backup_file "${WIFI_FIRMWARE_DEST_DIR}/${WIFI_FIRMWARE_SRC}"
  run cp -f "$WIFI_FIRMWARE_SRC" "$WIFI_FIRMWARE_DEST_DIR/"
  rebuild_initramfs
  say "Wi‑Fi firmware installed – reboot required."
}

setup_efi_helper() {
  msg "${BOLD}-- apple_set_os.efi --${RESET}"
  need_pkg wget
  mkdir -p "$APPLE_SET_OS_DEST_DIR"
  local dest="${APPLE_SET_OS_DEST_DIR}/apple_set_os.efi"
  if [[ ! -f $dest ]]; then
    run wget -q -O "$dest" "$APPLE_SET_OS_URL"
  else
    say "apple_set_os.efi already present."
  fi
  if ! grep -q "apple_set_os.efi" "$GRUB_CUSTOM_FILE"; then
    msg "Adding custom GRUB entry…"
    cat >>"$GRUB_CUSTOM_FILE" <<'EOF'
# apple_set_os.efi added by setup script
autoreboot off
menuentry "apple_set_os.efi (spoof macOS)" {
    search --no-floppy --set=root --label EFI
    chainloader (${root})/EFI/custom/apple_set_os.efi
}
EOF
    update_grub
  else
    say "GRUB entry already present."
  fi
}

switch_gpu_common() {
  backup_file "$INTEL_XORG_CONF" && rm -f "$INTEL_XORG_CONF" || true
  backup_file "$AMD_MODPROBE_CONF" && rm -f "$AMD_MODPROBE_CONF" || true
}

switch_to_dgpu() {
  msg "${BOLD}-- Switch to AMD dGPU --${RESET}"
  switch_gpu_common
  local add=("amdgpu.dpm=0" "amdgpu.dc=1" "amdgpu.debug=0x4")
  local del=("modprobe.blacklist=amdgpu" "acpi_backlight=intel_backlight")
  run grubby --update-kernel=ALL --remove-args="${del[*]}" --args="${add[*]}"
  update_grub
  say "dGPU enabled – reboot to take effect."
}

switch_to_igpu() {
  msg "${BOLD}-- Switch to Intel iGPU --${RESET}"
  switch_gpu_common
  local add=("modprobe.blacklist=amdgpu" "acpi_backlight=intel_backlight")
  local del=("amdgpu.dpm=0" "amdgpu.dc=1" "amdgpu.debug=0x4")
  run grubby --update-kernel=ALL --remove-args="${del[*]}" --args="${add[*]}"
  setup_efi_helper
  mkdir -p "$(dirname "$INTEL_XORG_CONF")"
  cat >"$INTEL_XORG_CONF" <<'EOF'
Section "Device"
  Identifier "Intel Graphics"
  Driver     "intel"
  Option     "TearFree" "true"
EndSection
EOF
  echo "blacklist amdgpu" >"$AMD_MODPROBE_CONF"
  update_grub
  say "iGPU enabled – select the apple_set_os entry on first reboot."
}

setup_touchbar() {
  msg "${BOLD}-- Touch Bar (applespi) --${RESET}"
  need_pkg git; need_pkg dkms; need_kernel_dev

  # Clone or update the driver source
  if [[ ! -d $TOUCHBAR_SRC_DIR/.git ]]; then
    run git clone --depth 1 -b "$TOUCHBAR_SRC_BRANCH" "$TOUCHBAR_SRC_REPO" "$TOUCHBAR_SRC_DIR"
  else
    run git -C "$TOUCHBAR_SRC_DIR" pull --ff-only
  fi

  # Build/install via DKMS
  local dkms_target="applespi/0.1"
  if ! dkms status | grep -q "$dkms_target.*installed"; then
    run dkms add "$TOUCHBAR_SRC_DIR"
    run dkms build "$dkms_target"
    run dkms install "$dkms_target"
  else
    say "applespi already installed (dkms)."
  fi

  # Ensure modules load on boot
  cat >"$TOUCHBAR_MODULES_CONF" <<'EOF'
applespi
apple-ib-tb
intel_lpss_pci
spi_pxa2xx_platform
EOF

  # Rebuild initramfs and force dracut regeneration
  rebuild_initramfs
  run dracut --force

  say "Touch Bar ready."
}

setup_audio() {
  msg "${BOLD}-- Cirrus audio --${RESET}"
  need_pkg git; need_pkg dkms; need_kernel_dev; need_pkg make; need_pkg gcc
  if [[ ! -d $AUDIO_SRC_DIR/.git ]]; then
    run git clone --depth 1 "$AUDIO_SRC_REPO" "$AUDIO_SRC_DIR"
  else
    run git -C "$AUDIO_SRC_DIR" pull --ff-only
  fi
  local script="$AUDIO_SRC_DIR/$AUDIO_INSTALL_SCRIPT"
  [[ -x $script ]] || chmod +x "$script"
  (cd "$AUDIO_SRC_DIR" && run "$script")
  rebuild_initramfs
  say "Audio driver installed."
}

install_gnome() {
  msg "${BOLD}-- Minimal GNOME --${RESET}"
  run "${PKG_GROUP_INSTALL[@]}" "$GNOME_GROUP"
  run systemctl set-default graphical.target
  say "GNOME installed – reboot to enter GUI."
}

all_hw()        { setup_wifi; setup_efi_helper; setup_touchbar; setup_audio; }
all_hw_dgpu()   { all_hw; switch_to_dgpu; }
all_hw_igpu()   { all_hw; switch_to_igpu; }

# ---------------- CLI -----------------------------------------------------
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]
Options (can combine):
  --wifi            Install Broadcom Wi‑Fi firmware
  --efi             Install apple_set_os.efi helper
  --dgpu            Switch to discrete AMD GPU
  --igpu            Switch to integrated Intel GPU (spoofs macOS)
  --touchbar        Build + install Touch Bar driver
  --audio           Build + install Cirrus audio driver
  --gnome           Install minimal GNOME desktop
  --all‑hw          Run all hardware setups (wifi, efi, touchbar, audio)
  --all‑dgpu        All hardware + switch to dGPU
  --all‑igpu        All hardware + switch to iGPU
  -y, --yes         Non‑interactive – assume “yes” to prompts
  -h, --help        Show this help and exit
Running with no options will start an interactive menu.
EOF
}

AUTO_YES=0
ACTION_SET=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wifi)       ACTION_SET+=(setup_wifi) ; shift;;
    --efi)        ACTION_SET+=(setup_efi_helper) ; shift;;
    --dgpu)       ACTION_SET+=(switch_to_dgpu) ; shift;;
    --igpu)       ACTION_SET+=(switch_to_igpu) ; shift;;
    --touchbar)   ACTION_SET+=(setup_touchbar) ; shift;;
    --audio)      ACTION_SET+=(setup_audio) ; shift;;
    --gnome)      ACTION_SET+=(install_gnome) ; shift;;
    --all-hw|--all‑hw) ACTION_SET+=(all_hw) ; shift;;
    --all-dgpu|--all‑dgpu) ACTION_SET+=(all_hw_dgpu) ; shift;;
    --all-igpu|--all‑igpu) ACTION_SET+=(all_hw_igpu) ; shift;;
    -y|--yes)     AUTO_YES=1 ; shift;;
    -h|--help)    usage ; exit 0;;
    *) usage; fail "Unknown option $1";;
  esac
done

need_root
mkdir -p "$(dirname "$LOG_FILE")" && touch "$LOG_FILE"
msg "\n===== $(date) – $SCRIPT_NAME begin =====\n"

if ((${#ACTION_SET[@]})); then
  for fn in "${ACTION_SET[@]}"; do "$fn"; done
else
  # interactive – mimic original menu
  PS3="Select action: "
  select opt in \
    "Wi‑Fi firmware" \
    "apple_set_os.efi helper" \
    "Switch to dGPU" \
    "Switch to iGPU" \
    "Touch Bar driver" \
    "Audio driver" \
    "Install minimal GNOME" \
    "All hardware" \
    "All hardware + dGPU" \
    "All hardware + iGPU" \
    "Quit"; do
      case $REPLY in
        1) setup_wifi;; 2) setup_efi_helper;; 3) switch_to_dgpu;; 4) switch_to_igpu;;
        5) setup_touchbar;; 6) setup_audio;; 7) install_gnome;; 8) all_hw;; 9) all_hw_dgpu;;
        10) all_hw_igpu;; 11) break;; *) warn "Invalid option";;
      esac
      break
  done
fi

say "All done. Check $LOG_FILE for details. Reboot if kernel components changed."
