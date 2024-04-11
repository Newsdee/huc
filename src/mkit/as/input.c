#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <sys/stat.h>
#include "defs.h"
#include "externs.h"
#include "protos.h"

int file_count;
t_file_names * file_names;
t_file * file_hash[HASH_COUNT];

#define INCREMENT_BASE 256
#define INCREMENT_BASE_MASK 255

char full_path[PATHSZ * 2];
int infile_error;
int infile_num;
t_input input_file[MAX_NESTING + 1];

static char *incpath = NULL;
static int *incpath_offset = NULL;
static int incpath_remaining = 0;
static int incpath_size = 0;
static int incpath_offset_count = 0;
static int incpath_count = 0;

/* ----
 * void cleanup_path()
 * ----
 * clean up allocated paths
 */
void
cleanup_path(void)
{
	if (incpath)
		free(incpath);

	if (incpath_offset)
		free(incpath_offset);
}

/* ----
 * int add_path(char*, int)
 * ----
 * add a path to includes (newpath_size includes the trailing '\0')
 */
int
add_path(char* newpath, int newpath_size)
{
	/* sanity check */
	if (newpath_size < 2)
		return 0;

	/* remove trailing PATH_SEPARATOR characters */
	while (newpath[newpath_size - 2] == PATH_SEPARATOR)
		--newpath_size;

	/* Expand incpath_offset array if needed */
	if (incpath_count >= incpath_offset_count)
	{
		incpath_offset_count += 8;
		incpath_offset = (int*)realloc(incpath_offset, incpath_offset_count * sizeof(int));
		if (incpath_offset == NULL)
			return 0;
	}

	/* Initialize string offset */
	incpath_offset[incpath_count] = incpath_size - incpath_remaining;

	/* Realloc string buffer if needed */
	if (incpath_remaining < newpath_size)
	{
		incpath_remaining = incpath_size;
		/* evil trick, get the greater multiple of INCREMENT_BASE closer
		   to (size + path_len). Note : this only works for INCREMENT_BASE = 2^n*/
		incpath_size = ((incpath_size + newpath_size) + INCREMENT_BASE) & ~INCREMENT_BASE_MASK;
		incpath_remaining = incpath_size - incpath_remaining;
		incpath = (char*)realloc(incpath, incpath_size);
		if (incpath == NULL)
			return 0;
	}

	incpath_remaining -= newpath_size;

	/* Copy path */
	strncpy(incpath + incpath_offset[incpath_count], newpath, newpath_size);
	incpath[incpath_offset[incpath_count] + newpath_size - 1] = '\0';

	++incpath_count;

	return 1;
}

#ifdef _WIN32
#define ENV_PATH_SEPARATOR ';'
#else
#define ENV_PATH_SEPARATOR ':'
#endif

/* ----
 * int init_path()
 * ----
 * init the include path
 */

int
init_path(void)
{
	char *p,*pl;
	int	ret, l;

	/* Get env variable holding PCE path*/
	p = getenv(machine->include_env);
	printf("%s = \"%s\"\n\n", machine->include_env, p);

	if (p == NULL)
		return 2;

	l  = 0;
	pl = p;
	while(pl != NULL)
	{

		/* Jump to next separator */
		pl = strchr(p, ENV_PATH_SEPARATOR);

		/* Compute new substring size */
		if (pl == NULL)
			l = strlen(p) + 1;
		else
			l = pl - p + 1;

		/* Might be empty, jump to next char */
		if (l <= 1)
		{
			++p;
			continue;
		}

		/* Add path */
		ret = add_path(p, l);
		if (!ret)
			return 0;

		/* Eat remaining separators */
		while (*p == ENV_PATH_SEPARATOR) ++p;

		p += l;
	}

	return 1;
}


/* ----
 * readline()
 * ----
 * read and format an input line.
 */

