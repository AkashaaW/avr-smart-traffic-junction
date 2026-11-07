;===============================================
; SMART TRAFFIC JUNCTION
; ATmega328P / Arduino Uno
; 16 MHz
; FEATURES
; ------------------------------------------------------------
; 1. 24-phase normal traffic
; 2. Timer1 1 ms timing
; 3. Pedestrian button
; 4. Pedestrian request storage
; 5. GREEN-button behavior
; 6. YELLOW-button deferred behavior
; 7. ALL-RED-button deferred behavior
; 8. Pedestrian 5-4-3-2-1-0 countdown
; 9. Pedestrian RED / GREEN indication
; 10. Pedestrian crossing protection
; 11. 5-second cooldown
; 12. Button ignored during crossing/cooldown
; 13. 20 ms button debounce
; 14. LDR Night Mode
; 15. 1 Hz yellow flashing in Night Mode
; 16. 5-second continuous bright recovery
; 17. Phase timing protected during Night Mode
;
; ============================================================

.include "m328pdef.inc"


; ============================================================
; TRAFFIC LIGHT PINS
; ============================================================

; NORTH
.equ NR = 3              ; D3 = PD3
.equ NY = 4              ; D4 = PD4
.equ NG = 5              ; D5 = PD5

; SOUTH
.equ SR = 6              ; D6 = PD6
.equ SY = 7              ; D7 = PD7
.equ SG = 0              ; D8 = PB0

; EAST
.equ ER = 1              ; D9 = PB1
.equ EY = 2              ; D10 = PB2
.equ EG = 3              ; D11 = PB3

; WEST
.equ WR = 4              ; D12 = PB4
.equ WY = 5              ; D13 = PB5
.equ WG = 0              ; A0 = PC0


; ============================================================
; PEDESTRIAN
; ============================================================

.equ PED_BUTTON = 2      ; D2 = PD2
.equ PED_RED    = 5      ; A5 = PC5


; ============================================================
; 74HC595
; ============================================================

.equ SHIFT_DATA  = 2     ; A2 = PC2
.equ SHIFT_LATCH = 3     ; A3 = PC3
.equ SHIFT_CLOCK = 4     ; A4 = PC4


; ============================================================
; LDR
; ============================================================

.equ LDR_ADC_CHANNEL = 1     ; A1 = ADC1
.equ DARK_THRESHOLD = 400



; ============================================================
; BUTTON DEBOUNCE
; ============================================================

.equ BUTTON_DEBOUNCE_MS = 20


; ============================================================
; PHASE STATE
;
; 1 = GREEN
; 2 = YELLOW
; 3 = ALL RED
; ============================================================

.equ STATE_GREEN  = 1
.equ STATE_YELLOW = 2
.equ STATE_ALLRED = 3


; ============================================================
; 7-SEGMENT
;
; Q0 = a
; Q1 = b
; Q2 = c
; Q3 = d
; Q4 = e
; Q5 = f
; Q6 = g
; Q7 = pedestrian GREEN
;
; Common-anode:
; LOW  = segment ON
; HIGH = segment OFF
;
; MSB FIRST
; ============================================================

.equ SEG_0 = 0b11000000
.equ SEG_1 = 0b11111001
.equ SEG_2 = 0b10100100
.equ SEG_3 = 0b10110000
.equ SEG_4 = 0b10011001
.equ SEG_5 = 0b10010010

.equ SEG_OFF = 0b01111111


; ============================================================
; SRAM VARIABLES
; ============================================================

.dseg

millis_0:           .byte 1
millis_1:           .byte 1
millis_2:           .byte 1
millis_3:           .byte 1

; 0 = no request
; 1 = request stored
ped_request:        .byte 1

; 0 = normal
; 1 = crossing
ped_active:         .byte 1

; 0 = no cooldown
; 1 = cooldown
ped_cooldown:       .byte 1

; 0 = crossing can happen at current eligible ALL-RED
; 1 = defer this ALL-RED
ped_defer:          .byte 1

; Current traffic state
; 1 = GREEN
; 2 = YELLOW
; 3 = ALL RED
phase_state:        .byte 1

; ------------------------------------------------------------
;  WAIT_PHASE duration-These variables protect the phase duration from being
; overwritten by Night Mode routines.
; ------------------------------------------------------------

phase_wait_0:       .byte 1
phase_wait_1:       .byte 1

; Saved phase start timestamp (protects it from called routines)
phase_start_0:      .byte 1
phase_start_1:      .byte 1

; Saved pedestrian cooldown start timestamp
cooldown_start_0:   .byte 1
cooldown_start_1:   .byte 1

; Night yellow output state
; 0 = OFF
; 1 = ON
night_yellow_state: .byte 1

