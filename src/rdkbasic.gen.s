; RDK G2 Basic Apple 1 -- an Integer BASIC compatible interpreter for the Apple 1
; Clean-room implementation, written from the behaviour specification only
; (published manuals, black-box observation of typed lines and of the program
; stored in memory, and the documented token format).  No code of Apple's
; Integer BASIC was read, disassembled or copied.
; MIT license.  Dedicated to Uncle Bernie.
;
; Loads at $E000 (cold start), warm start at $E2B3, like the Apple-1 BASIC.
; Assembles with ca65/ld65 (flat image) or with the kit's native assembler.

; ------------------------------------------------------------ constants
IBUF    = $0200                 ; typed line (Woz Monitor buffer)
OBUF    = $0280                 ; tokenized line being entered / direct line
KBD     = $D010
KBDCR   = $D011
ECHO    = $FFEF                 ; Woz Monitor character output
CR      = $0D

; ------------------------------------------------------------ zero page
ACC     = $00                   ; 16 bit accumulator (value of expressions)
TMP     = $02                   ; second operand
IP      = $04                   ; token pointer
CUR     = $06                   ; start of the current line
PTR     = $08                   ; scratch pointer
VP      = $0A                   ; variable found
SPT     = $0C                   ; string value: pointer
SLN     = $0E                   ; string value: length
COL     = $0F                   ; output column 0-39
SI      = $10                   ; index in IBUF
OI      = $11                   ; index in OBUF
T1      = $12
T2      = $13
LAST    = $14                   ; last character written
AUTON   = $15                   ; AUTO active
AUTOL   = $16                   ; next AUTO line (2)
ASTEP   = $18
RS      = $19                   ; random seed (2)
LN      = $1B                   ; line number being entered (2)
W1      = $1D                   ; work (2)
W2      = $1F                   ; work (2)
DST     = $21                   ; destination cell (2)
KB      = $23                   ; key read while running (0 = none)
SGN     = $24                   ; sign
LNK     = $25                   ; kind of the last lvalue
SUBN    = $26                   ; substring start for A$(n)=...  (0 = none)
IDX     = $27                   ; INPUT: read index in IBUF
NK1     = $28                   ; name: letter
NK2     = $29                   ; name: digit or 0
CNT     = $2A                   ; byte count (2)
S1      = $2C                   ; copy source (2)
S2      = $2E                   ; copy destination (2)
T3      = $30
; pointers shared with the tape format (cassette blocks $4A-$FF)
LOMEM   = $4A
HIMEM   = $4C
PP      = $CA                   ; start of the program (it grows down from HIMEM)
PV      = $CC                   ; end of the variables (they grow up from LOMEM)

; error numbers
E_SYN   = 0
E_BIG   = 1
E_BRA   = 2
E_NXT   = 3
E_RET   = 4
E_RNG   = 5
E_DIM   = 6
E_OVF   = 7
E_STR   = 8
E_MEM   = 9
E_LONG  = 10
E_GOSUB = 11
E_FORS  = 12
E_END   = 13
E_255   = 14
E_PAR   = 15

.macro inc16 zp
        inc zp
        bne *+4
        inc zp+1
.endmacro

.macro dec16 zp
        lda zp
        bne *+4
        dec zp+1
        dec zp
.endmacro

.macro eat ch, tok
        lda #tok
        sta T1
        lda #ch
        jsr EATC
.endmacro

.macro setptr addr
        lda #<addr
        sta PTR
        lda #>addr
        sta PTR+1
.endmacro

        .org $E000
        jmp COLD

; ------------------------------------------------------------ data tables
; `hs "TEXT"` = the text with bit 7 set on the last character (build.py)
MSGS:   .byte "SYNTA", $D8
        .byte ">3276", $B7
        .byte "BAD BRANC", $C8
        .byte "BAD NEX", $D4
        .byte "BAD RETUR", $CE
        .byte "RANG", $C5
        .byte "DI", $CD
        .byte "STR OVF", $CC
        .byte "STRIN", $C7
        .byte "MEM FUL", $CC
        .byte "TOO LON", $C7
        .byte ">8 GOSUB", $D3
        .byte ">8 FOR", $D3
        .byte "EN", $C4
        .byte ">25", $B5
        .byte "TOO MANY PAREN", $D3
M_ERR:  .byte " ER", $D2
M_STOP: .byte "STOPPED AT", $A0
M_BAN:  .byte "RDK G2 BASIC 1.0", CR
        .byte "DEDICATED TO UNCLE BERNIE", CR+$80

; immediate commands: text, index
IMMTAB: .byte "LIS", $D4
        .byte 0
        .byte "RU", $CE
        .byte 1
        .byte "CL", $D2
        .byte 2
        .byte "SC", $D2
        .byte 3
        .byte "DE", $CC
        .byte 4
        .byte "AUT", $CF
        .byte 5
        .byte "MA", $CE
        .byte 6
        .byte 0

; statements: text, class (<$40 = special handler*2, $40-$7F = token alone, $C0+ = token + expression)
STMTAB: .byte "RE", $CD
        .byte 0
        .byte "LE", $D4
        .byte 2
        .byte "DI", $CD
        .byte 4
        .byte "TA", $C2
        .byte $D0
        .byte "EN", $C4
        .byte $51
        .byte "INPU", $D4
        .byte 6
        .byte "FO", $D2
        .byte 8
        .byte "NEX", $D4
        .byte 10
        .byte "RETUR", $CE
        .byte $5B
        .byte "GOSU", $C2
        .byte $DC
        .byte "GOT", $CF
        .byte $DF
        .byte "I", $C6
        .byte 12
        .byte "PRIN", $D4
        .byte 14
        .byte "POK", $C5
        .byte 16
        .byte "CAL", $CC
        .byte $CD
        .byte 0

; binary operators, longest first
BOPTAB: .byte "<", $BD
        .byte $1A
        .byte ">", $BD
        .byte $18
        .byte "<", $BE
        .byte $1B
        .byte $BC
        .byte $1C
        .byte $BE
        .byte $19
        .byte $BD
        .byte $16
        .byte $A3
        .byte $17
        .byte $AB
        .byte $12
        .byte $AD
        .byte $13
        .byte $AA
        .byte $14
        .byte $AF
        .byte $15
        .byte $DE
        .byte $20
        .byte "AN", $C4
        .byte $1D
        .byte "O", $D2
        .byte $1E
        .byte "MO", $C4
        .byte $1F
        .byte 0

FNTAB:  .byte "PEE", $CB
        .byte $2E
        .byte "RN", $C4
        .byte $2F
        .byte "SG", $CE
        .byte $30
        .byte "AB", $D3
        .byte $31
        .byte 0

; words that may follow a name directly
NMTAB:  .byte "THE", $CE
        .byte 0
        .byte "T", $CF
        .byte 0
        .byte "STE", $D0
        .byte 0
        .byte "AN", $C4
        .byte 0
        .byte "O", $D2
        .byte 0
        .byte "MO", $C4
        .byte 0
        .byte 0

; operator precedence, tokens $12-$20
PTAB:   .byte 4,4,5,5,3,3,3,3,3,3,3,2,1,5,6

; text of the tokens for LIST: token, text (a leading space is dropped after a space)
TOKTXT: .byte $03
        .byte $BA
        .byte $12
        .byte $AB
        .byte $13
        .byte $AD
        .byte $14
        .byte $AA
        .byte $15
        .byte $AF
        .byte $16
        .byte $BD
        .byte $17
        .byte $A3
        .byte $18
        .byte ">", $BD
        .byte $19
        .byte $BE
        .byte $1A
        .byte "<", $BD
        .byte $1B
        .byte "<", $BE
        .byte $1C
        .byte $BC
        .byte $1D
        .byte " AND", $A0
        .byte $1E
        .byte " OR", $A0
        .byte $1F
        .byte " MOD", $A0
        .byte $20
        .byte " ^", $A0
        .byte $22
        .byte $A8
        .byte $23
        .byte $AC
        .byte $24
        .byte " THEN", $A0
        .byte $25
        .byte " THEN", $A0
        .byte $26
        .byte $AC
        .byte $27
        .byte $AC
        .byte $2A
        .byte $A8
        .byte $2D
        .byte $A8
        .byte $2E
        .byte " PEEK", $A0
        .byte $2F
        .byte " RND", $A0
        .byte $30
        .byte " SGN", $A0
        .byte $31
        .byte " ABS", $A0
        .byte $34
        .byte $A8
        .byte $35
        .byte $AB
        .byte $36
        .byte $AD
        .byte $37
        .byte " NOT", $A0
        .byte $38
        .byte $A8
        .byte $39
        .byte $BD
        .byte $3A
        .byte $A3
        .byte $3B
        .byte " LEN", $A8
        .byte $3F
        .byte $A8
        .byte $40
        .byte $A4
        .byte $42
        .byte $A8
        .byte $43
        .byte $AC
        .byte $44
        .byte $AC
        .byte $45
        .byte $BB
        .byte $46
        .byte $BB
        .byte $47
        .byte $BB
        .byte $48
        .byte $AC
        .byte $49
        .byte $AC
        .byte $4D
        .byte " CALL", $A0
        .byte $4E
        .byte " DIM", $A0
        .byte $4F
        .byte " DIM", $A0
        .byte $50
        .byte " TAB", $A0
        .byte $51
        .byte " END", $A0
        .byte $52
        .byte " INPUT", $A0
        .byte $53
        .byte " INPUT", $A0
        .byte $54
        .byte " INPUT", $A0
        .byte $55
        .byte " FOR", $A0
        .byte $56
        .byte $BD
        .byte $57
        .byte " TO", $A0
        .byte $58
        .byte " STEP", $A0
        .byte $59
        .byte " NEXT", $A0
        .byte $5A
        .byte $AC
        .byte $5B
        .byte " RETURN", $A0
        .byte $5C
        .byte " GOSUB", $A0
        .byte $5D
        .byte " REM", $A0
        .byte $5E
        .byte " LET", $A0
        .byte $5F
        .byte " GOTO", $A0
        .byte $60
        .byte " IF", $A0
        .byte $61
        .byte " PRINT", $A0
        .byte $62
        .byte " PRINT", $A0
        .byte $63
        .byte " PRINT", $A0
        .byte $64
        .byte " POKE", $A0
        .byte $65
        .byte $AC
        .byte $70
        .byte $BD
        .byte $71
        .byte $BD
        .byte $72
        .byte $A9
        .byte 0

