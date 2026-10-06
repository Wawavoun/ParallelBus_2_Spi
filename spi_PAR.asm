;*
;* SPI_PAR PARALLEL-BUS SPI MASTER
;*
;* FOR ELEKTOR EC-6809 / EC-6809-V7
;* BOARD AT $EEE0 (A0 = REGISTER SELECT)
;* U3 74LS166 TRANSMITS, U4 74LS299 RECEIVES, MODE 0, MSB FIRST
;*
;* PH. ROEHR 10/2026
;*
;*   $EEE0  W  DATA   LOAD THE 166 AND START EIGHT SCK
;*   $EEE0  R  DATA   BYTE NOW IN THE 299
;*   $EEE1  W  CTRL   D1-D0 CS, D2 CS ON, D4-D3 SPEED, D5 IE
;*   $EEE1  R  STAT   D7 = BUSY. D6-D0 ARE NOT DRIVEN.
;*
;* SPEED AT E = 2 MHZ (SCALES WITH E). RESET IS 11, ALL CS HIGH.
;*   0   1 MHZ      1   500 KHZ      2   250 KHZ      3   125 KHZ
;*
;* CTRL CANNOT BE READ BACK, SO SPI_IMG HOLDS THE LAST VALUE WRITTEN.
;* A TRANSFER IS STARTED BY THE WRITE TO DATA. BUSY IS SET BEFORE
;* THAT WRITE INSTRUCTION ENDS AND CLEARS WHEN THE EIGHTH BIT IS DONE.
;* INTN (OPEN COLLECTOR) FOLLOWS THE SAME EDGE WHEN IE = 1 AND DROPS
;* ON THE NEXT READ OR WRITE OF DATA. THE FOREGROUND READ IN SPI_BYTE
;* CLEARS IT. AN INTERRUPT ROUTINE MUST NOT READ DATA.
;*
;* C = 0 ON SUCCESS. C = 1 WHEN BUSY NEVER CLEARS (A = $FF).
;* SPI_INIT DOES NOT WAIT: IT FORCES THE IDLE IMAGE ONTO THE BOARD.
;*


SPI_BASE        EQU     $EEE0
SPI_DAT         EQU     SPI_BASE        ; W START, R RECEIVED BYTE
SPI_STA         EQU     SPI_BASE+1      ; R D7 = BUSY
SPI_CTL         EQU     SPI_BASE+1      ; W CONTROL

;* CONTROL IMAGE
CTL_CS          EQU     %00000011       ; D1-D0 CHIP NUMBER
CTL_ON          EQU     %00000100       ; D2 1 = THAT CS LOW
CTL_SPD         EQU     %00011000       ; D4-D3
CTL_IE          EQU     %00100000       ; D5 INTN ENABLE

;* VALUES FOR SPI_SPD (SHIFTED INTO D4-D3 BY THE DRIVER)
SP_1M           EQU     0
SP_500K         EQU     1
SP_250K         EQU     2
SP_125K         EQU     3

IMG_IDLE        EQU     SP_125K<<3      ; CS OFF, 125 KHZ, IRQ OFF

;* POLL LOOPS. ONE BYTE IS 8 TO 64 US AT E = 2 MHZ.
SPI_TMO         EQU     $0800


;*------------------------------------------------------------
;* SPI_INIT
;* ALL CS HIGH, 125 KHZ, INTN OFF. NO BUSY WAIT.
;* DESTROYS A. Z = 1, C = 0.
;*------------------------------------------------------------
SPI_INIT        LDA     #IMG_IDLE
                STA     SPI_IMG
                STA     SPI_CTL
                CLRA
                RTS


;*------------------------------------------------------------
;* SPI_SEL    ASSERT CS NUMBER IN B (0-3). OTHER CS STAY HIGH.
;* SPI_IDLE   ALL CS HIGH.
;* SPEED AND IE ARE LEFT AS THEY ARE.
;* B PRESERVED. C = 0 OK, C = 1 STILL BUSY (IMAGE NOT WRITTEN).
;*------------------------------------------------------------
SPI_SEL         PSHS    A,B
                LDB     1,S
                ANDB    #CTL_CS
                ORB     #CTL_ON
                LDA     SPI_IMG
                ANDA    #CTL_SPD|CTL_IE
                PSHS    B
                ORA     ,S+
                BSR     SPI_PUTC
                PULS    A,B,PC