; 0 = not currently counting bright time
; 1 = bright timer active
bright_seen:        .byte 1

; Timer start for night yellow flashing
night_toggle_0:     .byte 1
night_toggle_1:     .byte 1

; Timer start for bright recovery
bright_start_0:     .byte 1
bright_start_1:     .byte 1


; ============================================================
; CODE
; ============================================================

.cseg


; ============================================================
; RESET VECTOR
; ============================================================

.org 0x0000

    jmp RESET


; ============================================================
; TIMER1 COMPARE A VECTOR
; ============================================================

.org OC1Aaddr

    jmp TIMER1_COMPA_ISR


; ============================================================
; RESET
; ============================================================

RESET:

    ; --------------------------------------------------------
    ; Stack
    ; --------------------------------------------------------

    ldi r16, high(RAMEND)
    out SPH, r16

    ldi r16, low(RAMEND)
    out SPL, r16


    ; --------------------------------------------------------
    ; Clear SRAM variables
    ; --------------------------------------------------------

    clr r16

    sts millis_0, r16
    sts millis_1, r16
    sts millis_2, r16
    sts millis_3, r16

    sts ped_request, r16
    sts ped_active, r16
    sts ped_cooldown, r16
    sts ped_defer, r16
    sts phase_state, r16

    sts phase_wait_0, r16
    sts phase_wait_1, r16
    sts phase_start_0, r16
    sts phase_start_1, r16
    sts cooldown_start_0, r16
    sts cooldown_start_1, r16

    sts night_yellow_state, r16
    sts bright_seen, r16

    sts night_toggle_0, r16
    sts night_toggle_1, r16

    sts bright_start_0, r16
    sts bright_start_1, r16


    ; ========================================================
    ; PORT D
    ;
    ; PD2 = button input
    ; PD3 = NR
    ; PD4 = NY
    ; PD5 = NG
    ; PD6 = SR
    ; PD7 = SY
    ; ========================================================

    ldi r16, (1<<NR)|(1<<NY)|(1<<NG)|(1<<SR)|(1<<SY)

    out DDRD, r16


    ; Button pull-up

    sbi PORTD, PED_BUTTON


    ; ========================================================
    ; PORT B
    ;
    ; PB0 = SG
    ; PB1 = ER
    ; PB2 = EY
    ; PB3 = EG
    ; PB4 = WR
    ; PB5 = WY
    ; ========================================================

    ldi r16, (1<<SG)|(1<<ER)|(1<<EY)|(1<<EG)|(1<<WR)|(1<<WY)

    out DDRB, r16


    ; ========================================================
    ; PORT C
    ;
    ; PC0 = WG
    ; PC1 = LDR ADC input
    ; PC2 = 595 DATA
    ; PC3 = 595 LATCH
    ; PC4 = 595 CLOCK
    ; PC5 = pedestrian RED
    ; ========================================================

    ldi r16, (1<<WG)|(1<<SHIFT_DATA)|(1<<SHIFT_LATCH)|(1<<SHIFT_CLOCK)|(1<<PED_RED)

    out DDRC, r16


    ; --------------------------------------------------------
    ; Traffic OFF
    ; --------------------------------------------------------

    call ALL_TRAFFIC_OFF


    ; --------------------------------------------------------
    ; Pedestrian RED OFF
    ; --------------------------------------------------------

    cbi PORTC, PED_RED


    ; --------------------------------------------------------
    ; 7-segment OFF
    ; pedestrian GREEN OFF
    ; --------------------------------------------------------

    ldi r18, SEG_OFF

    call SHIFT_OUT


    ; ========================================================
    ; ADC SETUP
    ;
    ; AVCC reference
    ; ADC1 = A1
    ; Prescaler = 128
    ; ADC clock = 125 kHz
    ; ========================================================

    ldi r16, (1<<REFS0)|(LDR_ADC_CHANNEL)

    sts ADMUX, r16


    ldi r16, (1<<ADEN)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)

    sts ADCSRA, r16


    ; ========================================================
    ; TIMER1
    ;
    ; 16 MHz / 64 = 250 kHz
    ; OCR1A = 249
    ; 250 counts = 1 ms
    ; ========================================================

    clr r16

    sts TCCR1A, r16


    ldi r16, (1<<WGM12)|(1<<CS11)|(1<<CS10)

    sts TCCR1B, r16


    ldi r16, high(249)
    sts OCR1AH, r16

    ldi r16, low(249)
    sts OCR1AL, r16


    ; Clear pending interrupt

    ldi r16, (1<<OCF1A)

    sts TIFR1, r16


    ; Enable Timer1 Compare A

    ldi r16, (1<<OCIE1A)

    sts TIMSK1, r16


    ; Enable global interrupts

    sei


    rjmp MAIN


