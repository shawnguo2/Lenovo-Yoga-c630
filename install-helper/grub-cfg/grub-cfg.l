%{
	#include "grub-cfg.tab.h"
	#include <list>
	#include <string>

	unsigned int line_num = 1;
	unsigned int menu_entry_num = 0;
	unsigned int *menu_selection_list, menu_selection_list_size;
	unsigned char is_menuentry = 0;
	unsigned char is_submenu = 0;

	std::list<int> menu_entry_stack;

	void push_menu_entry_num() {
		menu_entry_stack.push_back(menu_entry_num);
		menu_entry_num = 0;
	}

	void pop_menu_entry_num() {
		menu_entry_num = menu_entry_stack.back();
		menu_entry_stack.pop_back();
	}

	unsigned int check_menu_entry_num() {
		unsigned int i, menu_entry_stack_size = menu_entry_stack.size();

		// Root show
		if ((menu_selection_list_size == 0) && (menu_entry_stack_size == 0)) return 1;

		//  Submenu show
		if (menu_selection_list_size == menu_entry_stack_size) {
			std::list<int>::iterator menu_stack_iter = menu_entry_stack.begin();
			for (i = 0; i < menu_entry_stack_size; i++) {
				if (*menu_stack_iter != menu_selection_list[i]) {
					return 0;
				}
				menu_stack_iter++;
			}
			is_submenu = 1;
			return 1;
		}

		// Element show
		if ((menu_selection_list_size - 1) == menu_entry_stack_size) {
			std::list<int>::iterator menu_stack_iter = menu_entry_stack.begin();
			for (i = 0; i < menu_entry_stack_size; i++) {
				if (*menu_stack_iter != menu_selection_list[i]) {
					return 0;
				}
				menu_stack_iter++;
			}
			if (menu_entry_num != menu_selection_list[i]) {
				return 0;
			}
			if (is_menuentry) {
				return 2;
			}
		}

		return 0;
	}
%}
%option stack
%x set_cfg insmod_cfg if_cfg submenu_cfg menuentry_cfg menuentry_title_cfg menuentry_body_cfg linux_cfg initrd_cfg
%%
^[ \t]*\n					{
	++line_num;
}
^[ \t]*background_image[^\n]*\n			{
	++line_num;
}
^[ \t]*set					{
	yy_push_state(set_cfg);
}
<set_cfg>[= \t]					;
<set_cfg>[^= \t\n]+				{
	yylval.sval = strdup(yytext);
	return SETVALUE;
}
<set_cfg>[ \t]*\n				{
	++line_num;
	yy_pop_state();
}
^[ \t]*insmod					{
	yy_push_state(insmod_cfg);
}
<insmod_cfg>[= \t]				;
<insmod_cfg>[^= \t\n]+				{
	yylval.sval = strdup(yytext);
	return INSMOD;
}
<insmod_cfg>[ \t]*\n				{
	++line_num;
	yy_pop_state();
}
^[ \t]*if					{
	yy_push_state(if_cfg);
}
<if_cfg>[^\n]*					;
<if_cfg>\n					{
	++line_num;
}
<if_cfg>[ \t]*fi[ \t]*\n			{
	++line_num;
	yy_pop_state();
}
^[ \t]*submenu					{
	menu_entry_num++;
	yy_push_state(submenu_cfg);
}
<submenu_cfg>[ \t]*--hotkey=[a-zA-Z0-9]		;
<submenu_cfg>[ \t]*['"][^'"\n]+['"]		{
	yylval.sval = strdup(yytext);
	return MENUTITLE;
}
<submenu_cfg>[ \t]*\{[ \t]*\n			{
	push_menu_entry_num();
	++line_num;
	yy_pop_state();
}
[ \t]*\}[ \t]*\n				{
	pop_menu_entry_num();
}
^[ \t]*menuentry				{
	is_menuentry = 1;
	menu_entry_num++;
	yy_push_state(menuentry_cfg);
}
<menuentry_cfg>[ \t]*--hotkey=[a-zA-Z0-9]	;
<menuentry_cfg>[ \t]*['"][^'"\n]+['"]		{
        yylval.sval = strdup(yytext);
        return MENUTITLE;
}
<menuentry_cfg>[ \t]*\{[ \t]*\n			{
	++line_num;
	BEGIN(menuentry_body_cfg);
}
<menuentry_body_cfg>^[ \t]*set			{
	yy_push_state(set_cfg);
}
<menuentry_body_cfg>^[ \t]*linux[ \t]*		{
	yy_push_state(linux_cfg);
}
<menuentry_body_cfg>^[ \t]*initrd[ \t]*		{
	yy_push_state(initrd_cfg);
}
<menuentry_body_cfg>[ \t]*\}[ \t]*\n		{
	is_menuentry = 0;
	++line_num;
	yy_pop_state();
}
<linux_cfg>[^\n]+				{
	yylval.sval = strdup(yytext);
	return LINUX;
}
<linux_cfg>[ \t]*\n				{
	++line_num;
	yy_pop_state();
}
<initrd_cfg>[^\n]+				{
	yylval.sval = strdup(yytext);
	return INITRD;
}
<initrd_cfg>[ \t]*\n				{
	++line_num;
	yy_pop_state();
}
%%