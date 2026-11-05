#import <Foundation/Foundation.h>

#include <libjailbreak/libjailbreak.h>
#include "common.h"
#include "_configuration.h"
#include <sys/stat.h>

// Host integration tests override only the container root, not the resolver.
#ifndef APP_PATH_PREFIX
#define APP_PATH_PREFIX "/private/var/containers/Bundle/Application/"
#endif
#define NULL_UUID "00000000-0000-0000-0000-000000000000"

NSString *getAppBundlePathFromSpawnPath(const char *path)
{
    if (!path) return nil;

    char abspath[PATH_MAX];
    if (!realpath(path, abspath)) return nil;

    if (strncmp(abspath, APP_PATH_PREFIX, sizeof(APP_PATH_PREFIX) - 1) != 0)
        return nil;

    char *p1 = abspath + sizeof(APP_PATH_PREFIX) - 1;
    char *p2 = strchr(p1, '/');
    if (!p2) return nil;

    //is normal app or jailbroken app/daemon?
    if ((p2 - p1) != (sizeof(NULL_UUID) - 1))
        return nil;

    char *p = strstr(p2, ".app/");
    if (!p) return nil;

    p[sizeof(".app/") - 1] = '\0';

    return [NSString stringWithUTF8String:abspath];
}

// get main bundle identifier of app for (PlugIns's) executable path
NSString *getAppIdentifierFromPath(const char *path)
{
    if (!path) return nil;

    NSString *bundlePath = getAppBundlePathFromSpawnPath(path);
    if (!bundlePath) return nil;

    NSDictionary *appInfo = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
    if (![appInfo isKindOfClass:NSDictionary.class]) return nil;

    NSString *identifier = appInfo[@"CFBundleIdentifier"];
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;

    return identifier;
}

NSSet* builtinApps()
{
    static NSSet* apps = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        JBLogDebug("Initializing builtin apps set");
        apps = [NSSet setWithObjects:@"com.opa334.Dopamine-roothide", @"cn.zqbb.dopaRH", @"com.doimty.dopamine", nil];
        NSString* customBundleId = [NSString stringWithContentsOfFile:JBROOT_PATH(@"/basebin/.AppIdentifier") encoding:NSUTF8StringEncoding error:nil];
        if(customBundleId && customBundleId.length > 0) {
            JBLogDebug("Added custom bundle identifier to builtin apps: %s", customBundleId.UTF8String);
            apps = [apps setByAddingObject:customBundleId];
        }
    });
    return apps;
}

static XPC_RETURNS_RETAINED xpc_object_t copyRootHideConfig(void)
{
    return zqbb_read_dictionary(JBROOT_PATH("/var/mobile/Library/RootHide/RootHideConfig.plist"));
}

static bool isBlacklistedAppInSnapshot(const char *identifier, xpc_object_t snapshot)
{
    if (!identifier || [builtinApps() containsObject:@(identifier)]) return false;
    return zqbb_dictionary_snapshot_bool_value(snapshot, identifier, "appconfig");
}

// 从共享配置快照查询应用黑名单，保留既有 boolValue 转换规则。
bool isBlacklistedApp(const char* identifier)
{
    if (!identifier) return false;
    xpc_object_t snapshot = copyRootHideConfig();
    return isBlacklistedAppInSnapshot(identifier, snapshot);
}

// 主程序、helper 和扩展继续按原来的主 bundle 标识查询黑名单。
static bool isBlacklistedPath_orig(const char* path, xpc_object_t snapshot)
{
    if(!path) return false;
    NSString* identifier = getAppIdentifierFromPath(path);
    if(!identifier) return false;
    return isBlacklistedAppInSnapshot(identifier.UTF8String, snapshot);
}

