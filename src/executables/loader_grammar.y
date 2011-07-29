/*
 * Copyright (C) 2008 Search Solution Corporation. All rights reserved by Search Solution.
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or 
 *   (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *
 */

/*
 * loader_grammar.y - loader grammar file
 */

%{
#ident "$Id$"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "dbi.h"
#include "utility.h"
#include "dbtype.h"
#include "language_support.h"
#include "message_catalog.h"
#include "memory_alloc.h"
#include "error_manager.h"
#include "loader.h"

/*#define PARSER_DEBUG*/
#ifdef PARSER_DEBUG
#define DBG_PRINT(s) printf("rule: %s\n", (s));
#else
#define DBG_PRINT(s)
#endif

#define FREE_STRING(s) \
do { \
  if ((s)->need_free_val) free_and_init ((s)->val); \
  if ((s)->need_free_self) free_and_init ((s)); \
} while (0)

#define CONSTANT_POOL_SIZE (1024)

extern bool loader_In_instance_line;
extern FILE *loader_yyin;

extern int loader_yylex(void);
extern void loader_yyerror(char* s);
extern void loader_reset_string_pool (void);
extern void loader_initialize_lexer (void);
extern void do_loader_parse(FILE *fp);

static LDR_CONSTANT constant_Pool[CONSTANT_POOL_SIZE];
static int constant_Pool_idx = 0;

static LDR_STRING *loader_append_string_list(LDR_STRING *head, LDR_STRING *str);
static LDR_CLASS_COMMAND_SPEC *loader_make_class_command_spec(int qualifier, LDR_STRING *attr_list, LDR_CONSTRUCTOR_SPEC *ctor_spec);
static LDR_CONSTANT* loader_make_constant(int type, void *val);
static LDR_CONSTANT *loader_append_constant_list(LDR_CONSTANT *head, LDR_CONSTANT *tail);
static void loader_process_constants (LDR_CONSTANT *c);
static void loader_process_object_ref (LDR_OBJECT_REF * ref, int type);

%}

%error_verbose

%union {
	int 	intval;
	LDR_STRING	*string;
	LDR_CLASS_COMMAND_SPEC *cmd_spec;
	LDR_CONSTRUCTOR_SPEC *ctor_spec;
	LDR_CONSTANT *constant;
	LDR_OBJECT_REF *obj_ref;
}

%token NL
%token NULL_
%token CLASS
%token SHARED
%token DEFAULT
%token DATE_
%token TIME
%token UTIME
%token TIMESTAMP
%token DATETIME
%token CMD_ID
%token CMD_CLASS
%token CMD_CONSTRUCTOR
%token REF_ELO_INT
%token REF_ELO_EXT
%token REF_USER
%token REF_CLASS
%token OBJECT_REFERENCE
%token OID_DELIMETER
%token SET_START_BRACE
%token SET_END_BRACE
%token START_PAREN
%token END_PAREN
%token <string> REAL_LIT
%token <string> INT_LIT
%token <intval> OID_
%token <string> TIME_LIT4
%token <string> TIME_LIT42
%token <string> TIME_LIT3
%token <string> TIME_LIT31
%token <string> TIME_LIT2
%token <string> TIME_LIT1
%token <string> DATE_LIT2
%token YEN_SYMBOL
%token WON_SYMBOL
%token BACKSLASH
%token DOLLAR_SYMBOL
%token <string> IDENTIFIER
%token Quote
%token DQuote
%token NQuote
%token BQuote
%token XQuote
%token <string> SQS_String_Body
%token <string> DQS_String_Body
%token COMMA

%type <intval> attribute_list_qualifier
%type <cmd_spec> class_commamd_spec
%type <ctor_spec> constructor_spec
%type <string> attribute_name
%type <string> argument_name
%type <string> attribute_names
%type <string> attribute_list
%type <string> argument_names
%type <string> constructor_argument_list
%type <constant> constant
%type <constant> constant_list

%type <constant> ansi_string
%type <constant> dq_string
%type <constant> nchar_string
%type <constant> bit_string
%type <constant> sql2_date
%type <constant> sql2_time
%type <constant> sql2_timestamp
%type <constant> sql2_datetime
%type <constant> utime
%type <constant> monetary
%type <constant> object_reference
%type <constant> set_constant
%type <constant> system_object_reference