int
readline(void)
{
	char *ptr, *arg, num[8];
	int j, n;
	int i;		/* pointer into prlnbuf */
	int c;		/* current character		*/
	int temp;	/* temp used for line number conversion */

start:
	memset(prlnbuf, ' ', SFIELD - 1);
	prlnbuf[SFIELD - 1] = '\t';

	/* if 'expand_macro' is set get a line from macro buffer instead */
	if (expand_macro) {
		if (mlptr == NULL) {
			while (mlptr == NULL) {
				midx--;
				mlptr = mstack[midx];
				mcounter = mcntstack[midx];
				if (midx == 0) {
					mlptr = NULL;
					expand_macro = 0;
					break;
				}
			}
		}

		/* expand line */
		if (mlptr) {
			i = SFIELD;
			ptr = mlptr->data;
			for (;;) {
				c = *ptr++;
				if (c == '\0')
					break;
				if (c != '\\')
					prlnbuf[i++] = c;
				else {
					c = *ptr++;
					prlnbuf[i] = '\0';

					/* \@ */
					if (c == '@') {
						n = 5;
						sprintf(num, "%05i", mcounter);
						arg = num;
					}

					/* \# */
					else if (c == '#') {
						for (j = 9; j > 0; j--)
							if (strlen(marg[midx][j - 1]))
								break;
						n = 1;
						sprintf(num, "%i", j);
						arg = num;
					}

					/* \?1 - \?9 */
					else if (c == '?') {
						c = *ptr++;
						if (c >= '1' && c <= '9') {
							n = 1;
							sprintf(num, "%i", macro_getargtype(marg[midx][c - '1']));
							arg = num;
						}
						else {
							error("Invalid macro argument index!");
							return (-1);
						}
					}

					/* \1 - \9 */
					else if (c >= '1' && c <= '9') {
						j = c - '1';
						n = strlen(marg[midx][j]);
						arg = marg[midx][j];
					}

					/* unknown macro special command */
					else {
						error("Invalid macro argument index!");
						return (-1);
					}

					/* check for line overflow */
					if ((i + n) >= LAST_CH_POS - 1) {
						error("Invalid line length!");
						return (-1);
					}

					/* copy macro string */
					strncpy(&prlnbuf[i], arg, n);
					i += n;
				}
				if (i >= LAST_CH_POS - 1)
					i = LAST_CH_POS - 1;
			}
			prlnbuf[i] = '\0';
			mlptr = mlptr->next;
			return (0);
		}
	}

	if (list_level) {
		/* put source line number into prlnbuf */
		i = 4;
		temp = ++slnum;
		while (temp != 0) {
			prlnbuf[i--] = temp % 10 + '0';
			temp /= 10;
		}
	}

	/* get a line */
	i = SFIELD;
	c = getc(in_fp);
	if (c == EOF) {
		if (close_input()) {
			if (stop_pass != 0 || ((sdcc_final == 0) && (kickc_final == 0))) {
				return (-1);
			} else {
				const char * name = (sdcc_final) ? "sdcc-final.asm" : "kickc-final.asm";
				sdcc_final = kickc_final = 0;
				if (open_input(name) == -1) {
					fatal_error("Cannot open \"%s\" file!", name);
					return (-1);
				}
				in_final = 1;
			}
		}
		goto start;
	}
	for (;;) {
		/* check for the end of line */
		if (c == '\r') {
			c = getc(in_fp);
			if (c == '\n' || c == EOF)
				break;
			ungetc(c, in_fp);
			break;
		}
		if (c == '\n' || c == EOF)
			break;

		/* store char in the line buffer */
		prlnbuf[i] = c;
		i += (i < LAST_CH_POS) ? 1 : 0;

		/* get next char */
		c = getc(in_fp);
	}
	prlnbuf[i] = '\0';

	/* reset these at the beginning of the new line */
	preproc_sfield = SFIELD;
	preproc_modidx = 0;

	/* pre-process the input to change C-style comments into ASM ';' comments */
	if (asm_opt[OPT_CCOMMENT])
	{
		int i = SFIELD;
		int c = 0;

		/* repeat this loop until we know how the line ends */
		do {
			/* if we're in a block comment, look for the end of the block */
			if (preproc_inblock != 0) {
				for (; prlnbuf[i] != '\0'; ++i) {
					if (prlnbuf[i] == '*' && prlnbuf[i+1] == '/') {
						preproc_inblock = 0;
						if (preproc_modidx != 0 && c == 0) {
							prlnbuf[preproc_modidx] = '/';
							preproc_modidx = 0;
						}
						i = i + 2;
						if (preproc_modidx == 0) {
							preproc_sfield = i;
						}
						break;
					}
				}
			}

			/* if we're not in a block comment, look for a new comment */
			for (; prlnbuf[i] != '\0'; ++i) {
				if (prlnbuf[i] == '/') {
					if (prlnbuf[i+1] == '/') {
						if (preproc_modidx == 0) {
							preproc_modidx = i;
							prlnbuf[i] = ';';
						}
						break;
					}
					else
					if (prlnbuf[i+1] == '*') {
						preproc_inblock = 1;
						if (preproc_modidx == 0) {
							preproc_modidx = i;
							prlnbuf[i] = ';';
						}
						i = i + 2;
						break;
					}
				}
				/* remember if we see text that needs to be assembled */
				if (!isspace(prlnbuf[i])) { c = 1; }
			}

			/* repeat if we're in a block comment, and not at the EOL */
		} while (preproc_inblock != 0 && prlnbuf[i] != '\0');

		/* if we've been in a block comment for the whole line */
		if (preproc_inblock != 0 && preproc_modidx == 0) {
			preproc_sfield = i;
		}
	}

	return (0);
}


/* ----
 * remember_file()
 * ----
 * remember all source file names
 */

