#ifndef APP_ISOLATION_HOST_LIBJAILBREAK_H
#define APP_ISOLATION_HOST_LIBJAILBREAK_H

/* Only the root provider/log sink is substituted. Production jbroot conversion,
 * blacklist/eligibility, configuration cache and whitelist readers are compiled.
 * No jailbreak primitive, device process or network is used by these tests. */
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <alloca.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <bsm/audit.h>
#include <xpc/xpc.h>
#include "jbroot.h"

#define JBLogDebug(...) ((void)0)
#define JBLogError(...) ((void)0)

#endif