%type <obj_ref> class_identifier
%type <string> instance_number
%type <intval> ref_type
%type <intval> object_id

%type <constant> set_elements

%start loader_start
%%

loader_start :
  {
    loader_initialize_lexer ();
    constant_Pool_idx = 0;
  }
  loader_lines
  {
    ldr_act_finish (ldr_Current_context, 0);
  }
  ;

loader_lines :
  line
  {
    DBG_PRINT ("line");
  }
  |
  loader_lines line
  {
    DBG_PRINT ("line_list line");
  }
  ;

line :
  one_line NL
  {
    DBG_PRINT ("one_line");
    loader_In_instance_line = true;
  }
  |
  NL
  {
    loader_In_instance_line = true;
  }
  ;

one_line :
  command_line
  {
    DBG_PRINT ("command_line");
    loader_reset_string_pool ();
    constant_Pool_idx = 0;
  }
  |
  instance_line
  {
    DBG_PRINT ("instance_line");
    ldr_act_finish_line (ldr_Current_context);
    loader_reset_string_pool ();
    constant_Pool_idx = 0;
  }
  ;

command_line :
  class_command
  {
    DBG_PRINT ("class_command");
  }
  |
  id_command
  {
    DBG_PRINT ("id_command");
  }
  ;

id_command :
  CMD_ID IDENTIFIER INT_LIT
  {
    skipCurrentclass = false;

    ldr_act_start_id (ldr_Current_context, $2->val);
    ldr_act_set_id (ldr_Current_context, atoi ($3->val));

    FREE_STRING ($2);
    FREE_STRING ($3);
  }
  ;

class_command :
  CMD_CLASS IDENTIFIER class_commamd_spec
  {
    LDR_CLASS_COMMAND_SPEC *cmd_spec;
    LDR_STRING *class_name;
    LDR_STRING *attr, *save, *args;

    DBG_PRINT ("class_commamd_spec");

    class_name = $2;
    cmd_spec = $3;

    ldr_act_set_skipCurrentclass (class_name->val, class_name->size);
    ldr_act_init_context (ldr_Current_context, class_name->val,
                          class_name->size);

    if (cmd_spec->qualifier != LDR_ATTRIBUTE_ANY)
      {
        ldr_act_restrict_attributes (ldr_Current_context, cmd_spec->qualifier);
      }

    for (attr = cmd_spec->attr_list; attr; attr = attr->next)
      {
        ldr_act_add_attr (ldr_Current_context, attr->val, attr->size);
      }

    ldr_act_check_missing_non_null_attrs (ldr_Current_context);

    if (cmd_spec->ctor_spec)
      {
        ldr_act_set_constructor (ldr_Current_context,
                                 cmd_spec->ctor_spec->idname->val);

        for (args = cmd_spec->ctor_spec->arg_list; args; args = args->next)
          {
            ldr_act_add_argument (ldr_Current_context, args->val);
          }

        for (args = cmd_spec->ctor_spec->arg_list; args; args = save)
          {
            save = args->next;
            FREE_STRING (args);
          }

        FREE_STRING (cmd_spec->ctor_spec->idname);
        free_and_init (cmd_spec->ctor_spec);
      }

    for (attr = cmd_spec->attr_list; attr; attr = save)
      {
        save = attr->next;
        FREE_STRING (attr);
      }

    FREE_STRING (class_name);
    free_and_init (cmd_spec);
  }
  ;

class_commamd_spec :
  attribute_list
  {
    DBG_PRINT ("attribute_list");
    $$ = loader_make_class_command_spec (LDR_ATTRIBUTE_ANY, $1, NULL);
  }
  |
  attribute_list constructor_spec
  {
    DBG_PRINT ("attribute_list constructor_spec");
    $$ = loader_make_class_command_spec (LDR_ATTRIBUTE_ANY, $1, $2);
  }
  |
  attribute_list_qualifier attribute_list
  {
    DBG_PRINT ("attribute_list_qualifier attribute_list");
    $$ = loader_make_class_command_spec ($1, $2, NULL);
  }
  |
  attribute_list_qualifier attribute_list constructor_spec
  {
    DBG_PRINT ("attribute_list_qualifier attribute_list constructor_spec");
    $$ = loader_make_class_command_spec ($1, $2, $3);
  }
  ;