; ============================================================
; TIMER1 ISR
;
; 1 ms tick
; ============================================================

TIMER1_COMPA_ISR:

    push r16

    in r16, SREG

    push r16


    lds r16, millis_0

    inc r16

    sts millis_0, r16

    brne TIMER_ISR_DONE


    lds r16, millis_1

    inc r16

    sts millis_1, r16

    brne TIMER_ISR_DONE


    lds r16, millis_2

    inc r16

    sts millis_2, r16

    brne TIMER_ISR_DONE


    lds r16, millis_3

    inc r16

    sts millis_3, r16


TIMER_ISR_DONE:

    pop r16

    out SREG, r16

    pop r16

    reti


; ============================================================
; CHECK PEDESTRIAN BUTTON
;
; Button LOW = pressed
;
; 20 ms debounce is applied before accepting the press.
;
; GREEN:
;   request stored
;   defer = 0
;
; YELLOW:
;   request stored
;   defer = 1
;
; ALL RED:
;   request stored
;   defer = 1
;
; CROSSING:
;   ignored
;
; COOLDOWN:
;   ignored
; ============================================================

CHECK_PED_BUTTON:

    ; Update cooldown in the background on every button check.
    call CHECK_COOLDOWN

    ; --------------------------------------------------------
    ; Button HIGH?
    ; --------------------------------------------------------

    sbic PIND, PED_BUTTON

    rjmp BUTTON_NOT_PRESSED


    ; ========================================================
    ; POSSIBLE BUTTON PRESS
    ;
    ; Wait 20 ms to confirm that the button remains LOW.
    ; ========================================================

    ldi r24, low(BUTTON_DEBOUNCE_MS)
    ldi r25, high(BUTTON_DEBOUNCE_MS)

    call WAIT_NO_BUTTON


    ; --------------------------------------------------------
    ; Check button again after debounce period.
    ;
    ; If it became HIGH, it was probably switch bounce.
    ; --------------------------------------------------------

    sbic PIND, PED_BUTTON

    rjmp BUTTON_NOT_PRESSED


    ; --------------------------------------------------------
    ; Crossing active?
    ; --------------------------------------------------------

    lds r16, ped_active

    tst r16

    brne IGNORE_BUTTON


    ; --------------------------------------------------------
    ; Cooldown active?
    ; --------------------------------------------------------

    lds r16, ped_cooldown

    tst r16

    brne IGNORE_BUTTON


    ; --------------------------------------------------------
    ; Request already stored?
    ; --------------------------------------------------------

    lds r16, ped_request

    tst r16

    brne IGNORE_BUTTON


    ; ========================================================
    ; STORE REQUEST
    ; ========================================================

    ldi r16, 1

    sts ped_request, r16


    ; --------------------------------------------------------
    ; RED pedestrian LED ON
    ; --------------------------------------------------------

    sbi PORTC, PED_RED


    ; --------------------------------------------------------
    ; Determine current traffic state
    ; --------------------------------------------------------

    lds r16, phase_state


    ; GREEN?
    cpi r16, STATE_GREEN

    breq BUTTON_GREEN


    ; --------------------------------------------------------
    ; YELLOW or ALL-RED
    ; both require defer
    ; --------------------------------------------------------

    ldi r16, 1

    sts ped_defer, r16

    rjmp IGNORE_BUTTON


BUTTON_GREEN:

    ; GREEN request can cross at next ALL-RED

    clr r16

    sts ped_defer, r16


IGNORE_BUTTON:

    ; --------------------------------------------------------
    ; Wait for physical release.
    ;
    ; This prevents one long press from becoming
    ; multiple button events.
    ; --------------------------------------------------------

WAIT_BUTTON_RELEASE:

    sbis PIND, PED_BUTTON

    rjmp WAIT_BUTTON_RELEASE


BUTTON_NOT_PRESSED:

    ret


; ============================================================
; WAIT_PHASE
;
; r25:r24 = milliseconds
;
;  
; The requested duration is first copied into SRAM.
;
; This protects the phase duration from being overwritten
; by CHECK_NIGHT / NIGHT_MODE / SHIFT_OUT.
;
; During this wait:
;   - button checked
;   - LDR checked
;
; If Night Mode begins:
;   Night Mode runs
;   phase timer restarts safely
; ============================================================

WAIT_PHASE:

    ; --------------------------------------------------------
    ; Save requested phase duration in SRAM
    ; --------------------------------------------------------

    sts phase_wait_0, r24
    sts phase_wait_1, r25


    ; --------------------------------------------------------
    ; Capture start time
    ; --------------------------------------------------------

    cli
    lds r16, millis_0
    sts phase_start_0, r16
    lds r16, millis_1
    sts phase_start_1, r16
    sei


