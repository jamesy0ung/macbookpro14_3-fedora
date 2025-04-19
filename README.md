# Fedora 42 Setup: MacBookPro14,3 (2017 15")

Scripts and config files for Fedora 42 on MacBookPro14,3. Based on [Gentoo Wiki MBP 15" (2016)](https://wiki.gentoo.org/wiki/Apple_MacBook_Pro_15-inch_(2016,_Intel,_Four_Thunderbolt_3_Ports)).

**Primary Tool:** `aiosetup.sh` automates most configurations.
Run `sudo ./aiosetup.sh --help` for options or `sudo ./aiosetup.sh` for interactive setup.

## `aiosetup.sh` Capabilities

*   Installs Broadcom Wi-Fi firmware (`brcmfmac43602-pcie.txt`)
*   Downloads/configures `apple_set_os.efi` for iGPU enablement
*   Configures system for dGPU (AMD) or iGPU (Intel) usage
*   Builds/installs `applespi` DKMS module for Touch Bar (`Heratiki/macbook12-spi-driver`)
*   Builds/installs `snd_hda_macbookpro` DKMS module for Audio (`davidjo/snd_hda_macbookpro`)
*   (Optional) Installs minimal GNOME desktop

**Recommended Usage:** Use script flags (e.g., `sudo ./aiosetup.sh --all-dgpu`) or interactive menu over manual steps.

## GPU Configuration

### dGPU (Default - Radeon Pro 560)

*   **Issue:** Random cursor disappearance on desktop.
*   **Fix:** Add `amdgpu.dpm=0 amdgpu.dc=1 amdgpu.debug=0x4` to kernel cmdline.
*   **Script:** `sudo ./aiosetup.sh --dgpu` or `--all-dgpu` applies kernel params via GRUB config.

### iGPU (Intel)

*   **Requirement:** `apple_set_os.efi` needed in EFI boot chain to bypass firmware iGPU disable.
*   **Configuration:** Blacklist `amdgpu` kernel module. Optional minimal Xorg config (`10-intel.conf`).
*   **Script:** `sudo ./aiosetup.sh --igpu` or `--all-igpu` handles EFI helper download/config, GRUB update, `amdgpu` blacklisting, and Xorg config.

### Switching GPUs

Use the all-in-one script:
*   Enable dGPU: `sudo ./aiosetup.sh --dgpu`
*   Enable iGPU: `sudo ./aiosetup.sh --igpu`
*   **Note:** Requires reboot. Handles GRUB, module blacklisting, EFI helper (for iGPU), and Xorg config.

## Wi-Fi (Broadcom BCM43602)

*   **Issue:** Poor performance, unable to connect to most networks.
*   **Fix:** Replace `/usr/lib/firmware/brcm/brcmfmac43602-pcie.txt` with provided file. Update the file with your real mac address, optionally.
*   **Script:** `sudo ./aiosetup.sh --wifi` (or any `--all-*`) replaces file and runs `dracut -f`.
*   **Manual:**
    ```bash
    # Optional: Edit macaddr= line in repo's brcmfmac43602-pcie.txt first
    sudo cp brcmfmac43602-pcie.txt /usr/lib/firmware/brcm/
    sudo dracut -f
    # Reboot required
    ```

## Touch Bar

*   **Prerequisite:** Retain macOS EFI partition containing `EFI/APPLE/FIRMWARE/MBP143.fd`. T1 chip loads firmware from here.
*   **Driver:** `applespi` kernel module via DKMS. Repo: `Heratiki/macbook12-spi-driver`.
*   **Script:** `sudo ./aiosetup.sh --touchbar` (or any `--all-*`) handles:
    *   Dependency installation (`dkms`, `kernel-devel`, `gcc`, `make`, `git`).
    *   Cloning repo, DKMS build/install.
    *   Loading modules via `/etc/modules-load.d/applespi.conf` (`applespi`, `apple-ib-tb`, `intel_lpss_pci`, `spi_pxa2xx_platform`).
    *   `dracut -f`.
*   **Note:** Reboot required. Provides standard Touch Bar functions (brightness, volume, Fn -> F-keys).

## Audio (Cirrus Logic CS42L83A)

*   **Issue:** No sound.
*   **Driver:** `snd_hda_macbookpro` kernel module via DKMS. Repo: `davidjo/snd_hda_macbookpro`.
*   **Script:** `sudo ./aiosetup.sh --audio` (or any `--all-*`) handles:
    *   Dependency installation.
    *   Cloning repo, running `install.cirrus.driver.sh` (uses DKMS).
    *   `dracut -f`.
*   **Note:** Reboot required. Enables speaker and headphone output. Microphone status untested/unreliable.

## Other Hardware

*   **Camera:** Works after installing the Touch Bar drivers.
*   **Suspend:** Untested/likely unreliable without tuning.

## Battery Life Estimation

*   **dGPU Enabled:** ~3 hours (idle, 50% brightness).
*   **iGPU Enabled:** Untested, expected significant improvement.