attribute_list_qualifier :
  CLASS
  {
    DBG_PRINT ("CLASS");
    $$ = LDR_ATTRIBUTE_CLASS;
  }
  |
  SHARED
  {
    DBG_PRINT ("SHARED");
    $$ = LDR_ATTRIBUTE_SHARED;
  }
  |
  DEFAULT
  {
    DBG_PRINT ("DEFAULT");
    $$ = LDR_ATTRIBUTE_DEFAULT;
  }
  ;

attribute_list :
  START_PAREN END_PAREN
  {
    $$ = NULL;
  }
  |
  START_PAREN attribute_names END_PAREN
  {
    $$ = $2;
  }
  ;

attribute_names :
  attribute_name
  {
    DBG_PRINT ("attribute_name");
    $$ = loader_append_string_list (NULL, $1);
  }
  |
  attribute_names attribute_name
  {
    DBG_PRINT ("attribute_names attribute_name");
    $$ = loader_append_string_list ($1, $2);
  }
  |
  attribute_names COMMA attribute_name
  {
    DBG_PRINT ("attribute_names COMMA attribute_name");
    $$ = loader_append_string_list ($1, $3);
  }
  ;

attribute_name :
  IDENTIFIER
  {
    $$ = $1;
  }
  ;

constructor_spec :
  CMD_CONSTRUCTOR IDENTIFIER constructor_argument_list
  {
    LDR_CONSTRUCTOR_SPEC *spec;

    spec = (LDR_CONSTRUCTOR_SPEC *) malloc (sizeof (LDR_CONSTRUCTOR_SPEC));
    if (spec == NULL)
      {
	er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE,
	        ER_OUT_OF_VIRTUAL_MEMORY, 1, sizeof (LDR_CONSTRUCTOR_SPEC));
	YYABORT;
      }

    spec->idname = $2;
    spec->arg_list = $3;
    $$ = spec;
  }
  ;

constructor_argument_list :
  START_PAREN END_PAREN
  {
    $$ = NULL;
  }
  |
  START_PAREN argument_names END_PAREN
  {
    $$ = $2;
  }
  ;

argument_names :
  argument_name
  {
    DBG_PRINT ("argument_name");
    $$ = loader_append_string_list (NULL, $1);
  }
  |
  argument_names argument_name
  {
    DBG_PRINT ("argument_names argument_name");
    $$ = loader_append_string_list ($1, $2);
  }
  |
  argument_names COMMA argument_name
  {
    DBG_PRINT ("argument_names COMMA argument_name");
    $$ = loader_append_string_list ($1, $3);
  }
  ;

argument_name :
  IDENTIFIER
  {
    $$ = $1;
  };
  ;

instance_line :
  object_id
  {
    ldr_act_start_instance (ldr_Current_context, $1);
  }
  |
  object_id constant_list
  {
    ldr_act_start_instance (ldr_Current_context, $1);
    loader_process_constants ($2);
  }
  |
  constant_list
  {
    ldr_act_start_instance (ldr_Current_context, -1);
    loader_process_constants ($1);
  }
  ;

object_id :
  OID_
  {
    $$ = $1;
  }
  ;

constant_list :
  constant
  {
    DBG_PRINT ("constant");
    $$ = loader_append_constant_list (NULL, $1);
  }
  |
  constant_list constant
  {
    DBG_PRINT ("constant_list constant");
    $$ = loader_append_constant_list ($1, $2);
  }
  ;

