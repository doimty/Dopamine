# Experimental app isolation with prelaunch spinlock repair

## Status and scope

This repair branch (`fix/merge-isolation-20261105`, based on the merged `a8f0b01`) keeps the old automatic isolation feature while fixing its integration contracts. Only an effectively blacklisted, verified main executable on a supported device is eligible, with a global switch and per-app opt-out. Source changes and host tests do not change the connected phone, replace an installed engine, or request a reboot.

The aim is to combine genuine non-injection of the normal RootHide chain with existing server-side full-blacklist treatment, while retaining the existing iOS15 arm64e loadDyldCache repair. This is not a promise of zero spinlock panics, an undetectable jailbreak, or a complete stock process. It does not falsify dyld image lists or other detection results.

## Eligible route

All of these must be true:

- The process is already effectively fully blacklisted by the existing RootHide/fork whitelist policy.
- It is the verified main executable of an ordinary removable application bundle.
- Platform is iOS15 arm64e, the existing global dyld fix and isolation switches are enabled, initial activation is finished, and a bounded v2 PING verifies the helper's receive loop.
- Effective blacklist and opt-out are read from one retained RootHide configuration snapshot. A malformed/temporarily unreadable file preserves both last-good values together. Eligibility independently verifies the canonical top-level bundle's regular executable, rather than assuming every path below its container is an application main program.
- The per-bundle `appconfigSpinlockSafe` entry is entirely optional now. The route
  is automatic for every effectively blacklisted app on a supported device; an
  explicit plist Boolean `false` opts one app out, anything else keeps it on.
- TrollStore and TrollStore Lite applications are eligible too. Lite keeps the
  legacy pre-launch trust grant, which is re-issued from launchd before the repair.

System processes, daemons, arbitrary helpers and unsupported platforms cannot enter this route. If the platform gate fails or an app opts out, the old full-blacklist route remains in force. Extension and ActivePrewarm/DYLD_USE_CLOSURES restrictions retain their original precedence, even for opted-in apps. This first candidate does not restore blocked extensions or prewarming.

Configuration in the EXISTING `jbroot:/var/mobile/Library/RootHide/RootHideConfig.plist`
is now only an opt-out:

```text
appconfig:                     # existing RootHide blacklist configuration
  com.example.application: true
appconfigSpinlockSafe:          # optional; only Boolean false disables the route
  com.example.application: false
```

No preference file is shipped or written by the build. Removing the entry, or
setting it to true, keeps the automatic behaviour. Changes require a fresh app
process; existing running processes cannot be reverted by a config edit.

## What the new route preserves and changes

- The PID output slot is registered with the existing blacklist BEFORE raw spawn and passed directly to the kernel. It remains registered during the repair request and optional resume, then is committed using PID and PID version.
- Existing launchd-hosted jailbreak service denials and selected launchd/LaunchServices/preference-query filtering continue to use that same blacklisted PID. The child is not granted a check-in exemption.
- Raw original spawn does not add normal systemhook/tweak injection. A checked deep environment copy removes safe-mode markers and only known RootHide-owned DYLD_INSERT_LIBRARIES entries. Unrelated libraries, relative paths, malformed paths and App-embedded load commands are not secretly rewritten, so zero foreign images is not guaranteed.
- The child is forced START_SUSPENDED before creation. Attribute errors abort before spawn. Original attribute flags are restored afterward; that userspace operation does not resume the already-created child.
- Strict repair uses a dedicated fixed-layout Mach v2 request from launchd for its own paused child, binding PID version, nonce, operation and an absolute deadline. It has bounded send/receive waits and one fresh reply receive right per request. An originally suspended child does not silently substitute csflags-only handling.
- The dedicated service port is offered through the existing helper check-in, then verified with a real bounded PING; allocating a port alone never establishes readiness. Old or mismatched helpers leave this route unavailable. The original XPC request1007/protocol1 remains a legacy interface, not the transport used by the repaired strict route.
- The acknowledgment means the prelaunch repair-hook INSTALLATION succeeded. The server never resumes the child. Launchd resumes only after validating the acknowledgment and only if the caller originally requested a running child.
- Any restoration/repair/resume failure after creation requests termination of only that child, keeps its published PID, and never retries native spawn unpatched. Returning native success after creation allows launchd to observe the real child's exit; it is not a claim that the application initialized successfully.
- Complete function/trampoline spans and mapped addresses are checked before the strict route writes child memory. The patched trampoline and entry must survive header-page removal.