WAIT_PHASE_LOOP:

    ; --------------------------------------------------------
    ; Reload protected phase duration.
    ;
    ; This is important because Night Mode may use r18/r19.
    ; --------------------------------------------------------

    lds r18, phase_wait_0
    lds r19, phase_wait_1


    ; --------------------------------------------------------
    ; Check LDR / Night Mode
    ; --------------------------------------------------------

    call CHECK_NIGHT


    ; r16 = 1 if Night Mode was entered
    ; r16 = 0 otherwise

    tst r16

    breq WAIT_PHASE_BUTTON


    ; --------------------------------------------------------
    ; Night Mode occurred.
    ;
    ; Restart this phase timing after recovery.
    ; Reloading from SRAM ensures the original phase duration
    ; has not been lost.
    ; --------------------------------------------------------

    cli
    lds r16, millis_0
    sts phase_start_0, r16
    lds r16, millis_1
    sts phase_start_1, r16
    sei


WAIT_PHASE_BUTTON:

    ; --------------------------------------------------------
    ; Check pedestrian button
    ; --------------------------------------------------------

    call CHECK_PED_BUTTON


    ; --------------------------------------------------------
    ; Read current time
    ; --------------------------------------------------------

    cli

    lds r16, millis_0
    lds r17, millis_1

    sei


    ; elapsed = current - saved phase start timestamp.
    ; Called routines may use r20:r21, so the timestamp lives in SRAM.
    lds r20, phase_start_0
    lds r21, phase_start_1
    sub r16, r20
    sbc r17, r21


    ; --------------------------------------------------------
    ; Reload target duration again.
    ; --------------------------------------------------------

    lds r18, phase_wait_0
    lds r19, phase_wait_1


    ; elapsed < target?

    cp r16, r18

    cpc r17, r19

    brlo WAIT_PHASE_LOOP


    ret


; ============================================================
; HANDLE ALL RED
;
; CASE 1:
;   request = 0
;   -> current ALL-RED completes normally
;
; CASE 2:
;   request = 1
;   defer = 0
;   -> cross NOW
;
; CASE 3:
;   request = 1
;   defer = 1
;   -> current ALL-RED completes
;   -> NO crossing
;   -> defer cleared
;   -> next ALL-RED will cross
; ============================================================

HANDLE_ALL_RED:

    ; --------------------------------------------------------
    ; Is there a request?
    ; --------------------------------------------------------

    lds r16, ped_request

    tst r16

    breq NORMAL_ALL_RED


    ; --------------------------------------------------------
    ; Request exists.
    ; Check defer flag.
    ; --------------------------------------------------------

    lds r16, ped_defer

    tst r16

    breq CROSS_NOW


    ; ========================================================
    ; DEFER THIS ALL-RED
    ; ========================================================

    clr r16

    sts ped_defer, r16


    ; Current ALL-RED must finish normally.

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


    ret


CROSS_NOW:

    call PEDESTRIAN_CROSSING

    ret


NORMAL_ALL_RED:

    ; --------------------------------------------------------
    ; Normal 2-second ALL-RED
    ;
    ; Button can be pressed here.
    ; If pressed:
    ;   request = 1
    ;   defer = 1
    ;
    ; Therefore it will NOT cross in this ALL-RED.
    ; --------------------------------------------------------

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE

    ret


; ============================================================
; PEDESTRIAN CROSSING
; ============================================================