SPI_IDLE        PSHS    A
                LDA     SPI_IMG
                ANDA    #CTL_SPD|CTL_IE
                BSR     SPI_PUTC
                PULS    A,PC


;*------------------------------------------------------------
;* SPI_SPD    A = 0..3 (SP_1M .. SP_125K)
;* SPI_IRQ    A = 0 DISABLES INTN, ANY OTHER VALUE ENABLES IT
;* A PRESERVED. C = 0 OK, C = 1 STILL BUSY (IMAGE NOT WRITTEN).
;*------------------------------------------------------------
SPI_SPD         PSHS    A
                ANDA    #3
                LSLA
                LSLA
                LSLA
                PSHS    A
                LDA     SPI_IMG
                ANDA    #CTL_CS|CTL_ON|CTL_IE
                ORA     ,S+
                BSR     SPI_PUTC
                PULS    A,PC

SPI_IRQ         PSHS    A
                LDA     SPI_IMG
                TST     ,S
                BEQ     IRQ_OFF
                ORA     #CTL_IE
                BRA     IRQ_WR
IRQ_OFF         ANDA    #%11011111
IRQ_WR          BSR     SPI_PUTC
                PULS    A,PC


;*------------------------------------------------------------
;* SPI_BYTE   EXCHANGE A. RETURNS A = MISO.
;* C = 0 BYTE VALID. C = 1 TIMEOUT, A = $FF.
;* PRESERVES B,X,Y.
;*------------------------------------------------------------
SPI_BYTE        PSHS    B,X
                BSR     SPI_WAIT
                BCS     BY_TMO
                STA     SPI_DAT
                BSR     SPI_WAIT
                BCS     BY_TMO
                LDA     SPI_DAT
                ANDCC   #%11111110
                PULS    B,X,PC
BY_TMO          LDA     #$FF
                PULS    B,X,PC


;*------------------------------------------------------------
;* SPI_BLK    EXCHANGE B BYTES AT X, IN PLACE.
;* B = 0 MEANS 256. X,Y,B PRESERVED.
;* Z = 1 AND C = 0 WHEN EVERY BYTE COMPLETED.
;* Z = 0, C = 1, A = $FF IF A BYTE TIMED OUT.
;* BYTES ALREADY STORED STAY IN THE BUFFER.
;*------------------------------------------------------------
SPI_BLK         PSHS    Y,X,B
                TFR     X,Y
BLK_LP          LDA     ,Y
                BSR     SPI_BYTE
                BCS     BLK_TMO
                STA     ,Y+
                DEC     ,S
                BNE     BLK_LP
                CLRA
                PULS    B,X,Y,PC
BLK_TMO         LDA     #$FF
                PULS    B,X,Y,PC


;*------------------------------------------------------------
;* WRITE A TO CTRL ONCE THE SHIFTER IS IDLE. UPDATES SPI_IMG.
;* PRESERVES A,B,X,Y. C = 0 WRITTEN, C = 1 NOT WRITTEN.
;*------------------------------------------------------------
SPI_PUTC        BSR     SPI_WAIT
                BCS     PUTC_R
                STA     SPI_IMG
                STA     SPI_CTL
                ANDCC   #%11111110
PUTC_R          RTS


;*------------------------------------------------------------
;* WAIT UNTIL D7 OF STAT IS CLEAR.
;* PRESERVES A,B,X,Y. C = 0 IDLE, C = 1 TIMEOUT.
;*------------------------------------------------------------
SPI_WAIT        PSHS    A,X
                LDX     #SPI_TMO
WAIT_LP         LDA     SPI_STA
                BPL     WAIT_OK
                LEAX    -1,X
                BNE     WAIT_LP
                PULS    A,X
                ORCC    #%00000001
                RTS
WAIT_OK         PULS    A,X
                ANDCC   #%11111110
                RTS


;* LAST CONTROL BYTE WRITTEN. MATCHES A HARDWARE RESET.
SPI_IMG         FCB     IMG_IDLE
