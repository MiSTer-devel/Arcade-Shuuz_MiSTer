# Shuuz for MiSTer FPGA

FPGA recreation of the **Atari Games Shuuz** arcade board (1990, PCB
A047365-01), the trackball horseshoe-pitching game. The board has a 68000 at
7.159 MHz, Atari's VAD and MOB video chips, an OKI MSM6295 for sound, a
28C16 EEPROM for settings and high scores, and a trackball read by Atari's
LETA chip.

The core recreates the board, not the game. It was built from the
schematics in Atari's manual (TM-358) and the board's dumped GALs. MAME
0.289 was used as a cross-check, and as the only source for the video chips,
whose schematics were never published.

<img src="https://img.shields.io/badge/Quartus-17.0.2-blue" alt="Quartus 17.0.2"> <img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="GPL-3.0-or-later">

---

## Supported games

| MRA | MAME set | Program |
|-----|----------|---------|
| `Shuuz.mra` | `shuuz` | version 8.0 |
| `_alternatives/_Shuuz/Shuuz (version 7.1).mra` | `shuuz2` | version 7.1 |

Both versions run on the same bitstream. Only the two program ROMs differ.

---

## Installing

1. Copy `releases/Shuuz_<date>.rbf` to `/media/fat/_Arcade/cores/`.
2. Copy `releases/Shuuz.mra` to `/media/fat/_Arcade/`. For version 7.1, also
   copy the `releases/_alternatives/_Shuuz` folder to
   `/media/fat/_Arcade/_alternatives/`.
3. Put the MAME 0.289 ROM sets in `/media/fat/games/mame/`: `shuuz.zip`, and
   `shuuz2.zip` as well for version 7.1. The version 7.1 MRA takes the ROMs
   it shares with version 8.0 from `shuuz.zip`, so it needs both files.

**No ROM data is in this repository.** The MRA files name the ROMs and give
their CRCs.

Keep only one `Shuuz_*.rbf` in `_Arcade/cores/`. An MRA finds its core by
name prefix, so an older dated file left there may load instead of the new
one.

### Settings and high scores

The board has no DIP switches. Coinage, game options, statistics and high
scores live in its EEPROM, which the core saves as a 2 KB file in MiSTer's
saves folder. MiSTer writes the file the next time its menu is opened, so
after changing settings or setting a high score, open the menu once before
switching off.

On the very first start the EEPROM is blank. The game then sets its defaults
and shows "RESETTING HIGH SCORES" once; this is normal.

---

## Controls

The cabinet has one trackball and two buttons, left and right.

| Cabinet | MiSTer |
|---------|--------|
| Trackball | Mouse, spinner, paddle, left analog stick or d-pad (all at once) |
| Left button | Pad A, or the left mouse button |
| Right button | Pad B, or the right mouse button |
| Coin | Select |
| Self-test switch | OSD `Service` |

A spinner or paddle moves the trackball horizontally only. The analog stick
and the d-pad act as a trackball held at a steady speed.

The cabinet's trackball is mounted at 45 degrees to the screen, so each of
its two rollers turns with a mix of left-right and up-down motion. The core
does that conversion for you: move the mouse right and the trackball rolls
right.

In the self-test menu, the right button moves down and the left button
selects.

### OSD options

| Option | Effect |
|--------|--------|
| Aspect ratio | Original, Full Screen, or the two custom ratios from `MiSTer.ini` |
| Orientation | Original or Flip |
| Scale | Normal, V-Integer, HV-Integer, Narrower HV-Integer |
| Analog alignment | CRT H-Size and H-Position (stretch and move the picture inside the line), Analog VGA H-Shift and V-Shift (move the sync). Analog output only |
| Trackball speed | 0.25x to 4x; 1x is the default |
| Trackball X, Trackball Y | Invert either axis |
| Service | The board's self-test switch |
| Reset | Restart the game |

Nobody knows how many counts the real trackball gives per turn, so 1x is an
estimate. Use `Trackball speed` to suit your mouse or trackball.

---

## Accuracy notes

Everything runs from one 57.272727 MHz clock, four times the board's
14.318 MHz crystal, with clock enables for the slower clocks. These parts
follow the schematics and the GAL fuse maps:

- **Address decode.** The GAL at 55C (136083-1050) and the 74LS138 at 55B,
  with the GAL's equations taken from its fuse map. The sheet draws a
  PAL20L10 there; the boards carry a GAL16V8, and the core follows the GAL.