PEDESTRIAN_CROSSING:

    ; ========================================================
    ; CROSSING ACTIVE
    ; ========================================================

    ldi r16, 1

    sts ped_active, r16


    ; --------------------------------------------------------
    ; Clear request
    ; --------------------------------------------------------

    clr r16

    sts ped_request, r16


    ; --------------------------------------------------------
    ; Clear defer
    ; --------------------------------------------------------

    sts ped_defer, r16


    ; ========================================================
    ; ALL VEHICLE LIGHTS RED
    ; ========================================================

    call PHASE_ALL_RED


    ; ========================================================
    ; PED RED OFF
    ; ========================================================

    cbi PORTC, PED_RED


    ; ========================================================
    ; 5
    ; ========================================================

    ldi r18, SEG_5

    call SHIFT_OUT

    ldi r24, low(1000)
    ldi r25, high(1000)

    call WAIT_NO_BUTTON


    ; ========================================================
    ; 4
    ; ========================================================

    ldi r18, SEG_4

    call SHIFT_OUT

    ldi r24, low(1000)
    ldi r25, high(1000)

    call WAIT_NO_BUTTON


    ; ========================================================
    ; 3
    ; ========================================================

    ldi r18, SEG_3

    call SHIFT_OUT

    ldi r24, low(1000)
    ldi r25, high(1000)

    call WAIT_NO_BUTTON


    ; ========================================================
    ; 2
    ; ========================================================

    ldi r18, SEG_2

    call SHIFT_OUT

    ldi r24, low(1000)
    ldi r25, high(1000)

    call WAIT_NO_BUTTON


    ; ========================================================
    ; 1
    ; ========================================================

    ldi r18, SEG_1

    call SHIFT_OUT

    ldi r24, low(1000)
    ldi r25, high(1000)

    call WAIT_NO_BUTTON


    ; ========================================================
    ; 0
    ; 200 ms
    ; ========================================================

    ldi r18, SEG_0

    call SHIFT_OUT

    ldi r24, low(200)
    ldi r25, high(200)

    call WAIT_NO_BUTTON


    ; ========================================================
    ; DISPLAY OFF
    ; GREEN OFF
    ; ========================================================

    ldi r18, SEG_OFF

    call SHIFT_OUT


    ; ========================================================
    ; CROSSING FINISHED
    ; ========================================================

    clr r16

    sts ped_active, r16


    ; ========================================================
    ; PED RED MUST STAY OFF
    ; ========================================================

    cbi PORTC, PED_RED


    ; ========================================================
    ; START NON-BLOCKING 5-SECOND COOLDOWN
    ;
    ; Cooldown only blocks new pedestrian requests.
    ; It does NOT hold vehicle lights at all-red.
    ; The normal traffic sequence resumes immediately.
    ; ========================================================

    ldi r16, 1
    sts ped_cooldown, r16

    ; Save the cooldown start timestamp atomically.
    cli
    lds r16, millis_0
    sts cooldown_start_0, r16
    lds r16, millis_1
    sts cooldown_start_1, r16
    sei

    cbi PORTC, PED_RED

    ret


; ============================================================
; CHECK_COOLDOWN
;
; Non-blocking cooldown expiry check. It never changes traffic
; outputs and never waits for the cooldown to finish.
; ============================================================

CHECK_COOLDOWN:

    lds r16, ped_cooldown
    tst r16
    breq COOLDOWN_CHECK_DONE

    ; Read current timer atomically.
    cli
    lds r16, millis_0
    lds r17, millis_1
    sei

    ; elapsed = current time - cooldown start
    lds r20, cooldown_start_0
    lds r21, cooldown_start_1
    sub r16, r20
    sbc r17, r21

    ; Has 5000 ms elapsed?
    ldi r18, low(5000)
    ldi r19, high(5000)
    cp r16, r18
    cpc r17, r19
    brlo COOLDOWN_CHECK_DONE

    clr r16
    sts ped_cooldown, r16

COOLDOWN_CHECK_DONE:
    ret


; ============================================================
; WAIT_NO_BUTTON
;
; r25:r24 = milliseconds
;
; No pedestrian button checking.
; Used during:
;   - button debounce
;   - pedestrian countdown
; Cooldown is non-blocking and does not use this routine.
; ============================================================

WAIT_NO_BUTTON:

    mov r18, r24
    mov r19, r25


    cli

    lds r20, millis_0
    lds r21, millis_1

    sei


WAIT_NO_BUTTON_LOOP:

    cli

    lds r16, millis_0
    lds r17, millis_1

    sei


    sub r16, r20

    sbc r17, r21


    cp r16, r18

    cpc r17, r19

    brlo WAIT_NO_BUTTON_LOOP


    ret


; ============================================================
; WAIT_BUTTON_RELEASE_ONLY
; ============================================================

WAIT_BUTTON_RELEASE_ONLY:

    sbis PIND, PED_BUTTON

    rjmp WAIT_BUTTON_RELEASE_ONLY

    ret


; ============================================================
; CHECK NIGHT
;
; Returns:
;
; r16 = 0
;   normal operation
;
; r16 = 1
;   Night Mode was entered and completed
; ============================================================

CHECK_NIGHT:

    call READ_LDR


    ; r25:r24 = ADC value


    ; --------------------------------------------------------
    ; Compare with 400
    ; --------------------------------------------------------

    cpi r25, high(DARK_THRESHOLD)

    brlo LDR_DARK


    brne LDR_BRIGHT


    cpi r24, low(DARK_THRESHOLD)

    brlo LDR_DARK


LDR_BRIGHT:

    clr r16

    ret


LDR_DARK:

    call NIGHT_MODE

    ldi r16, 1

    ret


; ============================================================
; READ LDR
;
; Returns ADC value in r25:r24
; ============================================================

READ_LDR:

    ; --------------------------------------------------------
    ; ADC1
    ; --------------------------------------------------------

    ldi r16, (1<<REFS0)|(LDR_ADC_CHANNEL)

    sts ADMUX, r16


    ; Start conversion

    lds r16, ADCSRA

    ori r16, (1<<ADSC)

    sts ADCSRA, r16


