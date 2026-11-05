#!/usr/bin/env python3
"""Source-contract checks, not evidence of kernel execution or a Mach runtime pass."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
def source(path):
    return (root / path).read_text(encoding="utf-8")

client = source("BaseBin/libroothider/src/jailbreakd.c")
main = source("BaseBin/jailbreakd/src/main.m")
server = source("BaseBin/jailbreakd/src/isolation_server.c")
mach = source("BaseBin/libroothider/src/app_isolation_mach.c")
dyld = source("BaseBin/libroothider/src/dyld_patch.m")
domain = source("BaseBin/launchdhook/src/jbserver/jbdomain_roothide.c")
ready = client.split("bool jbdIsolationHelperReady(void)", 1)[1].split("int jbdAppIsolationRepair", 1)[0]
repair = client.split("int jbdAppIsolationRepair", 1)[1].split("int jbdSpawnExecStart", 1)[0]
assert "RH_ISOLATION_PING" in ready and "rh_isolation_mach_call" in ready
assert "return MACH_PORT_VALID" not in ready
assert "xpc_pipe_routine" not in repair and "dispatch_async" not in repair
assert "isolation_copy_service(true" in repair
assert "__firstLoad || !__jailbreakd_initialized" in client
assert "isolationVerified = false" in client and "isolationGeneration == generation" in client
assert main.index("if(ret != 0)") < main.index("mach_port_t isolationPort")
assert main.index('getenv("RESPAWN_REQUIRED")') < main.index("mach_port_t isolationPort")
assert main.index("jailbreakd_start_isolation_server();") < main.index("jbdCheckinWithIsolation(isolationPort)")
assert "jbdIsolationHelperReady" not in main and "jbdIsolationHelperReady" not in server
assert "isolation-capability" in client and "isolation-capability" in domain
assert "jbdRegisterIsolationHelper(callerToken, isolationCapability)" in domain
assert "dispatch_async" not in server and "jbserver_xpc_send_dict" not in server
assert "RH_ISOLATION_REPAIR_MS" in repair
assert "MACH_SEND_TIMEOUT" in mach and "MACH_RCV_TIMEOUT" in mach
assert "mach_port_destroy(mach_task_self(), reply_port)" in mach
assert "reply->nonce != request.nonce" in mach
assert "audit_token_to_pidversion(trailer->msgh_audit) != helper_pidversion" in mach
assert "rh_isolation_request_cancelled" in server
assert "proc_fix_spinlock_strict_checked(request->pid, request->pidversion" in server
assert "SIGCONT" not in server
assert "audit_token_to_pidversion(token) != isolationGuard->pidversion" in dyld
assert "current != isolationGuard->proc" in dyld
assert "proc_task(current) != isolationGuard->kernel_task" in dyld
assert "cooperative" in dyld and "narrow race" in dyld
assert "pinnedProc" not in dyld and "proc_rele(resolvedProc)" not in dyld
hook = dyld.split("int hook_dyld_function(", 1)[1].split("int proc_patch_dyld_internal", 1)[0]
assert hook.count("isolation_guard_allows_task") == 7
assert "remoteLoadAddress && isolation_guard_allows_task(task)" in dyld
print("PASS: source wiring/initialization/cancellation contracts (static only)")
