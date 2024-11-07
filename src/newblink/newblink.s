;/usr/bin/cl65 --listing monitor.lst --cpu 65c02 --target none -C firmware.cfg monitor.s
.PC02
.include "via.inc"


.code 

; NewBlink v 0.01  21 Oct 2024
; VIA1 is at $7000, LED array on PORTA 

;
; Tick timer counts at 20 mSec intervals


T1LSB1 = VIA1_T1CL ; VIA1 + $4
T1MSB1 = VIA1_T1CH  ; VIA1 + $5
ACR1   = VIA1_ACR ; VIA1 + $B
IER1   = VIA1_IER ; VIA1 + $E

LED_DATA    = VIA1_PORTA
LED_DDR     = VIA1_DDRA

TIMER1_CONT	  = %01000000		; TIMER1 continuous, PB7 toggle disabled (ACR)
ENABLE_T1	  = %11000000      ; enable interrupt TIMER1 (IER)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  Global variables
;;
UMEM	 = $00	; start of page user mem locations
TICKS   = UMEM+0        ; 4 bytes, tick counter for TIMER1 on VIA1

; Temp area for brk interrupt (registers)
PCH     = UMEM+4    ; Program counter HIGH byte
PCL     = UMEM+5    ; Program counter LOW byte
AREG    = UMEM+6
XREG    = UMEM+7
YREG    = UMEM+8
SPREG   = UMEM+9
PREG    = UMEM+10    ; processor status reg

;  ACIA read and write pointers
RD_PTR	     = UMEM + 76	     ; 1 byte read pointer
WR_PTR       = UMEM + 77	     ; 1 byte write pointer
ACIABUF      = UMEM + $0200      ; 256 bytes circ buffer for ACIA
COMMAND_BUFF    = UMEM+80        ; buffer for incoming keyb command, 64 byte

PB_KEY   = UMEM+53		; 1 byte, pb keypad from VIA2 Port B
PB_BUFF	 = UMEM+54		; 8 bytes, circ buffer for debouncing keypad
;          UMEM+61

; General purpose registers
STRING_PTR      = UMEM + 74    ; 2 byte pointer






welcomemsg: 
	.asciiz "NewBlink v0.01"
releasemsg: 
	.asciiz "KJ 21 Oct 2024"
hexascii: 
	.asciiz "0123456789ABCDEF"
regdumplabel:
	.asciiz "A X Y  PC   P SP"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Entry point for reset
reset:
    cld
    sei

;; clear page zero ram
    ldx #$00
clear_page0:
    stz $00,X
    inx 
    bne clear_page0

;; init stack    
    ldx #$ff
    txs             ; initialize stack pointer

;; set up VIAs
    lda #$ff
    sta LED_DDR     ; set LED port data direction
    sta LED_DATA	; turn on all LEDs

    jsr init_timer1

    cli             ; enable interrupts

    jsr delay
    jsr delay
    jsr delay
    jsr delay
    lda #$0
    sta LED_DATA	; turn off LEDs
    jsr delay
    jsr delay
    jsr delay

busy_loop:
.scope _MAIN_LOOP
    lda TICKS
    sta LED_DATA

    jmp busy_loop
.endscope ; _MAIN_LOOP




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  Initialize timer interrupt from VIA 1
init_timer1:
.scope _INIT_TIMER1
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; set up timer interrupts on T1 (VIA1) for PB polling
    lda #TIMER1_CONT
    sta ACR1
    lda #ENABLE_T1
    sta IER1
    lda #$1E        ; subtract 2 from the following:  (ref https://www.youtube.com/watch?v=g_koa00MBLg)
    sta T1LSB1		; $4e20 = 20,000 cycles = 20 mSec interrupts @ 1 MHz
    lda #$4E		; $2710 = 10,000 cycles = 10 mSec interrupts @ 1 MHz
    sta T1MSB1		; $1388 = 5,000 cycles = 5 mSec interrupts @ 1 MHz
    rts
.endscope ; _INIT_TIMER1


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  General purpose delay routine	
delay:
.scope _DELAY
    phx
    phy
    ldy #$FF
outerloop:
    ldx #$FF
innerloop:
    dex
    bne innerloop
    dey
    bne outerloop
    ply
    plx
    rts
.endscope ; _DELAY


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; NMI service routine
nmi_service:
.scope _NMI_SERVICE
    cli
    ; jsr run_monitor
    rti
.endscope ; _NMI_SERVICE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Interrupt service routine
int_service:
.scope _INT_SERVICE
    pha
    phx
    phy
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; grab the stack point and read the status register
    tsx 
    lda $0100+4,x	; read status register from stack
    sta PREG		; processor status
    and #$10		; brk bit set?
    beq timer1_service	; no, check acia
	
brk_service:
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; brk occurred, save registers and display them on the LCD
    lda $100+6,x	
    sta PCH			; program counter high byte
    lda $100+5,x	
    sta PCL			; program counter low byte
    lda $100+3,x	
    sta AREG		; A register
    lda $100+2,x	
    sta XREG		; X register
    lda $100+1,x	
    sta YREG		; Y register
    tsx 
    stx SPREG		; Stack pointer
    ; jsr display_reg

do_nothing:
    jmp do_nothing  ; enter an infinite loop
    jmp exit_int_service

timer1_service:
    bit T1LSB1		; clear interrupt flag

    inc TICKS
    bne timer1_checkpb
    inc TICKS+1
    bne timer1_checkpb
    inc TICKS+2
    bne timer1_checkpb
    inc TICKS+3

timer1_checkpb:
    ; push button debouncing
    ;lda PB_DATA		; read VIA port, PB keypad input
                  ; PB pulls low on press
    ;sta LED_DATA
    ;ldx #0
;read_pb:
;    clc
;    ror A            ; rightmost bit in A rotated into carry
;    ror PB_BUFF,X       ; rotate that carry into PB_BUFF+x
;    inx
;    cpx #8          ; done all of them?
;    bne read_pb
 
exit_debounce:

exit_int_service:
    ply
    plx
    pla
    rti
.endscope ; _INT_SERVICE

    .segment "VECTORS"
    .word nmi_service       ; nmi
    .word reset
    .word int_service       ; irq

    

    