; ------------------------------------------------------------ start up
; GEN2 driver signature at $0800-$0807.  TODO(Bernie): the real bytes, and the
; A/X/Y parameters of the call at $0C00, are still to be specified.
        .res $E2B3-*, 0         ; warm start entry (E2B3R), as the Apple-1 BASIC
        jmp WARM
GSIG:   .byte "GEN2CARD"

COLD:   cld
        ldx #$FF
        txs
        lda #0
        sta LOMEM
        sta PTR
        lda #8
        sta LOMEM+1
        lda #$10                ; probe the RAM from $1000 up in 4K steps
@probe: sta PTR+1
        ldy #0
        lda (PTR),y
        eor #$FF
        sta (PTR),y
        cmp (PTR),y
        php
        eor #$FF
        sta (PTR),y
        plp
        bne @top
        lda PTR+1
        clc
        adc #$10
        cmp #$C0
        bcc @probe
@top:   lda PTR+1
        sta HIMEM+1
        lda #0
        sta HIMEM
        ldx #7                  ; GEN2 driver loaded at $0800 ?
@sig:   lda $0800,x
        cmp GSIG,x
        bne @nog
        dex
        bpl @sig
        lda #0                  ; TODO(Bernie): parameters of the call
        tax
        tay
        jsr $0C00               ; initialise the driver (once)
        lda #$20                ; LOMEM above its reserved area $0C00-$1FFF
        sta LOMEM+1
        lda #0
        sta LOMEM
@nog:   lda HIMEM
        sta PP
        lda HIMEM+1
        sta PP+1
        lda LOMEM
        sta PV
        lda LOMEM+1
        sta PV+1
        jsr INIT
        lda #<M_BAN
        sta PTR
        lda #>M_BAN
        sta PTR+1
        jsr PRSTR
        jmp PROMPT

; warm start ($E2B3): keeps LOMEM, HIMEM, PP, PV as loaded from tape
WARM:   cld
        ldx #$FF
        txs
        jsr INIT
        jmp PROMPT

INIT:   lda #0
        sta AUTON
        sta KB
        sta COL
        lda #$A7
        sta RS
        lda #$3D
        sta RS+1
        rts

; ------------------------------------------------------------ output
; PUTC: write A (bit 7 ignored); preserves X and Y; A is lost
PUTC:   pha
        and #$7F
        sta LAST
        ora #$80
        jsr ECHO
        pla
        and #$7F
        cmp #CR
        beq @cr
        inc COL                 ; not reset at 40: TAB 45 prints 44 spaces, like the Apple-1 BASIC
        rts
@cr:    lda #0
        sta COL
@r:     rts

CRLF:   lda #CR
        jmp PUTC

SPACE:  lda #' '
        jmp PUTC

; PRSTR: print the string at PTR (last character has bit 7 set; CR = $0D)
PRSTR:  ldy #0
@l:     lda (PTR),y
        pha
        jsr PUTC
        pla
        iny
        cmp #$80
        bcc @l
        rts

; PRMSG: print message number A (without the *** and ERR)
PRMSG:  tax
        setptr MSGS
@s:     dex
        bmi PRSTR
        ldy #0
@e:     lda (PTR),y
        iny
        cmp #$80
        bcc @e
        tya
        clc
        adc PTR
        sta PTR
        bcc @s
        inc PTR+1
        bne @s

; PRNUM: print ACC as a signed decimal number
PRNUM:  lda ACC+1
        bpl PRUNS
        lda #'-'
        jsr PUTC
        jsr NEG
PRUNS:  lda #0
        pha
@d:     jsr DIV10
        ora #'0'
        pha
        lda ACC
        ora ACC+1
        bne @d
@p:     pla
        beq @r
        jsr PUTC
        jmp @p
@r:     rts

; DIV10: ACC = ACC / 10 (unsigned), A = remainder
DIV10:  ldx #16
        lda #0
@l:     asl ACC
        rol ACC+1
        rol a
        cmp #10
        bcc @n
        sbc #10
        inc ACC
@n:     dex
        bne @l
        rts

; ------------------------------------------------------------ input
; GETCH: next key (7 bit); a key taken by the ESC test comes first
GETCH:  lda KB
        beq @w
        ldx #0
        stx KB
        rts
@w:     inc RS                  ; the seed of RND runs while we wait
        bne @k
        inc RS+1
@k:     lda KBDCR
        bpl @w
        lda KBD
        and #$7F
        rts

; CHKKEY (while running): any key stops the program (like the Apple-1 BASIC);
; the key stays pending and becomes the first character of the next line
CHKKEY: lda KBDCR
        bpl @r
        jmp STOPKEY
@r:     rts

; GETLN: print the prompt A and read a line into IBUF (CR terminated)
GETLN:  jsr PUTC
        ldx #0
GETLX:  stx T3                  ; X = characters already in the buffer
@k:     jsr GETCH
        cmp #$1B
        beq @esc
        cmp #CR
        beq @cr
        cmp #'_'
        beq @bs
        cmp #' '
        bcc @k
        ldx T3
        sta IBUF,x
        inc T3
        jsr PUTC
        lda T3
        cmp #128                ; a full line (128 characters) is cancelled, like ESC
        bne @k
        jmp @esc
@bs:    jsr PUTC
        lda T3
        beq @k
        dec T3
        jmp @k
@esc:   lda #'\'                ; cancel: backslash, new line, no new prompt
        jsr PUTC
        jsr CRLF
        ldx #0
        jmp GETLX
@cr:    ldx T3
        sta IBUF,x
        jmp CRLF

; ------------------------------------------------------------ tokenizer
; Turns the typed line (IBUF) into the tokens of the Apple-1 Integer BASIC
; (same values, context by context) in OBUF: length, number (lo, hi), tokens, $01.
PH      = $31                   ; index of a token to patch in OBUF
LP      = $32                   ; LIST: line pointer (2)
TOK     = $34                   ; statement token being executed
FORSP   = $35                   ; FOR stack depth (bytes)
GOSP    = $36                   ; GOSUB stack depth (bytes)
DIRF    = $37                   ; 1 = executing the typed line
LSF     = $38                   ; LIST: something printed on this line
PNM     = $39                   ; LIST: previous token was a name
INPF    = $3A                   ; INPUT is parsing a value
NOQ     = $3B                   ; INPUT: a prompt string was given
NEWL    = $3C                   ; INPUT: a new line must be read
PCOM    = $3F                   ; PRINT: a comma is pending
IPV     = $3D                   ; INPUT: start of the variable (2)
FORSTK  = $50                   ; 8 FOR frames of 10 bytes ($50-$9F)
GOSTK   = $A0                   ; 8 GOSUB frames of 4 bytes ($A0-$BF)

SYNERR: lda #E_SYN
        jmp ERROR
SYNERRJ: jmp SYNERR

; PK: skip spaces, A = next character of IBUF (not consumed)
PK:     ldx SI
@a:     lda IBUF,x
        cmp #' '
        bne @b
        inx
        bne @a
@b:     stx SI
        rts

; EM: store the token A in OBUF
EM:     ldy OI
        bmi @l
        sta OBUF,y
        inc OI
        rts
@l:     lda #E_LONG
        jmp ERROR

; EATC: next character must be A, then emit T1
EATC:   sta T2
        jsr PK
        cmp T2
        bne SYNERR
        inc SI
        lda T1
        jmp EM

EATRP:  lda #$72
        sta T1
        lda #')'
        jmp EATC

; MKW: PTR = keyword (last char bit 7); match it ignoring spaces; C=1 and SI
; moved on success, C=0 and SI unchanged otherwise.  Y = index after the text.
MKW:    lda SI
        pha
        ldy #0
@l:     jsr PK
        eor (PTR),y
        and #$7F
        bne @f
        inc SI
        lda (PTR),y
        iny
        cmp #$80
        bcc @l
        pla
        sec
        rts
@f:     pla
        sta SI
        clc
        rts

; MTAB: PTR = table of (text, byte); A = byte of the first entry matching
MTAB:   ldy #0
        lda (PTR),y
        beq @no
        jsr MKW
        bcs @hit
        ldy #0
@s:     lda (PTR),y
        iny
        cmp #$80
        bcc @s
        iny
        tya
        clc
        adc PTR
        sta PTR
        bcc MTAB
        inc PTR+1
        bne MTAB
@hit:   lda (PTR),y
        sec
        rts
@no:    clc
        rts

; DIGITS: ACC = decimal number at SI (a digit is there), at most 32767
DIGITS: lda #0
        sta ACC
        sta ACC+1
@l:     jsr PK
        cmp #'0'
        bcc @r
        cmp #'9'+1
        bcs @r
        inc SI
        and #$0F
        pha
        lda ACC+1
        cmp #$0D
        bcs @big
        lda ACC
        sta W1
        lda ACC+1
        sta W1+1
        asl ACC
        rol ACC+1
        asl ACC
        rol ACC+1
        clc
        lda ACC
        adc W1
        sta ACC
        lda ACC+1
        adc W1+1
        sta ACC+1
        asl ACC
        rol ACC+1
        pla
        clc
        adc ACC
        sta ACC
        bcc @n
        inc ACC+1
@n:     lda ACC+1
        bpl @l
@big:   lda #E_BIG
        jmp ERROR
@r:     rts

; TNUM: constant at SI -> $B0+first digit, lo, hi
TNUM:   jsr PK
        sta T3
        jsr DIGITS
        lda T3
        and #$0F
        ora #$B0
        jsr EM
        lda ACC
        jsr EM
        lda ACC+1
        jmp EM

; TNAME: name (letter, digit or $); C=1 for a string
TNAME:  jsr PK
        cmp #'A'
        bcs *+5      ; far branch: bcc SYNERR
        jmp SYNERR
        cmp #'Z'+1
        bcc *+5      ; far branch: bcs SYNERR
        jmp SYNERR
        inc SI
        ora #$80
        jsr EM
        jsr PK
        cmp #'0'
        bcc @nd
        cmp #'9'+1
        bcs @nd
        inc SI
        ora #$80
        jsr EM
        jsr PK
        cmp #'$'
        bne *+5      ; far branch: beq SYNERR
        jmp SYNERR
        cmp #'0'
        bcc @e
        cmp #'9'+1
        bcs *+5      ; far branch: bcc SYNERR
        jmp SYNERR
@e:     jsr NAMEEND
        clc
        rts
@nd:    cmp #'$'
        bne @e
        inc SI
        lda #$40
        jsr EM
        sec
        rts

