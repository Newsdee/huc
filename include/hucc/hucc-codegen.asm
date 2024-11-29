; ***************************************************************************
; ***************************************************************************
;
; hucc-codegen.asm
;
; The HuCC compiler translates C code into these macros, it does not directly
; generate HuC6280 instructions.
;
; Based on the original HuC macros created by David Michel and the other HuC
; developers, later modified and improved by Ulrich Hecht.
;
; Modifications copyright John Brandwood 2024.
;
; Distributed under the Boost Software License, Version 1.0.
; (See accompanying file LICENSE_1_0.txt or copy at
;  http://www.boost.org/LICENSE_1_0.txt)
;
; ***************************************************************************
; ***************************************************************************
;
; NAMING SCHEME FOR HuCC MACROS ...
;
;   __function.parameters
;
; {parameters} is a list of alphanumeric specifiers, starting with {size} and
; followed by {where}, followed by {index} if an array, then optional {value}
; and finally ending with optional {suffix}
;
; {size}
;   w : 16-bit signed int (default "int" in HuCC)
;   c : 16-bit unsigned int (a "cardinal" in Pascal terms)
;   b :  8-bit signed char
;   u :  8-bit unsigned char (default "char" in HuCC)
;
; {where} or {index}
;   r : HuCC primary register, made up of the Y:A cpu registers
;   t : top of arithmetic stack
;   p : indirect pointer, usually [__ptr]
;   i : immediate value, i.e. a decimal number
;   m : memory, i.e. C global, static, and "-fno-recursive" variables
;   s : stack, i.e. C function parameters and locals (not "-fno-recursive")
;   a : array, i.e. C global, static, "-fno-recursive" arrays <= 256 bytes
;   x : array index already in the X register
;   y : array index already in the Y register
;
; {value} OPTIONAL
;   i : immediate value, i.e. a decimal number
;   z : zero value
;
; {suffix} OPTIONAL
;   q : quick, used for optimized math on only 8-bit values, because all math
;       is normally promoted to "int" size in C; and when optimized stores do
;       not need to preserve the primary register contents
;
; ***************************************************************************
; ***************************************************************************



; ***************************************************************************
; ***************************************************************************
; i-code that retires the primary register contents
; ***************************************************************************
; ***************************************************************************

; **************
; this only exists to mark the end of a C statement when the primary register
; contents are no longer needed

__fence		.macro
		.endm



; ***************************************************************************
; ***************************************************************************
; i-code that declares a byte sized primary register
; ***************************************************************************
; ***************************************************************************

; **************
; this exists to mark that the primary register only needs byte accuracy

__short		.macro
		.endm



; ***************************************************************************
; ***************************************************************************
; i-codes for handling farptr
; ***************************************************************************
; ***************************************************************************

;	/* far pointer support funcs */
;	"fastcall farpeekb(farptr __fbank:__fptr)",
;	"fastcall farpeekw(farptr __fbank:__fptr)",
;	"fastcall farmemget(word __bx, farptr __fbank:__fptr, word acc)",
;	/* asm-lib wrappers */

;	case I_FARPTR_I:
;		ot("__farptr_i\t");
;		outsymbol((char *)data);
;		outstr(",");
;		outstr(tmp->arg[0]);
;		outstr(",");
;		outstr(tmp->arg[1]);
;		nl();
;		break;

;	case I_FARPTR_GET:
;		ot("__farptr_get\t");
;		outstr(tmp->arg[0]);
;		outstr(",");
;		outstr(tmp->arg[1]);
;		nl();
;		break;

;	case I_FGETB:
;		ot("__farptr_i\t");
;		outsymbol((char *)data);
;		nl();
;		ol("__fgetb");
;		break;

;	case I_FGETUB:
;		ot("__farptr_i\t");
;		outsymbol((char *)data);
;		nl();
;		ol("__fgetub");
;		break;

;	case I_FGETW:
;		ot("__farptr_i\t");
;		outsymbol((char *)data);
;		nl();
;		ol("  jsr\t_farpeekw.fast");
;		break;

; **************
; __farptr
; this is used for __far parameters to a __fastcall

__farptr	.macro
		lda.l	#$6000 + ($1FFF & (\1))
		sta.l	\3
		lda.h	#$6000 + ($1FFF & (\1))
		sta.h	\3
		lda	#bank(\1)
		sta	\2
		.endm

; **************
; adds 16-bit unsigned offset in Y:A to data address in \1
; if 1-param then Y=bank, __fptr=addr, used for farpeekb() and farpeekw()
; if 3-param then \2=bank, \3=addr

__farptr_i	.macro
	.if	(\# = 3)
		clc
		adc.l	#(\1) & $1FFF
		sta.l	\3
		tya
		adc.h	#(\1) & $1FFF
		tay
		and	#$1F
		ora	#$60
		sta.h	\3
		tya
		ror	a
		lsr	a
		lsr	a
		lsr	a
		lsr	a
		clc
		adc	#bank(\1)
		sta	\2
	.else
		clc
		adc.l	#(\1) & $1FFF
		sta.l	<__fptr
		tya
		adc.h	#(\1) & $1FFF
		tay
		and	#$1F
		ora	#$60
		sta.h	<__fptr
		tya
		ror	a
		lsr	a
		lsr	a
		lsr	a
		lsr	a
		clc
		adc	#bank(\1)
		tay
	.endif
		.endm

; **************
; JCB: I don't know what this is supposed to do!

	.if	0
__farptr_get	.macro
		sta	<\1
		ldy	#2
		lda	[__ptr], y
		sta.l	<\2
		iny
		lda	[__ptr], y
		sta.h	<\2
		.endm
	.endif

; **************
; only executed immediately after a 1-parameter __farptr_i!
; expects Y=bank, __fptr=addr
; N.B. Preserves MPR3 unlike original HuC code.
; **************
; unsigned int __fastcall __xsafe farpeekw( void far *base<__fbank:__fptr> );
; **************
; _farpeekw.fast is called by HuCC after executing __farptr_i macro.

_farpeekw.1:	ldy	<__fbank
_farpeekw.fast:	tma3
		pha
		tya
		tam3
		lda	[__fptr]
		say
		inc.l	<__fptr
		bne	!+
		inc.h	<__fptr
		bpl	!+
		inc	a
		tam3
		lda	#$60
		sta.h	<__fptr
!:		lda	[__fptr]
		sta	<__temp
		pla
		tam3
		tya
		ldy	<__temp
		rts

; **************
; only executed immediately after a 1-parameter __farptr_i!
; expects Y=bank, __fptr=addr
; N.B. Preserves MPR3 unlike original HuC code.

__fgetb		.macro
		tma3
		pha
		tya
		tam3
		lda	[__fptr]
		tay
		pla
		tam3
		tya
		cly
		bpl	!+
		dey
!:
		.endm

; **************
; only executed immediately after a 1-parameter __farptr_i!
; expects Y=bank, __fptr=addr
; N.B. Preserves MPR3 unlike original HuC code.

__fgetub	.macro
		tma3
		pha
		tya
		tam3
		lda	[__fptr]
		tay
		pla
		tam3
		tya
		cly
		.endm



; ***************************************************************************
; ***************************************************************************
; i-codes for calling functions
; ***************************************************************************
; ***************************************************************************

; **************
; the compiler can generate this to aid debugging C data-stack
; balance problems before/after a function call

__calling	.macro
		phx
		.endm

; **************
; the compiler can generate this to aid debugging C data-stack
; balance problems before/after a function call

__called	.macro
		stx	<__sp
		plx
		cpx	<__sp
!hang:		bne	!hang-
		.endm

; **************

__call		.macro
		call	\1
		.endm

; **************

__funcp.wr	.macro
		sta.l	__func
		sty.h	__func
		.endm

; **************

__callp		.macro
		jsr	call_indirect
		.endm

call_indirect:	jmp	[__func]



; ***************************************************************************
; ***************************************************************************
; i-codes for C functions and the C parameter stack
; ***************************************************************************
; ***************************************************************************

; **************
; function prolog

__enter		.macro
		.endm

; **************
; function epilog
; \1 == 0 if no return value

__return		.macro
	.if	(\1 != 0)
		sta	<__hucc_ret
	.endif
		jmp	leave_proc
		.endm

; **************
; get the acc lo-byte after returning from a function

__getacc	.macro
		lda	<__hucc_ret
		.endm

; **************
; main C data-stack for arguments/locals/expressions
; used when entering a #asm section that is not __xsafe

__savesp	.macro	; __STACK
		phx
		.endm

; **************
; main C data-stack for arguments/locals/expressions
; used when leaving a #asm section that is not __xsafe

__loadsp	.macro	; __STACK
		plx
		.endm

; **************
; main C data-stack for arguments/locals/expressions

__modsp		.macro
	.if (\1 < 0)

	.if (\1 == -2)
		dex
		dex
	.else
	.if (\1 == -4)
		dex
		dex
		dex
		dex
	.else
		sax
		clc
		adc.l	#\1
		sax
	.endif
	.endif
	.if	HUCC_DEBUG_SP
!overflow:	bmi	!overflow-
	.endif

	.else

	.if (\1 == 2)
		inx
		inx
	.else
	.if (\1 == 4)
		inx
		inx
		inx
		inx
	.else
		sax
		clc
		adc.l	#\1
		sax
	.endif
	.endif

	.endif
		.endm

; **************
; main C data-stack for arguments/locals/expressions
; this is used to adjust the stack in a C "goto"

__modsp_sym	.macro
		sax
		clc
		adc.l	#\1
		sax
		.endm

; **************
; main C data-stack for arguments/locals/expressions

__push.wr	.macro	; __STACK
		dex
		dex
	.if	HUCC_DEBUG_SP
!overflow:	bmi	!overflow-
	.endif
		sta.l	<__stack, x
		sty.h	<__stack, x
		.endm

; **************
; main C data-stack for arguments/locals/expressions

__pop.wr	.macro	; __STACK
		lda.l	<__stack, x
		ldy.h	<__stack, x
		inx
		inx
		.endm

; **************
; hardware-stack used for *temporary* storage of spilled arguments

__spush.wr	.macro
		phy
		pha
		.endm

; **************
; hardware-stack used for *temporary* storage of spilled arguments

__spop.wr	.macro
		pla
		ply
		.endm

; **************
; hardware-stack used for *temporary* storage of spilled arguments

__spush.ur	.macro
		pha
		.endm

; **************
; hardware-stack used for *temporary* storage of spilled arguments

__spop.ur	.macro
		pla
		.endm



; ***************************************************************************
; ***************************************************************************
; i-codes for handling boolean tests and branching
; ***************************************************************************
; ***************************************************************************

; **************
; Y:A is the value to check for.

__switch.wr	.macro
		sty.h	__temp
		ldy.l	#\1
		sty.l	__ptr
		ldy.h	#\1
		jmp	do_switchw
		.endm

; **************
; Y:A is the value to check for.

__switch.ur	.macro
		ldy.l	#\1
		sty.l	__ptr
		ldy.h	#\1
		jmp	do_switchb
		.endm

; **************
; the start of a "default" statement

__default	.macro
		plx
		.endm

; **************
; the start of a "case" statement

__case		.macro
		plx
		.endm

; **************
; the end of the previous "case" statement if it drops through
; turns next __case "plx" into an "ora"

__endcase	.macro
		db	$09
		.endm

; **************
; branch to the end of a statement or to a C label

__bra		.macro
		bra	\1
		.endm

; **************
; always preceeded by a __tst.wr before peephole optimization

__bfalse	.macro
		bcc	\1
		.endm

; **************
; always preceeded by a __tst.wr before peephole optimization

__btrue		.macro
		bcs	\1
		.endm

; **************
; boolean test, always followed by a __tst.wr or __not.wr before peephole optimization
; this MUST set the Z flag for the subsequent branches!

__cmp.wt	.macro
		jsr	\1
		.endm

; **************
; optimized boolean test
; C is true (1) if Y:A == integer-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__equ_w.wi	.macro
		cmp.l	#\1
		bne	!false+
		cpy.h	#\1
		beq	!+
!false:		clc
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if Y:A != integer-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__neq_w.wi	.macro
		sec
		eor.l	#\1
		bne	!+
		tya
		eor.h	#\1
		bne	!+
		clc
!:
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A < integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__slt_w.wi	.macro
		cmp.l	#\1		; Subtract integer from Y:A.
		tya
		sbc.h	#\1
		bvc	!+
		eor	#$80		; -ve if Y:A < integer (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A <= integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sle_w.wi	.macro
		clc			; Subtract integer+1 from Y:A.
		sbc.l	#\1
		tya
		sbc.h	#\1
		bvc	!+
		eor	#$80		; -ve if Y:A <= integer (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A > integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sgt_w.wi	.macro
		clc			; Subtract integer+1 from Y:A.
		sbc.l	#\1
		tya
		sbc.h	#\1
		bvc	!+
		eor	#$80		; +ve if Y:A > integer (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A >= integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sge_w.wi	.macro
		cmp.l	#\1		; Subtract integer from Y:A.
		tya
		sbc.h	#\1
		bvc	!+
		eor	#$80		; +ve if Y:A >= integer (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A < integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ult_w.wi	.macro
		cmp.l	#\1		; Subtract integer from Y:A.
		tya
		sbc.h	#\1		; CC if Y:A < integer.
		ror	a
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A <= integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ule_w.wi	.macro
		clc			; Subtract integer+1 from Y:A.
		sbc.l	#\1
		tya
		sbc.h	#\1		; CC if Y:A <= integer.
		ror	a
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A > integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ugt_w.wi	.macro
		clc			; Subtract integer+1 from Y:A.
		sbc.l	#\1
		tya
		sbc.h	#\1		; CS if Y:A > integer.
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A >= integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__uge_w.wi	.macro
		cmp.l	#\1		; Subtract integer from Y:A.
		tya
		sbc.h	#\1		; CS if Y:A >= integer.
		.endm

; **************
; optimized boolean test
; C is true (1) if A == integer-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__equ_b.uiq	.macro
		cmp	#\1
		beq	!+
		clc
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if A != integer-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__neq_b.uiq	.macro
		sec
		eor	#\1
		bne	!+
		clc
!:
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A < integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__slt_b.biq	.macro
		sec			; Subtract integer from A.
		sbc	#\1
		bvc	!+
		eor	#$80		; -ve if A < integer (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A <= integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sle_b.biq	.macro
		clc			; Subtract integer+1 from A.
		sbc	#\1
		bvc	!+
		eor	#$80		; -ve if A <= integer (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A > integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sgt_b.biq	.macro
		clc			; Subtract integer+1 from A.
		sbc.l	#\1
		bvc	!+
		eor	#$80		; +ve if A > integer (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A >= integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sge_b.biq	.macro
		sec			; Subtract integer from A.
		sbc	#\1
		bvc	!+
		eor	#$80		; +ve if A >= integer (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A < integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ult_b.uiq	.macro
		cmp	#\1		; Subtract integer from A.
		ror	a		; CC if A < integer.
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A <= integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ule_b.uiq	.macro
		clc			; Subtract integer+1 from A.
		sbc	#\1
		ror	a		; CC if A <= integer.
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A > integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ugt_b.uiq	.macro
		clc			; Subtract integer+1 from A.
		sbc	#\1		; CS if A > integer.
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A >= integer-value, else false (0)
; this MUST set the C flag for the susequent branches!

__uge_b.uiq	.macro
		cmp	#\1		; Subtract integer from A.
					; CS if A >= integer.
		.endm

; **************
; optimized boolean test
; C is true (1) if Y:A == memory-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__equ_w.wm	.macro
		cmp.l	\1
		bne	!false+
		cpy.h	\1
		beq	!+
!false:		clc
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if Y:A != memory-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__neq_w.wm	.macro
		sec
		eor.l	\1
		bne	!+
		tya
		eor.h	\1
		bne	!+
		clc
!:
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A < memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__slt_w.wm	.macro
		cmp.l	\1		; Subtract memory from Y:A.
		tya
		sbc.h	\1
		bvc	!+
		eor	#$80		; -ve if Y:A < memory (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A <= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sle_w.wm	.macro
		clc			; Subtract memory+1 from Y:A.
		sbc.l	\1
		tya
		sbc.h	\1
		bvc	!+
		eor	#$80		; -ve if Y:A <= memory (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A > memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sgt_w.wm	.macro
		clc			; Subtract memory+1 from Y:A.
		sbc.l	\1
		tya
		sbc.h	\1
		bvc	!+
		eor	#$80		; +ve if Y:A > memory (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A >= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sge_w.wm	.macro
		cmp.l	\1		; Subtract memory from Y:A.
		tya
		sbc.h	\1
		bvc	!+
		eor	#$80		; +ve if Y:A >= memory (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A < memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ult_w.wm	.macro
		cmp.l	\1		; Subtract memory from Y:A.
		tya
		sbc.h	\1		; CC if Y:A < memory.
		ror	a
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A <= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ule_w.wm	.macro
		clc			; Subtract memory+1 from Y:A.
		sbc.l	\1
		tya
		sbc.h	\1		; CC if Y:A <= memory.
		ror	a
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A > memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ugt_w.wm	.macro
		clc			; Subtract memory+1 from Y:A.
		sbc.l	\1
		tya
		sbc.h	\1		; CS if Y:A > memory.
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A >= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__uge_w.wm	.macro
		cmp.l	\1		; Subtract memory from Y:A.
		tya
		sbc.h	\1		; CS if Y:A >= memory.
		.endm

; **************
; optimized boolean test
; C is true (1) if A == memory-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__equ_b.umq	.macro
		cmp	\1
		beq	!+
		clc
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if A != memory-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__neq_b.umq	.macro
		sec
		eor	\1
		bne	!+
		clc
!:
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A < memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__slt_b.bmq	.macro
		sec			; Subtract memory from A.
		sbc	\1
		bvc	!+
		eor	#$80		; -ve if A < memory (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A <= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sle_b.bmq	.macro
		clc			; Subtract memory+1 from A.
		sbc	\1
		bvc	!+
		eor	#$80		; -ve if A <= memory (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A > memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sgt_b.bmq	.macro
		clc			; Subtract memory+1 from A.
		sbc.l	\1
		bvc	!+
		eor	#$80		; +ve if A > memory (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A >= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sge_b.bmq	.macro
		sec			; Subtract memory from A.
		sbc	\1
		bvc	!+
		eor	#$80		; +ve if A >= memory (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A < memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ult_b.umq	.macro
		cmp	\1		; Subtract memory from A.
		ror	a		; CC if A < memory.
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A <= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ule_b.umq	.macro
		clc			; Subtract memory+1 from A.
		sbc	\1
		ror	a		; CC if A <= memory.
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A > memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ugt_b.umq	.macro
		clc			; Subtract memory+1 from A.
		sbc	\1		; CS if A > memory.
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A >= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__uge_b.umq	.macro
		cmp	\1		; Subtract memory from A.
					; CS if A >= memory.
		.endm

; **************
; optimized boolean test
; C is true (1) if Y:A == memory-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__equ_w.ws	.macro
		cmp.l	<__stack + \1, x
		bne	!false+
		tya
		cmp.h	<__stack + \1, x
		beq	!+
!false:		clc
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if Y:A != memory-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__neq_w.ws	.macro
		sec
		eor.l	<__stack + \1, x
		bne	!+
		tya
		eor.h	<__stack + \1, x
		bne	!+
		clc
!:
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A < memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__slt_w.ws	.macro
		cmp.l	<__stack + \1, x; Subtract memory from Y:A.
		tya
		sbc.h	<__stack + \1, x
		bvc	!+
		eor	#$80		; -ve if Y:A < memory (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A <= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sle_w.ws	.macro
		clc			; Subtract memory+1 from Y:A.
		sbc.l	<__stack + \1, x
		tya
		sbc.h	<__stack + \1, x
		bvc	!+
		eor	#$80		; -ve if Y:A <= memory (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A > memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sgt_w.ws	.macro
		clc			; Subtract memory+1 from Y:A.
		sbc.l	<__stack + \1, x
		tya
		sbc.h	<__stack + \1, x
		bvc	!+
		eor	#$80		; +ve if Y:A > memory (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (signed word)
; C is true (1) if Y:A >= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sge_w.ws	.macro
		cmp.l	<__stack + \1, x; Subtract memory from Y:A.
		tya
		sbc.h	<__stack + \1, x
		bvc	!+
		eor	#$80		; +ve if Y:A >= memory (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A < memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ult_w.ws	.macro
		cmp.l	<__stack + \1, x; Subtract memory from Y:A.
		tya
		sbc.h	<__stack + \1, x; CC if Y:A < memory.
		ror	a
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A <= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ule_w.ws	.macro
		clc			; Subtract memory+1 from Y:A.
		sbc.l	<__stack + \1, x
		tya
		sbc.h	<__stack + \1, x; CC if Y:A <= memory.
		ror	a
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A > memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ugt_w.ws	.macro
		clc			; Subtract memory+1 from Y:A.
		sbc.l	<__stack + \1, x
		tya
		sbc.h	<__stack + \1, x; CS if Y:A > memory.
		.endm

; **************
; optimized boolean test (unsigned word)
; C is true (1) if Y:A >= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__uge_w.ws	.macro
		cmp.l	<__stack + \1, x; Subtract memory from Y:A.
		tya
		sbc.h	<__stack + \1, x; CS if Y:A >= memory.
		.endm

; **************
; optimized boolean test
; C is true (1) if A == memory-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__equ_b.usq	.macro
		cmp	<__stack + \1, x
		beq	!+
		clc
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if A != memory-value, else false (0)
; this MUST set the C flag for the subsequent branches!

__neq_b.usq	.macro
		sec
		eor	<__stack + \1, x
		bne	!+
		clc
!:
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A < memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__slt_b.bsq	.macro
		sec			; Subtract memory from A.
		sbc	<__stack + \1, x
		bvc	!+
		eor	#$80		; -ve if A < memory (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A <= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sle_b.bsq	.macro
		clc			; Subtract memory+1 from A.
		sbc	<__stack + \1, x
		bvc	!+
		eor	#$80		; -ve if A <= memory (signed).
!:		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A > memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sgt_b.bsq	.macro
		clc			; Subtract memory+1 from A.
		sbc.l	<__stack + \1, x
		bvc	!+
		eor	#$80		; +ve if A > memory (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (signed byte)
; C is true (1) if A >= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__sge_b.bsq	.macro
		sec			; Subtract memory from A.
		sbc	<__stack + \1, x
		bvc	!+
		eor	#$80		; +ve if A >= memory (signed).
!:		eor	#$80
		asl	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A < memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ult_b.usq	.macro
		cmp	<__stack + \1, x; Subtract memory from A.
		ror	a		; CC if A < memory.
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A <= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ule_b.usq	.macro
		clc			; Subtract memory+1 from A.
		sbc	<__stack + \1, x
		ror	a		; CC if A <= memory.
		eor	#$80
		rol	a
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A > memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__ugt_b.usq	.macro
		clc			; Subtract memory+1 from A.
		sbc	<__stack + \1, x; CS if A > memory.
		.endm

; **************
; optimized boolean test (unsigned byte)
; C is true (1) if A >= memory-value, else false (0)
; this MUST set the C flag for the susequent branches!

__uge_b.usq	.macro
		cmp	<__stack + \1, x; Subtract memory from A.
					; CS if A >= memory.
		.endm

; **************
; boolean test, optimized into __not.wr if used before a __tst.wr
; C is true (1) if Y:A == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.wr	.macro
		sty	__temp
		ora	__temp
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.wp	.macro
		ldy	#1
		lda	[\1], y
		ora	[\1]
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.wm	.macro
		lda.l	\1
		ora.h	\1
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.ws	.macro	; __STACK
		lda.l	<__stack + \1, x
		ora.h	<__stack + \1, x
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.war	.macro
		asl	a
		tay
		lda.l	\1, y
		ora.h	\1, y
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.up	.macro
		lda	[\1]
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.um	.macro
		lda	\1
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.us	.macro	; __STACK
		lda.l	<__stack + \1, x
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.uar	.macro
		tay
		lda	\1, y
		clc
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__not.uay	.macro
		lda	\1, y
		clc
		bne	!+
		sec
!:
		.endm

; **************
; boolean test, always output immediately before a __bfalse or __btrue
; C is true (1) if Y:A != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.wr	.macro
		sty	__temp
		ora	__temp
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.wp	.macro
		ldy	#1
		lda	[\1], y
		ora	[\1]
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.wm		.macro
		lda.l	\1
		ora.h	\1
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.ws	.macro	; __STACK
		lda.l	<__stack + \1, x
		ora.h	<__stack + \1, x
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.war	.macro
		asl	a
		tay
		lda.l	\1, y
		ora.h	\1, y
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.up	.macro
		lda	[\1]
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.um	.macro
		lda	\1
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.us	.macro	; __STACK
		lda.l	<__stack + \1, x
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.uar	.macro
		tay
		lda	\1, y
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if memory-value != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tst.uay	.macro
		lda	\1, y
		cmp	#1
		.endm

; **************
; optimized boolean test
; C is true (1) if (Y:A & integer) == 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__nand.wi	.macro
		clc
	.if	((\1 & $FF00) == 0)
		and	#\1
	.else
	.if	((\1 & $00FF) == 0)
		tya
		and.h	#\1
	.else
		and.l	#\1
		bne	!+
		tya
		and.h	#\1
	.endif
	.endif
		bne	!+
		sec
!:
		.endm

; **************
; optimized boolean test
; C is true (1) if (Y:A & integer) != 0, else false (0)
; this MUST set the C flag for the subsequent branches!

__tand.wi	.macro
	.if	((\1 & $FF00) == 0)
		and	#\1
	.else
	.if	((\1 & $00FF) == 0)
		tya
		and.h	#\1
	.else
		and.l	#\1
		bne	!+
		tya
		and.h	#\1
	.endif
	.endif
!:		cmp	#1
		.endm

; **************
; optimized boolean test
; invert C flag

__not.cf	.macro
		ror	a
		eor	#$80
		rol	a
		.endm

; **************
; convert comparison result C flag into a 16-bit Y:A boolean integer

__bool		.macro
		cla
		rol	a
		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if Y:A == 0, else false (0)

__boolnot.wr	.macro
		sty	__temp
		ora	__temp
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.wp	.macro
		ldy	#1
		lda	[\1], y
		ora	[\1]
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.wm	.macro
		lda.l	\1
		ora.h	\1
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.ws	.macro	; __STACK
		lda.l	<__stack + \1, x
		ora.h	<__stack + \1, x
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.war	.macro
		asl	a
		tay
		lda.l	\1, y
		ora.h	\1, y
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.up	.macro
		lda	[\1]
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.um	.macro
		lda	\1
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.us	.macro	; __STACK
		lda.l	<__stack + \1, x
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.uar	.macro
		tay
		lda	\1, y
		cla
		bne	!+
		inc	a
!:		cly
		.endm

; **************
; optimized boolean test used before a store, not a branch
; Y:A is true (1) if memory-value == 0, else false (0)

__boolnot.uay	.macro
		lda	\1, y
		cla
		bne	!+
		inc	a
!:		cly
		.endm



; ***************************************************************************
; ***************************************************************************
; i-codes for loading the primary register
; ***************************************************************************
; ***************************************************************************

; **************

__ld.wi		.macro
	.if	(\?1 != ARG_ABS)
		lda.l	#\1
		ldy.h	#\1
	.else
	.if	(\1 & $00FF)
		lda.l	#\1
	.else
		cla
	.endif
	.if	(\1 & $FF00)
		ldy.h	#\1
	.else
		cly
	.endif
	.endif
		.endm

; **************

__ld.uiq	.macro
	.if	(\?1 != ARG_ABS)
		lda.l	#\1
	.else
	.if	(\1 & $00FF)
		lda	#\1
	.else
		cla
	.endif
	.endif
		.endm

; **************

__lea.s		.macro	; __STACK
		txa
		clc
		adc.l	#__stack + (\1)
		ldy.h	#__stack
		.endm

; **************

__ld.wm		.macro
		lda.l	\1
		ldy.h	\1
		.endm

; **************

__ld.bm		.macro
		lda	\1
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__ld.um		.macro
		lda	\1
		cly
		.endm

; **************

__ld.wmq	.macro
		lda.l	\1
		.endm

; **************

__ld.bmq	.macro
		lda	\1
		.endm

; **************

__ld.umq	.macro
		lda	\1
		.endm

; **************

__ldy.wmq	.macro
		ldy.l	\1
		.endm

; **************

__ldy.bmq	.macro
		ldy	\1
		.endm

; **************

__ldy.umq	.macro
		ldy	\1
		.endm

; **************

__ld.wp		.macro
		ldy	#1
		lda	[\1], y
		tay
		lda	[\1]
		.endm

; **************

__ld.bp		.macro
		lda	[\1]
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__ld.up		.macro
		lda	[\1]
		cly
		.endm

; **************

__ld.war	.macro
		asl	a
		tay
		lda.h	\1, y
		pha
		lda.l	\1, y
		ply
		.endm

; **************

__ld.bar	.macro
		tay
		lda	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__ld.uar	.macro
		tay
		lda	\1, y
		cly
		.endm

; **************

__ld.bay	.macro
		lda	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__ld.uay	.macro
		lda	\1, y
		cly
		.endm

; **************

__ld.wam	.macro
		lda	\2
		asl	a
		tay
		lda.h	\1, y
		pha
		lda.l	\1, y
		ply
		.endm

; **************

__ld.bam	.macro
		ldy	\2
		lda	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__ld.uam	.macro
		ldy	\2
		lda	\1, y
		cly
		.endm

; **************
; special load for when array writes are optimized
; the cpu stack is balanced with an __st.wat

__ldp.war	.macro
		phx
		asl	a
		tay
		phy
		lda.h	\1, y
		pha
		lda.l	\1, y
		ply
		.endm

; **************
; special load for when array writes are optimized
; the cpu stack is balanced with an __st.uat

__ldp.bar	.macro
		phx
		tay
		phy
		lda	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************
; special load for when array writes are optimized
; the cpu stack is balanced with an __st.uat

__ldp.uar	.macro
		phx
		tay
		phy
		lda	\1, y
		cly
		.endm

; **************
; special load for when array writes are optimized
; the cpu stack is balanced with an __st.uat

__ldp.bay	.macro
		phx
		phy
		lda	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************
; special load for when array writes are optimized
; the cpu stack is balanced with an __st.uat

__ldp.uay	.macro
		phx
		phy
		lda	\1, y
		cly
		.endm

; **************

__ld.ws		.macro	; __STACK
		lda.l	<__stack + \1, x
		ldy.h	<__stack + \1, x
		.endm

; **************

__ld.bs		.macro	; __STACK
		lda	<__stack + \1, x
		cly
		bpl	!+	; signed
		dey
!:
		.endm

; **************

__ld.us		.macro	; __STACK
		lda	<__stack + \1, x
		cly
		.endm

; **************

__ld.wsq	.macro	; __STACK
		lda.l	<__stack + \1, x
		.endm

; **************

__ld.bsq	.macro	; __STACK
		lda	<__stack + \1, x
		.endm

; **************

__ld.usq	.macro	; __STACK
		lda	<__stack + \1, x
		.endm

; **************

__ldy.wsq	.macro	; __STACK
		ldy.l	<__stack + \1, x
		.endm

; **************

__ldy.bsq	.macro	; __STACK
		ldy	<__stack + \1, x
		.endm

; **************

__ldy.usq	.macro	; __STACK
		ldy	<__stack + \1, x
		.endm

	.if	0

; **************

__ldwa_s	.macro	; __STACK
		lda	<__stack + \2, x
		asl	a
		tay
		lda.h	\1, y
		pha
		lda.l	\1, y
		ply
		.endm

; **************

__ldba_s	.macro	; __STACK
		ldy	<__stack + \2, x
		lda	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__lduba_s	.macro	; __STACK
		ldy	<__stack + \2, x
		lda	\1, y
		cly
		.endm

	.endif



; ***************************************************************************
; ***************************************************************************
; i-codes for pre- and post- increment and decrement
; ***************************************************************************
; ***************************************************************************

; **************

__incld.wm	.macro
		inc.l	\1
		bne	!+
		inc.h	\1
!:		lda.l	\1
		ldy.h	\1
		.endm

; **************

__incld.bm	.macro
		inc	\1
		lda	\1
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__incld.um	.macro
		inc	\1
		lda	\1
		cly
		.endm

; **************

__decld.wm	.macro
		lda.l	\1
		bne	!+
		dec.h	\1
!:		dec	a
		sta.l	\1
		ldy.h	\1
		.endm

; **************

__decld.bm	.macro
		dec	\1
		lda	\1
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__decld.um	.macro
		dec	\1
		lda	\1
		cly
		.endm

; **************

__ldinc.wm	.macro
		lda.l	\1
		ldy.h	\1
		inc.l	\1
		bne	!+
		inc.h	\1
!:
		.endm

; **************

__ldinc.bm	.macro
		lda	\1
		cly
		bpl	!+
		dey
!:		inc	\1
		.endm

; **************

__ldinc.um	.macro
		lda	\1
		cly
		inc	\1
		.endm

; **************

__lddec.wm	.macro
		ldy.h	\1
		lda.l	\1
		bne	!+
		dec.h	\1
!:		dec.l	\1
		.endm

; **************

__lddec.bm	.macro
		lda	\1
		cly
		bpl	!+
		dey
!:		dec	\1
		.endm

; **************

__lddec.um	.macro
		lda	\1
		cly
		dec	\1
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__inc.wmq	.macro
		inc.l	\1
		bne	!+
		inc.h	\1
!:
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__inc.umq	.macro
		inc	\1
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__dec.wmq	.macro
		lda.l	\1
		bne	!+
		dec.h	\1
!:		dec.l	\1
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__dec.umq	.macro
		dec	\1
		.endm

; **************

__incld.ws	.macro
		inc.l	<__stack + \1, x
		bne	!+
		inc.h	<__stack + \1, x
!:		lda.l	<__stack + \1, x
		ldy.h	<__stack + \1, x
		.endm

; **************

__incld.bs	.macro
		inc	<__stack + \1, x
		lda	<__stack + \1, x
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__incld.us	.macro
		inc	<__stack + \1, x
		lda	<__stack + \1, x
		cly
		.endm

; **************

__decld.ws	.macro
		lda.l	<__stack + \1, x
		bne	!+
		dec.h	<__stack + \1, x
!:		dec	a
		sta.l	<__stack + \1, x
		ldy.h	<__stack + \1, x
		.endm

; **************

__decld.bs	.macro
		dec	<__stack + \1, x
		lda	<__stack + \1, x
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__decld.us	.macro
		dec	<__stack + \1, x
		lda	<__stack + \1, x
		cly
		.endm

; **************

__ldinc.ws	.macro
		lda.l	<__stack + \1, x
		ldy.h	<__stack + \1, x
		inc.l	<__stack + \1, x
		bne	!+
		inc.h	<__stack + \1, x
!:
		.endm

; **************

__ldinc.bs	.macro
		lda	<__stack + \1, x
		cly
		bpl	!+
		dey
!:		inc	<__stack + \1, x
		.endm

; **************

__ldinc.us	.macro
		lda	<__stack + \1, x
		cly
		inc	<__stack + \1, x
		.endm

; **************

__lddec.ws	.macro
		ldy.h	<__stack + \1, x
		lda.l	<__stack + \1, x
		bne	!+
		dec.h	<__stack + \1, x
!:		dec.l	<__stack + \1, x
		.endm

; **************

__lddec.bs	.macro
		lda	<__stack + \1, x
		cly
		bpl	!+
		dey
!:		dec	<__stack + \1, x
		.endm

; **************

__lddec.us	.macro
		lda	<__stack + \1, x
		cly
		dec	<__stack + \1, x
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__inc.wsq	.macro
		inc.l	<__stack + \1, x
		bne	!+
		inc.h	<__stack + \1, x
!:
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__inc.usq	.macro
		inc	<__stack + \1, x
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__dec.wsq	.macro
		lda.l	<__stack + \1, x
		bne	!+
		dec.h	<__stack + \1, x
!:		dec.l	<__stack + \1, x
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__dec.usq	.macro
		dec	<__stack + \1, x
		.endm

; **************

__incld.war	.macro
		phx
		asl	a
		tax
		inc.l	\1, x
		bne	!+
		inc.h	\1, x
!:		lda.l	\1, x
		ldy.h	\1, x
		plx
		.endm

; **************

__ldinc.war	.macro
		phx
		asl	a
		tax
		lda.l	\1, x
		ldy.h	\1, x
		inc.l	\1, x
		bne	!+
		inc.h	\1, x
!:		plx
		.endm

; **************

__decld.war	.macro
		phx
		asl	a
		tax
		lda.l	\1, x
		bne	!+
		dec.h	\1, x
!:		dec	a
		sta.l	\1, x
		ldy.h	\1, x
		plx
		.endm

; **************

__lddec.war	.macro
		phx
		asl	a
		tax
		ldy.h	\1, x
		lda.l	\1, x
		bne	!+
		dec.h	\1, x
!:		dec.l	\1, x
		plx
		.endm

; **************

__incld.bar	.macro
		tay
		lda	\1, y
		inc	a
		sta	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__incld.uar	.macro
		tay
		lda	\1, y
		inc	a
		sta	\1, y
		cly
		.endm

; **************

__ldinc.bar	.macro
		tay
		lda.l	\1, y
		inc	a
		sta.l	\1, y
		dec	a
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__ldinc.uar	.macro
		tay
		lda.l	\1, y
		inc	a
		sta.l	\1, y
		dec	a
		cly
		.endm

; **************

__decld.bar	.macro
		tay
		lda	\1, y
		dec	a
		sta	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__decld.uar	.macro
		tay
		lda	\1, y
		dec	a
		sta	\1, y
		cly
		.endm

; **************

__lddec.bar	.macro
		tay
		lda.l	\1, y
		dec	a
		sta.l	\1, y
		inc	a
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__lddec.uar	.macro
		tay
		lda.l	\1, y
		dec	a
		sta.l	\1, y
		inc	a
		cly
		.endm

; **************

__incld.bay	.macro
		lda	\1, y
		inc	a
		sta	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__incld.uay	.macro
		lda	\1, y
		inc	a
		sta	\1, y
		cly
		.endm

; **************

__ldinc.bay	.macro
		lda.l	\1, y
		inc	a
		sta.l	\1, y
		dec	a
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__ldinc.uay	.macro
		lda.l	\1, y
		inc	a
		sta.l	\1, y
		dec	a
		cly
		.endm

; **************

__decld.bay	.macro
		lda	\1, y
		dec	a
		sta	\1, y
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__decld.uay	.macro
		lda	\1, y
		dec	a
		sta	\1, y
		cly
		.endm

; **************

__lddec.bay	.macro
		lda.l	\1, y
		dec	a
		sta.l	\1, y
		inc	a
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__lddec.uay	.macro
		lda.l	\1, y
		dec	a
		sta.l	\1, y
		inc	a
		cly
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__inc.warq	.macro
		asl	a
		sax
		inc.l	\1, x
		bne	!+
		inc.h	\1, x
!:		tax
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__inc.uarq	.macro
		sax
		inc	\1, x
		tax
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__inc.uayq	.macro
		sxy
		inc	\1, x
		sxy
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__dec.warq	.macro
		asl	a
		sax
		ldy.l	\1, x
		bne	!+
		dec.h	\1, x
!:		dec.l	\1, x
		tax
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__dec.uarq	.macro
		sax
		dec	\1, x
		tax
		.endm

; **************
; optimized macro used when the value isn't needed in the primary register

__dec.uayq	.macro
		sxy
		dec	\1, x
		sxy
		.endm



; ***************************************************************************
; ***************************************************************************
; i-codes for saving the primary register
; ***************************************************************************
; ***************************************************************************

; **************

__st.wmiq	.macro
	.if	(\?1 != ARG_ABS)
		lda.l	#\1
		sta.l	\2
		lda.h	#\1
		sta.h	\2
	.else
	.if	(\1 & $00FF)
		lda.l	#\1
		sta.l	\2
	.else
		stz.l	\2
	.endif
	.if	(\1 & $FF00)
		lda.h	#\1
		sta.h	\2
	.else
		stz.h	\2
	.endif
	.endif
		.endm

; **************

__st.umiq	.macro
	.if	(\1 != 0)
		lda.l	#\1
		sta	\2
	.else
		stz	\2
	.endif
		.endm

; **************

__st.wpi	.macro
		sta.l	__ptr
		sty.h	__ptr
		ldy	#1
		lda.h	#\1
		sta	[__ptr], y
		tay
		lda.l	#\1
		sta	[__ptr]
		.endm

; **************

__st.upi	.macro
		sta.l	__ptr
		sty.h	__ptr
		lda.l	#\1
		ldy.h	#\1
		sta	[__ptr]
		.endm

; **************

__st.wm		.macro
		sta.l	\1
		sty.h	\1
		.endm

; **************

__st.um		.macro
		sta	\1
		.endm

; **************

__st.wp		.macro
		sta	[\1]
		pha
		tya
		ldy	#1
		sta	[\1], y
		tay
		pla
		.endm

; **************

__st.up		.macro
		sta	[\1]
		.endm

; **************

__st.wpt	.macro	; __STACK
		sta	[__stack, x]
		inc.l	<__stack, x
		bne	!+
		inc.h	<__stack, x
!:		say
		sta	[__stack, x]
		say
		inx
		inx
		.endm

; **************

__st.upt	.macro	; __STACK
		sta	[__stack, x]
		inx
		inx
		.endm

; **************
; special store for when array writes are optimized
; the cpu stack is balanced with an __st.wat

__index.wr	.macro
		phx
		asl	a
		pha
		.endm

; **************
; special store for when array writes are optimized
; the cpu stack is balanced with an __st.uat

__index.ur	.macro
		phx
		pha
		.endm

; **************
; special store for when array writes are optimized
; this balances the cpu stack after an __index.wr or __ldp.war

__st.wat	.macro
		plx
		sta.l	\1, x
		say
		sta.h	\1, x
		say
		plx
		.endm

; **************
; special store for when array writes are optimized
; this balances the cpu stack after an __index.ur or __ldp.uar

__st.uat	.macro
		plx
		sta	\1, x
		plx
		.endm

; **************

__st.wsiq	.macro
	.if	(\?1 != ARG_ABS)
		lda.l	#\1
		sta.l	<__stack + \2, x
		lda.h	#\1
		sta.h	<__stack + \2, x
	.else
	.if	(\1 & $00FF)
		lda.l	#\1
		sta.l	<__stack + \2, x
	.else
		stz.l	<__stack + \2, x
	.endif
	.if	(\1 & $FF00)
		lda.h	#\1
		sta.h	<__stack + \2, x
	.else
		stz.h	<__stack + \2, x
	.endif
	.endif
		.endm

; **************

__st.usiq	.macro
	.if	(\1 != 0)
		lda.l	#\1
		sta	<__stack + \2, x
	.else
		stz	<__stack + \2, x
	.endif
		.endm

; **************

__st.ws		.macro	; __STACK
		sta.l	<__stack + \1, x
		sty.h	<__stack + \1, x
		.endm

; **************

__st.us		.macro	; __STACK
		sta	<__stack + \1, x
		.endm

; **************

__st.was	.macro	; __STACK
		phy
		pha
		lda	<__stack + \2, x
		asl	a
		say
		sta.h	\1, y
		pla
		sta.l	\1, y
		ply
		.endm

; **************

__st.uas	.macro	; __STACK
		phy
		ldy	<__stack + \2, x
		sta	\1, y
		ply
		.endm



; ***************************************************************************
; ***************************************************************************
; i-codes for extending the primary register
; ***************************************************************************
; ***************************************************************************

; **************

__ext.br	.macro
		tay
		cly
		bpl	!+
		dey
!:
		.endm

; **************

__ext.ur	.macro
		cly
		.endm



; ***************************************************************************
; ***************************************************************************
; i-codes for math with the primary register
; ***************************************************************************
; ***************************************************************************

; **************

__com.wr	.macro
		eor	#$FF
		say
		eor	#$FF
		say
		.endm

; **************

__neg.wr	.macro
		sec
		eor	#$FF
		adc	#0
		say
		eor	#$FF
		adc	#0
		say
		.endm

; **************

__add.wt	.macro	; __STACK
		clc
		adc.l	<__stack, x
		say
		adc.h	<__stack, x
		say
		inx
		inx
		.endm

; **************

__add.wi	.macro
	.if	((\?1 == ARG_ABS) && ((\1) == 1))
		inc	a
		bne	!+
		iny
!:
	.else
	.if	((\?1 == ARG_ABS) && ((\1) >= 0) && ((\1) < 256))
		clc
		adc.l	#\1
		bcc	!+
		iny
!:
	.else
		clc
		adc.l	#\1
		say
		adc.h	#\1
		say
	.endif
	.endif
		.endm

; **************

__add.wm	.macro
		clc
		adc.l	\1
		say
		adc.h	\1
		say
		.endm

; **************

__add.um	.macro
		clc
		adc	\1
		bcc	!+
		iny
!:
		.endm

; **************

__add.ws	.macro	; __STACK
		clc
		adc.l	<__stack + \1, x
		say
		adc.h	<__stack + \1, x
		say
		.endm

; **************

__add.us	.macro	; __STACK
		clc
		adc	<__stack + \1, x
		bcc	!+
		iny
!:
		.endm

; **************

__sub.wt	.macro	; __STACK
		sec
		eor	#$FF
		adc.l	<__stack, x
		say
		eor	#$FF
		adc.h	<__stack, x
		say
		inx
		inx
		.endm

; **************

__sub.wi	.macro
	.if	((\?1 == ARG_ABS) && ((\1) >= 0) && ((\1) < 256))
		sec
		sbc.l	#\1
		bcs	!+
		dey
!:
	.else
		sec
		sbc.l	#\1
		say
		sbc.h	#\1
		say
	.endif
		.endm

; **************

__sub.wm	.macro
		sec
		sbc.l	\1
		say
		sbc.h	\1
		say
		.endm

; **************

__sub.um	.macro
		sec
		sbc	\1
		bcs	!+
		dey
!:
		.endm

; **************

__isub.wi	.macro	; __STACK
		sec
		eor	#$FF
		adc.l	#\1
		say
		eor	#$FF
		adc.h	#\1
		say
		.endm

; **************

__and.wt	.macro	; __STACK
		and.l	<__stack, x
		say
		and.h	<__stack, x
		say
		inx
		inx
		.endm

; **************

__and.wi	.macro
	.if	(\?1 != ARG_ABS)
		and.l	#\1
		say
		and.h	#\1
		say
	.else
	.if	((\1 >= 0) && (\1 < 256))
		and	#\1
		cly
	.else
	.if	(\1 & 255)
		and.l	#\1
		say
		and.h	#\1
		say
	.else
		tya
		and.h	#\1
		tay
		cla
	.endif
	.endif
	.endif
		.endm

; **************

__and.uiq	.macro
		and	#\1
		.endm

; **************

__and.wm	.macro
		and.l	\1
		say
		and.h	\1
		say
		.endm

; **************

__and.um	.macro
		and	\1
		cly
		.endm

; **************

__eor.wt	.macro	; __STACK
		eor.l	<__stack, x
		say
		eor.h	<__stack, x
		say
		inx
		inx
		.endm

; **************

__eor.wi	.macro
	.if	((\1 >= 0) && (\1 < 256))
		eor	#\1
	.else
	.if	(\1 & 255)
		eor.l	#\1
		say
		eor.h	#\1
		say
	.else
		say
		eor.h	#\1
		say
	.endif
	.endif
		.endm

; **************

__eor.wm	.macro
		eor.l	\1
		say
		eor.h	\1
		say
		.endm

; **************

__eor.um	.macro
		eor	\1
		.endm

; **************

__or.wt		.macro	; __STACK
		ora.l	<__stack, x
		say
		ora.h	<__stack, x
		say
		inx
		inx
		.endm

; **************

__or.wi		.macro
	.if	((\1 >= 0) && (\1 < 256))
		ora	#\1
	.else
	.if	(\1 & 255)
		ora.l	#\1
		say
		ora.h	#\1
		say
	.else
		say
		ora.h	#\1
		say
	.endif
	.endif
		.endm

; **************

__or.wm		.macro
		ora.l	\1
		say
		ora.h	\1
		say
		.endm

; **************

__or.um		.macro
		ora	\1
		.endm

; **************
; N.B. Used when calculating a pointer into a word array.

__double	.macro
		asl.l	<__stack, x
		rol.h	<__stack, x
		.endm

; **************

__asl.wt	.macro
		jsr	aslw
		.endm

; **************

__asl.wi	.macro
	.if (\1 = 1)
		asl	a
		say
		rol	a
		say
	.else
	.if (\1 = 2)
		asl	a
		say
		rol	a
		say
		asl	a
		say
		rol	a
		say
	.else
	.if (\1 < 5)
		sty	__temp
		jsr	aslw\1
	.else
	.if (\1 < 7)
		sta	__temp
		tya
		lsr	a
		jsr	aslw\1
		and.l	#$FF << \1
	.else
	.if (\1 = 7)
		say
		lsr	a
		say
		ror	a
		say
		ror	a
		and	#$80
	.else
	.if (\1 = 8)
		tay
		cla
	.else
	.if (\1 < 16)
		jsr	aslw\1
	.else
		cla
		cly
	.endif
	.endif
	.endif
	.endif
	.endif
	.endif
	.endif
		.endm

; **************

__asl.wr	.macro
		asl	a
		say
		rol	a
		say
		.endm

; **************

__asr.wt	.macro
		jsr	asrw
		.endm

; **************

__asr.wi	.macro
	.if (\1 = 1)
		cpy	#$80
		say
		ror	a
		say
		ror	a
	.else
	.if (\1 = 2)
		cpy	#$80
		say
		ror	a
		say
		ror	a
		cpy	#$80
		say
		ror	a
		say
		ror	a
	.else
	.if (\1 < 8)
		sty	__temp
		jsr	asrw\1
	.else
	.if (\1 = 8)
		tya
		cly
		bpl	!+
		dey
!:
	.else
	.if (\1 < 16)
		tya
		jsr	asrw\1
	.else
		cpy	#$80
		cly
		bcc	!+
		dey
!:		tya
	.endif
	.endif
	.endif
	.endif
	.endif
		.endm

; **************

__lsr.wt	.macro
		jsr	lsrw
		.endm

; **************

__lsr.wi	.macro
	.if (\1 = 1)
		say
		lsr	a
		say
		ror	a
	.else
	.if (\1 = 2)
		say
		lsr	a
		say
		ror	a
		say
		lsr	a
		say
		ror	a
	.else
	.if (\1 < 8)
		sty	__temp
		jsr	lsrw\1
	.else
	.if (\1 = 8)
		tya
		cly
		bmi	!+
		dey
!:
	.else
	.if (\1 < 16)
		tya
		jsr	lsrw\1
	.else
		cly
		bcc	!+
		dey
!:		tya
	.endif
	.endif
	.endif
	.endif
	.endif
		.endm

; **************

__lsr.uiq	.macro
	.if (\1 < 8)
	.if (\1 >= 1)
		lsr	a
	.endif
	.if (\1 >= 2)
		lsr	a
	.endif
	.if (\1 >= 3)
		lsr	a
	.endif
	.if (\1 >= 4)
		lsr	a
	.endif
	.if (\1 >= 5)
		lsr	a
	.endif
	.if (\1 >= 6)
		lsr	a
	.endif
	.if (\1 >= 7)
		lsr	a
	.endif
	.else
		cla
	.endif
		.endm

; **************

__mul.wt	.macro
		jsr	mulw
		.endm

; **************

__mul.wi	.macro
	.if (\1 = 2)
	__asl.wr
	.else
	.if (\1 = 3)
		sta.l	__temp
		sty.h	__temp
	__asl.wr
	__add.wm	__temp
	.else
	.if (\1 = 4)
	__asl.wr
	__asl.wr
	.else
	.if (\1 = 5)
		sta.l	__temp
		sty.h	__temp
	__asl.wr
	__asl.wr
	__add.wm	__temp
	.else
	.if (\1 = 6)
	__asl.wr
		sta.l	__temp
		sty.h	__temp
	__asl.wr
	__add.wm	__temp
	.else
	.if (\1 = 7)
		sta.l	__temp
		sty.h	__temp
	__asl.wr
	__asl.wr
	__asl.wr
	__sub.wm	__temp
	.else
	.if (\1 = 8)
	__asl.wr
	__asl.wr
	__asl.wr
	.else
	.if (\1 = 9)
		sta.l	__temp
		sty.h	__temp
	__asl.wr
	__asl.wr
	__asl.wr
	__add.wm	__temp
	.else
	.if (\1 = 10)
	__asl.wr
		sta.l	__temp
		sty.h	__temp
	__asl.wr
	__asl.wr
	__add.wm	__temp
	.else
	__push.wr
	__ld.wi		\1
		jsr	mulw
	.endif
	.endif
	.endif
	.endif
	.endif
	.endif
	.endif
	.endif
	.endif
		.endm

; **************

__sdiv.wt	.macro
		jsr	sdivw
		.endm

; **************

__sdiv.wi	.macro
		phx
		ldx.l	#\1
		stx.l	<divisor
		ldx.h	#\1
		stx.h	<divisor
		jsr	__divsint
		plx
		.endm

; **************

__udiv.wt	.macro
		jsr	udivw
		.endm

; **************

__udiv.wi	.macro
		phx
		ldx.l	#\1
		stx.l	<divisor
		ldx.h	#\1
		stx.h	<divisor
		jsr	__divuint
		plx
		.endm

; **************

__udiv.ui	.macro
		phx
		ldy	#\1
		jsr	__divuchar
		plx
		.endm

; **************

__smod.wt	.macro
		jsr	smodw
		.endm

; **************

__smod.wi	.macro
		phx
		ldx.l	#\1
		stx.l	<divisor
		ldx.h	#\1
		stx.h	<divisor
		jsr	__modsint
		plx
		.endm

; **************

__umod.wt	.macro
		jsr	umodw
		.endm

; **************

__umod.wi	.macro
		phx
		ldx.l	#\1
		stx.l	<divisor
		ldx.h	#\1
		stx.h	<divisor
		jsr	__moduint
		plx
		.endm

; **************

__umod.ui	.macro
		phx
		ldy	#\1
		jsr	__moduchar
		plx
		.endm



; ***************************************************************************
; ***************************************************************************
; i-codes for 32-bit longs
; ***************************************************************************
; ***************************************************************************

; **************

__ldd_i		.macro
		lda.l	#(\1) >> 16
		sta.l	<\3
		lda.h	#(\1) >> 16
		sta.h	<\3
		lda.l	#\1
		sta.l	<\2
		ldy.h	#\1
		sty.h	<\2
		.endm

; **************

__ldd_w		.macro
		lda.l	\1
		ldy.h	\1
		sta.l	<\2
		sty.h	<\2
		stz.l	<\3
		stz.h	<\3
		.endm

; **************

__ldd_b		.macro
		lda	\1
		cly
		sta.l	<\2
		stz.h	<\2
		stz.l	<\3
		stz.h	<\3
		.endm

; **************

__ldd_s_w	.macro	; __STACK
		lda.l	<__stack + \1, x
		ldy.h	<__stack + \1, x
		sta.l	<\2
		sty.h	<\2
		stz.l	<\3
		stz.h	<\3
		.endm
; **************

__ldd_s_b	.macro	; __STACK
		lda.l	<__stack + \1, x
		cly
		bpl	!+
		dey
!:		sta.l	<\2
		sty.h	<\2
		stz.l	<\3
		stz.h	<\3
		.endm



; ***************************************************************************
; ***************************************************************************
; subroutines for comparison tests with signed and unsigned words
; ***************************************************************************
; ***************************************************************************

; **************
; C is true (1) if stacked-value == Y:A, else false (0)

equ_w:		cmp.l	<__stack, x
		bne	return_false
		tya
		cmp.h	<__stack, x
		bne	return_false
;		bra	return_true

; **************
; boolean result, this MUST set the C flag for the subsequent branches!

return_true:	inx
		inx
		sec
		rts

; **************
; C is true (1) if stacked-value != Y:A, else false (0)

neq_w:		cmp.l	<__stack, x
		bne	return_true
		tya
		cmp.h	<__stack, x
		bne	return_true
;		bra	return_false

; **************
; boolean result, this MUST set the C flagy for the subsequent branches!

return_false:	inx
		inx
		clc
		rts

; **************
; C is true (1) if stacked-value < Y:A, else false (0)

slt_w:		clc			; Subtract memory+1 from Y:A.
		sbc.l	<__stack, x
		tya
		sbc.h	<__stack, x
		bvc	!+
		eor	#$80
!:		bpl	return_true	; +ve if Y:A  > memory (signed).
		bra	return_false	; -ve if Y:A <= memory (signed).

; **************
; C is true (1) if stacked-value <= Y:A, else false (0)

sle_w:		cmp.l	<__stack, x	; Subtract memory from Y:A.
		tya
		sbc.h	<__stack, x
		bvc	!+
		eor	#$80
!:		bpl	return_true	; +ve if Y:A >= memory (signed).
		bra	return_false	; -ve if Y:A  < memory (signed).

; **************
; C is true (1) if stacked-value > Y:A, else false (0)

sgt_w:		cmp.l	<__stack, x	; Subtract memory from Y:A.
		tya
		sbc.h	<__stack, x
		bvc	!+
		eor	#$80
!:		bmi	return_true	; -ve if Y:A  < memory (signed).
		bra	return_false	; +ve if Y:A >= memory (signed).

; **************
; C is true (1) if stacked-value >= Y:A, else false (0)

sge_w:		clc			; Subtract memory+1 from Y:A.
		sbc.l	<__stack, x
		tya
		sbc.h	<__stack, x
		bvc	!+
		eor	#$80
!:		bmi	return_true	; -ve if Y:A <= memory (signed).
		bra	return_false	; +ve if Y:A  > memory (signed).

; **************
; C is true (1) if stacked-value < Y:A, else false (0)

ult_w:		clc			; Subtract memory+1 from Y:A.
		sbc.l	<__stack, x
		tya
		sbc.h	<__stack, x
		bcs	return_true	; CS if Y:A  > memory.
		bra	return_false

; **************
; C is true (1) if stacked-value <= Y:A, else false (0)

ule_w:		cmp.l	<__stack, x	; Subtract memory from Y:A.
		tya
		sbc.h	<__stack, x
		bcs	return_true	; CS if Y:A >= memory.
		bra	return_false

; **************
; C is true (1) if stacked-value > Y:A, else false (0)

ugt_w:		cmp.l	<__stack, x	; Subtract memory from Y:A.
		tya
		sbc.h	<__stack, x
		bcc	return_true	; CC if Y:A  < memory.
		bra	return_false

; **************
; C is true (1) if stacked-value >= Y:A, else false (0)

uge_w:		clc			; Subtract memory+1 from Y:A.
		sbc.l	<__stack, x
		tya
		sbc.h	<__stack, x
		bcc	return_true	; CC if Y:A <= memory.
		bra	return_false



; ***************************************************************************
; ***************************************************************************
; subroutines for logical and arithmetic shifts by a constant amount
; ***************************************************************************
; ***************************************************************************

; **************
; Y:A = Y:A << const

aslw15:		asl	a
aslw14:		asl	a
aslw13:		asl	a
aslw12:		asl	a
aslw11:		asl	a
aslw10:		asl	a
aslw9:		asl	a
aslw8:		tay
		cla
		rts

	.if	1
aslw5:		ror	<__temp
		ror	a
aslw6:		ror	<__temp
		ror	a
aslw7:		ror	<__temp
		ror	a
		ldy	<__temp
		rts
	.else
aslw7:		asl	a
		rol	<__temp
aslw6:		asl	a
		rol	<__temp
aslw5:		asl	a
		rol	<__temp
	.endif
aslw4:		asl	a
		rol	<__temp
aslw3:		asl	a
		rol	<__temp
aslw2:		asl	a
		rol	<__temp
aslw1:		asl	a
		rol	<__temp
aslw0:		ldy	<__temp
		rts

; **************
; Y:A = Y:A >> const

asrw15:		cmp	#$80
		ror	a
asrw14:		cmp	#$80
		ror	a
asrw13:		cmp	#$80
		ror	a
asrw12:		cmp	#$80
		ror	a
asrw11:		cmp	#$80
		ror	a
asrw10:		cmp	#$80
		ror	a
asrw9:		cmp	#$80
		ror	a
asrw8:		cmp	#$80
		cly
		bcc	!+
		dey
!:		rts

asrw7:		cpy	#$80
		ror	<__temp
		ror	a
asrw6:		cpy	#$80
		ror	<__temp
		ror	a
asrw5:		cpy	#$80
		ror	<__temp
		ror	a
asrw4:		cpy	#$80
		ror	<__temp
		ror	a
asrw3:		cpy	#$80
		ror	<__temp
		ror	a
asrw2:		cpy	#$80
		ror	<__temp
		ror	a
asrw1:		cpy	#$80
		ror	<__temp
		ror	a
asrw0:		ldy	<__temp
		rts

; **************
; Y:A = Y:A >> const

lsrw15:		lsr	a
lsrw14:		lsr	a
lsrw13:		lsr	a
lsrw12:		lsr	a
lsrw11:		lsr	a
lsrw10:		lsr	a
lsrw9:		lsr	a
lsrw8:		cly
		rts

lsrw7:		lsr	<__temp
		ror	a
lsrw6:		lsr	<__temp
		ror	a
lsrw5:		lsr	<__temp
		ror	a
lsrw4:		lsr	<__temp
		ror	a
lsrw3:		lsr	<__temp
		ror	a
lsrw2:		lsr	<__temp
		ror	a
lsrw1:		lsr	<__temp
		ror	a
lsrw0:		ldy	<__temp
		rts



; ***************************************************************************
; ***************************************************************************
; subroutines for logical and arithmetic shifts by a variable amount
; ***************************************************************************
; ***************************************************************************

; **************
; Y:A = stacked-value << Y:A

aslw:		pha				; preserve count
		lda.h	<__stack, x
		sta	<__temp
		lda.l	<__stack, x
		inx
		inx
		ply				; restore count
		beq	.done
		cpy	#16
		bcs	.zero
.loop:		asl	a
		rol	<__temp
		dey
		bne	.loop
.done:		ldy	<__temp
		rts
.zero:		cla
		cly
		rts

; **************
; Y:A = stacked-value >> Y:A

asrw:		pha				; preserve count
		lda.h	<__stack, x
		bpl	asrw_positive
asrw_negative:	sta	<__temp
		lda.l	<__stack, x
		inx
		inx
		ply				; restore count
		beq	.done
		cpy	#16
		bcs	.sign
.loop:		sec
		ror	<__temp
		ror	a
		dey
		bne	.loop
.done:		ldy	<__temp
		rts

.sign:		lda	#$FF
		tay
		rts

; **************
; Y:A = stacked-value >> Y:A

lsrw:		pha				; preserve count
		lda.h	<__stack, x
asrw_positive:	sta	<__temp
		lda.l	<__stack, x
		inx
		inx
		ply				; restore count
		beq	.done
		cpy	#16
		bcs	.zero
.loop:		lsr	<__temp
		ror	a
		dey
		bne	.loop
.done:		ldy	<__temp
		rts

.zero:		cla
		cly
		rts



; ***************************************************************************
; ***************************************************************************
; subroutines for signed and unsigned multiplication and division
; ***************************************************************************
; ***************************************************************************

; **************
; Y:A = stacked-value * Y:A
;
; N.B. signed and unsigned multiply only differ in the top 16 of the 32bits!

mulw:		sta.l	<multiplier
		sty.h	<multiplier
		__pop.wr
		phx				; Preserve X (aka __sp).
		jsr	__mulint		; SDCC library name for this.
		plx				; Restore X (aka __sp).
		rts

; **************
; Y:A = stacked-value / Y:A

udivw:		sta.l	<divisor
		sty.h	<divisor
		__pop.wr
		phx				; Preserve X (aka __sp).
		jsr	__divuint		; SDCC library name for this.
		plx				; Restore X (aka __sp).
		rts

; **************
; Y:A = stacked-value / Y:A

sdivw:		sta.l	<divisor
		sty.h	<divisor
		__pop.wr
		phx				; Preserve X (aka __sp).
		jsr	__divsint		; SDCC library name for this.
		plx				; Restore X (aka __sp).
		rts

; **************
; Y:A = stacked-value % Y:A

umodw:		sta.l	<divisor
		sty.h	<divisor
		__pop.wr
		phx				; Preserve X (aka __sp).
		jsr	__moduint		; SDCC library name for this.
		plx				; Restore X (aka __sp).
		rts

; **************
; Y:A = stacked-value % Y:A

smodw:		sta.l	<divisor
		sty.h	<divisor
		__pop.wr
		phx				; Preserve X (aka __sp).
		jsr	__modsint		; SDCC library name for this.
		plx				; Restore X (aka __sp).
		rts



; ***************************************************************************
; ***************************************************************************
; subroutine for implementing a switch() statement
;
; case_table:
; +  0		db	6		; #bytes of case values.
; + 12		db	>val3, <val3
; + 34		db	>val2, <val2
; + 56		db	>val1, <val1
; + 78		dw	jmpdefault
; + 9A		dw	jmp3
; + BC		dw	jmp2
; + DE		dw	jmp1
; ***************************************************************************
; ***************************************************************************

; **************

do_switchw:	phx

		sty.h	<__ptr		; Save hi-byte of the table address.
		sta.l	<__temp		; Save lo-byte of the value to find.

		lda	[__ptr]		; Read #bytes of case values to check.
		tay
		beq	zero_cases

test_case_lo:	lda.l	<__temp		; Fast test loop for the lo-byte, which
.loop:		cmp	[__ptr], y	; is the most-likely to fail the match.
		beq	test_case_hi
		dey
		dey
		bne	.loop

default_case:	clc			; Need to CC for default or do_switchb!
case_found:	tya			; Add the offset to the label address.
		adc	[__ptr]
		tay
zero_cases:	iny

		lda	[__ptr], y	; Read label address lo-byte.
		sta.l	<__temp
		iny
		lda	[__ptr], y	; Read label address hi-byte.
		sta.h	<__temp
		jmp	[__temp]

test_case_hi:	lda.h	<__temp		; Slow test loop for the hi-byte, which
		dey			; should rarely be checked.
		cmp	[__ptr], y
		beq	case_found	; CS if case_found.
		dey
		bne	test_case_lo
		bra	default_case

; **************

do_switchb:	phx

		sty.h	<__ptr		; Save hi-byte of the table address.
		tay			; Save lo-byte of the value to find.

		lda	[__ptr]		; Read #bytes of case values to check.
		say
		beq	zero_cases

.loop:		cmp	[__ptr], y
		beq	default_case	; Need to CC if case_found!
		dey
		dey
		bne	.loop
		bra	default_case



; ***************************************************************************
; ***************************************************************************
; POTENTIAL OPTIMIZATIONS, NOT YET ADDED
; ***************************************************************************
; ***************************************************************************
