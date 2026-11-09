# RDK G2 Basic Apple 1

A clean-room, Integer BASIC-compatible interpreter for the Apple 1, written from scratch in 6502 assembly.

- **Compatible:** same syntax, same tokens and same tape format as the original Apple 1 Integer BASIC, so existing programs and tapes keep working.
- **Fixed:** the known bugs of the original are corrected.
- **Extended:** starts the GEN2 color graphics card driver when it finds one (graphics statements come in version 2).

RDK BASIC is part of the **Retro Dev Kit** family, alongside [Retro Dev Kit Apple 1](https://github.com/Old-Wirehead/rdk-apple1).

*Dedicated to Uncle Bernie, for his contributions to the Apple 1 world.*

## Status

Version 1.0 (RDK 7.9.2 build): complete interpreter, 7,933 bytes at `$E000`, **all test sessions identical to the original's output** (3 more cover the extensions `KEY`, `LOMEM=` and `HIMEM=`).
Extensions: `KEY(n)` (read the keyboard without waiting), `LOMEM=` and `HIMEM=`.
No graphics statements yet. See the [manual](docs/manual.md) (in English), the design note
(in French): [docs/conception/basic-rdk.md](docs/conception/basic-rdk.md).

```
python3 src/build.py --asm /path/to/apple1-emu bin/rdk-g2basic.bin   # build
tests/run-tests.sh                                                   # test
```

The binary is `bin/rdk-g2basic.bin` (load at `$E000`, start with `E000R`). It needs RAM at `$E000-$FEFF`.

## Clean-room statement

RDK BASIC contains no code from Apple's Integer BASIC and no code from POM-1. It is written only from the behaviour specification: the published manuals, black-box observation of programs stored in memory, and our own documented token format. Nobody working on it reads, disassembles or copies the original interpreter. The repository contains no ROM image and no copyrighted BASIC binary or tape.

## En bref (français)

RDK BASIC est un clone libre, écrit de zéro, de l'Integer BASIC de l'Apple 1 : même syntaxe, mêmes jetons, même format cassette, bugs corrigés, et extensions graphiques couleur GEN2. Projet en phase de conception, la note de conception est dans `docs/conception/`.

## License

GNU GPL version 3 only (GPL-3.0-only), like the [Retro Dev Kit Apple 1](https://github.com/Old-Wirehead/rdk-apple1) whose kit ships this BASIC: see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Consequence worth knowing: whoever distributes this BASIC on an EPROM or inside a kit must also make the source available, as the licence requires.
