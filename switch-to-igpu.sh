#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

echo "Switching to integrated GPU (Intel)..."

# Update GRUB configuration for iGPU
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="modprobe.blacklist=amdgpu acpi_backlight=intel_backlight"/' /etc/default/grub

# Create Intel GPU configuration if it doesn't exist
if [ ! -d "/etc/X11/xorg.conf.d" ]; then
  echo "Creating X11 configuration directory..."
  mkdir -p /etc/X11/xorg.conf.d
fi

echo "Creating Intel GPU configuration..."
cat > /etc/X11/xorg.conf.d/20-intel.conf << EOF
Section "Device"
	Identifier "Intel Graphics"
	Driver "intel"
	BusID "PCI:0:2:0"
	Option "TearFree" "true"
	Option "AccelMethod" "glamor"
EndSection
EOF

# Blacklist AMD GPU
echo "Blacklisting AMD GPU driver..."
cat > /etc/modprobe.d/amdgpu.conf << EOF
blacklist amdgpu
EOF

# Rebuild GRUB configuration
echo "Rebuilding GRUB configuration..."
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "Done! Please reboot your system to complete the switch to the integrated GPU."
echo "After reboot, the Intel GPU will be active and AMD GPU will be powered off for better battery life."