// Eligibility is independent of opt-out. A missing override is not evidence
// that an arbitrary executable below an app container is the main executable.
static NSString *isolationAppIdentifier(const char *path)
{
    NSString *bundlePath = getAppBundlePathFromSpawnPath(path);
    if (!bundlePath) return nil;
    char bundleReal[PATH_MAX];
    if (!realpath(bundlePath.fileSystemRepresentation, bundleReal)) return nil;
    if (strncmp(bundleReal, APP_PATH_PREFIX, sizeof(APP_PATH_PREFIX) - 1) != 0) return nil;
    const char *container = bundleReal + sizeof(APP_PATH_PREFIX) - 1;
    const char *bundleName = strchr(container, '/');
    if (!bundleName || bundleName - container != sizeof(NULL_UUID) - 1 ||
        strchr(bundleName + 1, '/')) return nil;
    NSString *uuid = [[NSString alloc] initWithBytes:container length:bundleName - container encoding:NSUTF8StringEncoding];
    if (!uuid || ![[NSUUID alloc] initWithUUIDString:uuid]) return nil;
    bundlePath = [NSString stringWithUTF8String:bundleReal];

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    if (![info isKindOfClass:NSDictionary.class]) return nil;
    NSString *identifier = info[@"CFBundleIdentifier"];
    NSString *executable = info[@"CFBundleExecutable"];
    if (![identifier isKindOfClass:NSString.class] || !identifier.length ||
        ![executable isKindOfClass:NSString.class] || !executable.length ||
        [executable containsString:@"/"] ||
        [executable rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    NSString *expected = [bundlePath stringByAppendingPathComponent:executable];
    struct stat st;
    // A symlink naming a helper/outside file must not promote that file. A
    // caller's alias resolving to a regular, top-level main executable is fine.
    if (lstat(expected.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode) ||
        access(expected.fileSystemRepresentation, X_OK) != 0) return nil;
    char expectedReal[PATH_MAX], actualReal[PATH_MAX];
    if (!realpath(expected.fileSystemRepresentation, expectedReal) ||
        !realpath(path, actualReal) || strcmp(actualReal, expectedReal) != 0) return nil;
    return identifier;
}

// -1 is absent/wrong type; only an actual plist Boolean false opts an app out.
static int isolationOverrideInSnapshot(NSString *identifier, xpc_object_t snapshot)
{
    if (!identifier || !snapshot || xpc_get_type(snapshot) != XPC_TYPE_DICTIONARY) return -1;
    xpc_object_t apps = xpc_dictionary_get_value(snapshot, "appconfigSpinlockSafe");
    if (!apps || xpc_get_type(apps) != XPC_TYPE_DICTIONARY) return -1;
    xpc_object_t value = xpc_dictionary_get_value(apps, identifier.UTF8String);
    if (!value || xpc_get_type(value) != XPC_TYPE_BOOL) return -1;
    return xpc_bool_get_value(value) ? 1 : 0;
}

static int isolationOverrideValue(const char *path)
{
    NSString *identifier = isolationAppIdentifier(path);
    xpc_object_t snapshot = copyRootHideConfig();
    return isolationOverrideInSnapshot(identifier, snapshot);
}

bool appSpinlockIsolationRequested(const char *path)
{
    return isolationOverrideValue(path) == 1;
}

bool appSpinlockIsolationOptedOut(const char *path)
{
    return isolationOverrideValue(path) == 0;
}

static const char *injectPlistPath = NULL;
static const char *injectSystemPlistPath = NULL;

bool zqbb_wantsInject(const char *execName, const char *injectPath);
// 查询需要同时遵循原黑名单的进程。
static BOOL zqbb_wantsBlacklist(NSString *execName) {
    if(!execName) return NO;

    return zqbb_dictionary_bool_value(execName.UTF8String, NULL,
        JBROOT_PATH("/var/mobile/Library/RootHide/cn.zqbb.inject.wantsblacklist.plist"));
}

// 按可执行文件名判断白名单，并应用指定进程的黑名单覆盖。
static bool zqbb_isBlacklistedExec(const char *path, const char *injectPath, xpc_object_t snapshot) {
    const char *exec = strrchr(path, '/');
    if (!exec) return true;
    exec++;

    if (zqbb_wantsBlacklist([NSString stringWithUTF8String:exec])) {
        if (isBlacklistedPath_orig(path, snapshot)) return true;
    }

    if (zqbb_wantsInject(exec, injectPath))
        return false; // 在白名单则注入

    return true;
}

bool zqbb_isWhiteListForSystem(const char *path, const char *injectSystemPath);
// 存在用户白名单时切换模式，否则保留原有黑名单逻辑。
static bool isBlacklistedPathInSnapshot(const char *path, xpc_object_t snapshot) {
    if(!path) return false;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        injectPlistPath = strdup(JBROOT_PATH("/var/mobile/Library/RootHide/cn.zqbb.inject.plist"));
        injectSystemPlistPath = strdup(JBROOT_PATH("/var/mobile/Library/RootHide/cn.zqbb.inject.system.plist"));
    });
    if (!injectPlistPath) return isBlacklistedPath_orig(path, snapshot);

    if (access(injectPlistPath, F_OK) == 0){
        if (!strcmp(path, "/sbin/launchd")) return false;
        if (zqbb_isWhiteListForSystem(path, injectSystemPlistPath)) return false;
        return zqbb_isBlacklistedExec(path, injectPlistPath, snapshot);
    }
    return isBlacklistedPath_orig(path, snapshot);
}

bool isBlacklistedPath(const char *path)
{
    if (!path) return false;
    xpc_object_t snapshot = copyRootHideConfig();
    return isBlacklistedPathInSnapshot(path, snapshot);
}

struct roothide_app_spawn_policy roothide_get_app_spawn_policy(const char *path)
{
    struct roothide_app_spawn_policy result = {0};
    if (!path) return result;
    // Keep this exact snapshot through both decisions, including whitelist mode's
    // wantsBlacklist override. A bad file retains BOTH previous settings.
    xpc_object_t snapshot = copyRootHideConfig();
    result.blacklisted = isBlacklistedPathInSnapshot(path, snapshot);
    NSString *identifier = isolationAppIdentifier(path);
    result.verified_main_executable = identifier != nil;
    result.isolation_opted_out = isolationOverrideInSnapshot(identifier, snapshot) == 0;
    return result;
}