The original blacklisted TrollStoreLite/signing route, Choicy route, ordinary injected processes and global mode remain separate. No instruction in this candidate deletes RootHide infrastructure libraries globally.

## Verification

`bash scripts/test-app-isolation.sh` compiles the actual production decision/filter and spawn-lifecycle modules. The fixtures do not spawn, signal, patch or connect to a device. They cover:

1. All2048 route-flag combinations and explicit legacy behavior when opt-in is off.
2. Effective blacklist/ordinary-app/TrollStore/architecture/dyld gates, extension/prewarm rejection and first-load precedence.
3. Exact owned-library filtering, path boundaries and aliases, preservation of unrelated environment data and input ownership.
4. Direct published-PID pointer, forced suspension before spawn, repair-before-resume and caller-suspended launches.
5. get/set/spawn/restore/repair/resume/termination fault paths; no PID0/PID1 signalling, no retry and errno preservation.
6. Patch/trampoline range and integer-overflow boundaries.
7. Real host XPC dictionaries for valid, old, missing, malformed and wrong-type repair acknowledgments.

The CI additionally runs production Foundation/path/config/whitelist integration tests (`scripts/test-app-isolation-integration.py`), real host Mach transport tests (`scripts/test-app-isolation-mach.sh`), update identity/version tests (`scripts/test-update-contracts.py`) and the existing configuration-cache regressions. These tests exercise the production input construction instead of treating hand-filled policy booleans as a complete integration proof.

The CI also builds the actual launchdhook, libroothider and jailbreakd integration for arm64/arm64e and verifies the byte-identical IPA/TIPA, package ID, executable modes, paired basebin versions and hashes. Passing host tests does not prove actual kernel mappings or permissions on the phone. App installation and runtime basebin activation must be verified separately.

## Remaining limitations and device acceptance

- The strict function installs a hook before the child executes. The original shared-cache runtime remapping happens AFTER resume. Existing code does not report every signature/mmap/subcache failure; a v2 acknowledgment is not verification of those later results.
- The new transport bounds the client's Mach send/receive wait, and the checked repair cooperatively tests cancellation and target identity before remote writes. It does not preempt an in-flight kernel primitive. `proc_find` does not acquire a real proc reference, so checks and writes retain a narrow race window; retaining a Mach task right is not a claim of atomic BSD process pinning.
- Existing assertions, kernel-offset discovery and legacy helper IPC remain separate failure points. They are not silently converted to the new transport or covered by its deadlines.
- Partial low-level patch failure is not a rollback guarantee. That is why the child is terminated and never released/retried after any uncertain repair.
- Private cache mappings, the small dyld function patch, helper code mappings and pmap permissions are real and can be observable. Keeping necessary repair and being indistinguishable from stock are not the same objective.
- Only a separately authorized controlled test should establish effective blacklist membership, ordinary-app eligibility, actual strict repair acknowledgment, existing native dyld identity, RX/private executable-cache mappings, absence of the normal owned injected modules, unchanged jailbreak API denials, and normal foreground/background behavior. Installation, blacklist edits and restart are not performed automatically.
- Keep a known-good Dopamine and recovery path. Do not use a banking/work/critical app as the first experimental target.

## Relationship to the earlier startup patch

A Chinese, step-by-step device acceptance checklist is available in [APP_ISOLATION_VALIDATION_ZH.md](APP_ISOLATION_VALIDATION_ZH.md). It is a plan, not a record of device tests performed.

The libhooker22/23 dyld fork-SPI misuse fix is a separate engine change. This Dopamine isolation route does not silently install that engine patch and does not claim to repair every unrelated launchd or plugin incompatibility.