- **Wait states.** The 74LS163A counter at 50B ends every bus cycle: no
  wait state for the program ROM, one for the EEPROM, two for the LETA and
  the MSM6295. The video section ends its own cycles when it has a free
  video RAM slot. MAME has no wait states, so the game program runs slightly
  slower here, as on the board.
- **Watchdog.** The 74LS197 at 30B holds the 68000 in reset for eight frames
  after power-on, and resets the board if the program stops writing to it
  for eight frames.
- **EEPROM.** The 28C16 with the flop at 10B that locks it. Each write must
  first be unlocked, and a write takes the chip's 10 ms programming time.
- **Video bus strobes.** The GAL at 45E (136083-1051) passes the bus
  strobes to the video section one clock late.
- **Switches and trackball.** The input multiplexer, the output latch and
  the LETA counters. The LETA's RESOL pin is grounded on this board, so it
  counts one step for every two edges.
- **Priority and shadows.** The GAL at 85N (136083-1053) decides whether a
  motion object pixel or the playfield shows. Pen 1 of a motion object
  darkens the playfield under it: these are the shadows under the
  horseshoes.
- **Colour output.** 5 bits each of red, green and blue plus a shared
  intensity bit. A channel whose 5 bits are all zero is forced to black, as
  the board's gates do.
- **Sound.** The MSM6295 runs from 894.886 kHz with its SS pin high:
  6,779 samples a second. Its output goes through the three analogue stages
  drawn in the manual, built from their component values. They cut off
  above about 900 Hz, so **the core sounds duller than MAME**, which plays
  the chip unfiltered. The board's second sound chip, a YM2149, is drawn in
  the manual but its socket is empty on real boards. The game still writes
  to it, with every volume at zero.

### What follows MAME instead

No schematic of the video section has been published, for this board or any
of its sister boards. The VAD (timing, scroll registers, end-of-frame
reload), the MOB (motion object list walk) and the line buffer therefore
follow MAME's `atarivad` and `atarimo` devices and the video model of the
Off the Wall MiSTer core, and were compared with MAME frame by frame. Two
known points:

- This board carries the VAD 137656-001, an earlier revision than the -002
  on the sister boards. Nothing is known about how the two differ; the core
  models the -002.
- When the program changes a motion object partway down the screen, the
  core shows the change from that line on, as a line buffer that is drawn
  one line ahead does. MAME draws whole frames and shows it on the next
  frame. This happens on the title screen and the player introduction.

The order in which the VAD shares the video RAM between the playfield, the
motion objects and the 68000 is also not known. The core gives each one a
fixed slot in every pixel.

---

## Verification

This core was developed simulation-first, with AI assistance, under human
review and hardware testing. Each part was checked against an independent
reference before it counted as done:

| Part | Method | Result |
|------|--------|--------|
| GALs | Each GAL module compared with its fuse map, input by input | Equal |
| Main bus | Boot of both program versions compared with MAME, bus access by bus access (polling loops merged) | The same 46,911 accesses in the same order, through the first interrupt |
| Video | 46 frames of each version (attract mode, a game, self-test) in which the program does not change the picture mid-frame, compared with MAME pixel by pixel as colour RAM addresses | Equal, with no late graphics fetch |
| MSM6295 | Compared with MAME's own MSM6295 device, built from MAME's source and driven by the real sample ROMs | 17,811 samples equal |
| Audio filter | Response compared with the three stages computed from the schematic | Within 0.05 dB up to 4 kHz |
| Whole core | Both versions run for 2,900 frames: attract mode, a coin, player selection and pitches with the trackball, then the game's own ROM and video RAM tests | Pictures, interrupts and sound writes follow MAME, apart from 12 frames at four scene changes (the mid-frame motion object changes above); both self-tests pass |
| Release | This repository, compiled on its own | Byte-identical to the released bitstream |
| Hardware | Played on MiSTer DE10-Nano boards by many testers, October 2026 | No problems reported |

Shipped build (Cyclone V 5CSEBA6U23I7): 12,865 ALMs (31 %), 58 % of block
memory bits, 42 DSP blocks. Timing closes on every corner: worst setup slack
+0.385 ns, worst hold +0.112 ns.

---

## Building

You need Quartus Prime **17.0.2** (Lite or Standard), as for all MiSTer cores.

