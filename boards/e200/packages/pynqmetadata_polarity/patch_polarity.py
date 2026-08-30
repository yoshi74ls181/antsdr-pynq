#!/usr/bin/env python3
"""Downgrade pynqmetadata's signal polarity check from fatal to a warning.

PYNQ 3.0's metadata frontend refuses to parse the ADI base design:

    system:sys_rgmii:MDIO_GEM:MDIO_O cannot be connected to
    system:sys_ps7:MDIO_ETHERNET_0:MDIO_O as they have the same polarity

sys_rgmii declares its MDIO_GEM ports with directions inverted relative to
their names (mdio_gem_i is DIR=O, mdio_gem_o is DIR=I), so the shared net joins
two signals that both look like drivers. MDIO is a tristate bus, and the O/I/T
triple does not fit the strict one-driver model the check assumes.

Without this, no E200 overlay can be loaded through PYNQ at all -- not just a
QICK one. It has gone unnoticed because the board programs its PL at boot and
the stock notebooks reach the radio through libiio rather than pynq.Overlay.

Patching the .hwh is not a workable alternative: sys_rgmii is a block-design
container with its own sub-.hwh, so the connection is rebuilt from there even
after the ports and the BUSINTERFACE are detached in the top-level file.

The check is advisory validation of metadata. Getting it wrong cannot damage
hardware -- the bitstream is already built and is not derived from this parse --
so a warning is the proportionate response. Idempotent, and fails loudly if
pynqmetadata changes shape, so an upgrade cannot silently drop the patch.
"""
import glob
import os
import sys

CANDIDATES = glob.glob(
    "/usr/local/share/pynq-venv/lib/python*/site-packages/pynqmetadata/models/signal.py"
) + glob.glob(
    "/usr/local/lib/python*/dist-packages/pynqmetadata/models/signal.py"
)

if not CANDIDATES:
    sys.exit("patch_polarity: could not find pynqmetadata/models/signal.py")

path = CANDIDATES[0]
src = open(path).read()

if "_QICK_POLARITY_PATCHED" in src:
    print("patch_polarity: already applied to %s" % path)
    sys.exit(0)

n = src.count("raise WrongPolarityConnection(")
if n != 2:
    sys.exit("patch_polarity: expected 2 'raise WrongPolarityConnection(' in %s, found %d "
             "-- pynqmetadata has changed, re-check the patch" % (path, n))

backup = path + ".orig"
if not os.path.exists(backup):
    open(backup, "w").write(src)

src = src.replace(
    "from __future__ import annotations",
    "from __future__ import annotations\n\n"
    "import warnings  # _QICK_POLARITY_PATCHED\n",
    1,
)
src = src.replace("raise WrongPolarityConnection(", "warnings.warn(")

open(path, "w").write(src)
print("patch_polarity: patched %s (backup at %s)" % (path, backup))
