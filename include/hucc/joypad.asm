; ***************************************************************************
; ***************************************************************************
;
; joypad.asm
;
; Read 2-button & 6-button joypads & PCE mouse, with or without a MultiTap.
;
; Copyright John Brandwood 2019-2025.
;
; Distributed under the Boost Software License, Version 1.0.
; (See accompanying file LICENSE_1_0.txt or copy at
;  http://www.boost.org/LICENSE_1_0.txt)
;
; ***************************************************************************
; ***************************************************************************
;
; Unlike Lemmings, this code does not interfere with a Memory Base 128! ;-)
;
; ***************************************************************************
; ***************************************************************************
;
; With SUPPORT_MOUSE ..... 2602 cycles to read 5 ports with 5 mice
;
; With HuC library code .. 2442 cycles to read 5 ports with 5 pads (2-button)
; With HuC library code .. 2442 cycles to read 5 ports with 5 pads (6-button)
;
; With SUPPORT_MOUSE ....  2016 cycles to read 5 ports with 5 pads (2-button)
; With SUPPORT_MOUSE ..... 1976 cycles to read 5 ports with 5 pads (6-button)
;
; With SUPPORT_MOUSE ....  1618 cycles to read 3 ports with 3 mice
; With SUPPORT_MOUSE ..... 1462 cycles to read 3 ports with 2 mice
; With SUPPORT_MOUSE ..... 1306 cycles to read 3 ports with 1 mouse
;
; With SUPPORT_6BUTTON ... 1235 cycles to read 5 ports with 5 pads (2-button)
; With SUPPORT_6BUTTON ... 1215 cycles to read 5 ports with 5 pads (6-button)
;
; With SUPPORT_MOUSE ..... 1126 cycles to read 2 ports with 2 mice
; With SUPPORT_MOUSE ...... 970 cycles to read 2 ports with 1 mouse
;
; Only SUPPORT_2BUTTON .... 971 cycles to read 5 ports with 5 pads (2-button)
; Only SUPPORT_2BUTTON .... 861 cycles to read 5 ports with 5 pads (6-button)
;
; With SUPPORT_MOUSE ...... 634 cycles to read 1 port  with 1 mouse
;
; ***************************************************************************
; ***************************************************************************

		.nolist

;
; Select which version of the joystick library code to include, only one of
; these can be set to '1' ...
;
; SUPPORT_2BUTTON : Only returns buttons I and II.
; SUPPORT_6BUTTON : Read buttons III-VI, but ignore a mouse.
; SUPPORT_MOUSE	  : Read mouse, but ignore buttons III-VI.
;
; It doesn't make sense to design a game the relies on both the 6-button and
; the mouse, so the joystick library is optimized for one or the other.
;
; Note that both those devices are always detected and no conflicts occur,
; this just controls reading either buttons III-VI or the Mouse Y-movement.
;
; There is hidden support for setting both SUPPORT_6BUTTON and SUPPORT_MOUSE
; which has little use in games, but can be useful for hardware-test code.
;

	.ifndef SUPPORT_2BUTTON
	.ifndef	SUPPORT_6BUTTON
	.ifndef	SUPPORT_MOUSE
SUPPORT_2BUTTON	=	1	; (0 or 1)
SUPPORT_6BUTTON	=	0	; (0 or 1)
SUPPORT_MOUSE	=	0	; (0 or 1)
	.endif
	.endif
	.endif

	.ifndef SUPPORT_2BUTTON
SUPPORT_2BUTTON	=	0
	.endif

;
; How many joypad/mouse devices should be supported?
;
; This is normally 5, but can be set to 3 (or lower) in order to speed up
; the processing and free up CPU time for other code, which is especially
; useful for mouse games.
;

	.ifndef MAX_PADS
MAX_PADS	=	5
	.endif

;
; Remove Phantom Mice?
;
; If there is no multitap, and one mouse in port 1, then the code will
; detect mice in every port.
;
; Setting this adds a check for this case, which then sets the maximum
; number of ports to 1.
;
; Note that it is actually possible to have mice in every port, but it
; is so unlikely that it is easier to use this setting to take care of
; the far-more-common case of having a single mouse and no multitap.
;

	.ifndef DETECT_PHANTOMS
DETECT_PHANTOMS	=	1
	.endif

