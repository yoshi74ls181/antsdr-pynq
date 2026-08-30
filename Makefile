SD ?=
SD_MSG := "ERROR: SD is not set. Please provide the path to your SD card mount directory."

OL ?=
OL_MSG := "ERROR: OL is not set. Please provide the name of your overlay directory."

all: base pynq sdimg dtbo

base:
	$(MAKE) -C ./boards/e200/base/antsdre200 ADI_IGNORE_VERSION_CHECK=1
	cp ./boards/e200/base/antsdre200/antsdre200.runs/impl_1/system_top.bit ./boards/e200/base/base.bit
	mkdir -p ./boards/e200/petalinux_bsp/hardware_project/ && cp ./boards/e200/base/antsdre200/antsdre200.sdk/system_top.xsa ./boards/e200/petalinux_bsp/hardware_project/base.xsa
	cp ./boards/e200/base/antsdre200/antsdre200.gen/sources_1/bd/system/hw_handoff/system.hwh ./boards/e200/base/base.hwh
	python3 ./boards/e200/utils/hwh_patch.py -f ./boards/e200/base/base.hwh
	
pynq/kernel:
	rm -rf ./PYNQ/boards/e200
	cp -r ./boards/e200 ./PYNQ/boards
	$(MAKE) -C ./PYNQ/sdbuild BOARDS=e200 boot_files

# PYNQ/sdbuild hard-errors unless it can find a prebuilt PYNQ sdist and root
# filesystem, or is explicitly told to rebuild them:
#   $(error REBUILD_PYNQ_SDIST not set and PYNQ_SDIST file ... does not exist)
# sdbuild/prebuilt/ ships empty, so a fresh checkout must rebuild both. Detect
# that automatically instead of failing with a confusing message.
#
# Rebuilding the sdist costs two extra Vivado overlay builds and a MicroBlaze
# BSP compile; rebuilding the rootfs costs a full multistrap/qemu bootstrap.
# After one successful build, `make cache-prebuilt` stores both artifacts so
# subsequent builds skip all of it -- see the README.
PYNQ_PREBUILT_DIR    := ./PYNQ/sdbuild/prebuilt
PYNQ_PREBUILT_SDIST  := $(PYNQ_PREBUILT_DIR)/pynq_sdist.tar.gz
PYNQ_PREBUILT_ROOTFS := $(PYNQ_PREBUILT_DIR)/pynq_rootfs.arm.tar.gz

# The cache is only valid for the tree it was built from. Existence alone is not
# enough: bumping the PYNQ submodule or its VERSION would otherwise silently
# reuse a mismatched rootfs and sdist. Stamp both and compare.
PYNQ_PREBUILT_STAMP := $(PYNQ_PREBUILT_DIR)/cache.stamp
PYNQ_CACHE_ID := \
  $(shell git -C ./PYNQ rev-parse HEAD 2>/dev/null) \
  $(shell sed -n 's/^VERSION[[:space:]]*:*=[[:space:]]*//p' ./PYNQ/sdbuild/Makefile 2>/dev/null | head -1)
PYNQ_CACHE_ID_STAMPED := $(shell cat $(PYNQ_PREBUILT_STAMP) 2>/dev/null)

SDBUILD_FLAGS :=
ifneq ($(strip $(PYNQ_CACHE_ID)),$(strip $(PYNQ_CACHE_ID_STAMPED)))
# No stamp (fresh clone, or a cache from before this check) or a stale one.
SDBUILD_FLAGS += REBUILD_PYNQ_SDIST=True REBUILD_PYNQ_ROOTFS=True
ifneq ($(strip $(PYNQ_CACHE_ID_STAMPED)),)
$(warning prebuilt cache was built from "$(PYNQ_CACHE_ID_STAMPED)", tree is now \
"$(PYNQ_CACHE_ID)" -- rebuilding sdist and rootfs)
endif
else
ifeq ($(wildcard $(PYNQ_PREBUILT_SDIST)),)
SDBUILD_FLAGS += REBUILD_PYNQ_SDIST=True
endif
ifeq ($(wildcard $(PYNQ_PREBUILT_ROOTFS)),)
SDBUILD_FLAGS += REBUILD_PYNQ_ROOTFS=True
endif
endif

pynq:
	rm -rf ./PYNQ/boards/e200
	cp -r ./boards/e200 ./PYNQ/boards
	$(MAKE) -C ./PYNQ/sdbuild BOARDS=e200 $(SDBUILD_FLAGS)

