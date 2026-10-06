EC-6809 PARALLEL TO SPI INTERFACE
================================================================
Soultz Haut-Rhin - 10/2026

Schematic: PAR_SPI_Test.pdf (sheet SD_CARD).
Equations: SPIDEC.PLD in U7, SPISEQ.PLD in U8.

There is no ic on the market doing parallel bus to spi interface.

I have done this as a proof of concept.
The system use two 22V10 gals and two shift registers (74LS166 and 74LS299).

WinCupl and TL866II Plus are used to program gals.

The timing is adapted to 6809 bus and use E and Q.
It is SPI Mode 0 only, MSB first.

The proposed schematics if for a specific Motorola 6809 computer configuration.
The first usage of this system is to add a SD card interface to this computer.

No pcb is proposed here because it will almost never be usable 'as is'.

You have to adapt the schematic and, possibly, the gal equations to you configuration :
- processor
- bus timing
- bus interface
- and so on....

This circuit has been tested at SCK 1 MHz in loopback mode and with a microSD card.
22V10 gal and 74LS chips can easily go higher.

HOW IT WORKS
------------
The CPU writes one byte.
The board clocks that byte out on MOSI and shifts the slave reply in
on MISO then stops.

U7 watches the bus. A write to DATA pulls SHLDN low for the whole time
E is high. That loads U3 (74LS166) with D7-D0 and tells U8 to start.
U8 then makes eight SCK pulses and drives BUSY on D7 until the last
one is done.

U3 shifts on TXCLK. TXCLK stays low from the rise of E until Q falls,
then rises while SHLDN is still low, so the 74LS166 loads and does not
shift on that edge. After that TXCLK is the inverse of SCK, MOSI
changes on each falling SCK.

U9 (74LS299) is wired shift-right (S1 low, S0 held high) and clocks
on rising SCK, so it samples MISO on the rising edge. The first bit
ends in D7. A read of DATA turns its outputs on (RDRX low while E is
high) and puts that byte on the bus.

U2 (4050, powered at 3.3 V) drops SCK, MOSI and the four CS lines
from 5 V to 3.3 V. MISO comes back through Q3 (2N7000), low on the
3.3 V side pulls MISO5 low, high lets R21 pull MISO5 up to 5 V.

U4 (LM3940) makes the 3.3 V rail from +5 V.

/RESET clears U3 and U9. In the two GALs it is synchronous, so E and
Q must be running, all CS go high, speed goes to 125 kHz, BUSY
clears, the interrupt turns off.


REGISTERS
---------
  BASE+0  Write  DATA   load U3 and start eight SCK
  
  BASE+0  Read  DATA   last byte received, from U9
  
  BASE+1  Write  CTRL   D1-D0 CS number, D2 1 = that CS on,
                    D4-D3 speed, D5 interrupt enable
                    
  BASE+1  Read  STAT   D7 = BUSY. D6-D0 are not driven.

  SPEED at E = 2 MHz (scales with E): BASE+1 D4-D3
    0-0  1 MHz  /   0-1  500 kHz  /   1-0  250 kHz   /  1-1  125 kHz

/INT goes low when a byte finishes, and only if D5 was set.
It is open collector. A read or a write of DATA releases it.
Reading STAT does not.


SOFTWARE
--------
spi_PAR.asm drives the board.

C = 0 on success. C = 1 if BUSY never clears.

  SPI_INIT                 CS off, 125 kHz, interrupt off
  
  SPI_SEL    B = 0-3       assert that CS
  
  SPI_IDLE                 all CS high
  
  SPI_SPD    A = 0-3       1 MHz, 500 kHz, 250 kHz, 125 kHz
  
  SPI_IRQ    A = 0 / else  interrupt off / on
  
  SPI_BYTE   A = TX        A = RX
  
  SPI_BLK    X, B          exchange B bytes in place (B = 0 means 256)

Be careful not to select more that one CS at a time !

Philippe

THIS DESIGN (HARDWARE AND SOFTWARE) IS PROVIDED 'AS IS' UNDER GNU GPL v3 LICENSE.