constant :
  ansi_string 		{ $$ = $1; }
  | dq_string		{ $$ = $1; }
  | nchar_string 	{ $$ = $1; }
  | bit_string 		{ $$ = $1; }
  | sql2_date 		{ $$ = $1; }
  | sql2_time 		{ $$ = $1; }
  | sql2_timestamp 	{ $$ = $1; }
  | utime 		{ $$ = $1; }
  | sql2_datetime 	{ $$ = $1; }
  | NULL_         	{ $$ = loader_make_constant(LDR_NULL, NULL); }
  | TIME_LIT4     	{ $$ = loader_make_constant(LDR_TIME, $1); }
  | TIME_LIT42    	{ $$ = loader_make_constant(LDR_TIME, $1); }
  | TIME_LIT3     	{ $$ = loader_make_constant(LDR_TIME, $1); }
  | TIME_LIT31    	{ $$ = loader_make_constant(LDR_TIME, $1); }
  | TIME_LIT2     	{ $$ = loader_make_constant(LDR_TIME, $1); }
  | TIME_LIT1     	{ $$ = loader_make_constant(LDR_TIME, $1); }
  | INT_LIT       	{ $$ = loader_make_constant(LDR_INT, $1); }
  | REAL_LIT
  {
    if (strchr ($1->val, 'F') != NULL || strchr ($1->val, 'f') != NULL)
      {
        $$ = loader_make_constant (LDR_FLOAT, $1);
      }
    else if (strchr ($1->val, 'E') != NULL || strchr ($1->val, 'e') != NULL)
      {
        $$ = loader_make_constant (LDR_DOUBLE, $1);
      }
    else
      {
        $$ = loader_make_constant (LDR_NUMERIC, $1);
      }
  }
  | DATE_LIT2     	{ $$ = loader_make_constant(LDR_DATE, $1); }
  | monetary		{ $$ = $1; }
  | object_reference	{ $$ = $1; }
  | set_constant	{ $$ = $1; }
  | system_object_reference	{ $$ = $1; }
  ;

ansi_string :
  Quote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_STR, $2);
  }
  ;

nchar_string :
  NQuote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_NSTR, $2);
  }
  ;

dq_string
  :DQuote DQS_String_Body
  {
    $$ = loader_make_constant (LDR_STR, $2);
  }
  ;

sql2_date :
  DATE_ Quote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_DATE, $3);
  }
  ;

sql2_time :
  TIME Quote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_TIME, $3);
  }
  ;

sql2_timestamp :
  TIMESTAMP Quote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_TIMESTAMP, $3);
  }
  ;

utime :
  UTIME Quote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_TIMESTAMP, $3);
  }
  ;

sql2_datetime :
  DATETIME Quote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_DATETIME, $3);
  }
  ;

bit_string :
  BQuote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_BSTR, $2);
  }
  |
  XQuote SQS_String_Body
  {
    $$ = loader_make_constant (LDR_XSTR, $2);
  }
  ;

object_reference :
  OBJECT_REFERENCE class_identifier
  {
    $$ = loader_make_constant (LDR_CLASS_OID, $2);
  }
  |
  OBJECT_REFERENCE class_identifier instance_number
  {
    $2->instance_number = $3;
    $$ = loader_make_constant (LDR_OID, $2);
  }
  ;

class_identifier:
  INT_LIT
  {
    LDR_OBJECT_REF *ref;

    ref = (LDR_OBJECT_REF *) malloc (sizeof (LDR_OBJECT_REF));
    if (ref == NULL)
      {
	er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE,
	        ER_OUT_OF_VIRTUAL_MEMORY, 1, sizeof (LDR_OBJECT_REF));
	YYABORT;
      }

    ref->class_id = $1;
    ref->class_name = NULL;
    ref->instance_number = NULL;
    
    $$ = ref;
  }
  |
  IDENTIFIER
  {
    LDR_OBJECT_REF *ref;

    ref = (LDR_OBJECT_REF *) malloc (sizeof (LDR_OBJECT_REF));
    if (ref == NULL)
      {
	er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE,
	        ER_OUT_OF_VIRTUAL_MEMORY, 1, sizeof (LDR_OBJECT_REF));
      	YYABORT;
      }

    ref->class_id = NULL;
    ref->class_name = $1;
    ref->instance_number = NULL;
    
    $$ = ref;
  }
  ;

instance_number :
  OID_DELIMETER INT_LIT
  {
    $$ = $2;
  }
  ;

