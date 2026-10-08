# License and acknowledgements

The Shuuz core is licensed under GPL-3.0-or-later. The complete GPL version
3 text is in LICENSE. The game name and hardware identifiers identify
compatible hardware; no game ROMs, fuse dumps or Atari manuals are included.

The MiSTer framework (the `sys` folder) is copied without modification from
the Off the Wall MiSTer core, with its original notices. Framework sources
include work by Alexey Melnikov and their respective credited authors.

The integration shell, PLL, SDRAM controller, download loader, ROM memory,
program ROM and analogue adjustment derive from the Off the Wall MiSTer core
and, through it, from the Relief Pitcher, Rampart, Batman and Skull &
Crossbones MiSTer cores, all GPL-3.0-or-later. Their copyright notices are
retained. The analogue horizontal-size module credits Umberto Parisi.

The video section (VAD, video RAM schedule, playfield, motion objects, line
buffer, colour RAM, DAC, graphics readers), the 68000 wrapper, wait-state
counter, watchdog, EEPROM and LETA models also come from the Off the Wall
core, with the same lineage. The LETA follows leta_rep.vhd by JROK through
the Atari System 1 and Rampart cores.

The MSM6295 model comes from the Relief Pitcher MiSTer core (Copyright (C)
2026 RetroShrimp), which adapted it from the Rampart and Batman cores and
from the GPL-2.0-or-later Klax OKI model; it is used here under
GPL-3.0-or-later. The analogue audio path follows the method of the Relief
Pitcher core's audio filter.

The trackball quadrature and pacing modules and the controls module come
from the Rampart MiSTer core (Copyright (C) 2026 RetroShrimp); the pacing and
sensitivity schemes originate in the Blasteroids MiSTer core. All are
GPL-3.0-or-later.

fx68k by Jorge Cwik is vendored unchanged with its GPL-3.0 license and
notices.