t_file *
remember_file(int hash)
{
	int need;
	t_file * file = malloc(sizeof(t_file));

	if (file == NULL)
		return (NULL);

	need = strlen(full_path) + 1;

	if ((file_names == NULL) || (file_names->remain < need)) {
		t_file_names *temp = malloc(sizeof(t_file_names));
		if (temp == NULL)
			return (NULL);
		temp->remain = FILE_NAMES_SIZE;
		temp->next = file_names;
		file_names = temp;
	}

	file->name = memcpy(file_names->buffer + FILE_NAMES_SIZE - file_names->remain, full_path, need);
	file_names->remain -= need;

	file->number = ++file_count;
	file->included = 0;

	file->next = file_hash[hash];
	file_hash[hash] = file;

	return (file);
}


/* ----
 * clear_included()
 * ----
 * remember all source file names
 */

void
clear_included(void)
{
	t_file *file;
	int i;

	for (i = 0; i < HASH_COUNT; i++) {
		file = file_hash[i];
		while (file) {
			file->included = 0;
			file = file->next;
		}
	}
}


/* ----
 * open_input()
 * ----
 * open input files - up to MAX_NESTING levels.
 */

int
open_input(const char *name)
{
	FILE *fp;
	char *p;
	t_file * file;
	char temp[PATHSZ + 4];
	int hash;

	/* only MAX_NESTING nested input files */
	if (infile_num == MAX_NESTING) {
		error("Too many include levels, maximum 31!");
		return (1);
	}

	/* backup current input file infos */
	if (infile_num) {
		input_file[infile_num].lnum = slnum;
		input_file[infile_num].fp = in_fp;
	}

	/* auto add the .asm file extension */
	if (((p = strrchr(name, '.')) == NULL) ||
	    (strchr(p, PATH_SEPARATOR) != NULL)) {
		strcpy(temp, name);
		strcat(temp, ".asm");
		name = temp;
	}

	/* open the file */
	if ((fp = open_file(name, "r")) == NULL)
		return (-1);

	/* remember all filenames */
	hash = filename_crc(full_path) & (HASH_COUNT - 1);
	file = file_hash[hash];
	while (file) {
#if defined(_WIN32) || defined(__APPLE__)
		if (strcasecmp(file->name, full_path) == 0)
			break;
#else
		if (strcmp(file->name, full_path) == 0)
			break;
#endif
		file = file->next;
	}
	if (file == NULL) {
		file = remember_file(hash);
		if (file == NULL) {
			fclose(fp);
			fatal_error("No memory left to remember filename!");
			return (-1);
		}
	}

	/* do not include the same file twice in a pass */
	if (file->included) {
		fclose(fp);
		return (0);
	}

	/* remember that this file has been included */
	file->included = 1;

	/* update input file infos */
	in_fp = fp;
	slnum = 0;
	infile_num++;
	input_file[infile_num].fp = fp;
	input_file[infile_num].if_level = if_level;
	input_file[infile_num].file = file;
	if ((pass == LAST_PASS) && (xlist) && (list_level))
		fprintf(lst_fp, "#[%i]   \"%s\"\n", infile_num, input_file[infile_num].file->name);

	/* ok */
	return (0);
}


/* ----
 * close_input()
 * ----
 * close an input file, return -1 if no more files in the stack.
 */

int
close_input(void)
{
	if (proc_ptr) {
		fatal_error("Incomplete .PROC/.PROCGROUP!");
		return (-1);
	}
	if (scopeptr) {
		fatal_error("Incomplete .STRUCT!");
		return (-1);
	}
	if (in_macro) {
		fatal_error("Incomplete .MACRO definition!");
		return (-1);
	}
	if (input_file[infile_num].if_level != if_level) {
		fatal_error("Incomplete .IF/.ENDIF statement, beginning at line %d!", if_line[if_level-1]);
		return (-1);
	}
	if (infile_num <= 1)
		return (-1);

	fclose(in_fp);
	infile_num--;
	infile_error = -1;
	slnum = input_file[infile_num].lnum;
	in_fp = input_file[infile_num].fp;
	if ((pass == LAST_PASS) && (xlist) && (list_level))
		fprintf(lst_fp, "#[%i]   \"%s\"\n", infile_num, input_file[infile_num].file->name);

	/* ok */
	return (0);
}


/* ----
 * open_file()
 * ----
 * open a file - browse paths
 */

FILE *
open_file(const char *name, const char *mode)
{
	FILE 	*fileptr;
	int	i;

	fileptr = fopen(name, mode);
	if (fileptr != NULL) {
		strcpy(full_path, name);
		return(fileptr);
	}

	for (i = 0; i < incpath_count; ++i) {
#ifdef _WIN32
		strcpy(full_path, incpath + incpath_offset[i]);
		strcat(full_path, PATH_SEPARATOR_STRING);
		strcat(full_path, name);
#else
		char *p;
		p = stpcpy(full_path, incpath + incpath_offset[i]);
		p = stpcpy(p, PATH_SEPARATOR_STRING);
		stpcpy(p, name);
#endif

		if (strlen(full_path) > (PATHSZ - 1)) {
			error("The include-path + filename string is too long!");
			return (NULL);
		}

		fileptr = fopen(full_path, mode);
		if (fileptr != NULL) break;
	}

	return (fileptr);
}