;
; Implement a HuC-compatible seperate array for accumulating joypad presses?
;
; This is only really needed if your game is not expected to run at 60Hz and
; so you will sometimes miss joypad presses.
;
; Alternatively you can set ACCUMULATE_JOY so that joypad presses are always
; accumulated in the normal joytrg array, which is how asm programmers would
; normally deal with this situation.
;

	.ifndef HUC_JOY_EVENTS
HUC_JOY_EVENTS	=	0
	.endif

;
; Should "joytrg" accumulate presses, and so need to be explicitely cleared
; after reading, or should it just be the result of the last read?
;
; This option has no effect if HUC_JOY_EVENTS is non-zero since that option
; takes precedence over this one!
;

	.ifndef ACCUMULATE_JOY
ACCUMULATE_JOY	=	0
	.endif



		.list

;
; Now choose which version of the code to include.
;

	.if	SUPPORT_2BUTTON

; ***************************************************************************
; ***************************************************************************
;
; read_joypads - 6-button pad recognized, but the extra buttons are ignored.
;
; This is small, and functionally similar to the System Card's ex_joysns,
; except that it handles the presence of a 6-button joypad correctly.
;
; A mouse will read I/II/SELECT/RUN correctly, but the rest are random.
;
; The code loops two times to skip extra buttons on a 6-button joypad.
;
; bit values for joypad 2-button bytes: (MSB = #7; LSB = #0)
; ----------------------------------------------------------
; bit 0 (ie $01) = I
; bit 1 (ie $02) = II
; bit 2 (ie $04) = SELECT
; bit 3 (ie $08) = RUN
; bit 4 (ie $10) = UP
; bit 5 (ie $20) = RIGHT
; bit 6 (ie $40) = DOWN
; bit 7 (ie $80) = LEFT
;

		.code

	.if	(* >= $4000)			; Make this a ".proc" if it
read_joypads	.proc                           ; not running in RAM.
	.else
read_joypads:
	.endif

		lda	#$80			; Acquire port mutex to avoid
		tsb	port_mutex		; conflict with a delayed VBL
		bmi	.exit			; or access to an MB128.

		tii	joynow,joyold,MAX_PADS	; Save the previous values.

.calc_pressed:	bsr	.read_devices		; Read all devices normally.

		ldy	#MAX_PADS - 1

.pressed_loop:	lda	joynow, y		; Calc which buttons have just
		tax                             ; been pressed (2-button).
		eor	joyold, y
		and	joynow, y
	.if	HUC_JOY_EVENTS
		sta	joytrg, y
		ora	joybuf, y		; HuC/HuCC accumulates presses
		sta	joybuf, y		; in a seperate array.
	.else
	.if	ACCUMULATE_JOY
		ora	joytrg, y
	.endif
		sta	joytrg, y
	.endif

		cmp	#$04			; Detect the soft-reset combo,
		bne	.not_reset		; hold RUN then press SELECT.
		cpx	#$0C
		bne	.not_reset
		lda	bit_mask, y
		bit	joyena
		bne	.soft_reset

.not_reset:	dey				; Check the next pad from the
		bpl	.pressed_loop		; multitap.

		stz	port_mutex		; Release port mutex.

	.if	(* >= $4000)			; This is a ".proc" if it is
.exit:		leave                           ; not running in RAM.
	.else
.exit:		rts				; All done, phew!
	.endif

.soft_reset:	sei				; Disable interrupts.
		stz	port_mutex		; Release port mutex.
		jmp	[reset_hook]		; Jump to the soft-reset hook.

		; Read all of the devices attached to the MultiTap.

.read_devices:	bsr	.read_multitap		; Repeat this loop 2 times.

.read_multitap:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT
		lda	#$03			; CLR hi, SEL hi, reset tap.
		sta	IO_PORT
		cly				; Start at port 1.

.read_port:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT			; Wait 1.25us (9 cycles).
		pha
		pla
		nop

.read_pad:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		beq	.next_port		; 6-btn pad if UDLR all held.

.read_2button:	sta	joynow, y		; Get buttons of 2-btn pad.
		lda	IO_PORT
		and	#$0F
		ora	joynow, y
		eor	#$FF
		sta	joynow, y

.next_port:	iny				; Get the next pad from the
		cpy	#MAX_PADS		; multitap.
		bcc	.read_port

		rts				; Now that everything is read.

	.if	(* >= $4000)			; This is a ".proc" if it is
		.endp                           ; not running in RAM.
		.bss				; Put the variables in RAM.
	.endif

port_mutex:	ds	1			; NZ when controller port busy.
	.if	HUC_JOY_EVENTS
joybuf:		ds	MAX_PADS
	.endif

		.code

	.endif	SUPPORT_2BUTTON



	.if	SUPPORT_MOUSE

	.if	SUPPORT_6BUTTON			; With mouse!

; ***************************************************************************
; ***************************************************************************
;
; read_joypads - full mouse support, AND full 6-button pad support.
;
; This code distinguishes between a mouse and a 2-button or 6-button joypad,
; so that unsupported devices do not have to be unplugged from the MultiTap.
;
; The code loops four times to get both sets of 8-bit mouse delta values.
;
; N.B. Takes approx 1/3 frame to detect mice the first time it is run.
;
; bit values for joypad 2-button bytes: (MSB = #7; LSB = #0)
; ----------------------------------------------------------
; bit 0 (ie $01) = I
; bit 1 (ie $02) = II
; bit 2 (ie $04) = SELECT
; bit 3 (ie $08) = RUN
; bit 4 (ie $10) = UP
; bit 5 (ie $20) = RIGHT
; bit 6 (ie $40) = DOWN
; bit 7 (ie $80) = LEFT
;
; bit values for joypad 6-button bytes: (MSB = #7; LSB = #0)
; ----------------------------------------------------------
; bit 0 (ie $01) = III
; bit 1 (ie $02) = IV
; bit 2 (ie $04) = V
; bit 3 (ie $08) = VI
; bit 4 (ie $10) = zero
; bit 5 (ie $20) = zero
; bit 6 (ie $40) = zero
; bit 7 (ie $80) = zero, but set to one if 6-button pad detected.
;
; This version of the code also detects whether an NEC MultiTap is being used
; by reading its 6th port, which returns $00 (all buttons pressed).
;

		.code

	.if	(* >= $4000)			; Make this a ".proc" if it
read_joypads	.proc                           ; not running in RAM.
	.else
read_joypads:
	.endif

		lda	#$80			; Acquire port mutex to avoid
		tsb	port_mutex		; conflict with a delayed VBL
		bmi	.exit			; or access to an MB128.

		tii	joynow,joyold,MAX_PADS	; Save the previous values.
		tii	joy6now,joy6old,MAX_PADS

		; Reset the 6-btn bits, the user might change the joypad mode!

		tai	const_0000, joy6now, MAX_PADS

		; Detect attached mice the first time this routine is called.

		lda	mouse_flg		; Has mouse detection happened?
		bpl	.detect_mice

		; See what has just been pressed, and check for soft-reset.

.calc_pressed:	jsr	.read_devices		; Read all devices normally.

		ldx	#MAX_PADS - 1

.pressed_loop:	lda	joy6now, x		; Calc which buttons have just
		eor	joy6old, x		; been pressed (6-button).
		and	joy6now, x
	.if	HUC_JOY_EVENTS
		sta	joy6trg, y
		ora	joy6buf, y		; HuC/HuCC accumulates presses
		sta	joy6buf, y		; in a seperate array.
	.else
	.if	ACCUMULATE_JOY
		ora	joy6trg, y
	.endif
		sta	joy6trg, y
	.endif

		lda	joynow, x		; Calc which buttons have just
		tay                             ; been pressed (2-button).
		eor	joyold, x
		and	joynow, x
	.if	HUC_JOY_EVENTS
		sta	joytrg, y
		ora	joybuf, y		; HuC/HuCC accumulates presses
		sta	joybuf, y		; in a seperate array.
	.else
	.if	ACCUMULATE_JOY
		ora	joytrg, y
	.endif
		sta	joytrg, y
	.endif

		cmp	#$04			; Detect the soft-reset combo,
		bne	.not_reset		; hold RUN then press SELECT.
		cpy	#$0C
		bne	.not_reset
		lda	bit_mask, x
		bit	joyena
		bne	.soft_reset

.not_reset:	dex				; Check the next pad from the
		bpl	.pressed_loop		; multitap.

		stz	port_mutex		; Release port mutex.

	.if	(* >= $4000)			; This is a ".proc" if it is
.exit:		leave                           ; not running in RAM.
	.else
.exit:		rts				; All done, phew!
	.endif

.soft_reset:	sei				; Disable interrupts.
		stz	port_mutex		; Release port mutex.
		jmp	[reset_hook]		; Jump to the soft-reset hook.

		;
		; Detect attached mice the first time this routine is called.
		;

.detect_mice:	lda	#MAX_PADS		; Reset number of pads to read.
		sta	num_ports

		lda	#%00011111		; Try reading everything as a
		sta	mouse_flg		; mouse.

		ldy	#15			; Initialize repeat count.
		lda	#$80			; Initialize mouse detection.
.detect_loop:	phy
		pha
		bsr	.read_devices		; Read all devices as if mice.
		pla
		clx
.detect_port:	ldy	mouse_y, x		; A movement of zero means
		bne	.detect_next		; this port is a mouse.
		ora	bit_mask, x
.detect_next:	inx				; Get the next pad from the
		cpx	#MAX_PADS		; multitap.
		bne	.detect_port
		ply				; Repeat the detection test.
		dey
		bne	.detect_loop

		tay				; Preserve mouse detection.

.ignore_port:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT			; Wait 1.25us (9 cycles).
		pha
		pla
		inx
		lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		cpx	#6			; Keep looping until port #6
		bne	.ignore_port		; to detect an NEC multitap.

		sta	joytrg			; Get buttons of 2-btn pad.
		lda	IO_PORT
		and	#$0F
		ora	joytrg
		sta	port6
		bne	.no_multitap		; NEC multitap if zero.

		tya				; Restore mouse detection.
		ora	#$40			; Signal multitap present.
		db	$F0			; Turn "tya" into a "beq".

.no_multitap:	tya				; Restore mouse detection.

	.if	DETECT_PHANTOMS
		cmp	#(1 << MAX_PADS) + 127	; If we find a mouse in every
		bne	.detect_done		; port, then assume mirrored!
		lda	#1			; Report a single mouse in a
		sta	num_ports		; single port.
		lda	#$81
	.endif	DETECT_PHANTOMS

.detect_done:	sta	mouse_flg		; Report mouse detection.
		jmp	.calc_pressed

		;
		; Read all of the devices attached to the MultiTap.
		;

.read_devices:	ldx	#6			; Repeat this loop 4 times.

.read_multitap:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT
		lda	#$03			; CLR hi, SEL hi, reset tap.
		sta	IO_PORT
		cly				; Start at port 1.

.read_port:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT			; Wait 1.25us (9 cycles).

		lda	bit_mask, y		; Is there a mouse attached?
		and	mouse_flg
		bne	.read_mouse

.read_pad:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		beq	.read_6button		; 6-btn pad if UDLR all held.

.read_2button:	sta	joynow, y		; Get buttons of 2-btn pad.
		lda	IO_PORT
		and	#$0F
		ora	joynow, y
		eor	#$FF
		sta	joynow, y

.next_port:	iny				; Get the next pad from the
		cpy	num_ports		; multitap.
		bcc	.read_port

		dex				; Do the next complete pass.
		dex
		bpl	.read_multitap		; Have we finished 4 passes?
		rts				; Now that everything is read.

.read_6button:	lda	IO_PORT			; Get buttons of 6-btn pad.
		and	#$0F
		eor	#$8F			; Set bit-7 to show that a
		sta	joy6now, y		; 6-button pad is present.
		bra	.next_port

.read_mouse:	jmp	[.mouse_vectors, x]	; Which mouse info is next?

		;
		; Mouse processing, split into four passes.
		;

.mouse_x_hi:	lda	#28			; 189 cycle delay after CLR lo
.wait_loop:	dec	a			; on port to allow the mouse
		bne	.wait_loop		; to buffer and reset counters.

		lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		sta	mouse_x, y		; Save port's X-hi nibble.

		lda	IO_PORT			; Get mouse buttons.
		and	#$0F
		eor	#$0F
		sta	joynow, y
		bra	.next_port

.mouse_x_lo:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		and	#$0F			; Wait 1.25us (9 cycles).
		ora	mouse_x, y		; Add port's X-hi nibble.
		eor	#$FF			; Negate so LEFT is -ve.
		inc	a
		sta	mouse_x, y
		bra	.next_port

.mouse_y_hi:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		sta	mouse_y, y		; Save port's Y-hi nibble.
		bra	.next_port

.mouse_y_lo:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		and	#$0F			; Wait 1.25us (9 cycles).
		ora	mouse_y, y		; Add port's Y-hi nibble.
		eor	#$FF			; Negate so UP is -ve.
		inc	a
		sta	mouse_y, y
		bra	.next_port

.mouse_vectors: dw	.mouse_y_lo		; Pass 4
		dw	.mouse_y_hi		; Pass 3
		dw	.mouse_x_lo		; Pass 2
		dw	.mouse_x_hi		; Pass 1

	.if	(* >= $4000)			; This is a ".proc" if it is
		.endp                           ; not running in RAM.
		.bss				; Put the variables in RAM.
	.endif

port_mutex:	ds	1			; NZ when controller port busy.
num_ports:	ds	1			; Set to 1 if no multitap.
mouse_flg:	ds	1			; Which ports are mice?
port6:		ds	1			; Contents of port6.
	.if	HUC_JOY_EVENTS
joybuf:		ds	MAX_PADS
joy6buf:	ds	MAX_PADS
	.endif
joy6now:	ds	MAX_PADS
joy6old:	ds	MAX_PADS
joy6trg:	ds	MAX_PADS
mouse_x:	ds	MAX_PADS
mouse_y:	ds	MAX_PADS

		.code



	.else	SUPPORT_6BUTTON			; With mouse!

; ***************************************************************************
; ***************************************************************************
;
; read_joypads - full mouse support, but 6-button pad III..VI are ignored.
;
; This code distinguishes between a mouse and a 2-button or 6-button joypad,
; so that unsupported devices do not have to be unplugged from the MultiTap.
;
; The code loops four times to get both sets of 8-bit mouse delta values.
;
; N.B. Takes approx 1/3 frame to detect mice the first time it is run.
;
; bit values for joypad 2-button bytes: (MSB = #7; LSB = #0)
; ----------------------------------------------------------
; bit 0 (ie $01) = I
; bit 1 (ie $02) = II
; bit 2 (ie $04) = SELECT
; bit 3 (ie $08) = RUN
; bit 4 (ie $10) = UP
; bit 5 (ie $20) = RIGHT
; bit 6 (ie $40) = DOWN
; bit 7 (ie $80) = LEFT
;

		.code

	.if	(* >= $4000)			; Make this a ".proc" if it
read_joypads	.proc                           ; not running in RAM.
	.else
read_joypads:
	.endif

		lda	#$80			; Acquire port mutex to avoid
		tsb	port_mutex		; conflict with a delayed VBL
		bmi	.exit			; or access to an MB128.

		tii	joynow,joyold,MAX_PADS	; Save the previous values.

		; Detect attached mice the first time this routine is called.

		lda	mouse_flg		; Has mouse detection happened?
		bpl	.detect_mice

		; See what has just been pressed, and check for soft-reset.

.calc_pressed:	jsr	.read_devices		; Read all devices normally.

		ldx	#MAX_PADS - 1

.pressed_loop:	lda	joynow, x		; Calc which buttons have just
		tay                             ; been pressed (2-button).
		eor	joyold, x
		and	joynow, x
	.if	HUC_JOY_EVENTS
		sta	joytrg, y
		ora	joybuf, y		; HuC/HuCC accumulates presses
		sta	joybuf, y		; in a seperate array.
	.else
	.if	ACCUMULATE_JOY
		ora	joytrg, y
	.endif
		sta	joytrg, y
	.endif

		cmp	#$04			; Detect the soft-reset combo,
		bne	.not_reset		; hold RUN then press SELECT.
		cpy	#$0C
		bne	.not_reset
		lda	bit_mask, x
		bit	joyena
		bne	.soft_reset

.not_reset:	dex				; Check the next pad from the
		bpl	.pressed_loop		; multitap.

		stz	port_mutex		; Release port mutex.

	.if	(* >= $4000)			; This is a ".proc" if it is
.exit:		leave                           ; not running in RAM.
	.else
.exit:		rts				; All done, phew!
	.endif

.soft_reset:	sei				; Disable interrupts.
		stz	port_mutex		; Release port mutex.
		jmp	[reset_hook]		; Jump to the soft-reset hook.

		;
		; Detect attached mice the first time this routine is called.
		;

.detect_mice:	lda	#MAX_PADS		; Reset number of pads to read.
		sta	num_ports

		lda	#%00011111		; Try reading everything as a
		sta	mouse_flg		; mouse.

		ldy	#15			; Initialize repeat count.
		lda	#$80			; Initialize mouse detection.
.detect_loop:	phy
		pha
		bsr	.read_devices		; Read all devices as if mice.
		pla
		clx
.detect_port:	ldy	mouse_y, x		; A movement of zero means
		bne	.detect_next		; this port is a mouse.
		ora	bit_mask, x
.detect_next:	inx				; Get the next pad from the
		cpx	#MAX_PADS		; multitap.
		bne	.detect_port
		ply				; Repeat the detection test.
		dey
		bne	.detect_loop

	.if	DETECT_PHANTOMS
		cmp	#(1 << MAX_PADS) + 127	; If we find a mouse in every
		bne	.detect_done		; port, then assume mirrored!
		lda	#1			; Report a single mouse in a
		sta	num_ports		; single port.
		lda	#$81
	.endif

.detect_done:	sta	mouse_flg		; Report mouse detection.
		bra	.calc_pressed

		;
		; Read all of the devices attached to the MultiTap.
		;

.read_devices:	ldx	#6			; Repeat this loop 4 times.

.read_multitap:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT
		lda	#$03			; CLR hi, SEL hi, reset tap.
		sta	IO_PORT
		cly				; Start at port 1.

.read_port:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT			; Wait 1.25us (9 cycles).

		lda	bit_mask, y		; Is there a mouse attached?
		and	mouse_flg
		bne	.read_mouse

.read_pad:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		beq	.next_port		; 6-btn pad if UDLR all held.

.read_2button:	sta	joynow, y		; Get buttons of 2-btn pad.
		lda	IO_PORT
		and	#$0F
		ora	joynow, y
		eor	#$FF
		sta	joynow, y

.next_port:	iny				; Get the next pad from the
		cpy	num_ports		; multitap.
		bcc	.read_port

		dex				; Do the next complete pass.
		dex
		bpl	.read_multitap		; Have we finished 4 passes?
		rts				; Now that everything is read.

.read_mouse:	jmp	[.mouse_vectors, x]	; Which mouse info is next?

		;
		; Mouse processing, split into four passes.
		;

.mouse_x_hi:	lda	#28			; 189 cycle delay after CLR lo
.wait_loop:	dec	a			; on port to allow the mouse
		bne	.wait_loop		; to buffer and reset counters.

		lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		sta	mouse_x, y		; Save port's X-hi nibble.

		lda	IO_PORT			; Get mouse buttons.
		and	#$0F
		eor	#$0F
		sta	joynow, y
		bra	.next_port

.mouse_x_lo:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		and	#$0F			; Wait 1.25us (9 cycles).
		ora	mouse_x, y		; Add port's X-hi nibble.
		eor	#$FF			; Negate so LEFT is -ve.
		inc	a
		sta	mouse_x, y
		bra	.next_port

.mouse_y_hi:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		sta	mouse_y, y		; Save port's Y-hi nibble.
		bra	.next_port

.mouse_y_lo:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		and	#$0F			; Wait 1.25us (9 cycles).
		ora	mouse_y, y		; Add port's Y-hi nibble.
		eor	#$FF			; Negate so UP is -ve.
		inc	a
		sta	mouse_y, y
		bra	.next_port

.mouse_vectors: dw	.mouse_y_lo		; Pass 4
		dw	.mouse_y_hi		; Pass 3
		dw	.mouse_x_lo		; Pass 2
		dw	.mouse_x_hi		; Pass 1

	.if	(* >= $4000)			; This is a ".proc" if it is
		.endp                           ; not running in RAM.
		.bss				; Put the variables in RAM.
	.endif

port_mutex:	ds	1			; NZ when controller port busy.
num_ports:	ds	1			; Set to 1 if no multitap.
mouse_flg:	ds	1			; Which ports are mice?
	.if	HUC_JOY_EVENTS
joybuf:		ds	MAX_PADS
	.endif
mouse_x:	ds	MAX_PADS
mouse_y:	ds	MAX_PADS

		.code

	.endif	SUPPORT_6BUTTON			; With mouse!

	.else	SUPPORT_MOUSE



	.if	SUPPORT_6BUTTON			; Without mouse!

; ***************************************************************************
; ***************************************************************************
;
; read_joypads - full 6-button pad support, but mouse movement is ignored.
;
; This code distinguishes between a mouse and a 2-button or 6-button joypad,
; so that unsupported devices do not have to be unplugged from the MultiTap.
;
; The code loops two times to get both sets of buttons on a 6-button joypad.
;
; N.B. Takes approx 1/3 frame to detect mice the first time it is run.
;
; bit values for joypad 2-button bytes: (MSB = #7; LSB = #0)
; ----------------------------------------------------------
; bit 0 (ie $01) = I
; bit 1 (ie $02) = II
; bit 2 (ie $04) = SELECT
; bit 3 (ie $08) = RUN
; bit 4 (ie $10) = UP
; bit 5 (ie $20) = RIGHT
; bit 6 (ie $40) = DOWN
; bit 7 (ie $80) = LEFT
;
; bit values for joypad 6-button bytes: (MSB = #7; LSB = #0)
; ----------------------------------------------------------
; bit 0 (ie $01) = III
; bit 1 (ie $02) = IV
; bit 2 (ie $04) = V
; bit 3 (ie $08) = VI
; bit 4 (ie $10) = zero
; bit 5 (ie $20) = zero
; bit 6 (ie $40) = zero
; bit 7 (ie $80) = zero, but set to one if 6-button pad detected.
;

		.code

	.if	(* >= $4000)			; Make this a ".proc" if it
read_joypads	.proc                           ; not running in RAM.
	.else
read_joypads:
	.endif

		lda	#$80			; Acquire port mutex to avoid
		tsb	port_mutex		; conflict with a delayed VBL
		bmi	.exit			; or access to an MB128.

		tii	joynow,joyold,MAX_PADS	; Save the previous values.
		tii	joy6now,joy6old,MAX_PADS

		; Reset the 6-btn bits, the user might change the joypad mode!

		tai	const_0000, joy6now, MAX_PADS

		; Detect attached mice the first time this routine is called.

		lda	mouse_flg		; Has mouse detection happened?
		bmi	.calc_pressed

		lda	#MAX_PADS		; Reset number of pads to read.
		sta	num_ports

		lda	#%00011111		; Try reading everything as a
		sta	mouse_flg		; mouse.

		ldy	#23			; Initialize repeat count.
		lda	#$80			; Initialize mouse detection.
.detect_loop:	phy
		pha
		bsr	.read_devices		; Read all devices as if mice.
		pla
		clx
.detect_port:	ldy	mouse_x, x		; A movement of zero means
		bne	.detect_next		; this port is a mouse.
		ora	bit_mask, x
.detect_next:	inx				; Get the next pad from the
		cpx	#MAX_PADS		; multitap.
		bne	.detect_port
		ply				; Repeat the detection test.
		dey
		bne	.detect_loop

;	.if	DETECT_PHANTOMS
;		cmp	#(1 << MAX_PADS) + 127	; If we find a mouse in every
;		bne	.detect_done		; port, then assume mirrored!
;		lda	#1			; Report a single mouse in a
;		sta	num_ports		; single port.
;		lda	#$81
;	.endif

.detect_done:	sta	mouse_flg		; Report mouse detection.

		; See what has just been pressed, and check for soft-reset.

.calc_pressed:	bsr	.read_devices		; Read all devices normally.

		ldx	#MAX_PADS - 1

.pressed_loop:	lda	joy6now, x		; Calc which buttons have just
		eor	joy6old, x		; been pressed (6-button).
		and	joy6now, x
	.if	HUC_JOY_EVENTS
		sta	joy6trg, y
		ora	joy6buf, y		; HuC/HuCC accumulates presses
		sta	joy6buf, y		; in a seperate array.
	.else
	.if	ACCUMULATE_JOY
		ora	joy6trg, y
	.endif
		sta	joy6trg, y
	.endif

		lda	joynow, x		; Calc which buttons have just
		tay                             ; been pressed (2-button).
		eor	joyold, x
		and	joynow, x
	.if	HUC_JOY_EVENTS
		sta	joytrg, y
		ora	joybuf, y		; HuC/HuCC accumulates presses
		sta	joybuf, y		; in a seperate array.
	.else
	.if	ACCUMULATE_JOY
		ora	joytrg, y
	.endif
		sta	joytrg, y
	.endif

		cmp	#$04			; Detect the soft-reset combo,
		bne	.not_reset		; hold RUN then press SELECT.
		cpy	#$0C
		bne	.not_reset
		lda	bit_mask, x
		bit	joyena
		bne	.soft_reset

.not_reset:	dex				; Check the next pad from the
		bpl	.pressed_loop		; multitap.

		stz	port_mutex		; Release port mutex.

	.if	(* >= $4000)			; This is a ".proc" if it is
.exit:		leave                           ; not running in RAM.
	.else
.exit:		rts				; All done, phew!
	.endif

.soft_reset:	sei				; Disable interrupts.
		stz	port_mutex		; Release port mutex.
		jmp	[reset_hook]		; Jump to the soft-reset hook.

		; Read all of the devices attached to the MultiTap.

.read_devices:	ldx	#2			; Repeat this loop 2 times.

.read_multitap:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT
		lda	#$03			; CLR hi, SEL hi, reset tap.
		sta	IO_PORT
		cly				; Start at port 1.

.read_port:	lda	#$01			; CLR lo, SEL hi for d-pad.
		sta	IO_PORT			; Wait 1.25us (9 cycles).

		lda	bit_mask, y		; Is there a mouse attached?
		and	mouse_flg
		bne	.read_mouse

.read_pad:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		beq	.read_6button		; 6-btn pad if UDLR all held.

.read_2button:	sta	joynow, y		; Get buttons of 2-btn pad.
		lda	IO_PORT
		and	#$0F
		ora	joynow, y
		eor	#$FF
		sta	joynow, y

.next_port:	iny				; Get the next pad from the
		cpy	num_ports		; multitap.
		bcc	.read_port

		dex				; Do the next complete pass.
		dex
		bpl	.read_multitap		; Have we finished 2 passes?
		rts				; Now that everything is read.

.read_6button:	lda	IO_PORT			; Get buttons of 6-btn pad.
		and	#$0F
		eor	#$8F			; Set bit-7 to show that a
		sta	joy6now, y		; 6-button pad is present.
		bra	.next_port

.read_mouse:	jmp	[.mouse_vectors, x]	; Which mouse info is next?

		; Mouse processing, normally four passes, here just two.

.mouse_x_hi:	lda	#28			; 189 cycle delay after CLR lo
.wait_loop:	dec	a			; on port to allow the mouse
		bne	.wait_loop		; to buffer and reset counters.

		lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		asl	a			; Wait 1.25us (9 cycles).
		asl	a
		asl	a
		asl	a
		sta	mouse_x, y		; Save port's X-hi nibble.

		lda	IO_PORT			; Get mouse buttons.
		and	#$0F
		eor	#$0F
		sta	joynow, y
		bra	.next_port

.mouse_x_lo:	lda	IO_PORT			; Read direction-pad bits.
		stz	IO_PORT			; CLR lo, SEL lo for buttons.
		and	#$0F			; Wait 1.25us (9 cycles).
		ora	mouse_x, y		; Add port's X-hi nibble.
;		eor	#$FF			; Negate so LEFT is -ve.
;		inc	a
		sta	mouse_x, y
		bra	.next_port

.mouse_vectors: dw	.mouse_x_lo		; Pass 2
		dw	.mouse_x_hi		; Pass 1

	.if	(* >= $4000)			; This is a ".proc" if it is
		.endp                           ; not running in RAM.
		.bss				; Put the variables in RAM.
	.endif

port_mutex:	ds	1			; NZ when controller port busy.
num_ports:	ds	1			; Set to 1 if no multitap.
mouse_flg:	ds	1			; Which ports are mice?
	.if	HUC_JOY_EVENTS
joybuf:		ds	MAX_PADS
joy6buf:	ds	MAX_PADS
	.endif
joy6now:	ds	MAX_PADS
joy6old:	ds	MAX_PADS
joy6trg:	ds	MAX_PADS
mouse_x:	ds	MAX_PADS

		.code

	.endif	SUPPORT_6BUTTON			; Without mouse!

	.endif	SUPPORT_MOUSE
