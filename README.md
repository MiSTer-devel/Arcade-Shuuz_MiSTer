# Shuuz for MiSTer

A MiSTer FPGA core for Atari Games' Shuuz (1990), game board A047365-01: a
68000 at 7.159 MHz, the VAD and MOB video chips, five GALs, an MSM6295 with
its three filter stages, an EEPROM and a trackball.

It builds with positive timing slack, and in simulation the unpatched program
boots, passes its own ROM and video RAM tests, plays its attract mode and a
game, and follows MAME 0.289 frame by frame and sound write by sound write.
The 2026-10-02 bitstream has been played on MiSTer hardware by many testers
with no problems reported. `docs/PLAN.md` has the status,
`docs/HARDWARE_SPEC.md` what is known, what is derived and what is open.

## Using it

Build: `powershell -NoProfile -ExecutionPolicy Bypass -File core/build.ps1`
(Quartus Prime Lite 17.0.2). The bitstream is `core/output_files/Shuuz.rbf`.
MRA files for both MAME 0.289 sets (`shuuz`, `shuuz2`) are in `mra/`. You
must supply your own ROMs; none are included.

Controls: the mouse, a spinner, a paddle, the left analog stick and the
d-pad all move the trackball; A / left mouse button and B / right mouse
button are the two buttons; Select is the coin switch. The menu has the
trackball speed and direction, the self-test switch and the analogue video
alignment. Settings and high scores are kept in the core's EEPROM save file.

## What it is based on

The schematics in Atari's manual TM-358 are the source of truth for the
processor side, the inputs, the sound and the colour output; the GAL fuse
maps for the address decode, the bus strobes and the priority logic. The
manual has no sheet for the video section (none of the sister boards' manuals
has one either), so the VAD, the motion objects and the line buffer follow
MAME 0.289 and the Off the Wall MiSTer core's video model, checked against
MAME pixel by pixel.

Things you may notice against MAME:

* The sound is duller. The board's first audio stage rolls off at 884 Hz
  and a third-order low-pass follows; MAME has no filter.
* There is no second sound chip. The socket for a YM2149 is empty on real
  boards; the program still writes to it, with every volume at zero.
* The program runs slightly slower, because the board inserts wait states
  on some bus cycles and the video RAM makes the processor wait for its
  slot.

The GitHub release is the tree `python tools/publish.py stage` writes to
`publish/Arcade-Shuuz_MiSTer`, with its own README (`tools/release/README.md`).

## Layout

`core/` Quartus project and RTL, `docs/` plan, specification, sheet
transcriptions and validation record, `tests/` everything that checks it
(`tests/run_tests.ps1`), `tools/` ROM, MRA, survey and release tooling,
`reference/` pinned MAME sources and GAL equations.

License: GPL-3.0-or-later (see `LICENSE` and `NOTICE.md`).