; a letter after a name must start THEN, TO, STEP, AND, OR or MOD
NAMEEND: jsr PK
        cmp #'A'
        bcc @ok
        cmp #'Z'+1
        bcs @ok
        lda SI
        pha
        setptr NMTAB
        jsr MTAB
        pla
        sta SI
        bcs @ok
        jmp SYNERR
@ok:    rts

TLIT:   jsr PK
        cmp #'"'
        beq *+5      ; far branch: bne SYNERR
        jmp SYNERR
        inc SI
        lda #$28
        jsr EM
@c:     ldx SI
        lda IBUF,x
        cmp #CR
        bne *+5      ; far branch: beq SYNERRJ
        jmp SYNERRJ
        inc SI
        cmp #'"'
        beq @e
        ora #$80
        jsr EM
        jmp @c
@e:     lda #$29
        jmp EM

TSTAIL: jsr PK
        cmp #'('
        bne @r
        inc SI
        lda #$2A
        jsr EM
        jsr TEXPR
        jsr PK
        cmp #','
        bne @c
        inc SI
        lda #$23
        jsr EM
        jsr TEXPR
@c:     jmp EATRP
@r:     rts

TSEXPR: jsr PK
        cmp #'"'
        beq TLIT
        jsr TNAME
        bcs *+5      ; far branch: bcc SYNERR
        jmp SYNERR
        jmp TSTAIL

TSUBS:  jsr PK
        cmp #'('
        bne @r
        inc SI
        lda #$2D
        jsr EM
        jsr TEXPR
        jmp EATRP
@r:     rts

; AFTERS: after a string operand, A = string_ok. C=1: lone string.
AFTERS: pha
        jsr PK
        cmp #'='
        beq @eq
        cmp #'#'
        beq @ne
        pla
        bne @str
        jmp SYNERR
@str:   sec
        rts
@eq:    ldx #$39
        bne @go
@ne:    ldx #$3A
@go:    pla
        inc SI
        txa
        jsr EM
        jsr TSEXPR
        clc
        rts

NOTW:   .byte "NO", $D4
LENW:   .byte "LE", $CE
TOW:    .byte "T", $CF
STEPW:  .byte "STE", $D0
THENW:  .byte "THE", $CE
MANW:   .byte "MA", $CE

; TPRIM: primary, A = string_ok.  C=1 for a lone string.
TPRIM:  pha
        jsr PK
        cmp #CR
        beq @syn
        cmp #'0'
        bcc @n1
        cmp #'9'+1
        bcs @n1
        jsr TNUM
        pla
        clc
        rts
@syn:   jmp SYNERR
@n1:    cmp #'('
        bne @n2
        inc SI
        lda #$38
        jsr EM
        jsr TEXPR
        jsr EATRP
        pla
        clc
        rts
@n2:    cmp #'"'
        bne @n3
        jsr TLIT
        jmp @afs
@n3:    setptr FNTAB
        jsr MTAB
        bcc @n4
        jsr EM
        eat '(', $3F
        jsr TEXPR
        jsr EATRP
        pla
        clc
        rts
@n4:    setptr LENW
        jsr MKW
        bcc @nm
        jsr PK
        cmp #'('
        bne @syn
        inc SI
        lda #$3B
        jsr EM
        jsr TSEXPR
        jsr EATRP
        pla
        clc
        rts
@nm:    jsr TNAME
        bcc @num
        jsr TSTAIL
@afs:   pla
        jmp AFTERS
@num:   jsr TSUBS
        pla
        clc
        rts

; TOPERAND: operand with its sign or NOT, A = string_ok
TOPERAND: pha
        jsr PK
        cmp #'-'
        beq @m
        cmp #'+'
        beq @p
        setptr NOTW
        jsr MKW
        bcs @not
        pla
        jmp TPRIM
@m:     ldx #$36
        bne @u
@p:     ldx #$35
@u:     inc SI
        txa
        jsr EM
        jmp @pr
@not:   lda #$37
        jsr EM
@pr:    lda #0
        jsr TPRIM
        pla
        clc
        rts

; TANY: expression of either kind; C=1 for a lone string
TANY:   lda #1
        jsr TOPERAND
        bcs @r
@l:     setptr BOPTAB
        jsr MTAB
        bcc @d
        jsr EM
        lda #0
        jsr TOPERAND
        bcs @syn
        jmp @l
@d:     clc
@r:     rts
@syn:   jmp SYNERR

TEXPR:  jsr TANY
        bcs @syn
        rts
@syn:   jmp SYNERR

; ---- statements
HTAB:   .word H_REM, H_LET, H_DIM, H_INPUT, H_FOR, H_NEXT, H_IF, H_PRINT, H_POKE

STMT:   jsr PK
        cmp #CR
        beq @r
        cmp #':'
        beq @r
        setptr STMTAB
        jsr MTAB
        bcc ASSIGN
        cmp #$40
        bcc @sp
        pha
        and #$7F
        jsr EM
        pla
        bpl @r
        jmp TEXPR
@sp:    tax
        lda HTAB,x
        sta PTR
        lda HTAB+1,x
        sta PTR+1
        jmp (PTR)
@r:     rts

H_REM:  lda #$5D
        jsr EM
@l:     ldx SI
        lda IBUF,x
        cmp #CR
        beq @r
        inc SI
        ora #$80
        jsr EM
        jmp @l
@r:     rts

H_LET:  lda #$5E
        jsr EM
ASSIGN: jsr TNAME
        bcc @num
        jsr PK
        cmp #'('
        bne @eq
        inc SI
        lda #$42
        jsr EM
        jsr TEXPR
        jsr EATRP
@eq:    eat '=', $70
        jmp TSEXPR
@num:   jsr TSUBS
        eat '=', $71
        jmp TEXPR

PHOLD:  lda #0
        ldy OI
        sty PH
        jmp EM
PATCH:  ldy PH
        sta OBUF,y
        rts

DIMITEM: jsr TNAME
        php
        lda #$34
        bcc @t
        lda #$22
@t:     sta T1
        lda #'('
        jsr EATC
        jsr TEXPR
        jsr EATRP
        plp
        rts

H_DIM:  jsr PHOLD
        jsr DIMITEM
        lda #$4F
        bcc @a
        lda #$4E
@a:     jsr PATCH
@l:     jsr PK
        cmp #','
        bne @r
        inc SI
        jsr PHOLD
        jsr DIMITEM
        lda #$44
        bcc @b
        lda #$43
@b:     jsr PATCH
        jmp @l
@r:     rts

INVAR:  jsr TNAME
        php
        jsr PK
        cmp #'('
        bne @e
        inc SI
        lda #$2D
        plp
        php
        bcc @t
        lda #$42
@t:     jsr EM
        jsr TEXPR
        jsr EATRP
@e:     plp
        rts

H_INPUT: jsr PHOLD
        jsr PK
        cmp #'"'
        bne @v
        lda #$53
        jsr PATCH
        jsr TLIT
        jsr PK
        cmp #','
        beq @more
        jmp SYNERR
@v:     jsr INVAR
        lda #$54
        bcc @a
        lda #$52
@a:     jsr PATCH
@more:  jsr PK
        cmp #','
        bne @r
        inc SI
        jsr PHOLD
        jsr INVAR
        lda #$27
        bcc @b
        lda #$26
@b:     jsr PATCH
        jmp @more
@r:     rts

H_FOR:  lda #$55
        jsr EM
        jsr TNAME
        bcs @syn
        jsr PK
        cmp #'('
        beq @syn
        eat '=', $56
        jsr TEXPR
        setptr TOW
        jsr MKW
        bcc @syn
        lda #$57
        jsr EM
        jsr TEXPR
        setptr STEPW
        jsr MKW
        bcc @r
        lda #$58
        jsr EM
        jmp TEXPR
@r:     rts
@syn:   jmp SYNERR

NUMNAME: jsr TNAME
        bcs @syn
        rts
@syn:   jmp SYNERR

H_NEXT: lda #$59
        jsr EM
        jsr NUMNAME
@l:     jsr PK
        cmp #','
        bne @r
        inc SI
        lda #$5A
        jsr EM
        jsr NUMNAME
        jmp @l
@r:     rts

H_IF:   lda #$60
        jsr EM
        jsr TEXPR
        setptr THENW
        jsr MKW
        bcc @syn
        jsr PK
        cmp #'0'
        bcc @st
        cmp #'9'+1
        bcs @st
        lda #$24
        jsr EM
        jmp TNUM
@st:    lda #$25
        jsr EM
        jmp STMT
@syn:   jmp SYNERR

H_PRINT: lda #$63
        jsr EM
        ldy OI
        dey
        sty PH
        jsr PK
        cmp #CR
        beq @r
        cmp #':'
        beq @r
        jsr TANY
        lda #$62
        bcc @a
        lda #$61
@a:     jsr PATCH
@sep:   jsr PK
        cmp #';'
        beq @s
        cmp #','
        bne @r
@s:     inc SI
        pha
        jsr PHOLD
        jsr PK
        cmp #CR
        beq @end
        cmp #':'
        beq @end
        jsr TANY
        php
        pla
        and #1
        sta T3
        pla
        ldx #$46
        cmp #';'
        beq @sm
        ldx #$49
@sm:    txa
        sec
        sbc T3
        jsr PATCH
        jmp @sep
@end:   pla
        cmp #','
        beq @syn
        lda #$47
        jmp PATCH
@r:     rts
@syn:   jmp SYNERR

H_POKE: lda #$64
        jsr EM
        jsr TEXPR
        eat ',', $65
        jmp TEXPR

TOKSTMTS:
@l:     jsr STMT
        jsr PK
        cmp #CR
        beq @e
        cmp #':'
        beq *+5      ; far branch: bne SYNERRJ
        jmp SYNERRJ
        inc SI
        jsr PK
        cmp #CR                 ; nothing after the colon: syntax error
        bne *+5      ; far branch: beq SYNERRJ
        jmp SYNERRJ
        lda #$03
        jsr EM
        jmp @l
@e:     lda #$01
        jsr EM
        lda OI
        sta OBUF
        lda LN
        sta OBUF+1
        lda LN+1
        sta OBUF+2
        rts

; ------------------------------------------------------------ prompt, line entry
PROMPT: ldx #$FF
        txs
        lda #1
        sta DIRF
        sta KB
        lda #0
        sta KB
        sta INPF
        lda AUTON
        beq @n
        lda #'>'
        jsr PUTC
        lda AUTOL
        sta ACC
        lda AUTOL+1
        sta ACC+1
        jsr PRUNS
        jsr SPACE
        ldx #0
        jsr GETLX
        jmp PROCESS
@n:     lda #'>'
        jsr GETLN
