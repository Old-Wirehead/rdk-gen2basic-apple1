# RDK BASIC

A clean-room, Integer BASIC-compatible interpreter for the Apple 1, written from scratch in 6502 assembly.

- **Compatible:** same syntax, same tokens and same tape format as the original Apple 1 Integer BASIC, so existing programs and tapes keep working.
- **Fixed:** the known bugs of the original are corrected.
- **Extended:** new statements for the GEN2 color graphics card.

RDK BASIC is part of the **Retro Dev Kit** family, alongside [Retro Dev Kit Apple 1](https://github.com/Old-Wirehead/rdk-apple1).

*Dedicated to Uncle Bernie, for his contributions to the Apple 1 world.*

## Status

Design phase, no code yet. See the design note (in French): [docs/conception/basic-rdk.md](docs/conception/basic-rdk.md).

## Clean-room statement

RDK BASIC contains no code from Apple's Integer BASIC and no code from POM-1. It is written only from the behaviour specification: the published manuals, black-box observation of programs stored in memory, and our own documented token format. Nobody working on it reads, disassembles or copies the original interpreter. The repository contains no ROM image and no copyrighted BASIC binary or tape.

## En bref (français)

RDK BASIC est un clone libre, écrit de zéro, de l'Integer BASIC de l'Apple 1 : même syntaxe, mêmes jetons, même format cassette, bugs corrigés, et extensions graphiques couleur GEN2. Projet en phase de conception, la note de conception est dans `docs/conception/`.

## License

MIT, see [LICENSE](LICENSE).
