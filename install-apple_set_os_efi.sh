#!/bin/bash

# Create EFI directory if it doesn't exist
if [ ! -d "/boot/EFI/EFI/custom" ]; then
  echo "Creating custom EFI directory..."
  mkdir -p /boot/EFI/EFI/custom
fi

# Download apple_set_os.efi if it doesn't exist
if [ ! -f "/boot/EFI/EFI/custom/apple_set_os.efi" ]; then
  echo "Downloading apple_set_os.efi..."
  wget -P /boot/EFI/EFI/custom https://github.com/0xbb/apple_set_os.efi/releases/download/v1/apple_set_os.efi
fi

# Update GRUB custom configuration
echo "Updating GRUB custom configuration..."
if ! grep -q "apple_set_os.efi" /etc/grub.d/40_custom; then
  cat >> /etc/grub.d/40_custom << EOF
search --no-floppy --set=root --label EFI
chainloader (\${root})/EFI/custom/apple_set_os.efi
boot
EOF
fi

grub2-mkconfig -o /boot/grub2/grub.cfg
