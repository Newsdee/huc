/*	File code.c: 2.2 (84/08/31,10:05:13) */
/*% cc -O -c %
 *
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <time.h>
#include <string.h>

#include "defs.h"
#include "data.h"
#include "code.h"
#include "error.h"
#include "function.h"
#include "io.h"
#include "main.h"
#include "optimize.h"

/* locals */
int segment;

/* externs */
extern int arg_stack_flag;

/*
 *	print all assembler info before any code is generated
 *
 */
void gdata (void)
{
	if (segment == 1) {
		segment = 0;
		ol(".bss");
	}
}

void gtext (void)
{
	if (segment == 0) {
		segment = 1;
		ol(".code");
	}
}

void header (void)
{
	time_t today;

	outstr("; Small-C HuC6280 (1997-Nov-08)\n");
	outstr("; became HuC      (2000-Feb-22)\n");
	outstr("; became HuCC     (2024-May-01)\n");
	outstr(";\n");
	outstr("; This file generated by ");
	outstr(HUC_VERSION);
	outstr("\n");
	outstr("; on ");
	time(&today);
	outstr(ctime(&today));
	outstr(";\n");
	outstr("\n");
	outstr("HUC\t\t=\t1\n");
	outstr("HUCC\t\t=\t1\n");
	/* Reserve space for further global definitions. */
	output_globdef = ftell(output);
	outstr("                                                                           ");
	nl();
}

void asmdefines (void)
{
	outstr(asmdefs);
}

void inc_startup (void)
{
	if (startup_incl == 0) {
		startup_incl = 1;

		nl();
		outstr("\t\tinclude\t\"hucc.asm\"\n");
		outstr("\t\t.data\n");
		outstr("\t\t.bank\tDATA_BANK\n\n");
		gtext();
		nl();
	}
}

/*
 *	print pseudo-op  to define a byte
 *
 */
void defbyte (void)
{
	ot(".db\t");
}

/*
 *	print pseudo-op to define storage
 *
 */
void defstorage (void)
{
	ot(".ds\t");
}

/*
 *	print pseudo-op to define a word
 *
 */
void defword (void)
{
	ot(".dw\t");
}

/*
 *	output instructions
 *
 */
void out_ins (int code, int type, intptr_t data)
{
	INS tmp;

	memset(&tmp, 0, sizeof(INS));

	tmp.code = code;
	tmp.type = type;
	tmp.data = data;
	gen_ins(&tmp);
}

void out_ins_ex (int code, int type, intptr_t data, int imm_type, intptr_t imm_data)
{
	INS tmp;

	memset(&tmp, 0, sizeof(INS));

	tmp.code = code;
	tmp.type = type;
	tmp.data = data;
	tmp.imm_type = imm_type;
	tmp.imm_data = imm_data;
	gen_ins(&tmp);
}

void out_ins_sym (int code, int type, intptr_t data, SYMBOL *sym)
{
	INS tmp;

	memset(&tmp, 0, sizeof(INS));

	tmp.code = code;
	tmp.type = type;
	tmp.data = data;
	tmp.sym = sym;
	gen_ins(&tmp);
}

void gen_ins (INS *tmp)
{
	if (optimize)
		push_ins(tmp);
	else {
		if (arg_stack_flag)
			arg_push_ins(tmp);
		else
			gen_code(tmp);
	}
}

static void out_type (int type, intptr_t data)
{
	switch (type) {
	case T_VALUE:
		outdec((int)data);
		break;
	case T_LABEL:
		outlabel((int)data);
		break;
	case T_SYMBOL:
		outsymbol((SYMBOL *)data);
		break;
	case T_LITERAL:
		outstr((const char *)data);
		break;
	case T_STRING:
		outconst(litlab);
		outbyte('+');
		outdec((int)data);
		break;
	case T_BANK:
		outstr("BANK(");
		outstr((const char *)data);
		outstr(")");
		break;
	case T_VRAM:
		outstr("VRAM(");
		outstr((const char *)data);
		outstr(")");
		break;
	case T_PAL:
		outstr("PAL(");
		outstr((const char *)data);
		outstr(")");
		break;
	}
}

static void out_addr (int type, intptr_t data)
{
	switch (type) {
	case T_LABEL:
		outlabel((int)data);
		break;
	case T_SYMBOL:
		outsymbol((SYMBOL *)data);
		break;
	case T_LITERAL:
		outstr((const char *)data);
		break;
	case T_PTR:
		outstr("__ptr");
		break;
	case T_VALUE:
		outdec((int)data);
		break;
	case T_STACK:
		outstr("__stack");
		break;
	}
}