1. Open `Shuuz.qpf`, or run `quartus_sh --flow compile Shuuz` in this folder.
2. The bitstream is `output_files/Shuuz.rbf`. For a release, copy it to
   `releases/Shuuz_YYYYMMDD.rbf`.

The framework writes the build date into the bitstream, so a build made on
another day differs from the release in those bytes only.

Add source files to `files.qip` by hand, not through the Quartus GUI: the GUI
writes them into `Shuuz.qsf` instead and the two lists drift apart.
`Shuuz.qsf` fixes fitter seed 3; check timing again if you change it.

---

## Repository layout

```text
Shuuz.qpf / .qsf / .sdc   Quartus project and timing constraints
Arcade-Shuuz.sv           MiSTer top level: menu, controls, video and audio out
files.qip                 Source file list
rtl/                      The game board (shuuz_core.sv is its top)
  main/                   68000, address decode, wait states, watchdog, EEPROM
  io/                     Switches, LETA trackball counters, MiSTer controls
  video/                  VAD, playfield, motion objects, line buffer, colour RAM, DAC
  sound/                  MSM6295 and the analogue filter stages
  gal/                    The board's GALs, from their fuse maps
  mem/                    Program ROM, SDRAM, ROM download
  lib/fx68k/              68000 CPU core
  pll/                    PLL
sys/                      MiSTer framework, unmodified
releases/                 Bitstream and MRA files
```

Comments in the RTL name board parts by their location on the PCB (for
example "the 74LS163A at 50B") and signals by their schematic names, so they
can be checked against the manual.

---

## Licensing

The combined work is **GPL-3.0-or-later** (see `LICENSE`). `NOTICE.md` lists
where each part came from.

| Component | License |
|-----------|---------|
| `Arcade-Shuuz.sv`, `rtl/` (this core and the modules it adapts) | GPL-3.0-or-later |
| `rtl/lib/fx68k/`: fx68k 68000 core, Jorge Cwik | GPL-3.0 |
| `rtl/video/analog_hsize.sv`: Umberto Parisi (rmonic79) | GPL-3.0-or-later |
| `sys/`: MiSTer framework, Alexey Melnikov and contributors | GPL-2.0-or-later / GPL-3.0-or-later, as marked in each file |

---

## Credits

- **Atari Games**: the original hardware and game.
- **The MAME team**: `shuuz.cpp` (Aaron Giles), `atarivad`, `atarimo` and
  `okim6295`, the reference for everything the schematics do not settle.
- **Jorge Cwik**: the fx68k 68000 core.
- **Alexey Melnikov (Sorgelig)** and the MiSTer-devel community: the MiSTer
  framework.
- **Umberto Parisi (rmonic79)**: `analog_hsize.sv`, from
  [Arcade-Raiden_MiSTer](https://github.com/rmonic79/Arcade-Raiden_MiSTer).
- **RetroShrimp**: the trackball and controls modules (from the
  [Rampart](https://github.com/MiSTer-devel/Arcade-Rampart_MiSTer) MiSTer
  core) and the MSM6295 model (from the
  [Relief Pitcher](https://github.com/MiSTer-devel/Arcade-ReliefPitcher_MiSTer)
  MiSTer core).
- The authors of the MiSTer cores whose video models, SDRAM controller and
  MiSTer glue this core builds on:
  [Off the Wall](https://github.com/MiSTer-devel/Arcade-OffTheWall_MiSTer),
  [Relief Pitcher](https://github.com/MiSTer-devel/Arcade-ReliefPitcher_MiSTer),
  [Batman](https://github.com/MiSTer-devel/Arcade-Batman_MiSTer),
  [Skull & Crossbones](https://github.com/MiSTer-devel/Arcade-SkullXBones_MiSTer),
  [Bad Lands](https://github.com/MiSTer-devel/Arcade-Badlands_MiSTer),
  [Blasteroids](https://github.com/MiSTer-devel/Arcade-Blasteroids_MiSTer),
  [Xybots](https://github.com/MiSTer-devel/Arcade-Xybots_MiSTer) and
  [Toobin'](https://github.com/MiSTer-devel/Arcade-Toobin_MiSTer).
- **JROK**: `leta_rep.vhd` in the
  [Atari System 1](https://github.com/MiSTer-devel/Arcade-Atari-system1_MiSTer)
  core, which the LETA model follows.