ADC_WAIT:

    lds r16, ADCSRA

    sbrc r16, ADSC

    rjmp ADC_WAIT


    ; --------------------------------------------------------
    ; Read ADCL first
    ; --------------------------------------------------------

    lds r24, ADCL

    lds r25, ADCH


    ret


; ============================================================
; NIGHT MODE
;
; DARK:
;   traffic red/green OFF
;   all yellow flash
;   500 ms ON
;   500 ms OFF
;
; Button ignored.
; Pedestrian request cleared.
;
; Recovery:
;   LDR must remain bright for 5 continuous seconds.
; ============================================================

NIGHT_MODE:

    ; ========================================================
    ; Clear pedestrian state
    ; ========================================================

    clr r16

    sts ped_request, r16
    sts ped_active, r16
    sts ped_cooldown, r16
    sts ped_defer, r16


    ; ========================================================
    ; Pedestrian indicators OFF
    ; ========================================================

    cbi PORTC, PED_RED


    ldi r18, SEG_OFF

    call SHIFT_OUT


    ; ========================================================
    ; Vehicle lights OFF initially
    ; ========================================================

    call ALL_TRAFFIC_OFF


    ; ========================================================
    ; Yellow initially OFF
    ; ========================================================

    clr r16

    sts night_yellow_state, r16


    ; ========================================================
    ; Capture toggle start
    ; ========================================================

    cli

    lds r16, millis_0
    sts night_toggle_0, r16

    lds r16, millis_1
    sts night_toggle_1, r16

    sei


    ; ========================================================
    ; Bright recovery timer OFF
    ; ========================================================

    clr r16

    sts bright_seen, r16


NIGHT_LOOP:

    ; --------------------------------------------------------
    ; Read LDR
    ; --------------------------------------------------------

    call READ_LDR


    ; --------------------------------------------------------
    ; Check dark/bright
    ; --------------------------------------------------------

    cpi r25, high(DARK_THRESHOLD)

    brlo NIGHT_STILL_DARK

    brne NIGHT_IS_BRIGHT

    cpi r24, low(DARK_THRESHOLD)

    brlo NIGHT_STILL_DARK


NIGHT_IS_BRIGHT:

    ; ========================================================
    ; BRIGHT
    ;
    ; Need 5 continuous seconds.
    ; ========================================================

    lds r16, bright_seen

    tst r16

    brne BRIGHT_TIMER_RUNNING


    ; Start bright timer

    ldi r16, 1

    sts bright_seen, r16


    cli

    lds r16, millis_0
    sts bright_start_0, r16

    lds r16, millis_1
    sts bright_start_1, r16

    sei


BRIGHT_TIMER_RUNNING:

    ; --------------------------------------------------------
    ; Check elapsed bright time
    ; --------------------------------------------------------

    cli

    lds r16, millis_0
    lds r17, millis_1

    sei


    lds r20, bright_start_0
    lds r21, bright_start_1


    sub r16, r20
    sbc r17, r21


    ; Compare with 5000 ms

    ldi r18, low(5000)
    ldi r19, high(5000)

    cp r16, r18
    cpc r17, r19

    brsh NIGHT_RECOVERED


    ; Not yet 5 seconds

    rjmp NIGHT_FLASH_CHECK


NIGHT_STILL_DARK:

    ; ========================================================
    ; DARK AGAIN
    ;
    ; Reset bright recovery timer.
    ; ========================================================

    clr r16

    sts bright_seen, r16


NIGHT_FLASH_CHECK:

    ; ========================================================
    ; Check 500 ms yellow toggle timer
    ; ========================================================

    cli

    lds r16, millis_0
    lds r17, millis_1

    sei


    lds r20, night_toggle_0
    lds r21, night_toggle_1


    sub r16, r20
    sbc r17, r21


    ldi r18, low(500)
    ldi r19, high(500)


    cp r16, r18
    cpc r17, r19

    brlo NIGHT_LOOP


    ; ========================================================
    ; Reset toggle timer
    ; ========================================================

    cli

    lds r16, millis_0
    sts night_toggle_0, r16

    lds r16, millis_1
    sts night_toggle_1, r16

    sei


    ; ========================================================
    ; Toggle yellow
    ; ========================================================

    lds r16, night_yellow_state

    tst r16

    breq NIGHT_TURN_YELLOW_ON


NIGHT_TURN_YELLOW_OFF:

    call ALL_TRAFFIC_OFF

    clr r16

    sts night_yellow_state, r16

    rjmp NIGHT_LOOP