PROCESS: lda #0
        sta SI
        lda #3
        sta OI
        jsr PK
        cmp #CR
        bne @1
        jmp PROMPT
@1:     cmp #'0'
        bcc @nn
        cmp #'9'+1
        bcc @num
@nn:    lda AUTON
        beq @cmd
        setptr MANW
        jsr MKW
        bcc @auto
        lda #0
        sta AUTON
        jmp PROMPT
@auto:  lda AUTOL
        sta LN
        lda AUTOL+1
        sta LN+1
        jmp @lineno
@cmd:   setptr IMMTAB
        jsr MTAB
        bcc *+5      ; far branch: bcs COMMAND
        jmp COMMAND
        lda #0
        sta LN
        sta LN+1
        jsr TOKSTMTS
        lda #<OBUF
        sta CUR
        lda #>OBUF
        sta CUR+1
        lda #<(OBUF+3)
        sta IP
        lda #>(OBUF+3)
        sta IP+1
        jmp EXEC
@num:   jsr DIGITS
        lda ACC
        sta LN
        lda ACC+1
        sta LN+1
@lineno: jsr PK
        cmp #CR
        bne @st
        jsr DELLN
        jmp PROMPT
@st:    jsr TOKSTMTS
        jsr DELLN
        jsr INSLN
        lda AUTON
        beq @r
        clc
        lda LN
        adc ASTEP
        sta AUTOL
        lda LN+1
        adc #0
        sta AUTOL+1
@r:     jmp PROMPT

; DONE: end of a typed command or statement
DONE:   jsr CRLF
        jmp PROMPT

; FINDLN: PTR = first line number >= LN; C=1 when equal
FINDLN: lda PP
        sta PTR
        lda PP+1
        sta PTR+1
@l:     lda PTR
        cmp HIMEM
        lda PTR+1
        sbc HIMEM+1
        bcs @no
        ldy #2
        lda (PTR),y
        cmp LN+1
        bcc @nx
        bne @no
        dey
        lda (PTR),y
        cmp LN
        bcc @nx
        beq @eq
@no:    clc
        rts
@eq:    sec
        rts
@nx:    ldy #0
        lda (PTR),y
        clc
        adc PTR
        sta PTR
        bcc @l
        inc PTR+1
        bne @l

; COPYUP / COPYDN: copy CNT bytes from S1 to S2 (S1, S2 on the last byte / first byte)
MOVUP:  lda CNT
        ora CNT+1
        beq @r
        ldy #0
        lda (S1),y
        sta (S2),y
        dec16 S1
        dec16 S2
        dec16 CNT
        jmp MOVUP
@r:     rts
MOVDN:  lda CNT
        ora CNT+1
        beq @r
        ldy #0
        lda (S1),y
        sta (S2),y
        inc16 S1
        inc16 S2
        dec16 CNT
        jmp MOVDN
@r:     rts

; DELLN: delete the line LN if present (the variables are kept, as in the Apple-1 BASIC)
DELLN:
        jsr FINDLN
        bcc @r
        ldy #0
        lda (PTR),y
        sta T1                  ; length
        ; move [PP, PTR) up by the length: copy backwards
        sec
        lda PTR
        sbc PP
        sta CNT
        lda PTR+1
        sbc PP+1
        sta CNT+1
        lda PTR
        bne @a
        dec PTR+1
@a:     dec PTR
        lda PTR
        sta S1
        lda PTR+1
        sta S1+1
        clc
        adc #0
        lda PTR
        clc
        adc T1
        sta S2
        lda PTR+1
        adc #0
        sta S2+1
        jsr MOVUP
        clc
        lda PP
        adc T1
        sta PP
        bcc @r
        inc PP+1
@r:     rts

; INSLN: insert the tokenized line of OBUF
INSLN:  jsr FINDLN              ; PTR = insertion point
        lda OBUF
        sta T1
        sec
        lda PP
        sbc T1
        sta S2
        lda PP+1
        sbc #0
        sta S2+1
        bcc @mem
        lda S2
        cmp PV
        lda S2+1
        sbc PV+1
        bcs @ok
@mem:   lda #E_MEM
        jmp ERROR
@ok:    lda S2
        pha
        lda S2+1
        pha
        lda PP
        sta S1
        lda PP+1
        sta S1+1
        sec
        lda PTR
        sbc PP
        sta CNT
        lda PTR+1
        sbc PP+1
        sta CNT+1
        jsr MOVDN
        ; copy the new line below PTR
        sec
        lda PTR
        sbc T1
        sta S2
        lda PTR+1
        sbc #0
        sta S2+1
        lda #<OBUF
        sta S1
        lda #>OBUF
        sta S1+1
        lda T1
        sta CNT
        lda #0
        sta CNT+1
        jsr MOVDN
        pla
        sta PP+1
        pla
        sta PP
        rts

CLR:    lda LOMEM
        sta PV
        lda LOMEM+1
        sta PV+1
        lda #0
        sta FORSP
        sta GOSP
        rts

; ------------------------------------------------------------ immediate commands
COMMAND: asl a
        tax
        lda CTAB,x
        sta PTR
        lda CTAB+1,x
        sta PTR+1
        jmp (PTR)
CTAB:   .word C_LIST, C_RUN, C_CLR, C_NEW, C_DEL, C_AUTO, C_MAN

; ARGNUM: C=1 and ACC = number when a number follows
ARGNUM: jsr PK
        cmp #'0'
        bcc @n
        cmp #'9'+1
        bcs @n
        jsr DIGITS
        sec
        rts
@n:     clc
        rts
ENDARG: jsr PK
        cmp #CR
        beq *+5      ; far branch: bne SYNERRJ
        jmp SYNERRJ
        rts

C_CLR:  jsr ENDARG
        jsr CLR
        jmp DONE
C_NEW:  jsr ENDARG
        lda HIMEM
        sta PP
        lda HIMEM+1
        sta PP+1
        jsr CLR
        jmp DONE
C_MAN:  jsr ENDARG
        lda #0
        sta AUTON
        jmp DONE
C_AUTO: lda #10
        sta ASTEP
        lda #0
        sta AUTOL+1
        sta AUTOL
        jsr ARGNUM
        bcc @e
        lda ACC
        sta AUTOL
        lda ACC+1
        sta AUTOL+1
        jsr PK
        cmp #','
        bne @e
        inc SI
        jsr ARGNUM
        bcs *+5      ; far branch: bcc SYNERRJ
        jmp SYNERRJ
        lda ACC
        sta ASTEP
@e:     jsr ENDARG
        lda #1
        sta AUTON
        jmp DONE
C_DEL:  jsr ARGNUM
        bcs *+5      ; far branch: bcc SYNERRJ
        jmp SYNERRJ
        lda ACC
        sta W1
        lda ACC+1
        sta W1+1
        lda ACC
        sta W2
        lda ACC+1
        sta W2+1
        jsr PK
        cmp #','
        bne @e
        inc SI
        jsr ARGNUM
        bcs *+5      ; far branch: bcc SYNERRJ
        jmp SYNERRJ
        lda ACC
        sta W2
        lda ACC+1
        sta W2+1
@e:     jsr ENDARG
@l:     lda W1
        sta LN
        lda W1+1
        sta LN+1
        jsr FINDLN
        lda PTR                 ; end of the program ?
        cmp HIMEM
        lda PTR+1
        sbc HIMEM+1
        bcs @d
        ldy #2                  ; line number > W2 ?
        lda W2+1
        cmp (PTR),y
        bcc @d
        bne @go
        dey
        lda W2
        cmp (PTR),y
        bcc @d
@go:    ldy #1
        lda (PTR),y
        sta W1
        iny
        lda (PTR),y
        sta W1+1
        jsr DELLN
        jmp @l
@d:     jmp DONE

C_RUN:  jsr ARGNUM
        bcs @n
        lda #0
        sta ACC
        sta ACC+1
@n:     jsr ENDARG
        jsr CLR
        lda ACC
        sta LN
        lda ACC+1
        sta LN+1
        jsr FINDLN
        lda ACC
        ora ACC+1
        beq @top
        bcc BADBR
@top:   lda PTR
        cmp HIMEM
        lda PTR+1
        sbc HIMEM+1
        bcs ENDERR
        jmp SETLINE
BADBR:  lda #E_BRA
        jmp ERROR
ENDERR: lda #E_END
        jmp ERROR

; SETLINE: CUR = PTR, IP after the line header; run
SETLINE: lda PTR
        sta CUR
        clc
        adc #3
        sta IP
        lda PTR+1
        sta CUR+1
        adc #0
        sta IP+1
        lda #0
        sta DIRF
        jmp EXEC

; ------------------------------------------------------------ LIST
C_LIST: lda #0
        sta W1
        sta W1+1
        lda #$FF
        sta W2
        lda #$7F
        sta W2+1
        jsr ARGNUM
        bcc @e
        lda ACC
        sta W1
        sta W2
        lda ACC+1
        sta W1+1
        sta W2+1
        jsr PK
        cmp #','
        bne @e
        inc SI
        jsr ARGNUM
        bcs *+5      ; far branch: bcc SYNERRJ
        jmp SYNERRJ
        lda ACC
        sta W2
        lda ACC+1
        sta W2+1
@e:     jsr ENDARG
        lda PP
        sta LP
        lda PP+1
        sta LP+1
@l:     lda LP
        cmp HIMEM
        lda LP+1
        sbc HIMEM+1
        bcs @d
        ldy #2
        lda (LP),y
        cmp W2+1
        bcc @in
        bne @d
        dey
        lda (LP),y
        cmp W2
        beq @in
        bcs @d
@in:    ldy #2                  ; below the first requested line ?
        lda (LP),y
        cmp W1+1
        bcc @sk
        bne @do
        dey
        lda (LP),y
        cmp W1
        bcc @sk
@do:    jsr LISTLN
@sk:    ldy #0
        lda (LP),y
        clc
        adc LP
        sta LP
        bcc @l
        inc LP+1
        jmp @l
@d:     jmp DONE

; LPUT: print A, continuing a long line with a 6 space indent
LPUT:   jmp PUTC

; LWRAP: before a listed element: past column 31 continue on a new line with a 6 space indent
LWRAP:  pha
        lda COL
        cmp #32
        bcc LWR
        jsr LIND
LWR:    pla
        rts
; LCW: after a character of a string or a REM: past column 36 wrap
LCW:    pha
        lda COL
        cmp #37
        bcc LWR
        jsr LIND
        pla
        rts
