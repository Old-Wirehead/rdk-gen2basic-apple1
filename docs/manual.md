# RDK G2 Basic Apple 1: user manual

> **Dedicated to Uncle Bernie**, for everything he gave to the Apple 1 world.

RDK G2 Basic is a clean-room Integer BASIC for the Apple 1, written from scratch in 6502 assembly.
It is meant as a drop-in replacement for Apple's Integer BASIC: same syntax, same tokens, same
program format in memory, so programs, listings and tapes written for the original run unchanged.

Version 1.0 has **no graphics statements** yet. It only knows how to start the GEN2 color card
driver (see [GEN2 card hook](#gen2-card-hook)); graphics commands are planned for version 2.

## Loading

The image is `bin/rdk-g2basic.bin`, 7,709 bytes, to be loaded at `$E000`.

* In **Retro Dev Kit Apple 1** it is the BASIC selected in the *Machine* settings (the user's own
  original Integer BASIC stays available as the other choice, when the file is present).
* On other machines, load it at `$E000` and start it from the Woz Monitor with `E000R`.
  `E2B3R` is the warm start that keeps your program.

Because it is 7.6 KB, it needs RAM from `$E000` to `$FEFF` (the monitor ROM stays at `$FF00`). It does not
fit in a 4 KB EPROM window. The original lives in 4 KB at `$E000-$EFFF`.

On start the memory is probed from `$1000` upward in 4 KB steps to set `HIMEM` (the original assumes 4 KB).
`LOMEM` is `$0800`, or `$2000` when a GEN2 card driver is found.

## Banner

```
RDK G2 BASIC 1.0
DEDICATED TO UNCLE BERNIE
>
```

## Language summary

Commands (immediate mode): `LIST`, `LIST n`, `LIST a,b`, `RUN`, `CLR`, `SCR` (erase the program, this is the
original's NEW), `DEL a,b`, `AUTO n`, `MAN`.

Statements: `REM`, `LET` (or implicit), `DIM`, `TAB`, `END`, `INPUT`, `FOR`/`TO`/`STEP`/`NEXT`, `RETURN`,
`GOSUB`, `GOTO`, `IF`/`THEN`, `PRINT`, `POKE`, `CALL`. Several statements on a line with `:`.

Functions: `PEEK`, `RND`, `SGN`, `ABS`, `LEN`. Operators: `+ - * / MOD`, `= # < > <= >= <>`, `AND OR NOT`, `^`.
Integers from -32767 to 32767. String variables `A$` are dimensioned with `DIM A$(n)`, up to 255 characters;
`A$(i,j)` is a slice.

Typing: Backspace (`_`, as on the Apple 1 keyboard) erases a character, ESC cancels the line, a line longer than
127 characters is cancelled. Any key stops a running program.

Errors are printed as `*** MESSAGE ERR` (SYNTAX, >32767, BAD BRANCH, BAD NEXT, BAD RETURN, RANGE, DIM,
STR OVFL, STRING, MEM FULL, TOO LONG, >8 GOSUBS, >8 FORS, END, >255, TOO MANY PARENS), then `STOPPED AT n` in a program.

## Differences from the original

Bugs fixed or behaviours extended (the programs that worked on the original are not affected):

* `^` works (integer power). On the original it crashes the interpreter.
* Empty strings are allowed (`A$=""`, `LEN(A$)=0`).
* `FOR`, `NEXT`, `GOSUB`, `RETURN`, `END` and several statements separated by `:` are accepted in immediate mode
  (the original answers `SYNTAX ERR`).
* Editing a line does not erase the variables (only `RUN` and `CLR` do).
* `DIM` of an existing array or string to a smaller or equal size is accepted.
* `AUTO` also accepts `MAN`.
* The memory size is probed (the original assumes 4 KB), so large programs run on 8 KB or more without `HIMEM`.

Known differences kept as they are:

* `RND` is a different generator: sequences differ from the original's (the range of the results is the same).
* A larger `DIM` of an existing array gives `DIM ERR`.
* The interpreter keeps its working variables in zero page `$00-$3F`, so `POKE`/`PEEK` there are not harmless.
* `HIMEM:` and `LOMEM:` are not statements (like the original build we compared with, they give `SYNTAX ERR`).

## GEN2 card hook

Uncle Bernie's GEN2 card puts RAM in `$0000-$BFFF`, has its switches at `$C250-$C257` and ships a driver
in RAM at `$0C00-$1FFF` that is announced by an 8-byte signature at `$0800-$0807`.

At cold start, RDK G2 Basic looks for that signature. If it is there, it:

1. calls `JSR $0C00` **once**, with A, X and Y set to 0 (**TODO**: the real entry parameters are to be confirmed with Bernie);
2. sets `LOMEM` to `$2000`, above the driver's reserved area. (If a driver uses the HIRES buffers at `$2000-$5FFF`,
   a later version will raise it to `$6000`.)

If there is no signature, `LOMEM` stays at `$0800`. The signature value is a placeholder (`GEN2CARD`, **TODO**: replace
with the real bytes) at label `GSIG` in `src/rdkbasic.s`.

## Building

```
python3 src/build.py --asm /path/to/apple1-emu bin/rdk-g2basic.bin
```

`apple1-emu` is the native assembler of Retro Dev Kit Apple 1 (`apple1-emu asm`). `src/rdkbasic.gen.s` is the generated source, written in ca65 syntax.

## Tests

`tests/run-tests.sh` runs the sessions in `tests/sessions` (typed at the keyboard of an emulated Apple 1) and compares the
transcript with `tests/expected`. With `--real` and `ORIG_ROM=...` (your own copy of the original, which is not in this
repository) it checks that the transcript is identical to the original's. The 22 sessions cover arithmetic, strings, arrays,
`FOR`/`NEXT`, `GOSUB`, `INPUT`, `LIST` wrapping, errors, the editing keys, the examples of the kit and the BASIC games by Claude.

## Clean room

No code of Apple's Integer BASIC and none of POM-1 was read, disassembled or copied. The clone was written from the
published manuals, the documented token and memory format, and black-box observation of the original's output.

## License

MIT, see [LICENSE](../LICENSE).
