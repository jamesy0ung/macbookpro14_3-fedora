#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

echo "Switching to discrete GPU (AMD)..."

# Update GRUB configuration for dGPU
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="amdgpu.dpm=0 amdgpu.dc=1 amdgpu.debug=0x4"/' /etc/default/grub

# Remove any blacklisting of amdgpu if it exists
if [ -f "/etc/modprobe.d/amdgpu.conf" ]; then
  echo "Removing AMD GPU blacklist..."
  rm /etc/modprobe.d/amdgpu.conf
fi

# Rebuild GRUB configuration
echo "Rebuilding GRUB configuration..."
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "Done! Please reboot your system to complete the switch to the discrete GPU."
echo "After reboot, the AMD GPU will be active with debugging options enabled."