LIND:   lda LAST                ; the leading space of a token is still dropped after a space
        pha
        jsr CRLF
        ldx #6
@i:     lda #' '
        jsr PUTC
        dex
        bne @i
        pla
        sta LAST
        rts

; LNUM: print ACC through LPUT
LNUM:   lda #0
        pha
@d:     jsr DIV10
        ora #'0'
        pha
        lda ACC
        ora ACC+1
        bne @d
@p:     pla
        beq @r
        jsr LPUT
        jmp @p
@r:     rts

; LTEXT: print the text of token A (a leading space is skipped after a space)
LTEXT:  sta T2
        setptr TOKTXT
@f:     ldy #0
        lda (PTR),y
        beq @r
        cmp T2
        beq @m
@s:     iny
        lda (PTR),y
        cmp #$80
        bcc @s
        iny
        tya
        clc
        adc PTR
        sta PTR
        bcc @f
        inc PTR+1
        bne @f
@m:     iny
        lda (PTR),y
        cmp #' '
        bne @p
        lda LAST
        cmp #' '
        bne @p
        iny
@p:     lda (PTR),y
        pha
        and #$7F
        jsr LPUT
        pla
        iny
        cmp #$80
        bcc @p
@r:     rts

LISTLN: lda #0
        sta LSF
        sta PNM
        ldy #1
        lda (LP),y
        sta ACC
        iny
        lda (LP),y
        sta ACC+1
        ; number right aligned in 5 columns
        lda ACC
        pha
        lda ACC+1
        pha
        lda #0
        sta T3
@c:     jsr DIV10
        inc T3
        lda ACC
        ora ACC+1
        bne @c
        pla
        sta ACC+1
        pla
        sta ACC
        lda #5
        sec
        sbc T3
        tax
        beq @np
@pad:   lda #' '
        jsr LPUT
        dex
        bne @pad
@np:    jsr LNUM
        lda #' '
        jsr LPUT
        lda LP
        clc
        adc #3
        sta CNT
        lda LP+1
        adc #0
        sta CNT+1               ; CNT = token pointer
@t:     ldy #0
        lda (CNT),y
        inc16 CNT
        jsr LWRAP
        cmp #$01
        bne *+5      ; far branch: beq @end
        jmp @end
        cmp #$5D
        beq @rem
        cmp #$28
        bne *+5      ; far branch: beq @lit
        jmp @lit
        cmp #$C1
        bcc @n1
        cmp #$DB
        bcs @n1
        and #$7F
        jsr LPUT
        lda #1
        sta PNM
        jmp @t
@n1:    cmp #$B0
        bcc @o
        cmp #$BA
        bcs @o
        ldx PNM
        beq @const
        and #$7F
        jsr LPUT
        lda #0
        sta PNM
        jmp @t
@const: ldy #0
        lda (CNT),y
        sta ACC
        iny
        lda (CNT),y
        sta ACC+1
        clc
        lda CNT
        adc #2
        sta CNT
        bcc @cn
        inc CNT+1
@cn:    jsr LNUM
        jmp @t
@o:     ldx #0
        stx PNM
        jsr LTEXT
        jmp @t
@rem:   jsr LTEXT
@rl:    ldy #0
        lda (CNT),y
        inc16 CNT
        cmp #$01
        beq @end
        and #$7F
        jsr LPUT
        jsr LCW
        jmp @rl
@lit:   lda #'"'
        jsr LPUT
        jsr LCW
@ll:    ldy #0
        lda (CNT),y
        inc16 CNT
        cmp #$29
        beq @le
        and #$7F
        jsr LPUT
        jsr LCW
        jmp @ll
@le:    lda #'"'
        jsr LPUT
        jsr LCW
        jmp @t
@end:   jmp CRLF

; ------------------------------------------------------------ errors
ERRMSG: ldx #3
@a:     lda #'*'
        jsr PUTC
        dex
        bne @a
        jsr SPACE
        lda T1
        jsr PRMSG
        lda T1
        cmp #E_PAR
        beq @n
        setptr M_ERR
        jsr PRSTR
@n:     jmp CRLF

ERROR:  sta T1
        ldx #$FF
        txs
        lda INPF
        beq *+5      ; far branch: bne INPERR
        jmp INPERR
        jsr ERRMSG
        lda T1
        cmp #E_END
        beq @p
        lda DIRF
        bne @p
        jsr STOPAT
@p:     jmp PROMPT

STOPAT: setptr M_STOP
        jsr PRSTR
        ldy #1
        lda (CUR),y
        sta ACC
        iny
        lda (CUR),y
        sta ACC+1
        jsr PRUNS
        jmp CRLF

STOPKEY: ldx #$FF
        txs
        lda DIRF
        bne @p
        lda COL
        beq @s
        jsr CRLF
@s:     jsr STOPAT
@p:     jmp PROMPT

M_RET:  .byte "RETYPE LIN", $C5

; ------------------------------------------------------------ executor
SYNJ:   jmp SYNERR

STAB:   .word S_CALL, S_DIM, S_DIM, S_TAB, S_END, S_INPUT, S_INPUT, S_INPUT
        .word S_FOR, S_ERR, S_ERR, S_ERR, S_NEXT, S_ERR, S_RETURN, S_GOSUB
        .word S_REM, S_LET, S_GOTO, S_IF, S_PRINT, S_PRINT, S_PRINT, S_POKE

EXEC:   jsr CHKKEY
        ldy #0
        lda (IP),y
        cmp #$C1
        bcc *+5      ; far branch: bcs S_ASSIGN
        jmp S_ASSIGN
        sec
        sbc #$4D
        bcc SYNJ
        cmp #$18
        bcs SYNJ
        pha
        lda (IP),y
        sta TOK
        pla
        asl a
        tax
        lda STAB,x
        sta PTR
        lda STAB+1,x
        sta PTR+1
        inc16 IP
        jmp (PTR)

ENDST:  ldy #0
        lda (IP),y
        cmp #$03
        bne @e1
        inc16 IP
        jmp EXEC
@e1:    cmp #$01
        bne SYNJ
        lda DIRF
        beq @p
        jmp DONE
@p:     ldy #0
        lda (CUR),y
        clc
        adc CUR
        sta CUR
        bcc @c
        inc CUR+1
@c:     lda CUR
        cmp HIMEM
        lda CUR+1
        sbc HIMEM+1
        bcs @end
        lda CUR
        clc
        adc #3
        sta IP
        lda CUR+1
        adc #0
        sta IP+1
        jmp EXEC
@end:   jmp ENDERR

; stubs of statements
S_REM:  ldy #0
@l:     lda (IP),y
        cmp #$01
        beq @e
        inc16 IP
        jmp @l
@e:     jmp ENDST
S_LET:  jmp EXEC                ; LET: the name follows
S_END:  lda DIRF
        beq @r
        jmp DONE
@r:     jmp DONE
S_CALL: jsr EVAL
        jsr @c
        jmp ENDST
@c:     jmp (ACC)
S_POKE: jsr EVAL
        lda ACC
        pha
        lda ACC+1
        pha
        lda #$65
        jsr EXPECT
        jsr EVAL
        lda ACC+1
        bne @r
        ldx ACC
        pla
        sta PTR+1
        pla
        sta PTR
        ldy #0
        txa
        sta (PTR),y
        jmp ENDST
@r:     lda #E_255
        jmp ERROR

; EXPECT: next token must be A
EXPECT: ldy #0
        cmp (IP),y
        beq *+5      ; far branch: bne SYNJ
        jmp SYNJ
        inc16 IP
        rts
RPAR:   lda #$72
        jmp EXPECT

S_TAB:  jsr EVAL
        lda ACC+1
        bmi @r
        ora ACC
        beq @r
        lda ACC
        sec
        sbc #1
        sta T1
@l:     lda COL
        cmp T1
        bcs @r
        jsr SPACE
        jmp @l
@r:     jmp ENDST

; GOTO / GOSUB
S_GOTO: jsr EVAL
GOTO2:  lda ACC
        sta LN
        lda ACC+1
        sta LN+1
        jsr FINDLN
        bcc BADBRJ
        jmp SETLINE
BADBRJ: jmp BADBR
S_GOSUB: ldx GOSP
        cpx #32
        bcc @ok
        lda #E_GOSUB
        jmp ERROR
@ok:    jsr EVAL
        ldx GOSP
        lda CUR
        sta GOSTK,x
        lda CUR+1
        sta GOSTK+1,x
        lda IP
        sta GOSTK+2,x
        lda IP+1
        sta GOSTK+3,x
        inx
        inx
        inx
        inx
        stx GOSP
        jmp GOTO2
S_RETURN: ldx GOSP
        bne @ok
        lda #E_RET
        jmp ERROR
@ok:    dex
        dex
        dex
        dex
        stx GOSP
        lda GOSTK,x
        sta CUR
        lda GOSTK+1,x
        sta CUR+1
        lda GOSTK+2,x
        sta IP
        lda GOSTK+3,x
        sta IP+1
        jmp ENDST

; IF
S_IF:   jsr EVAL
        ldy #0
        lda ACC
        ora ACC+1
        beq @f
        lda (IP),y
        inc16 IP
        cmp #$24
        beq @ln
        cmp #$25
        beq *+5      ; far branch: bne SYNJ
        jmp SYNJ
        jmp EXEC
@ln:    ldy #1
        lda (IP),y
        sta ACC
        iny
        lda (IP),y
        sta ACC+1
        jmp GOTO2
@f:     jsr SKIP
        jmp ENDST

; SKIP: advance IP to the next ':' or end of line, walking over the tokens
SKIP:   ldy #0
@l:     lda (IP),y
        cmp #$03
        bne *+5      ; far branch: beq @r
        jmp @r
        cmp #$01
        bne *+5      ; far branch: beq @r
        jmp @r
        inc16 IP
        cmp #$5D
        beq @rem
        cmp #$28
        beq @lit
        cmp #$C1
        bcs @nm
        cmp #$B0
        bcc @l
        cmp #$BA
        bcs @l
        clc
        lda IP
        adc #2
        sta IP
        bcc @l
        inc IP+1
        jmp @l
@nm:    lda (IP),y
        cmp #$B0
        bcc @l
        cmp #$BA
        bcs @l
        inc16 IP
        jmp @l
@lit:   lda (IP),y
        inc16 IP
        cmp #$29
        bne @lit
        jmp @l
@rem:   lda (IP),y
        cmp #$01
        beq @r
        inc16 IP
        jmp @rem
@r:     rts

; ------------------------------------------------------------ PRINT
S_PRINT: lda #0
        sta PCOM
        lda TOK