void dump_ins (INS *tmp)
{
	FILE *save = output;

	output = stdout;
	gen_code(tmp);
	output = save;
}

/*
 *	gen assembly code
 *
 */
void gen_code (INS *tmp)
{
	int code;
	int type;
	intptr_t data;
	int imm_type;
	intptr_t imm_data;

	code = tmp->code;
	type = tmp->type;
	data = tmp->data;
	imm_type = tmp->imm_type;
	imm_data = tmp->imm_data;

	if (type == T_NOP)
		return;

	switch (code) {

	/* i-codes for handling farptr */

	case I_FARPTR:
		ot("__farptr\t");

		switch (type) {
		case T_LABEL:
			outlabel((int)data);
			break;
		case T_SYMBOL:
			outsymbol((SYMBOL *)data);
			break;
		}
		outstr(",");
		outstr(tmp->arg[0]);
		outstr(",");
		outstr(tmp->arg[1]);
		nl();
		break;

	case I_FARPTR_I:
		ot("__farptr_i\t");
		outsymbol((SYMBOL *)data);
		outstr(",");
		outstr(tmp->arg[0]);
		outstr(",");
		outstr(tmp->arg[1]);
		nl();
		break;

	case I_FARPTR_GET:
		ot("__farptr_get\t");
		outstr(tmp->arg[0]);
		outstr(",");
		outstr(tmp->arg[1]);
		nl();
		break;

	case I_FGETW:
		ot("__farptr_i\t");
		outsymbol((SYMBOL *)data);
		nl();
		ol("  jsr\t_farpeekw.fast");
		break;

	case I_FGETB:
		ot("__farptr_i\t");
		outsymbol((SYMBOL *)data);
		nl();
		ol("__fgetb");
		break;

	case I_FGETUB:
		ot("__farptr_i\t");
		outsymbol((SYMBOL *)data);
		nl();
		ol("__fgetub");
		break;

	/* i-codes for interrupts */

	case I_SEI:
		ol("sei");
		break;

	case I_CLI:
		ol("cli");
		break;

	/* i-codes for calling functions */

	case I_MACRO:
		/* because functions don't need to be pre-declared
		   in HuC we get a string and not a symbol */
		switch (type) {
		case T_LITERAL:
			ot(" ");
			prefix();
			outstr((const char *)data);
			if (imm_data) {
				outstr(".");
				outdec((int)imm_data);
			}
			break;
		}
		nl();
		break;

	case I_CALL:
		/* because functions don't need to be pre-declared
		   in HuC we get a string and not a symbol */
		switch (type) {
		case T_LITERAL:
			ot("  call\t");
			prefix();
			outstr((const char *)data);
			if (imm_data) {
				outstr(".");
				outdec((int)imm_data);
			}
			break;
		}
		nl();
		break;

	case I_CALLP:
		ol("__callp");
		break;

	case I_JSR:
		ot("  jsr\t");

		switch (type) {
		case T_SYMBOL:
			outsymbol((SYMBOL *)data);
			break;
		case T_LIB:
			outstr((const char *)data);
			break;
		}
		nl();
		break;

	/* i-codes for C functions and the C parameter stack */

	case I_ENTER:
		ot("__enter\t");
		outsymbol((SYMBOL *)data);
		nl();
		break;

	case I_LEAVE:
		ot("__leave\t");
		outdec((int)data);
		nl();
		break;

	case I_GETACC:
		ol("__getacc");
		break;

	case I_SAVESP:
		ol("__savesp");
		break;

	case I_LOADSP:
		ol("__loadsp");
		break;

	case I_MODSP:
		ot("__modsp");
		if (type == T_LITERAL) {
			outstr("_sym\t");
			outstr((const char *)data);
		}
		else {
			outstr("\t");
			outdec((int)data);
		}
		nl();
		break;

	case I_PUSHW:
		ol("__pushw");
		break;

	case I_POPW:
		ol("__popw");
		break;

	case I_SPUSHW:
		ol("__spushw");
		break;

	case I_SPOPW:
		ol("__spopw");
		break;

	case I_SPUSHB:
		ol("__spushb");
		break;

	case I_SPOPB:
		ol("__spopb");
		break;

	/* i-codes for handling boolean tests and branching */

	case I_SWITCHW:
		ot("__switchw\t");
		outlabel((int)data);
		nl();
		break;

	case I_SWITCHB:
		ot("__switchb\t");
		outlabel((int)data);
		nl();
		break;

	case I_CASE:
		ot("__case\t");
		if (type == T_VALUE)
			outdec((int)data);
		nl();
		break;

	case I_ENDCASE:
		ot("__endcase");
		nl();
		break;

	case I_LABEL:
		outlabel((int)data);
		col();
		break;

	case I_BRA:
		ot("__bra\t");
		outlabel((int)data);
		nl();
		break;

	case I_DEF:
		outstr((const char *)data);
		outstr(" .equ ");
		outdec((int)imm_data);
		nl();
		break;

	case I_CMPW:
		ot("__cmpw\t");

		switch (type) {
		case T_SYMBOL:
			outsymbol((SYMBOL *)data);
			break;
		case T_LIB:
			outstr((const char *)data);
			break;
		}
		nl();
		break;

	case I_CMPB:
		ot("__cmpb\t");

		switch (type) {
		case T_SYMBOL:
			outsymbol((SYMBOL *)data);
			break;
		case T_LIB:
			outstr((const char *)data);
			break;
		}
		nl();
		break;

	case X_CMPWI_EQ:
		ot("__cmpwi_eq\t");
		out_type(type, data);
		nl();
		break;

	case X_CMPWI_NE:
		ot("__cmpwi_ne\t");
		out_type(type, data);
		nl();
		break;

	case I_TSTW:
		ol("__tstw");
		break;

	case I_NOTW:
		ol("__notw");
		break;

	case I_BFALSE:
		ot("__bfalse\t");
		outlabel((int)data);
		nl();
		nl();
		break;

	case I_BTRUE:
		ot("__btrue\t");
		outlabel((int)data);
		nl();
		nl();
		break;

	case X_TZW:
		ot("__tzw\t");
		out_addr(type, data);
		nl();
		break;

	case X_TZWP:
		ot("__tzwp\t");
		out_addr(type, data);
		nl();
		break;

	case X_TZW_S:
		ot("__tzw_s\t");
		outdec((int)data);
		nl();
		break;

	case X_TZB:
		ot("__tzb\t");
		out_type(type, data);
		nl();
		break;

	case X_TZBP:
		ot("__tzbp\t");
		out_addr(type, data);
		nl();
		break;

	case X_TZB_S:
		ot("__tzb_s\t");
		outdec((int)data);
		nl();
		break;

	case X_TNZW:
		ot("__tnzw\t");
		out_addr(type, data);
		nl();
		break;

	case X_TNZWP:
		ot("__tnzwp\t");
		out_addr(type, data);
		nl();
		break;

	case X_TNZW_S:
		ot("__tnzw_s\t");
		outdec((int)data);
		nl();
		break;

	case X_TNZB:
		ot("__tnzb\t");
		out_type(type, data);
		nl();
		break;

	case X_TNZBP:
		ot("__tnzbp\t");
		out_addr(type, data);
		nl();
		break;

	case X_TNZB_S:
		ot("__tnzb_s\t");
		outdec((int)data);
		nl();
		break;

	/* i-codes for loading the primary register */

	case I_LDWI:
		ot("__ldwi\t");
		out_type(type, data);
		nl();
		break;

	case I_LDW:
		ot("__ldw\t");
		out_addr(type, data);
		nl();
		break;

	case I_LDB:
		ot("__ldb\t");
		out_type(type, data);
		nl();
		break;

	case I_LDUB:
		ot("__ldub\t");
		out_type(type, data);
		nl();
		break;

	case I_LDWP:
		ot("__ldwp\t");
		out_addr(type, data);
		nl();
		break;

	case I_LDBP:
		ot("__ldbp\t");
		out_addr(type, data);
		nl();
		break;

	case I_LDUBP:
		ot("__ldubp\t");
		out_addr(type, data);
		nl();
		break;

	case X_LDWA:
		ot("__ldwa\t");
		outsymbol((SYMBOL *)imm_data);
		outstr(",");
		out_addr(type, data);
		nl();
		break;

	case X_LDBA:
		ot("__ldba\t");
		outsymbol((SYMBOL *)imm_data);
		outstr(",");
		out_addr(type, data);
		nl();
		break;

	case X_LDUBA:
		ot("__lduba\t");
		outsymbol((SYMBOL *)imm_data);
		outstr(",");
		out_addr(type, data);
		nl();
		break;

	case X_LDW_S:
		ot("__ldw_s\t");
		outdec((int)data);
		nl();
		break;

	case X_LDB_S:
		ot("__ldb_s\t");
		outdec((int)data);
		nl();
		break;

	case X_LDUB_S:
		ot("__ldub_s\t");
		outdec((int)data);
		nl();
		break;

	case X_LDWA_S:
		ot("__ldwa_s\t");
		outsymbol((SYMBOL *)imm_data);
		outstr(",");
		outdec((int)data);
		nl();
		break;

	case X_LDBA_S:
		ot("__ldba_s\t");
		outsymbol((SYMBOL *)imm_data);
		outstr(",");
		outdec((int)data);
		nl();
		break;

	case X_LDUBA_S:
		ot("__lduba_s\t");
		outsymbol((SYMBOL *)imm_data);
		outstr(",");
		outdec((int)data);
		nl();
		break;

	/* i-codes for saving the primary register */

	case I_STWZ:
		ot("__stwz\t");
		out_type(type, data);
		nl();
		break;

	case I_STBZ:
		ot("__stbz\t");
		out_type(type, data);
		nl();
		break;

	case I_STWI:
		ot("__stwi\t");
		out_type(type, data);
		outstr(", ");
		out_type(imm_type, imm_data);
		nl();
		break;

	case I_STBI:
		ot("__stbi\t");
		out_type(type, data);
		outstr(", ");
		out_type(imm_type, imm_data);
		nl();
		break;

	case I_STWIP:
		ot("__stwip\t");
		outdec((int)data);
		nl();
		break;

	case I_STBIP:
		ot("__stbip\t");
		outdec((int)data);
		nl();
		break;

	case I_STW:
		ot("__stw\t");
		out_addr(type, data);
		nl();
		break;

	case I_STB:
		ot("__stb\t");
		out_addr(type, data);
		nl();
		break;

	case I_STWP:
		ot("__stwp\t");
		out_addr(type, data);
		nl();
		break;

	case I_STBP:
		ot("__stbp\t");
		out_addr(type, data);
		nl();
		break;

	case I_STWPS:
		ol("__stwps");
		break;

	case I_STBPS:
		ol("__stbps");
		break;

	case X_STWI_S:
		ot("__stwi_s\t");
		outdec((int)imm_data);
		outstr(",");
		outdec((int)data);
		nl();
		break;

	case X_STBI_S:
		ot("__stbi_s\t");
		outdec((int)imm_data);
		outstr(",");
		outdec((int)data);
		nl();
		break;

	case X_STW_S:
		ot("__stw_s\t");
		outdec((int)data);
		nl();
		break;

	case X_STB_S:
		ot("__stb_s\t");
		outdec((int)data);
		nl();
		break;

	case X_STWA_S:
		ot("__stwa_s\t");
		outsymbol((SYMBOL *)imm_data);
		outstr(",");
		outdec((int)data);
		nl();
		break;

	case X_STBA_S:
		ot("__stba_s\t");
		outsymbol((SYMBOL *)imm_data);
		outstr(",");
		outdec((int)data);
		nl();
		break;

	/* i-codes for extending a byte to a word */

	case I_EXTW:
		ol("__extw");
		break;

	case I_EXTUW:
		ol("__extuw");
		break;

	/* i-codes for math with the primary register  */

	case I_COMW:
		ol("__comw");
		break;

	case I_NEGW:
		ol("__negw");
		break;

	case I_INCW:
		ot("__incw\t");
		out_addr(type, data);
		nl();
		break;

	case I_INCB:
		ot("__incb\t");
		out_addr(type, data);
		nl();
		break;

	case I_ADDWS:
		ol("__addws");
		break;

	case I_ADDWI:
		ot("__addwi\t");
#if 0
		/* Assembler workaround; pceas doesn't like if the code
		   size changes as it resolved a symbol, so we use the
		   variant without ".if"s if there is a symbol involved. */
		if (type == T_SYMBOL ||
		    type == T_LITERAL ||
		    type == T_STRING)
			outstr("_sym");
		outstr("\t");
#endif
		out_type(type, data);
		nl();
		break;

	case I_ADDW:
		ot("__addw\t");
		out_addr(type, data);
		nl();
		break;

	case I_ADDUB:
		ot("__addub\t");
		out_addr(type, data);
		nl();
		break;

	case X_ADDW_S:
		ot("__addw_s\t");
		outdec((int)data);
		nl();
		break;

	case X_ADDUB_S:
		ot("__addub_s\t");
		outdec((int)data);
		nl();
		break;

	case I_ADDBI_P:
		ot("__addbi_p\t");
		out_type(type, data);
		nl();
		break;

	case I_SUBWS:
		ol("__subws");
		break;

	case I_SUBWI:
		ot("__subwi\t");
		out_type(type, data);
		nl();
		break;

	case I_SUBW:
		ot("__subw\t");
		out_addr(type, data);
		nl();
		break;

	case I_SUBUB:
		ot("__subub\t");
		out_addr(type, data);
		nl();
		break;

	case I_ANDWS:
		ol("__andws");
		break;

	case I_ANDWI:
		ot("__andwi\t");
		out_type(type, data);
		nl();
		break;

	case I_ANDW:
		ot("__andw\t");
		out_addr(type, data);
		nl();
		break;

	case I_ANDUB:
		ot("__andub\t");
		out_addr(type, data);
		nl();
		break;

	case I_EORWS:
		ol("__eorws");
		break;

	case I_EORWI:
		ot("__eorwi\t");
		out_type(type, data);
		nl();
		break;

	case I_EORW:
		ot("__eorw\t");
		out_addr(type, data);
		nl();
		break;

	case I_EORUB:
		ot("__eorub\t");
		out_addr(type, data);
		nl();
		break;

	case I_ORWS:
		ol("__orws");
		break;

	case I_ORWI:
		ot("__orwi\t");
		out_type(type, data);
		nl();
		break;

	case I_ORW:
		ot("__orw\t");
		out_addr(type, data);
		nl();
		break;

	case I_ORUB:
		ot("__orub\t");
		out_addr(type, data);
		nl();
		break;

	case I_ASLWS:
		ol("__aslws");
		break;

	case I_ASLWI:
		ot("__aslwi\t");
		out_type(type, data);
		nl();
		break;

	case I_ASLW:
		ol("__aslw");
		break;

	case I_ASRWI:
		ot("__asrwi\t");
		out_type(type, data);
		nl();
		break;

	case I_ASRW:
		ol("__asrw");
		break;

	case I_LSRWI:
		ot("__lsrwi\t");
		out_type(type, data);
		nl();
		break;

	case I_MULWI:
		ot("__mulwi\t");
		outdec((int)data);
		nl();
		break;

	/* optimized i-codes for local variables on the C stack */

	case X_LEA_S:
		ot("__lea_s\t");
		outdec((int)data);
		nl();
		break;

	case X_PEA_S:
		ot("__pea_s\t");
		outdec((int)data);
		nl();
		break;

	case X_INCW_S:
		ot("__incw_s\t");
		outdec((int)data);
		nl();
		break;

	case X_INCB_S:
		ot("__incb_s\t");
		outdec((int)data);
		nl();
		break;

	default:
		gen_asm(tmp);
		break;
	}
}