set_constant :
  SET_START_BRACE SET_END_BRACE
  {
    $$ = loader_make_constant (LDR_COLLECTION, NULL);
  }
  |
  SET_START_BRACE set_elements SET_END_BRACE
  {
    $$ = loader_make_constant (LDR_COLLECTION, $2);
  }
  ;

set_elements:
  constant
  {
    DBG_PRINT ("constant");
    $$ = loader_append_constant_list (NULL, $1);
  }
  |
  set_elements constant
  {
    DBG_PRINT ("set_elements constant");
    $$ = loader_append_constant_list ($1, $2);
  }
  |
  set_elements COMMA constant
  {
    DBG_PRINT ("set_elements COMMA constant");
    $$ = loader_append_constant_list ($1, $3);
  }
  |
  set_elements NL constant
  {
    DBG_PRINT ("set_elements NL constant");
    $$ = loader_append_constant_list ($1, $3);
  }
  |
  set_elements COMMA NL constant
  {
    DBG_PRINT ("set_elements COMMA NL constant");
    $$ = loader_append_constant_list ($1, $4);
  }
  ;

system_object_reference :
  ref_type Quote SQS_String_Body
  {
    $$ = loader_make_constant ($1, $3);
  }
  ;

ref_type :
  REF_ELO_INT { $$ = LDR_ELO_INT; }
  |
  REF_ELO_EXT { $$ = LDR_ELO_EXT; }
  |
  REF_USER { $$ = LDR_SYS_USER; }
  |
  REF_CLASS { $$ = LDR_SYS_CLASS; }
  ;

currency :
  DOLLAR_SYMBOL | YEN_SYMBOL | WON_SYMBOL | BACKSLASH;

monetary :
  currency REAL_LIT
  {
    $$ = loader_make_constant (LDR_MONETARY, $2);
  }
  ;
%%

static LDR_STRING *
loader_append_string_list (LDR_STRING * head, LDR_STRING * tail)
{
  tail->next = NULL;
  tail->last = NULL;

  if (head)
    {
      head->last->next = tail;
    }
  else
    {
      head = tail;
    }

  head->last = tail;
  return head;
}

static LDR_CLASS_COMMAND_SPEC *
loader_make_class_command_spec (int qualifier, LDR_STRING * attr_list,
			        LDR_CONSTRUCTOR_SPEC * ctor_spec)
{
  LDR_CLASS_COMMAND_SPEC *spec;

  spec = (LDR_CLASS_COMMAND_SPEC *) malloc (sizeof (LDR_CLASS_COMMAND_SPEC));
  if (spec == NULL)
    {
      er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE,
	      ER_OUT_OF_VIRTUAL_MEMORY, 1, sizeof (LDR_CLASS_COMMAND_SPEC));
      return NULL;
    }

  spec->qualifier = qualifier;
  spec->attr_list = attr_list;
  spec->ctor_spec = ctor_spec;

  return spec;
}

static LDR_CONSTANT *
loader_make_constant (int type, void *val)
{
  LDR_CONSTANT *con;

  if (constant_Pool_idx < CONSTANT_POOL_SIZE)
    {
      con = &(constant_Pool[constant_Pool_idx]);
      constant_Pool_idx++;
      con->need_free = false;
    }
  else
    {
      con = (LDR_CONSTANT *) malloc (sizeof (LDR_CONSTANT));
      if (con == NULL)
	{
          er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE,
	          ER_OUT_OF_VIRTUAL_MEMORY, 1, sizeof (LDR_CONSTANT));
	  return NULL;
	}
      con->need_free = true;
    }

  con->type = type;
  con->val = val;

  return con;
}

static LDR_CONSTANT *
loader_append_constant_list (LDR_CONSTANT * head, LDR_CONSTANT * tail)
{
  tail->next = NULL;
  tail->last = NULL;

  if (head)
    {
      head->last->next = tail;
    }
  else
    {
      head = tail;
    }

  head->last = tail;
  return head;
}