@item:  cmp #$63
        beq @cr
        cmp #$61
        beq @s
        cmp #$45
        beq @s
        cmp #$48
        beq @s
        jsr EVAL
        jsr PADC
        jsr PRNUM
        jmp @nx
@s:     jsr SEVAL
        jsr PADC
        jsr PRSV
@nx:    ldy #0
        lda (IP),y
        cmp #$47
        beq @semi
        cmp #$45
        beq @sep
        cmp #$46
        beq @sep
        cmp #$48
        beq @com
        cmp #$49
        beq @com
@cr:    jsr CRLF
        jmp ENDST
@semi:  inc16 IP
        jmp ENDST
@com:   inc16 IP
        sta PCOM                ; the padding comes once the next item is evaluated
        jmp @item
@sep:   inc16 IP
        jmp @item

; PADC: pending comma: pad to the next multiple of 8 (preserves A)
PADC:   lda PCOM
        beq @r
        lda #0
        sta PCOM
@t:     jsr SPACE
        lda COL
        and #7
        bne @t
@r:     rts

PRSV:   ldy #0
@l:     cpy SLN
        beq @r
        lda (SPT),y
        jsr PUTC
        iny
        bne @l
@r:     rts

; ------------------------------------------------------------ FOR / NEXT
S_FOR:  jsr LVNUM
        lda VP
        pha
        lda VP+1
        pha
        lda #$56
        jsr EXPECT
        jsr EVAL
        pla
        sta VP+1
        pla
        sta VP
        ldy #0
        lda ACC
        sta (VP),y
        iny
        lda ACC+1
        sta (VP),y
        lda VP
        pha
        lda VP+1
        pha
        lda #$57
        jsr EXPECT
        jsr EVAL
        lda ACC
        sta W2
        lda ACC+1
        sta W2+1
        ldy #0
        lda (IP),y
        cmp #$58
        bne @ds
        inc16 IP
        lda W2+1
        pha
        lda W2
        pha
        jsr EVAL
        pla
        sta W2
        pla
        sta W2+1
        lda ACC
        sta W1
        lda ACC+1
        sta W1+1
        jmp @fr
@ds:    lda #1
        sta W1
        lda #0
        sta W1+1
@fr:    pla
        sta VP+1
        pla
        sta VP
        ldx FORSP
@s:     txa
        beq @push
        sec
        sbc #10
        tax
        lda FORSTK,x
        cmp VP
        bne @s
        lda FORSTK+1,x
        cmp VP+1
        bne @s
        stx FORSP
@push:  ldx FORSP
        cpx #80
        bcc @ok
        lda #E_FORS
        jmp ERROR
@ok:    lda VP
        sta FORSTK,x
        lda VP+1
        sta FORSTK+1,x
        lda W2
        sta FORSTK+2,x
        lda W2+1
        sta FORSTK+3,x
        lda W1
        sta FORSTK+4,x
        lda W1+1
        sta FORSTK+5,x
        lda CUR
        sta FORSTK+6,x
        lda CUR+1
        sta FORSTK+7,x
        lda IP
        sta FORSTK+8,x
        lda IP+1
        sta FORSTK+9,x
        txa
        clc
        adc #10
        sta FORSP
        jmp ENDST
S_ERR:  jmp SYNERR

S_NEXT: jsr LVNUM
NEXT1:  ldx FORSP
@s:     txa
        bne @c
        lda #E_NXT
        jmp ERROR
@c:     sec
        sbc #10
        tax
        lda FORSTK,x
        cmp VP
        bne @s
        lda FORSTK+1,x
        cmp VP+1
        bne @s
        txa
        clc
        adc #10
        sta FORSP
        ldy #0
        clc
        lda (VP),y
        adc FORSTK+4,x
        sta (VP),y
        sta TMP
        iny
        lda (VP),y
        adc FORSTK+5,x
        bvs @ovf
        sta (VP),y
        sta TMP+1
        lda FORSTK+5,x
        bmi @neg
        lda FORSTK+2,x
        cmp TMP
        lda FORSTK+3,x
        sbc TMP+1
        jmp @cmp
@neg:   lda TMP
        cmp FORSTK+2,x
        lda TMP+1
        sbc FORSTK+3,x
@cmp:   bvc @v
        eor #$80
@v:     bmi @exit
        lda FORSTK+6,x
        sta CUR
        lda FORSTK+7,x
        sta CUR+1
        lda FORSTK+8,x
        sta IP
        lda FORSTK+9,x
        sta IP+1
        jmp ENDST
@ovf:   lda #E_BIG
        jmp ERROR
@exit:  stx FORSP
        ldy #0
        lda (IP),y
        cmp #$5A
        bne @en
        inc16 IP
        jmp S_NEXT
@en:    jmp ENDST

; ------------------------------------------------------------ expressions
; EVAL: ACC = value of the expression at IP
EVAL:   lda #1
EXPR:   pha
        jsr OPND
@loop:  ldy #0
        lda (IP),y
        cmp #$12
        bcc @done
        cmp #$21
        bcs @done
        tax
        lda PTAB-$12,x
        sta T3
        pla
        pha
        cmp T3
        beq @go
        bcs @done
@go:    txa
        pha
        lda ACC+1
        pha
        lda ACC
        pha
        inc16 IP
        lda T3
        clc
        adc #1
        jsr EXPR
        pla
        sta TMP
        pla
        sta TMP+1
        pla
        jsr APPLY
        jmp @loop
@done:  pla
        rts

; OPND: ACC = operand at IP
OPND:   tsx
        cpx #$40
        bcs @ok
        lda #E_PAR
        jmp ERROR
@ok:    ldy #0
        lda (IP),y
        cmp #$C1
        bcc *+5      ; far branch: bcs @var
        jmp @var
        cmp #$B0
        bcc @t
        cmp #$BA
        bcs @t
        iny
        lda (IP),y
        sta ACC
        iny
        lda (IP),y
        sta ACC+1
        clc
        lda IP
        adc #3
        sta IP
        bcc @r
        inc IP+1
@r:     rts
@t:     cmp #$28
        bne *+5      ; far branch: beq @slit
        jmp @slit
        inc16 IP
        cmp #$38
        bne @t1
        jsr EVAL
        jmp RPAR
@t1:    cmp #$35
        beq OPND
        cmp #$36
        bne @t2
        jsr OPND
        jmp NEG
@t2:    cmp #$37
        bne @t3
        jsr OPND
        lda ACC
        ora ACC+1
        beq @one
        lda #0
        beq @sv
@one:   lda #1
@sv:    sta ACC
        lda #0
        sta ACC+1
        rts
@t3:    cmp #$3B
        bne @t4
        jsr SEVAL
        jsr RPAR
        lda SLN
        sta ACC
        lda #0
        sta ACC+1
        rts
@t4:    cmp #$2E
        bcc @syn
        cmp #$32
        bcs @syn
        pha
        lda #$3F
        jsr EXPECT
        jsr EVAL
        jsr RPAR
        pla
        sec
        sbc #$2E
        asl a
        tax
        lda FTAB,x
        sta PTR
        lda FTAB+1,x
        sta PTR+1
        jmp (PTR)
@syn:   jmp SYNERR
@slit:  jsr SEVAL
        jmp SCMP
@var:   jsr NAMEPARSE
        ldy #0
        lda (IP),y
        cmp #$40
        beq @sv2
        jsr LVNUM2
        ldy #0
        lda (VP),y
        sta ACC
        iny
        lda (VP),y
        sta ACC+1
        rts
@sv2:   inc16 IP
        jsr SEVAL3
        jmp SCMP

FTAB:   .word F_PEEK, F_RND, F_SGN, F_ABS
F_PEEK: lda ACC
        sta PTR
        lda ACC+1
        sta PTR+1
        ldy #0
        lda (PTR),y
        sta ACC
        sty ACC+1
        rts
F_SGN:  lda ACC+1
        bmi @n
        ora ACC
        beq @z
        lda #1
        bne @s
@n:     lda #$FF
        sta ACC+1
@s:     sta ACC
        rts
@z:     rts
F_ABS:  lda ACC+1
        bpl @r
        jmp NEG
@r:     rts
F_RND:  lda ACC
        ora ACC+1
        bne @n
        lda #E_BIG
        jmp ERROR
@n:     lda RS+1
        lsr a
        lda RS
        ror a
        eor RS+1
        sta RS+1
        ror a
        eor RS
        sta RS
        eor RS+1
        sta RS+1
        lda ACC+1
        pha
        bpl @p
        jsr NEG
@p:     lda RS
        sta TMP
        lda RS+1
        and #$7F
        sta TMP+1
        jsr UDIV
        lda W1
        sta ACC
        lda W1+1
        sta ACC+1
        pla
        bpl @r
        jmp NEG
@r:     rts

; NEG: ACC = -ACC (-32768 cannot be negated)
NEG:    lda ACC
        ora ACC+1
        beq @r
        sec
        lda #0
        sbc ACC
        sta ACC
        lda #0
        sbc ACC+1
        sta ACC+1
        cmp #$80
        bne @r
        lda ACC
        bne @r
        lda #E_BIG
        jmp ERROR
@r:     rts

; UDIV: TMP / ACC unsigned; quotient in TMP, remainder in W1 (ACC <> 0 assumed)
UDIV:   lda #0
        sta W1
        sta W1+1
        ldx #16
@l:     asl TMP
        rol TMP+1
        rol W1
        rol W1+1
        sec
        lda W1
        sbc ACC
        tay
        lda W1+1
        sbc ACC+1
        bcc @n
        sta W1+1
        sty W1
        inc TMP
@n:     dex
        bne @l
        rts

; SIGNS: make TMP and ACC positive, SGN = sign of the result (xor)
SIGNS:  lda TMP+1
        eor ACC+1
        and #$80
        sta SGN
        lda TMP+1
        bpl @a
        sec
        lda #0
        sbc TMP
        sta TMP
        lda #0
        sbc TMP+1
        sta TMP+1
@a:     lda ACC+1
        bpl @r
        sec
        lda #0
        sbc ACC
        sta ACC
        lda #0
        sbc ACC+1
        sta ACC+1
@r:     rts

; FIXSG: result in ACC (unsigned, must be < 32768) with sign SGN
FIXSG:  lda ACC+1
        bmi OVF
        lda SGN
        bpl @r
        jmp NEG
@r:     rts
OVF:    lda #E_BIG
        jmp ERROR

