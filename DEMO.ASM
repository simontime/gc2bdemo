    title   Demo
    type    8521

    include keys.inc

    program

    db      10h
    db      20h
    dw      Entry
    db      00000001b
    dm      'TigerDMGC'
    db      0
    db      0
    db      0
    dm      'No steal OK?' ; "OK?" just so happens to be a valid security byte combo
    db      0
    dw      0

sp_control equ 0a8h

Entry:
    clr     r0
    cmp     r2,#1
    jmp     eq,GameExe
    ret

GameExe:
    ; draw graphic
    movw    rr8,#0a0c8h
    mov     r10,#8
    mov     r11,#21h
    movw    rr12,#6000h
    movw    rr14,#0000h
    call    Fi_graph2
    ; play sound
    movw    rr2,#6000h
    mov     r6,#22h
    call    PlaySpeech
main_loop:
    bbs     sp_control,#0,main_loop
    mov     r0,#2
    ret

    end