MSDOS ASM8521 DEMO.ASM
MSDOS ASM8521 SOUND.ASM
MSDOS ASM8521 SYSCALL.ASM
MSDOS LINK8521 @DEMO.LNK
MSDOS HEX8521 -P -F -B 020 DEMO
MSDOS HEX2BIN DEMO.HEX DEMO.BIN
MSDOS STUFF DEMO.BIN 8192 255
COPY /B DEMO.BIN+SPLASH.BIN+UTOPIA.BIN
