# Experimental app isolation with prelaunch spinlock repair

## Status and scope

This is an opt-in research candidate on `feature/app-isolation-spinlock`, based on Dopamine `c2b9cfe`. It does not change the connected phone, replace an installed engine, enable any app, or request a reboot. Default behavior is unchanged when the new key is absent.

The aim is to combine genuine non-injection of the normal RootHide chain with existing server-side full-blacklist treatment, while retaining the existing iOS15 arm64e loadDyldCache repair. This is not a promise of zero spinlock panics, an undetectable jailbreak, or a complete stock process. It does not falsify dyld image lists or other detection results.

## Eligible route

All of these must be true:

- The process is already effectively fully blacklisted by the existing RootHide/fork whitelist policy.
- It is the verified main executable of an ordinary removable application bundle.
- Neither `_TrollStore` nor `_TrollStoreLite` is present for that application.
- Platform is iOS15 arm64e and the existing global dyld fix is enabled.
- The per-bundle `appconfigSpinlockSafe` entry is the actual plist Boolean `true`.

System processes, daemons, arbitrary helpers, unknown bundles and unsupported platforms cannot be opted into this route by bundle name alone. If the toggle is off or eligibility fails, the old full-blacklist route remains in force. Extension and ActivePrewarm/DYLD_USE_CLOSURES restrictions retain their original precedence, even for opted-in apps. This first candidate does not restore blocked extensions or prewarming.

Configuration format in the EXISTING `jbroot:/var/mobile/Library/RootHide/RootHideConfig.plist`:

```text
appconfig:                     # existing RootHide blacklist configuration
  com.example.application: true
appconfigSpinlockSafe:          # new experimental opt-in; absent by default
  com.example.application: true
```

The new entry does not establish blacklist membership by itself and cannot override this fork's executable/system allowlists. Do not replace the whole config with this example; it illustrates two keys only. No preference file is shipped or written by the build, and there is no GUI toggle for this experimental key yet. Disable by removing only the target key from appconfigSpinlockSafe; all changes require a fresh app process. Existing running processes cannot be reverted/unloaded by a config edit.

## What the new route preserves and changes

- The PID output slot is registered with the existing blacklist BEFORE raw spawn and passed directly to the kernel. It remains registered during the repair request and optional resume, then is committed using PID and PID version.
- Existing launchd-hosted jailbreak service denials and selected launchd/LaunchServices/preference-query filtering continue to use that same blacklisted PID. The child is not granted a check-in exemption.
- Raw original spawn does not add normal systemhook/tweak injection. A checked deep environment copy removes safe-mode markers and only known RootHide-owned DYLD_INSERT_LIBRARIES entries. Unrelated libraries, relative paths, malformed paths and App-embedded load commands are not secretly rewritten, so zero foreign images is not guaranteed.
- The child is forced START_SUSPENDED before creation. Attribute errors abort before spawn. Original attribute flags are restored afterward; that userspace operation does not resume the already-created child.
- A new IPC request1007 is accepted only from launchd for its own paused child on the supported platform with dyld fix enabled. Unlike the legacy request, an originally suspended child does not silently substitute csflags-only handling.
- Reply protocol1 requires an explicitly typed result and repair-applied acknowledgment. Old/mismatched helpers returning empty replies fail closed.
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

The CI also builds the actual launchdhook, libroothider and jailbreakd integration for arm64/arm64e as part of the complete application. Passing host tests does not prove actual kernel mappings or permissions on the phone.

## Remaining limitations and device acceptance

- `proc_fix_spinlock` installs a hook before the child executes. The original shared-cache runtime remapping happens AFTER resume. Existing code does not report every signature/mmap/subcache failure and this candidate does not pretend that protocol1 verifies those later results.
- Existing assertions, kernel-offset discovery, synchronous helper IPC and low-level VM operations remain potential failure points. Helper unavailability/invalid replies are rejected; there is no newly proven bounded timeout/cancellation protocol for a stuck helper.
- Partial low-level patch failure is not a rollback guarantee. That is why the child is terminated and never released/retried after any uncertain repair.
- Private cache mappings, the small dyld function patch, helper code mappings and pmap permissions are real and can be observable. Keeping necessary repair and being indistinguishable from stock are not the same objective.
- Only a separately authorized controlled test should establish effective blacklist membership, ordinary-app eligibility, actual strict repair acknowledgment, existing native dyld identity, RX/private executable-cache mappings, absence of the normal owned injected modules, unchanged jailbreak API denials, and normal foreground/background behavior. Installation, blacklist edits and restart are not performed automatically.
- Keep a known-good Dopamine and recovery path. Do not use a banking/work/critical app as the first experimental target.

## Relationship to the earlier startup patch

The libhooker22/23 dyld fork-SPI misuse fix is a separate engine change. This Dopamine isolation route does not silently install that engine patch and does not claim to repair every unrelated launchd or plugin incompatibility.