NIGHT_TURN_YELLOW_ON:

    call ALL_TRAFFIC_OFF


    ; North yellow

    sbi PORTD, NY

    ; South yellow

    sbi PORTD, SY

    ; East yellow

    sbi PORTB, EY

    ; West yellow

    sbi PORTB, WY


    ldi r16, 1

    sts night_yellow_state, r16


    rjmp NIGHT_LOOP


; ============================================================
; NIGHT RECOVERED
; ============================================================

NIGHT_RECOVERED:

    ; --------------------------------------------------------
    ; Turn all lights OFF
    ; --------------------------------------------------------

    call ALL_TRAFFIC_OFF


    ; --------------------------------------------------------
    ; Clear night variables
    ; --------------------------------------------------------

    clr r16

    sts night_yellow_state, r16
    sts bright_seen, r16


    ; --------------------------------------------------------
    ; Pedestrian indicators OFF
    ; --------------------------------------------------------

    cbi PORTC, PED_RED


    ldi r18, SEG_OFF

    call SHIFT_OUT


    ret


; ============================================================
; MAIN TRAFFIC SEQUENCE
; ============================================================

MAIN:

    ; Initial startup safety phase only: all vehicle lights red for 1 second.
    ; All later normal all-red phases retain their original 2000 ms duration.
    call PHASE_ALL_RED
    ldi r24, low(1000)
    ldi r25, high(1000)
    call WAIT_PHASE


; ============================================================
; P1
; E + W YELLOW PREPARE
; ============================================================

    call PHASE_EW_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P2
; E + W GREEN
; ============================================================

    call PHASE_EW_GREEN

    ldi r24, low(7000)
    ldi r25, high(7000)

    call WAIT_PHASE


; ============================================================
; P3
; E + W YELLOW
; ============================================================

    call PHASE_EW_YELLOW

    ldi r24, low(3000)
    ldi r25, high(3000)

    call WAIT_PHASE


; ============================================================
; P4
; ALL RED
; ============================================================

    call PHASE_ALL_RED
    call HANDLE_ALL_RED


; ============================================================
; P5
; N + S YELLOW PREPARE
; ============================================================

    call PHASE_NS_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P6
; N + S GREEN
; ============================================================

    call PHASE_NS_GREEN

    ldi r24, low(7000)
    ldi r25, high(7000)

    call WAIT_PHASE


; ============================================================
; P7
; N + S YELLOW
; ============================================================

    call PHASE_NS_YELLOW

    ldi r24, low(3000)
    ldi r25, high(3000)

    call WAIT_PHASE


; ============================================================
; P8
; ALL RED
; ============================================================

    call PHASE_ALL_RED
    call HANDLE_ALL_RED


; ============================================================
; P9
; EAST YELLOW
; ============================================================

    call PHASE_E_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P10
; EAST GREEN
; ============================================================

    call PHASE_E_GREEN

    ldi r24, low(5000)
    ldi r25, high(5000)

    call WAIT_PHASE


; ============================================================
; P11
; EAST YELLOW
; ============================================================

    call PHASE_E_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P12
; ALL RED
; ============================================================

    call PHASE_ALL_RED
    call HANDLE_ALL_RED


; ============================================================
; P13
; WEST YELLOW
; ============================================================

    call PHASE_W_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P14
; WEST GREEN
; ============================================================

    call PHASE_W_GREEN

    ldi r24, low(5000)
    ldi r25, high(5000)

    call WAIT_PHASE


; ============================================================
; P15
; WEST YELLOW
; ============================================================

    call PHASE_W_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P16
; ALL RED
; ============================================================

    call PHASE_ALL_RED
    call HANDLE_ALL_RED


; ============================================================
; P17
; NORTH YELLOW
; ============================================================

    call PHASE_N_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P18
; NORTH GREEN
; ============================================================

    call PHASE_N_GREEN

    ldi r24, low(5000)
    ldi r25, high(5000)

    call WAIT_PHASE


; ============================================================
; P19
; NORTH YELLOW
; ============================================================

    call PHASE_N_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P20
; ALL RED
; ============================================================

    call PHASE_ALL_RED
    call HANDLE_ALL_RED


; ============================================================
; P21
; SOUTH YELLOW
; ============================================================

    call PHASE_S_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P22
; SOUTH GREEN
; ============================================================

    call PHASE_S_GREEN

    ldi r24, low(5000)
    ldi r25, high(5000)

    call WAIT_PHASE


; ============================================================
; P23
; SOUTH YELLOW
; ============================================================

    call PHASE_S_YELLOW

    ldi r24, low(2000)
    ldi r25, high(2000)

    call WAIT_PHASE


; ============================================================
; P24
; ALL RED
; ============================================================

    call PHASE_ALL_RED
    call HANDLE_ALL_RED


    ; Repeat

    rjmp MAIN


