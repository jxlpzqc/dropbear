/*
 * Dropbear - a SSH2 server
 *
 * Copyright (c) 2026 Chengzi
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE. */

#include "includes.h"
#include "usermap.h"
#include "dbutil.h"
#include "buffer.h"

static struct usermap_entry *usermap_list = NULL;

/* Append an already-filled entry to the list */
static void usermap_append(struct usermap_entry *entry) {
	struct usermap_entry **link = &usermap_list;
	while (*link) {
		link = &(*link)->next;
	}
	*link = entry;
}

void usermap_add(const char *spec) {
	char *login = NULL, *target = NULL, *password = NULL;
	char *tmp = NULL;
	struct passwd *pw = NULL;
	struct usermap_entry *entry = NULL;
	unsigned int uid = 0;

	if (!spec || spec[0] == '\0') {
		dropbear_exit("Bad usermap entry");
	}

	/* format: login:target:password */
	tmp = m_strdup(spec);
	login = tmp;
	target = strchr(login, ':');
	if (!target) {
		dropbear_exit("Bad usermap entry '%s', expected 'user:@uid_or_username:password'",
			spec);
	}
	*target++ = '\0';
	password = strchr(target, ':');
	if (!password) {
		dropbear_exit("Bad usermap entry '%s', expected 'user:@uid_or_username:password'",
			spec);
	}
	*password++ = '\0';

	if (login[0] == '\0' || password[0] == '\0') {
		dropbear_exit("Bad usermap entry '%s'", spec);
	}

	if (target[0] == '@') {
		/* target is a username */
		pw = getpwnam(target + 1);
		if (!pw) {
			dropbear_exit("usermap target user '%s' does not exist", target + 1);
		}
	} else {
		/* target is a numeric uid */
		if (m_str_to_uint(target, &uid) == DROPBEAR_FAILURE) {
			dropbear_exit("Bad usermap target '%s'", target);
		}
		pw = getpwuid((uid_t)uid);
		if (!pw) {
			dropbear_exit("usermap target uid %u does not exist", uid);
		}
	}

	entry = m_malloc(sizeof(*entry));
	memset(entry, 0, sizeof(*entry));
	entry->login_name = m_strdup(login);
	entry->uid = pw->pw_uid;
	entry->gid = pw->pw_gid;
	entry->pw_name = m_strdup(pw->pw_name);
	entry->pw_dir = m_strdup(pw->pw_dir);
	entry->pw_shell = m_strdup(pw->pw_shell);
	entry->pw_passwd = m_strdup(password);
	entry->next = NULL;

	m_free(tmp);
	usermap_append(entry);

	TRACE(("Added usermap entry '%s' -> '%s' (%d)", entry->login_name,
		entry->pw_name, (int)entry->uid))
}

void usermap_read_file(const char *filename) {
	FILE *f = NULL;
	buffer *line = NULL;

	f = fopen(filename, "r");
	if (!f) {
		dropbear_exit("Couldn't open usermap file '%s'", filename);
	}

	line = buf_new(DROPBEAR_MAX_LINE_LENGTH);
	while (buf_getline(line, f) == DROPBEAR_SUCCESS) {
		char *s = NULL;
		/* buf_getline returns a buffer without the trailing newline */
		s = m_malloc(line->len + 1);
		memcpy(s, line->data, line->len);
		s[line->len] = '\0';

		/* skip empty lines and comments */
		if (s[0] != '\0' && s[0] != '#') {
			usermap_add(s);
		}
		m_free(s);
	}

	buf_free(line);
	fclose(f);
}

struct usermap_entry *usermap_lookup(const char *login_name) {
	struct usermap_entry *entry;
	for (entry = usermap_list; entry != NULL; entry = entry->next) {
		if (strcmp(entry->login_name, login_name) == 0) {
			return entry;
		}
	}
	return NULL;
}

void usermap_cleanup(void) {
	struct usermap_entry *entry = usermap_list;
	while (entry) {
		struct usermap_entry *next = entry->next;
		m_free(entry->login_name);
		m_free(entry->pw_name);
		m_free(entry->pw_dir);
		m_free(entry->pw_shell);
		m_free(entry->pw_passwd);
		m_free(entry);
		entry = next;
	}
	usermap_list = NULL;
}