; APPLY: ACC = TMP (op A) ACC
APPLY:  cmp #$16
        bcs @c
        sec
        sbc #$12
        asl a
        tax
        lda ATAB,x
        sta PTR
        lda ATAB+1,x
        sta PTR+1
        jmp (PTR)
@c:     cmp #$1D
        bcs @l
        sec
        sbc #$16
        tay
        lda CMASK,y
        sta T1
        lda TMP
        cmp ACC
        lda TMP+1
        sbc ACC+1
        bvc @v
        eor #$80
@v:     bmi @lt
        lda TMP
        cmp ACC
        bne @gt
        lda TMP+1
        cmp ACC+1
        bne @gt
        lda #2
        bne @k
@gt:    lda #1
        bne @k
@lt:    lda #4
@k:     and T1
        beq @z
        lda #1
@z:     sta ACC
        lda #0
        sta ACC+1
        rts
@l:     cmp #$1F
        bcs @m
        ; AND / OR on truth values
        tax
        lda ACC
        ora ACC+1
        beq @r0
        lda #1
@r0:    sta T1
        lda TMP
        ora TMP+1
        beq @l0
        lda #1
@l0:    cpx #$1D
        bne @or
        and T1
        jmp @sv
@or:    ora T1
@sv:    sta ACC
        lda #0
        sta ACC+1
        rts
@m:     cmp #$20
        bne @mod
        jmp POW
@mod:   jmp MODOP
; truth masks, bit 0 = TMP>ACC, bit 1 = equal, bit 2 = TMP<ACC (tokens $16..$1C)
CMASK:  .byte 2, 5, 3, 1, 6, 5, 4

ATAB:   .word A_ADD, A_SUB, A_MUL, A_DIV

A_ADD:  clc
        lda TMP
        adc ACC
        sta ACC
        lda TMP+1
        adc ACC+1
        sta ACC+1
        bvs OVFJ
        rts
OVFJ:   jmp OVF
A_SUB:  sec
        lda TMP
        sbc ACC
        sta ACC
        lda TMP+1
        sbc ACC+1
        sta ACC+1
        bvs OVFJ
        rts
A_MUL:  jsr SIGNS
        jsr UMUL
        jmp FIXSG
A_DIV:  lda ACC
        ora ACC+1
        beq OVFJ
        jsr SIGNS
        jsr UDIV
        lda TMP
        sta ACC
        lda TMP+1
        sta ACC+1
        jmp FIXSG
MODOP:  lda ACC
        ora ACC+1
        beq OVFJ
        jsr SIGNS
        jsr UDIV
        lda W1
        sta ACC
        lda W1+1
        sta ACC+1
        jmp FIXSG

; UMUL: ACC = TMP * ACC (unsigned, overflow above 32767)
UMUL:   lda #0
        sta W1
        sta W1+1
@l:     lda TMP
        ora TMP+1
        beq @d
        lsr TMP+1
        ror TMP
        bcc @s
        clc
        lda W1
        adc ACC
        sta W1
        lda W1+1
        adc ACC+1
        sta W1+1
        bmi OVFJ
@s:     lda TMP
        ora TMP+1
        beq @d
        asl ACC
        rol ACC+1
        bcs OVFJ
        bmi OVFJ
        jmp @l
@d:     lda W1
        sta ACC
        lda W1+1
        sta ACC+1
        rts

; POW: integer power (the original crashes here): TMP ^ ACC
POW:    lda ACC+1
        bmi @zero
        lda TMP
        sta W2
        lda TMP+1
        sta W2+1                ; base
        lda ACC
        sta T1
        lda ACC+1
        sta T2                  ; exponent
        lda #1
        sta ACC
        lda #0
        sta ACC+1
@l:     lda T1
        ora T2
        beq @r
        lda ACC
        sta TMP
        lda ACC+1
        sta TMP+1
        lda W2
        sta ACC
        lda W2+1
        sta ACC+1
        jsr A_MUL
        lda T1
        bne @d
        dec T2
@d:     dec T1
        jmp @l
@r:     rts
@zero:  lda #0
        sta ACC
        sta ACC+1
        rts

; ------------------------------------------------------------ variables
; Entry: key1 (letter token), key2 (digit token or 0), kind (0 number, 1 array,
; 2 string); numbers: 2 bytes of value; arrays and strings: size (2 bytes) then
; the data (array: 2 bytes per element; string: length byte, then characters).

; NAMEPARSE: IP on the letter token -> NK1, NK2; IP after the name
NAMEPARSE: ldy #0
        lda (IP),y
        sta NK1
        inc16 IP
        lda (IP),y
        cmp #$B0
        bcc @nd
        cmp #$BA
        bcs @nd
        sta NK2
        inc16 IP
        rts
@nd:    lda #0
        sta NK2
        rts

; LOOKUP: X = kind; C=1 and VP = entry when found
LOOKUP: stx T3
        lda LOMEM
        sta VP
        lda LOMEM+1
        sta VP+1
@l:     lda VP
        cmp PV
        lda VP+1
        sbc PV+1
        bcs @nf
        ldy #0
        lda (VP),y
        cmp NK1
        bne @nx
        iny
        lda (VP),y
        cmp NK2
        bne @nx
        iny
        lda (VP),y
        cmp T3
        bne @nx
        sec
        rts
@nx:    ldy #2
        lda (VP),y
        bne @arr
        lda #5
        ldx #0
        beq @add
@arr:   ldy #3
        lda (VP),y
        pha
        iny
        lda (VP),y
        tax
        pla
@add:   clc
        adc VP
        sta VP
        txa
        adc VP+1
        sta VP+1
        jmp @l
@nf:    clc
        rts

; CREATE: A = kind, W1 = total size; creates the zeroed entry at PV
CREATE: sta T3
        clc
        lda PV
        adc W1
        tax
        lda PV+1
        adc W1+1
        bcs @mem
        tay
        cpy PP+1
        bcc @ok
        bne @mem
        cpx PP
        bcc @ok
@mem:   lda #E_MEM
        jmp ERROR
@ok:    lda PV
        sta VP
        lda PV+1
        sta VP+1
        stx PV
        sty PV+1
        ldy #0                  ; zero fill
@z:     lda #0
        sta (VP),y
        inc16 VP
        lda VP
        cmp PV
        bne @z
        lda VP+1
        cmp PV+1
        bne @z
        sec                     ; VP = start again
        lda VP
        sbc W1
        sta VP
        lda VP+1
        sbc W1+1
        sta VP+1
        ldy #0
        lda NK1
        sta (VP),y
        iny
        lda NK2
        sta (VP),y
        iny
        lda T3
        sta (VP),y
        beq @r
        iny
        lda W1
        sta (VP),y
        iny
        lda W1+1
        sta (VP),y
@r:     rts

; LVNUM: IP on a numeric variable -> VP = address of its value
LVNUM:  jsr NAMEPARSE
LVNUM2: ldy #0
        lda (IP),y
        cmp #$2D
        beq @arr
        ldx #0
        jsr LOOKUP
        bcs @f
        lda #5
        sta W1
        lda #0
        sta W1+1
        jsr CREATE
@f:     clc
        lda VP
        adc #3
        sta VP
        bcc @r
        inc VP+1
@r:     rts
@arr:   inc16 IP
        lda NK2
        pha
        lda NK1
        pha
        jsr EVAL
        jsr RPAR
        pla
        sta NK1
        pla
        sta NK2
        lda ACC+1
        bpl *+5      ; far branch: bmi @rng
        jmp @rng
        lda ACC
        ora ACC+1
        bne *+5      ; far branch: beq @rng
        jmp @rng
        ldx #1
        jsr LOOKUP
        bcs @g
        lda #7                  ; an undimensioned array has 1 element (like the Apple-1 BASIC)
        sta W1
        lda #0
        sta W1+1
        lda #1
        jsr CREATE
@g:     lda ACC+1
        bmi @rng
        lda ACC
        ora ACC+1
        beq @rng
        dec16 ACC
        asl ACC
        rol ACC+1
        clc
        lda ACC
        adc #7
        sta T1
        lda ACC+1
        adc #0
        sta T2
        bcs @rng
        ldy #3
        lda (VP),y
        sec
        sbc T1
        iny
        lda (VP),y
        sbc T2
        bcc @rng
        clc
        lda VP
        adc ACC
        sta VP
        lda VP+1
        adc ACC+1
        sta VP+1
        clc
        lda VP
        adc #5
        sta VP
        bcc @r2
        inc VP+1
@r2:    rts
@rng:   lda #E_RNG
        jmp ERROR

; ------------------------------------------------------------ strings
; STRVAR: NK set and the $ consumed: VP = entry (created with 80 characters)
STRVAR: ldx #2
        jsr LOOKUP
        bcs @r
        lda #7                  ; an undimensioned string holds 1 character (like the Apple-1 BASIC)
        sta W1
        lda #0
        sta W1+1
        lda #2
        jsr CREATE
@r:     rts

; SEVAL: string expression at IP -> SPT, SLN
SEVAL:  ldy #0
        lda (IP),y
        cmp #$28
        bne @v
        inc16 IP
        lda IP
        sta SPT
        lda IP+1
        sta SPT+1
        ldy #0
@c:     lda (IP),y
        iny
        cmp #$29
        bne @c
        dey
        sty SLN
        tya
        sec
        adc IP
        sta IP
        bcc @r
        inc IP+1
@r:     rts
@v:     cmp #$C1
        bcc @syn
        jsr NAMEPARSE
        ldy #0
        lda (IP),y
        cmp #$40
        bne @syn
        inc16 IP
        jmp SEVAL3
@syn:   jmp SYNERR

; SEVAL3: after name and $: the variable and its optional substring
SEVAL3: jsr STRVAR
        lda VP
        pha
        lda VP+1
        pha
        ldy #0
        lda (IP),y
        cmp #$2A
        beq @sub
        lda #$FF                ; the whole string: an empty one is fine
        sta TMP+1
        lda #1
        sta TMP
        lda #$00
        sta ACC
        lda #$80
        sta ACC+1
        jmp @go
@sub:   inc16 IP
        jsr EVAL
        lda ACC+1
        pha
        lda ACC
        pha
        lda #0
        sta ACC
        lda #$80
        sta ACC+1
        ldy #0
        lda (IP),y
        cmp #$23
        bne @noe
        inc16 IP
        jsr EVAL
@noe:   jsr RPAR
        pla
        sta TMP
        pla
        sta TMP+1
