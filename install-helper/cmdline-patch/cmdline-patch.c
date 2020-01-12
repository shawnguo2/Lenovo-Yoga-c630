#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libaudit.h>
#include <unistd.h>
#include <ev.h>
#include <errno.h>
#include "auditctl-llist.h"

int fd;

void monitoring(struct ev_loop *loop, struct ev_io *io, int revents) {
	const char prockey[] = "key=\"mount_proc\"";
	struct audit_reply reply;

	int rc = audit_get_reply(fd, &reply, GET_REPLY_NONBLOCKING, 0);
	if (rc > 0) {
		/* If we get done or error, break out */
		if (reply.type == NLMSG_DONE)
			return;

		if (reply.type == NLMSG_ERROR && reply.error->error)
			return;

		if (reply.type == AUDIT_SYSCALL && (strstr(reply.message, prockey) != NULL)) {
			printf("Event: Type=%s Message=%.*s\n",
				audit_msg_type_to_name(reply.type),
				reply.len,
				reply.message);
			ev_break(EV_A_ EVBREAK_ALL);
		}
	}
}

/* Returns 0 for success and -1 for failure */
int delete_all_rules(int fd)
{
	int seq, i, rc, retval = 0;
	int timeout = 40; /* tenths of seconds */
	struct audit_reply rep;
	fd_set read_mask;
	llist l;
	lnode *n;

	/* list the rules */
	seq = audit_request_rules_list_data(fd);
	if (seq <= 0)
		return -1;

	FD_ZERO(&read_mask);
	FD_SET(fd, &read_mask);
	list_create(&l);

	for (i = 0; i < timeout; i++) {
		struct timeval t;

		t.tv_sec  = 0;
		t.tv_usec = 100000; /* .1 second */
		do {
			rc = select(fd+1, &read_mask, NULL, NULL, &t);
		} while (rc < 0 && errno == EINTR);
		// We'll try to read just in case
		rc = audit_get_reply(fd, &rep, GET_REPLY_NONBLOCKING, 0);
		if (rc > 0) {
			/* Reset timeout */
			i = 0;

			/* Don't make decisions based on wrong packet */
			if (rep.nlh->nlmsg_seq != seq)
				continue;

			/* If we get done or error, break out */
			if (rep.type == NLMSG_DONE)
				break;

			if (rep.type == NLMSG_ERROR && rep.error->error) {
				retval = -1;
				break;
			}

			/* If its not what we are expecting, keep looping */
			if (rep.type != AUDIT_LIST_RULES)
				continue;

			//if (key_match(rep.ruledata))
				list_append(&l, rep.ruledata,
					sizeof(struct audit_rule_data) +
					rep.ruledata->buflen);
		}
	}
	list_first(&l);
	n = l.cur;
	if (retval == 0) {
		while (n) {
			struct audit_rule_data *ruledata = n->r;
			rc = audit_delete_rule_data(fd, ruledata, ruledata->flags, ruledata->action);
			if (rc < 0) {
				retval = -1;
				break;
			}
			n = list_next(&l);
		}
	}
	list_clear(&l);

	return retval;
}

int main() {
	int rc = nice(-4);
	if (rc == -1 && errno) {
		printf("Error: Could not change nice level.\n");
		return 1;
	}

	fd = audit_open();
	struct audit_rule_data* rule_new = new audit_rule_data();

	delete_all_rules(fd);

	audit_rule_syscallbyname_data(rule_new, "mount");
	// Set extra filter, for example, follow the user with id=1000.
	char arch[] = "arch=b64";
	audit_rule_fieldpair_data(&rule_new, arch, AUDIT_FILTER_EXIT);
	char path[] = "path=/projects/Lenovo/Lenovo-Yoga-c630/install-helper/cmdline-patch/tmp_dir";
	audit_rule_fieldpair_data(&rule_new, path, AUDIT_FILTER_EXIT);
	char key[] = "key=mount_proc";
	audit_rule_fieldpair_data(&rule_new, key, AUDIT_FILTER_EXIT);
	audit_add_rule_data(fd, rule_new, AUDIT_FILTER_EXIT, AUDIT_ALWAYS);

	if ((audit_is_enabled(fd) < 2) && (audit_set_enabled(fd, 1) < 0)) {
		printf("Failed to enable.\n");
		return 1;
	}
	if (audit_set_pid(fd, getpid(), WAIT_YES) < 0) {
		printf("Failed to set pid.\n");
		return 1;
	}

	struct ev_io monitor;
	struct ev_loop *loop = ev_default_loop(EVFLAG_NOENV);

	ev_io_init(&monitor, monitoring, fd, EV_READ);
	ev_io_start(loop, &monitor);

	ev_run(loop, 0);

	ev_io_stop (loop, &monitor);
	ev_default_destroy();

	audit_close(fd);
	return 0;
}