/* ----
 * gen_asm()
 * ----
 * generate optimizer asm code
 *
 */
void gen_asm (INS *inst)
{
//	int type = inst->type;
//	intptr_t data = inst->data;

	/* i-codes for 32-bit longs */

	switch (inst->code) {

	case X_LDD_I:
		ot("__ldd_i\t");
		outdec((int)inst->data);
		outstr(",");
		prefix();
		outstr(inst->arg[0]);
		outstr(",");
		prefix();
		outstr(inst->arg[1]);
		nl();
		break;

	case X_LDD_W:
		ot("__ldd_w\t");
		outsymbol((SYMBOL *)inst->data);
		outstr(",");
		prefix();
		outstr(inst->arg[0]);
		outstr(",");
		prefix();
		outstr(inst->arg[1]);
		nl();
		break;

	case X_LDD_B:
		ot("__ldd_b\t");
		outsymbol((SYMBOL *)inst->data);
		outstr(",");
		prefix();
		outstr(inst->arg[0]);
		outstr(",");
		prefix();
		outstr(inst->arg[1]);
		nl();
		break;

	case X_LDD_S_W:
		ot("__ldd_s_w\t");
		outdec((int)inst->data);
		outstr(",");
		prefix();
		outstr(inst->arg[0]);
		outstr(",");
		prefix();
		outstr(inst->arg[1]);
		nl();
		break;

	case X_LDD_S_B:
		ot("__ldd_s_b\t");
		outdec((int)inst->data);
		outstr(",");
		prefix();
		outstr(inst->arg[0]);
		outstr(",");
		prefix();
		outstr(inst->arg[1]);
		nl();
		break;

	default:
		error("internal error: invalid instruction");
		break;
	}
}
