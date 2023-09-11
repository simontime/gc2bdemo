    title   Sound Driver
    type    8521

    global  PlaySpeech
    global  StopSpeech

    program

; speech state variables
sp_control     equ 0a8h ; 1
sp_silence     equ 0ach ; 2
sp_buf         equ 0b0h ; 1
sp_state       equ 0beh ; 2
sp_index       equ 0c0h ; 1
sp_bit         equ 0c1h ; 1

; system flag
SYSFLAG        equ 0bch

; TMR1 equates
TMR1_bank      equ 0a6h
TMR1_ISR       equ 102h
TMR1_end       equ 2142h

; markers
marker_silence equ 0ff55h
marker_eof     equ 0ffaah

; speech decoding ISR
;
; inputs:
; rr2 = start address
; r6  = start bank
;
; uses:
; rr0  = tmp
; rr4  = tmp
; r8   = original r14
; r12  = tmp
; r13  = original mmu3
; rr14 = tmp
;
; notes:
; - start address MUST be aligned to 2
; - plays back at ~16KHz
;
; fastest instructions used where possible
DecodeISR:
    ; feed last decoded sample
    mov     sgda,sp_buf
    ; preserve r14 (used in kernel's ISR handler)
    mov     r8,r14
    ; any silence left?
    cmpw    sp_silence,#0
    ; yes, continue silence
    jmp     ne,DoSilence
    ; any bits left?
    cmp     sp_bit,#0
    ; no, fetch next word
    br      eq,fetch_nxt
    ; yes, continue current word
    jmp     dec_cur
fetch_nxt:
    ; preserve mmu3
    mov     r13,mmu3
    ; increment bank if exhausted
    bbc     r2,#7,no_adj
    inc     r6
    mov     r2,#60h
no_adj:
    ; switch bank
    mov     mmu3,r6
    ; fetch word
    movw    rr0,(rr2)+
    ; check first 2 marker bytes
    cmpw    rr0,#marker_eof
    ; test other EOF bytes
    jmp     eq,CheckEOF
chk_sil:
    ; check first 2 marker bytes
    cmpw    rr0,#marker_silence
    ; not silence, check bit count
    jmp     eq,CheckSilence
rst_bit:
    ; restore mmu3
    mov     mmu3,r13
    ; reset bit count
    mov     sp_bit,#8
dec_cur:
    dec     sp_bit
    ; index += DecTable[sp_index]
    clr     r4
    mov     r5,sp_index
    movw    rr4,DecTable(rr4)
    movw    rr14,rr4
    ; if bit clear, do subtraction
    bbc     r1,#7,sub_index
    ; index *= 3
    addw    rr14,rr14
    addw    rr14,rr4
    ; sp_index += 6
    add     sp_index,#6
    jmp     si_skip
sub_index:
    ; sp_index -= 2
    sub     sp_index,#2
si_skip:
    ; if bit set, do subtraction
    bbs     r0,#7,sub_state
    ; sp_state += rr14
    addw    sp_state,rr14
    ; clamp to 0xffff if over
    br      nc,clamp_index
    movw    sp_state,#0ffffh
    jmp     clamp_index
sub_state:
    ; sp_state -= rr14
    subw    sp_state,rr14
    ; clamp to 0 if under
    br      nc,clamp_index
    clr     sp_state
    clr     sp_state+1
clamp_index:
    ; clamp table index between 0 and 80
    cmp     sp_index,#0
    br      lt,ci_low
    cmp     sp_index,#80
    br      ule,ci_skip
    mov     sp_index,#80
    jmp     ci_skip
ci_low:
    clr     sp_index
ci_skip:
    ; shift bits
    sll     r0
    sll     r1
    ; load state
    movw    rr14,sp_state
    ; if r15 < 0x80 go to end
    bbc     r15,#7,di_end
    ; r14++
    inc     r14
    ; clamp to 0xff if over
    br      nz,di_end
    mov     r14,0ffh
di_end:
    ; move decoded sample to speech buffer
    mov     sp_buf,r14
    ; restore r14
    mov     r14,r8
    ; end ISR
    jmp     TMR1_end
stop_sp:
    ; restore mmu3
    mov     mmu3,r13
    ; stop speech
    call    StopSpeech
    ; restore r14
    mov     r14,r8
    ; end ISR
    jmp     TMR1_end

; check EOF marker
CheckEOF:
    ; check for bank overlap (2 bytes)
    bbs     r2,#7,chkeof_2
    ; check second 2 marker bytes
    movw    rr4,@rr2
    cmpw    rr4,#marker_eof
    ; stop speech if EOF
    jmp     eq,stop_sp
    ; otherwise, check silence
    jmp     chk_sil
chkeof_2:
    ; go to next bank
    inc     mmu3
    ; check second 2 marker bytes
    movw    rr4,6000h
    cmpw    rr4,#marker_eof
    ; stop speech if EOF
    jmp     eq,stop_sp
    ; return to previous bank
    dec     mmu3
    ; otherwise, check silence
    jmp     chk_sil

; check silence marker
CheckSilence:
    ; check for bank overlap (2 bytes)
    bbs     r2,#7,chksil_2
    ; check for bank overlap (4 bytes)
    cmpw    rr2,#8000h-2
    ; overlaps, go to 4 byte overlap version
    br      eq,chksil_4
    ; check second 2 marker bytes
    movw    rr4,@rr2
    cmpw    rr4,#marker_silence
    ; decode as speech if not silence
    jmp     ne,rst_bit
    ; read num silence bytes
    mov     r5,2(rr2)
    mov     r4,3(rr2)
    ; finish processing silence
    jmp     proc_sil
chksil_2:
    ; go to next bank
    inc     mmu3
    ; check second 2 marker bytes
    movw    rr4,6000h
    cmpw    rr4,#marker_silence
    ; do silence decoding if silence
    jmp     eq,dosil_2
    ; if not, return to previous bank and decode as speech
    dec     mmu3
    jmp     rst_bit
dosil_2:
    ; read num silence bytes
    mov     r5,6002h
    mov     r4,6003h
    ; return to previous bank
    dec     mmu3
    ; finish processing silence
    jmp     proc_sil
chksil_4:
    ; check second 2 marker bytes
    movw    rr4,8000h-2
    cmpw    rr4,#marker_silence
    ; do silence decoding if silence
    jmp     eq,dosil_4
    ; if not, decode as speech
    jmp     rst_bit
dosil_4:
    ; go to next bank
    inc     mmu3
    ; read num silence bytes
    mov     r5,6000h
    mov     r4,6001h
    ; return to previous bank
    dec     mmu3
proc_sil:
    ; add 27
    addw    rr4,#27
    ; advance ptr
    addw    rr2,#4
    ; multiply by 1.5 for speed compensation
    movw    sp_silence,rr4
    srl     r4
    rrc     r5
    addw    sp_silence,rr4
    ; reset state
    clr     sp_index
    movw    sp_state,#8000h
    ; restore mmu3
    mov     mmu3,r13

; do silence playback
DoSilence:
    ; feed silent sample
    decw    sp_silence
    mov     r14,#80h
    jmp     di_end

; start speech
;
; inputs:
; rr2 = start address
; r6  = start bank
;
; uses:
; rr0  = tmp
; r9   = original bank
; rr10 = original ISR address
StartSpeech:
    ; don't play speech if muted
    bbs     SYSFLAG,#5,no_speech
    ; preserve ps registers
    push    ps1
    push    ps0
    ; disable interrupts
    di
    ; new rp
    movm    ps0,#7,#38h
    ; preserve original interrupt
    movw    rr10,TMR1_ISR
    mov     r9,TMR1_bank
    ; setup new ISR
    movw    rr0,#DecodeISR
    movw    TMR1_ISR,rr0
    mov     r0,mmu2
    mov     TMR1_bank,r0
    ; set timer (just needs to be >16KHz, the cpu can't keep up anyway)
    mov     tm1d,#208
    mov     tm1c,#80h
    bset    SYSFLAG,#6
    ; initialise state variables
    clr     sp_bit
    mov     sp_buf,#80h
    movw    sp_state,#8000h
    clr     sp_index
    clr     sp_silence
    clr     sp_silence+1
    ; restore ps0
    pop     ps0
    ; start sound output
    mov     sgc,#88h
    ; ramp up to 0x80 (stops pop sound [see: sm8521 manual])
    clr     r0
ramp_up:
    cmp     r0,#80h
    br      eq,start_speech
    inc     r0
    ; stall for a few cycles
    push    r0
    pop     r0
    push    r0
    pop     r0
    push    r0
    pop     r0
    push    r0
    pop     r0
    ; feed sample
    mov     sgda,r0
    br      ramp_up
start_speech:
    bset    sp_control,#0
    ; restore ps1 (re-enables interrupts)
    pop     ps1
no_speech:
    ret

; stop speech
;
; uses:
; r0   = tmp
; r9   = original bank
; rr10 = original ISR address
StopSpeech:
    ; preserve ps registers
    push    ps1
    push    ps0
    ; disable interrupts
    di
    bclr    sp_control,#0
    ; restore timer
    mov     tm1d,#24
    mov     tm1c,#81h
    ; restore rp
    movm    ps0,#7,#38h
    ; restore ISR
    mov     TMR1_bank,r9
    movw    TMR1_ISR,rr10
    and     SYSFLAG,#0bfh
    ; ramp down to 0 (stops pop sound [see: sm8521 manual])
    mov     r0,sgda
ramp_down:
    cmp     r0,#0
    br      eq,stop_spch
    dec     r0
    ; stall for a few cycles
    push    r0
    pop     r0
    push    r0
    pop     r0
    push    r0
    pop     r0
    push    r0
    pop     r0
    ; feed sample
    mov     sgda,r0
    br      ramp_down
stop_spch:
    ; stop sound output
    clr     sgc
    ; restore ps registers
    pop     ps0
    pop     ps1
    ret

; play speech
;
; inputs:
; rr2 = start address
; r6  = start bank
PlaySpeech:
    movw    sp_state,rr2
    mov     sp_index,r6
    push    ps0
    movm    ps0,#7,#38h
    movw    rr2,sp_state
    mov     r6,sp_index
    pop     ps0
    call    StartSpeech
    ret

; ADPCM decoding table
DecTable:
    defw     128,  140,  152,  166,  181,  197,  215,  235
    defw     256,  278,  304,  332,  362,  395,  431,  470
    defw     512,  558,  609,  664,  724,  790,  861,  939
    defw    1024, 1117, 1218, 1328, 1448, 1579, 1722, 1878
    defw    2048, 2233, 2435, 2656, 2896, 3158, 3444, 3756
    defw    4096

    end