# MacBookPro14,3 Fedora Setup

This repository provides scripts and configuration files to aid in installing and configuring Fedora on a 2017 15-inch MacBook Pro (MacBookPro14,3). It leverages information from the Gentoo Wiki, adapted for Fedora 41. [Apple MacBook Pro 15-inch (2016, Intel, Four Thunderbolt 3 Ports)](https://wiki.gentoo.org/wiki/Apple_MacBook_Pro_15-inch_(2016,_Intel,_Four_Thunderbolt_3_Ports))

## GPU

### dGPU (Radeon Pro 560)

The Radeon Pro 560 generally works well. However, I encountered an issue where the cursor would randomly disappear. This was resolved by adding `amdgpu.dpm=0 amdgpu.dc=1 amdgpu.debug=0x4` to the kernel command line. My 4K monitor works at 60Hz through a ThinkPad Thunderbolt 3 dock without any additional configuration.

### iGPU

To enable the integrated GPU, you will need to install `apple_set_os.efi` using the provided `install-apple_set_os_efi.sh` script. Apple firmware typically disables the iGPU for operating systems other than macOS.

### Switching

I have not yet experimented with using a dedicated GPU switching utility. Instead, I have created scripts (`switch-to-igpu.sh` and `switch-to-dgpu.sh`) that enable or disable blacklisting of the respective GPU drivers. This provides a manual method for switching between GPUs.

## Wi-Fi

Out of the box, Wi-Fi performance may be subpar. To improve performance, replace the `brcmfmac43602-pcie.txt` file located in `/usr/lib/firmware/brcm` with the provided file. You can optionally modify the MAC address in the new file to match your device's actual MAC address. After replacing the file and rebooting, Wi-Fi should be stable.

## Touch Bar

It is essential to retain the macOS EFI firmware partition, as the T1 processor loads the Touch Bar firmware from this partition. You can nuke everything else, including macOS, as Apple does not provide any more firmware updates for this Mac.

My EFI partition looks like this
```
└── EFI
    └── APPLE
        ├── EMBEDDEDOS
        │   ├── FDRData
        │   ├── combined.memboot
        │   └── version.plist
        └── FIRMWARE
            └── MBP143.fd
```

1. Ensure that `dkms` is installed.
2. Clone the repository containing the required driver:
   `git clone https://github.com/Heratiki/macbook12-spi-driver/tree/kernel-6.12.10-fixes /usr/src/applespi-0.1`
3. Install the driver using DKMS:
   `dkms install applespi/0.1`
4. Create or modify `/etc/modules-load.d/applespi.conf` to include the following:

   ```
   applespi
   apple-ib-tb
   intel_lpss_pci
   spi_pxa2xx_platform
   ```

Reboot your system. The Touch Bar should now display the default controls. Pressing the "fn" key will reveal the function keys.

## Sound, Camera, Suspend

These features have not yet been configured or tested.

## Battery Life

With the dedicated GPU enabled (default configuration) and the system idle on the desktop at 50% brightness, I am getting approximately 3 hours of battery life. Battery life with the integrated GPU enabled has not yet been tested.
