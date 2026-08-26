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

#ifndef DROPBEAR_USERMAP_H_
#define DROPBEAR_USERMAP_H_

#include "includes.h"

/*
 * A usermap maps a login username (the name the client presents) onto a
 * system uid/username plus a fixed password. The entry is described on the
 * command line as
 *
 *     login:target:password
 *
 * where "target" is either a numeric uid (e.g. "1001") or, prefixed with '@',
 * a system username (e.g. "@root") that gets resolved via getpwnam().
 *
 * When a client logs in with a username present in the map the session runs as
 * the mapped user and the password is checked against the plaintext password
 * from the map (instead of /etc/shadow).
 */
struct usermap_entry {
	char *login_name; /* the name the client logs in with */
	uid_t uid;
	gid_t gid;
	char *pw_name;    /* system username the session runs as */
	char *pw_dir;
	char *pw_shell;
	char *pw_passwd;  /* plaintext password from the map */
	struct usermap_entry *next;
};

/* Parse one "login:target:password" spec and add it to the list.
 * Exits fatally on a malformed spec or an unresolvable target. */
void usermap_add(const char *spec);
/* Read one mapping per line from filename. Lines may be empty or start with
 * '#' to be skipped. Exits fatally on error. */
void usermap_read_file(const char *filename);
/* Return the entry for login_name, or NULL if not mapped */
struct usermap_entry *usermap_lookup(const char *login_name);
void usermap_cleanup(void);

#endif /* DROPBEAR_USERMAP_H_ */