@go:    pla
        sta VP+1
        pla
        sta VP
        ldy #5
        lda (VP),y
        sta T1                  ; current length
        lda TMP+1
        cmp #$FF
        beq @sok
        lda TMP+1
        beq *+5      ; far branch: bne @str
        jmp @str
        lda TMP
        bne *+5      ; far branch: beq @str
        jmp @str
        cmp T1
        beq @sok
        bcs @str
@sok:   lda ACC+1               ; end
        cmp #$80
        bne @e1
        lda T1
        sta ACC
        lda #0
        sta ACC+1
@e1:    lda ACC+1
        bne @str
        lda ACC
        cmp TMP
        bcs @e2
        lda #0                  ; end < start: empty
        sta SLN
        beq @sp
@e2:    cmp T1
        beq @e3
        bcs @str
@e3:    sec
        sbc TMP
        clc
        adc #1
        sta SLN
@sp:    clc
        lda VP
        adc #5
        sta SPT
        lda VP+1
        adc #0
        sta SPT+1
        lda TMP
        clc
        adc SPT
        sta SPT
        bcc @r
        inc SPT+1
@r:     rts
@str:   lda #E_STR
        jmp ERROR

; SCMP: compare the string in SPT/SLN with the one after = or #
SCMP:   lda SPT
        pha
        lda SPT+1
        pha
        lda SLN
        pha
        ldy #0
        lda (IP),y
        inc16 IP
        cmp #$39
        beq @e
        cmp #$3A
        beq @e
        jmp SYNERR
@e:     pha
        jsr SEVAL
        pla
        sta T2                  ; operator
        pla
        sta T1                  ; first length
        pla
        sta TMP+1
        pla
        sta TMP
        ldx #0                  ; X = 1 if equal
        lda T1
        cmp SLN
        bne @n
        ldy #0
@c:     cpy T1
        beq @eq
        lda (TMP),y
        eor (SPT),y
        and #$7F
        bne @n
        iny
        bne @c
@eq:    ldx #1
@n:     lda T2
        cmp #$3A
        bne @s
        txa
        eor #1
        tax
@s:     stx ACC
        lda #0
        sta ACC+1
        rts

; ------------------------------------------------------------ assignments, DIM, INPUT
S_ASSIGN: jsr NAMEPARSE
        ldy #0
        lda (IP),y
        cmp #$40
        beq @str
        jsr LVNUM2
        lda VP
        pha
        lda VP+1
        pha
        lda #$71
        jsr EXPECT
        jsr EVAL
        pla
        sta VP+1
        pla
        sta VP
        ldy #0
        lda ACC
        sta (VP),y
        iny
        lda ACC+1
        sta (VP),y
        jmp ENDST
@str:   inc16 IP
        jsr STRVAR
        lda VP
        pha
        lda VP+1
        pha
        ldy #0
        lda (IP),y
        cmp #$42
        bne @ns
        inc16 IP
        jsr EVAL
        jsr RPAR
        lda ACC+1
        bne @bad
        lda ACC
        beq @bad
        jmp @s1
@ns:    lda #1
@s1:    pha
        lda #$70
        jsr EXPECT
        jsr SEVAL
        pla
        sta T1                  ; start index
        pla
        sta VP+1
        pla
        sta VP
        jsr STRSET
        jmp ENDST
@bad:   lda #E_STR
        jmp ERROR

; STRSET: store SPT/SLN in the string VP from the index T1 (1 = whole)
STRSET: ldy #5
        lda (VP),y
        sta T2                  ; current length
        lda T1
        sec
        sbc #1
        sta W1                  ; offset
        cmp T2
        beq @o
        bcc *+5      ; far branch: bcs @bad
        jmp @bad
@o:     ldy #3
        lda (VP),y
        sec
        sbc #6                  ; capacity
        sec
        sbc W1
        cmp SLN
        bcc @l
        lda SLN
@l:     sta T3                  ; characters to copy
        lda VP
        clc
        adc #6
        sta S2
        lda VP+1
        adc #0
        sta S2+1
        lda S2
        clc
        adc W1
        sta S2
        bcc @c0
        inc S2+1
@c0:    ldy #0
@c:     cpy T3
        beq @d
        lda (SPT),y
        and #$7F
        sta (S2),y
        iny
        bne @c
@d:     lda W1
        clc
        adc T3
        ldy #5
        sta (VP),y
        lda T3
        cmp SLN
        bcc @ovf
        rts
@ovf:   lda #E_OVF
        jmp ERROR
@bad:   lda #E_STR
        jmp ERROR

S_DIM:  lda TOK
        cmp #$4E
        beq @s
        lda #0
        beq @i
@s:     lda #1
@i:     jsr DIMIT
@nx:    ldy #0
        lda (IP),y
        cmp #$43
        beq @s2
        cmp #$44
        bne @e
        inc16 IP
        lda #0
        jsr DIMIT
        jmp @nx
@s2:    inc16 IP
        lda #1
        jsr DIMIT
        jmp @nx
@e:     jmp ENDST

DIMIT:  pha
        jsr NAMEPARSE
        pla
        pha
        beq @num
        lda #$40
        jsr EXPECT
        lda #$22
        bne @p
@num:   lda #$34
@p:     jsr EXPECT
        lda NK2
        pha
        lda NK1
        pha
        jsr EVAL
        jsr RPAR
        pla
        sta NK1
        pla
        sta NK2
        pla
        beq @n2
        lda ACC+1
        beq *+5      ; far branch: bne @b255
        jmp @b255
        lda ACC
        bne *+5      ; far branch: beq @bstr
        jmp @bstr
        ldx #2
        jsr LOOKUP
        bcs @rd2
        lda ACC
        clc
        adc #6
        sta W1
        lda #0
        adc #0
        sta W1+1
        lda #2
        jmp CREATE
@n2:    lda ACC+1
        bpl *+5      ; far branch: bmi @rng
        jmp @rng
        lda ACC
        ora ACC+1
        bne *+5      ; far branch: beq @rng
        jmp @rng
        ldx #1
        jsr LOOKUP
        bcs @rd1
        asl ACC
        rol ACC+1
        clc
        lda ACC
        adc #5
        sta W1
        lda ACC+1
        adc #0
        sta W1+1
        bcs @mem
        lda #1
        jmp CREATE
@rd2:   lda ACC                 ; DIM of an existing string: fine when it is not larger
        clc
        adc #6
        sta W1
        lda #0
        sta W1+1
        beq REDIM
@rd1:   asl ACC                 ; DIM of an existing array
        rol ACC+1
        lda ACC
        clc
        adc #5
        sta W1
        lda ACC+1
        adc #0
        sta W1+1
        jmp REDIM
@b255:  lda #E_255              ; DIM A$(0) is a STRING error, more than 255 a >255 error
        jmp ERROR
@bstr:  lda #E_STR
        jmp ERROR
@dim:   lda #E_DIM
        jmp ERROR
@rng:   lda #E_RNG
        jmp ERROR
@mem:   lda #E_MEM
        jmp ERROR

REDIM:  ldy #3                  ; old size - new size >= 0 ?
        lda (VP),y
        sec
        sbc W1
        iny
        lda (VP),y
        sbc W1+1
        bcs @ok
        lda #E_DIM
        jmp ERROR
@ok:    rts


S_INPUT: lda #1
        sta NEWL
        lda #0
        sta NOQ
        lda TOK
        cmp #$53
        bne INVAR2
        inc16 IP
@p:     ldy #0
        lda (IP),y
        inc16 IP
        cmp #$29
        beq @pd
        and #$7F
        jsr PUTC
        jmp @p
@pd:    ldy #0
        lda (IP),y
        sta TOK
        inc16 IP
        lda #1
        sta NOQ
INVAR2: lda IP
        sta IPV
        lda IP+1
        sta IPV+1
        lda NEWL
        bne @rd
        ldx IDX
@sk:    lda IBUF,x
        cmp #' '
        bne @t
        inx
        bne @sk
@t:     cmp #CR
        bne @have
@rd:    lda #'?'                ; the '?' is always printed, also after a prompt string
        jsr GETLN
@got:   lda #0
        sta IDX
        sta NEWL
@have:  lda #1
        sta INPF
        lda TOK
        cmp #$52
        beq @sv
        cmp #$26
        beq @sv
        jsr INNUM
        lda #0
        sta INPF
        jsr LVNUM
        ldy #0
        lda ACC
        sta (VP),y
        iny
        lda ACC+1
        sta (VP),y
        jmp @after
@sv:    jsr NAMEPARSE
        lda #$40
        jsr EXPECT
        jsr STRVAR
        ldx IDX
@n:     lda IBUF,x
        cmp #CR
        beq @cnt
        inx
        bne @n
@cnt:   txa
        sec
        sbc IDX
        sta T2                  ; length typed
        ldy #3
        lda (VP),y
        sec
        sbc #6
        cmp T2
        bcs @fit
        lda #E_OVF
        jmp ERROR
@fit:   lda VP
        clc
        adc #6
        sta S2
        lda VP+1
        adc #0
        sta S2+1
        ldy #0
@cp:    cpy T2
        beq @cd
        txa                     ; X = end index: use IDX+Y
        lda IDX
        sty T3
        clc
        adc T3
        tax
        lda IBUF,x
        sta (S2),y
        iny
        bne @cp
@cd:    lda T2
        ldy #5
        sta (VP),y
        ldx IDX
        txa
        clc
        adc T2
        sta IDX
        lda #0
        sta INPF
@after: ldy #0
        lda (IP),y
        cmp #$26
        beq @nx
        cmp #$27
        bne @e
@nx:    sta TOK
        inc16 IP
        jmp INVAR2
@e:     lda NOQ                 ; with a prompt string: a blank line after the answer
        beq @ne
        jsr CRLF
@ne:    jmp ENDST

; INNUM: ACC = number at IDX in the typed line; IDX moves after it and a comma
INNUM:  lda IDX
        sta SI
        jsr PK
        ldx #0
        cmp #'-'
        bne @d
        inc SI
        ldx #1
@d:     txa
        pha
        jsr PK
        cmp #'0'
        bcc @syn
        cmp #'9'+1
        bcs @syn
        jsr DIGITS
        jsr PK
        cmp #','
        bne @c
        inc SI
        jmp @ok
@c:     cmp #CR
        bne @syn
@ok:    lda SI
        sta IDX
        pla
        beq @r
        jmp NEG
@r:     rts
@syn:   jmp SYNERR

INPERR: jsr ERRMSG
        lda #0
        sta INPF
        setptr M_RET
        jsr PRSTR
        jsr CRLF
        lda IPV
        sta IP
        lda IPV+1
        sta IP+1
        lda #1
        sta NEWL
        jmp INVAR2

