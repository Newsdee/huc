/*	File function.c: 2.1 (83/03/20,16:02:04) */
/*% cc -O -c %
 *
 */

#ifndef _FUNCTION_H
#define _FUNCTION_H

void newfunc (const char *sname, int ret_ptr_order, int ret_type, int ret_otag, int is_fastcall);
int getarg (int t, int syntax, int otag, int is_fastcall);
void callfunction (SYMBOL *ptr);
void new_arg_stack (int arg);
void arg_push_ins (INS *ptr);
void arg_flush (int arg, int adj);
void arg_to_fptr (struct fastcall *fast, int i, int arg, int adj);
void arg_to_dword (struct fastcall *fast, int i, int arg, int adj);

#endif