; ============================================================
; PHASE E + W YELLOW
; ============================================================

PHASE_EW_YELLOW:

    ldi r16, STATE_YELLOW
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTD, SR

    sbi PORTB, EY
    sbi PORTB, WY

    ret


; ============================================================
; PHASE E + W GREEN
; ============================================================

PHASE_EW_GREEN:

    ldi r16, STATE_GREEN
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTD, SR

    sbi PORTB, EG
    sbi PORTC, WG

    ret


; ============================================================
; PHASE N + S YELLOW
; ============================================================

PHASE_NS_YELLOW:

    ldi r16, STATE_YELLOW
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTB, ER
    sbi PORTB, WR

    sbi PORTD, NY
    sbi PORTD, SY

    ret


; ============================================================
; PHASE N + S GREEN
; ============================================================

PHASE_NS_GREEN:

    ldi r16, STATE_GREEN
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTB, ER
    sbi PORTB, WR

    sbi PORTD, NG
    sbi PORTB, SG

    ret


; ============================================================
; EAST YELLOW
; ============================================================

PHASE_E_YELLOW:

    ldi r16, STATE_YELLOW
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTD, SR
    sbi PORTB, WR

    sbi PORTB, EY

    ret


; ============================================================
; EAST GREEN
; ============================================================

PHASE_E_GREEN:

    ldi r16, STATE_GREEN
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTD, SR
    sbi PORTB, WR

    sbi PORTB, EG

    ret


; ============================================================
; WEST YELLOW
; ============================================================

PHASE_W_YELLOW:

    ldi r16, STATE_YELLOW
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTD, SR
    sbi PORTB, ER

    sbi PORTB, WY

    ret


; ============================================================
; WEST GREEN
; ============================================================

PHASE_W_GREEN:

    ldi r16, STATE_GREEN
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTD, SR
    sbi PORTB, ER

    sbi PORTC, WG

    ret


; ============================================================
; NORTH YELLOW
; ============================================================

PHASE_N_YELLOW:

    ldi r16, STATE_YELLOW
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, SR
    sbi PORTB, ER
    sbi PORTB, WR

    sbi PORTD, NY

    ret


; ============================================================
; NORTH GREEN
; ============================================================

PHASE_N_GREEN:

    ldi r16, STATE_GREEN
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, SR
    sbi PORTB, ER
    sbi PORTB, WR

    sbi PORTD, NG

    ret


; ============================================================
; SOUTH YELLOW
; ============================================================

PHASE_S_YELLOW:

    ldi r16, STATE_YELLOW
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTB, ER
    sbi PORTB, WR

    sbi PORTD, SY

    ret


; ============================================================
; SOUTH GREEN
; ============================================================

PHASE_S_GREEN:

    ldi r16, STATE_GREEN
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTB, ER
    sbi PORTB, WR

    sbi PORTB, SG

    ret


; ============================================================
; ALL RED
; ============================================================

PHASE_ALL_RED:

    ldi r16, STATE_ALLRED
    sts phase_state, r16

    call ALL_TRAFFIC_OFF

    sbi PORTD, NR
    sbi PORTD, SR

    sbi PORTB, ER
    sbi PORTB, WR

    ret


; ============================================================
; ALL TRAFFIC OFF
; ============================================================

ALL_TRAFFIC_OFF:

    ; NORTH

    cbi PORTD, NR
    cbi PORTD, NY
    cbi PORTD, NG

    ; SOUTH

    cbi PORTD, SR
    cbi PORTD, SY
    cbi PORTB, SG

    ; EAST

    cbi PORTB, ER
    cbi PORTB, EY
    cbi PORTB, EG

    ; WEST

    cbi PORTB, WR
    cbi PORTB, WY
    cbi PORTC, WG

    ret


; ============================================================
; SHIFT OUT
;
; r18 = data
; MSB first
; ============================================================

SHIFT_OUT:

    cbi PORTC, SHIFT_LATCH

    ldi r19, 8


SHIFT_LOOP:

    cbi PORTC, SHIFT_CLOCK


    sbrc r18, 7

    rjmp SHIFT_BIT_ONE


SHIFT_BIT_ZERO:

    cbi PORTC, SHIFT_DATA

    rjmp SHIFT_CLOCK_HIGH


SHIFT_BIT_ONE:

    sbi PORTC, SHIFT_DATA


SHIFT_CLOCK_HIGH:

    sbi PORTC, SHIFT_CLOCK

    lsl r18

    dec r19

    brne SHIFT_LOOP


    cbi PORTC, SHIFT_CLOCK

    sbi PORTC, SHIFT_LATCH

    cbi PORTC, SHIFT_LATCH

    ret