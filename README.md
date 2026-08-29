# PYNQ image for AntSDR

This repository has been forked from `https://github.com/MicroPhase/antsdr-pynq`.  See the MicroPhase repository for the original documentation.

## PYNQ Image

The MicroPhase PYNQ image was extended to include PYNQ packages for Analog Devices IIO.  This image will install IIO, the IIO Python bindings, and IIOD to allow remote connections to the RFIC.

To rebuild the PYNQ image using Vivado 2022.1, run `make all`.

To create a bootable SD card from the image, run `make sd SD=</PATH/TO/YOUR/SD/CARD>`.  The SD card should have two partitions: one called `PYNQ` for the boot files, and the other called `root` for the root filesystem.

## Overlays

The base overlay (`./boards/e200/base`) is provided to run the default MicroPhase Pluto SDR compatible system.  The base overlay can be rebuilt by running `make base`.

An overlay template is also provided in the `./boards/e200/template` directory.  This overlay directory can be copied to create a new overlay.  The template block diagram provides an empty component called `overlay` in the receive data stream to allow custom signal processing logic to be inserted.  The `overlay` component provides a wrapper for both channels of IQ data streams.  The clock for this subsystem runs at four times the request sample rate from the IIO software interface.  

Once an overlay bitstream has been generated, the required PYNQ files can be created by running `make ol OL=<YOUR OVERLAY DIRECTORY NAME>`.

## Testbench

The `template` overlay Vivado project also includes a skeleton for a testbench (`tb_overlay.v`) for verification of your signal processing IP.  The testbench must be modified to include the correct clock period, sample clock period, and IQ source files.

### IQ Files

The testbench expects one file for each I and Q data stream.  The files must contain hex string data representing 16-bit signed integers, with one sample per line.  A utility is provided in `./boards/e200/utils/iq_to_testbench.py` for generating these hex files.

---

# Building from a fresh clone

This fork is set up so that a clean checkout builds without manual
intervention. The changes from upstream are listed at the end.

## Toolchain

Pinned to **2022.1** throughout — Vivado, Vitis and PetaLinux. The version
matters beyond tool compatibility: PetaLinux 2022.1 builds **linux-xlnx
5.15.19**, and both the ADI kernel patch and `sdbuild`'s `LINUX_VERSION` must
agree with that. Mixing in a PetaLinux whose kernel is 5.15.36 will break the
kernel patch and `depmod`.

Vivado device support must include **Zynq-7000** (the AntSDR E200 is an
`xc7z020`). Nothing else is required — reference-board overlays needing Zynq
UltraScale+ MPSoC have been removed from the build.

## Host prerequisites

Ubuntu 20.04. Beyond `PYNQ/sdbuild/scripts/setup_host.sh`:

    sudo bash PYNQ/sdbuild/scripts/setup_host.sh

`setup_host.sh` appends `/opt/qemu/bin` to `~/.profile` and prints "re-login".
`sdbuild` resolves qemu with `which qemu-arm-static` at *make parse time*, and
`/usr/bin` holds the distro's 4.2.1 while sdbuild demands 5.2.0 — so either
log out and back in, or export it in the shell you build from:

    export PATH=/opt/qemu/bin:/opt/crosstool-ng/bin:$PATH

Then source the tools, in this order:

    source /tools/Xilinx/Vitis/2022.1/settings64.sh
    source /tools/Xilinx/PetaLinux/2022.1/settings.sh

Use a shell where `LD_LIBRARY_PATH` ends up unset — bitbake refuses to run
otherwise ("Your environment is misconfigured"). Sourcing in the order above
achieves that.

## Build

    git clone --recursive https://github.com/yoshi74ls181/antsdr-pynq.git
    cd antsdr-pynq
    make all

`make all` runs `base` (Vivado), `pynq` (rootfs + PYNQ image), `sdimg`
(BOOT.bin) and `dtbo` (device tree overlay). `make pynq` detects automatically
whether the prebuilt cache below exists and passes `REBUILD_PYNQ_*` as needed.

Expect several hours on the first run, dominated by the PYNQ root filesystem
bootstrap and the reference-board overlay build.

## Making rebuilds fast

After one successful build:

    make cache-prebuilt

This stores the board-agnostic PYNQ sdist and root filesystem under
`PYNQ/sdbuild/prebuilt/`. Subsequent fresh builds reuse them and skip the
multistrap/qemu rootfs bootstrap, the Pynq-Z2 overlay build and the MicroBlaze
BSP compile entirely — hours saved. `make pynq` picks them up with no flags.

## Changes from upstream

In this repository:

- `.gitmodules` uses HTTPS, not `git@github.com:`, so `--recursive` works
  without an SSH key. Same for `hdl`'s nested `testbenches` submodule.
- `e200_boot_gen/Makefile` uses `mkdir -p`. With a bare `mkdir` and
  `build_sdimg/boot.bif` committed, `make sdimg` could never succeed on a
  fresh clone.
- Generated artifacts (`pl.dtbo`, `build_sdimg/boot.bif`) are no longer
  tracked. Committing `pl.dtbo` made `make dtbo` a silent no-op, because it
  looked as new as its `.dts` source.
- `PYNQ-PRIO/device_tree_overlays/Makefile` builds `dtc` directly rather than
  via `install.sh`, which ran `sudo apt-get` and added
  `ppa:ubuntu-toolchain-r/ppa` solely to compile that one tool. The `.dtbo`
  rule now creates its own output directory.
- The e200 ADI kernel patch is refreshed for linux-xlnx 5.15.19. Upstream's
  copy was generated against 5.15.36 and failed on four files whose changes
  5.15.19 either already has or does not need.
- `make pynq` sets `REBUILD_PYNQ_*` automatically; `make cache-prebuilt` added.

In the `PYNQ` submodule (see its own history for detail):

- `setup_host.sh` fetches qemu from `download.qemu.org`; the old
  `wiki.qemu-project.org` URL fails TLS verification.
- `xvfb` added to `setup_host.sh` and `check_env.sh` — `boards/sw_repo` runs
  `xsct`, which needs it.
- `PIP_CONSTRAINT=setuptools-scm<8` when installing the pinned Python
  requirements, so building `argon2-cffi-bindings` from sdist does not pull a
  `packaging>=26.2` requirement that Ubuntu jammy cannot satisfy.
- `LINUX_VERSION` set to `5.15.19-xilinx-v2022.1` to match PetaLinux 2022.1.
- ZCU104 and Pynq-Z1 dropped from the sdist overlay list. ZCU104 needs an
  UltraScale+ MPSoC part; Pynq-Z1 was referenced nowhere else. Pynq-Z2 is
  retained because its XSAs build the MicroBlaze BSPs shipped in `pynq`.
- **A failed build can no longer delete the host's `/dev`.** sdbuild
  bind-mounted `/dev` into the staging chroot across separate make recipe
  lines; any failure left it mounted, and the next build's
  `rm -rf <staging>` followed it into the host. Deletions now go through
  `safe_rm_chroot.sh` (unmount, verify, `rm --one-file-system`) and the
  mount/depmod sequence through `install_kernel_modules.sh`, which unmounts
  from a trap.

Note that `boards/e310` is untouched and still carries upstream's kernel
patch, so it is not expected to build against PetaLinux 2022.1's 5.15.19.