# Save the board-agnostic artifacts from a completed build so the next fresh
# build can reuse them. Cuts hours off a rebuild.
cache-prebuilt:
	mkdir -p $(PYNQ_PREBUILT_DIR)
	cp ./PYNQ/sdbuild/build/PYNQ/dist/pynq-*.tar.gz $(PYNQ_PREBUILT_SDIST)
	cp ./PYNQ/sdbuild/output/jammy.arm.*.tar.gz $(PYNQ_PREBUILT_ROOTFS)
	@echo '$(PYNQ_CACHE_ID)' > $(PYNQ_PREBUILT_STAMP)
	@echo "Cached:"; ls -lh $(PYNQ_PREBUILT_DIR)
	@echo "Stamped: $$(cat $(PYNQ_PREBUILT_STAMP))"

sdimg:
	cp ./boards/e200/base/antsdre200/antsdre200.runs/impl_1/system_top.bit ./e200_boot_gen/system_top.bit
	$(MAKE) -C ./e200_boot_gen sdimg

# `make sd` deploys ./boards/e200/base/pl.dtbo, but the overlay is built under
# PYNQ-PRIO. Copy it across, the same way `base` copies base.bit/base.hwh into
# that directory. Without this the deployed pl.dtbo is whatever was committed and
# never reflects prio_linux/dtso/pl.dts -- silently shipping a stale overlay.
dtbo:
	$(MAKE) -C ./PYNQ-PRIO/device_tree_overlays BOARDS=e200
	cp -f ./PYNQ-PRIO/boards/e200/prio_linux/dtbo/pl.dtbo ./boards/e200/base/pl.dtbo

sd:
	@[ "${SD}" ] || ( echo $(SD_MSG); exit 1 )
	sudo cp -f ./e200_boot_gen/build_sdimg/BOOT.bin $(SD)/PYNQ
	sudo cp -f ./boards/e200/utils/boot.py $(SD)/PYNQ
	sudo mkdir -p $(SD)/root/home/xilinx/jupyter_notebooks/base
	sudo cp -f ./boards/e200/base/base.bit $(SD)/root/home/xilinx/jupyter_notebooks/base
	sudo cp -f ./boards/e200/base/base.hwh $(SD)/root/home/xilinx/jupyter_notebooks/base
	sudo cp -f ./boards/e200/base/pl.dtbo $(SD)/root/home/xilinx/jupyter_notebooks/base
	sudo cp -f ./boards/e200/base/notebooks/*.ipynb $(SD)/root/home/xilinx/jupyter_notebooks/base
	# Board-side runtime helper, unlike the host-side tools in utils/.
	sudo cp -f ./boards/e200/utils/e200-power.sh $(SD)/root/home/xilinx/
	sudo chmod +x $(SD)/root/home/xilinx/e200-power.sh

overlay:
	@[ "${OL}" ] || ( echo $(OL_MSG); exit 1 )
	cp -f ./boards/e200/$(OL)/antsdre200/antsdre200.runs/impl_1/system_top.bit ./boards/e200/$(OL)/$(OL).bit
	cp -f ./boards/e200/$(OL)/antsdre200/antsdre200.gen/sources_1/bd/system/hw_handoff/system.hwh ./boards/e200/$(OL)/$(OL).hwh
	python3 ./boards/e200/utils/hwh_patch.py -f ./boards/e200/$(OL)/$(OL).hwh
	mkdir -p ./boards/e200/$(OL)/sd
	cp -f ./boards/e200/$(OL)/$(OL).bit ./boards/e200/$(OL)/sd/
	cp -f ./boards/e200/$(OL)/$(OL).hwh ./boards/e200/$(OL)/sd/
	cp -f ./boards/e200/$(OL)/notebooks/* ./boards/e200/$(OL)/sd/	

clean: clean/base clean/pynq

clean/base:
	$(MAKE) -C ./boards/e200/base/antsdre200 clean
	rm -rf ./boards/e200/base/base.bit
	rm -rf ./boards/e200/base/base.hwh
	rm -rf boards/e200/petalinux_bsp/hardware_project/base.xsa

clean/pynq:
	$(MAKE) -C ./PYNQ/sdbuild clean

clean/sdimg:
	$(MAKE) -C ./e200_boot_gen clean