static void
loader_process_object_ref (LDR_OBJECT_REF * ref, int type)
{
  bool ignore_class = false;
  char *class_name;
  DB_OBJECT *ref_class = NULL;

  assert (ref != NULL);
  if (ref == NULL)
    {
      return;
    }

  if (ref->class_id && ref->class_id->val)
    {
      ldr_act_set_ref_class_id (ldr_Current_context,
				atoi (ref->class_id->val));
    }
  else
    {
      ldr_act_set_ref_class (ldr_Current_context, ref->class_name->val);
    }

  if (ref->instance_number && ref->instance_number->val)
    {
      ldr_act_set_instance_id (ldr_Current_context,
			       atoi (ref->instance_number->val));
    }
  else
    {
      /*ldr_act_set_instance_id(ldr_Current_context, 0); *//* right?? */
    }

  ref_class = ldr_act_get_ref_class (ldr_Current_context);
  if (ref_class != NULL)
    {
      class_name = db_get_class_name (ref_class);
      ignore_class = ldr_is_ignore_class (class_name, strlen (class_name));
    }

  if (type == LDR_OID)
    {
      (*ldr_act) (ldr_Current_context, ref->instance_number->val,
		  (ref->instance_number == NULL
		   && ref->instance_number->val) ? 0 : ref->
		  instance_number->size, (ignore_class) ? LDR_NULL : LDR_OID);
    }
  else
    {
      /* right ?? */
      if (ref->class_name)
	{
	  (*ldr_act) (ldr_Current_context, ref->class_name->val,
		      ref->class_name->size,
		      (ignore_class) ? LDR_NULL : LDR_CLASS_OID);
	}
      else
	{
	  (*ldr_act) (ldr_Current_context, ref->class_id->val,
		      (ref->class_id == NULL
		       && ref->class_id->val) ? 0 : ref->class_id->size,
		      (ignore_class) ? LDR_NULL : LDR_CLASS_OID);
	}
    }

  if (ref->class_id)
    {
      FREE_STRING (ref->class_id);
    }

  if (ref->class_name)
    {
      FREE_STRING (ref->class_name);
    }

  if (ref->instance_number)
    {
      FREE_STRING (ref->instance_number);
    }

  free_and_init (ref);
}

static void
loader_process_constants (LDR_CONSTANT * cons)
{
  LDR_CONSTANT *c, *save;

  for (c = cons; c; c = save)
    {
      save = c->next;

      switch (c->type)
	{
	case LDR_NULL:
	  (*ldr_act) (ldr_Current_context, NULL, 0, LDR_NULL);
	  break;

	case LDR_INT:
	case LDR_FLOAT:
	case LDR_DOUBLE:
	case LDR_NUMERIC:
	case LDR_MONETARY:
	case LDR_DATE:
	case LDR_TIME:
	case LDR_TIMESTAMP:
	case LDR_DATETIME:
	case LDR_STR:
	case LDR_NSTR:
	  {
	    LDR_STRING *str = (LDR_STRING *) c->val;
	     
	    (*ldr_act) (ldr_Current_context, str->val, str->size, c->type);
	    FREE_STRING (str);
	  }
	  break;

	case LDR_BSTR:
	case LDR_XSTR:
	case LDR_ELO_INT:
	case LDR_ELO_EXT:
	case LDR_SYS_USER:
	case LDR_SYS_CLASS:
	  {
	    LDR_STRING *str = (LDR_STRING *) c->val;
	     
	    (*ldr_act) (ldr_Current_context, str->val, strlen(str->val), c->type);
	    FREE_STRING (str);
	  }
	  break;

	case LDR_OID:
	case LDR_CLASS_OID:
	  loader_process_object_ref ((LDR_OBJECT_REF *) c->val, c->type);
	  break;

	case LDR_COLLECTION:
	  (*ldr_act) (ldr_Current_context, "{", 1, LDR_COLLECTION);
	  loader_process_constants ((LDR_CONSTANT *) c->val);
	  ldr_act_attr (ldr_Current_context, NULL, 0, LDR_COLLECTION);
	  break;

	default:
	  break;
	}

      if (c->need_free)
	{
	  free_and_init (c);
	}
    }
}

void do_loader_parse(FILE *fp)
{
  loader_In_instance_line = true;

  loader_yyin = fp;
  loader_yyparse();
}

#ifdef PARSER_DEBUG
/*int main(int argc, char *argv[])
{
	loader_yyparse();
	return 0;
}
*/
#endif
