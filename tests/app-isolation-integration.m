#import <Foundation/Foundation.h>
#include <libjailbreak/libjailbreak.h>
#include "common.h"
#include "_configuration.h"
#include "app_isolation_policy.h"
#include <sys/stat.h>

#ifndef APP_PATH_PREFIX
#error The test runner must supply its private canonical container directory.
#endif

static char rootPath[PATH_MAX];
static unsigned checks;
static NSString *const bundleID = @"com.example.isolation";

char *get_jbroot(void) { return rootPath; }

static void require(BOOL condition, NSString *message)
{
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static void makeDirectory(NSString *path)
{
    NSError *error = nil;
    require([NSFileManager.defaultManager createDirectoryAtPath:path
        withIntermediateDirectories:YES attributes:nil error:&error],
        [NSString stringWithFormat:@"mkdir %@: %@", path, error]);
}

static void writeBytes(NSString *path, NSString *text)
{
    require([[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO],
        [@"write bytes " stringByAppendingString:path]);
}

static void writePlist(NSString *path, id value)
{
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    require(data != nil && [data writeToFile:path options:NSDataWritingAtomic error:&error],
        [NSString stringWithFormat:@"replace plist %@: %@", path, error]);
}

static void removePath(NSString *path)
{
    NSError *error = nil;
    require([NSFileManager.defaultManager removeItemAtPath:path error:&error],
        [NSString stringWithFormat:@"remove %@: %@", path, error]);
}

static void makeExecutable(NSString *path)
{
    makeDirectory(path.stringByDeletingLastPathComponent);
    writeBytes(path, @"fixture only; never executed\n");
    require(chmod(path.fileSystemRepresentation, 0755) == 0, @"chmod executable");
}

static void makeSymlink(NSString *target, NSString *link)
{
    require(symlink(target.fileSystemRepresentation, link.fileSystemRepresentation) == 0,
        [@"symlink " stringByAppendingString:link]);
}

static NSDictionary *info(NSString *identifier, id executable)
{
    return @{ @"CFBundleIdentifier": identifier, @"CFBundleExecutable": executable };
}

static NSDictionary *config(id blacklisted, id override)
{
    NSMutableDictionary *result = [@{ @"appconfig": @{ bundleID: blacklisted } } mutableCopy];
    if (override) result[@"appconfigSpinlockSafe"] = @{ bundleID: override };
    return result;
}

static struct roothide_app_spawn_policy expectPolicy(NSString *name, NSString *path,
    bool blacklisted, bool eligible, bool optedOut)
{
    struct roothide_app_spawn_policy p = roothide_get_app_spawn_policy(path.fileSystemRepresentation);
    require(p.blacklisted == blacklisted && p.verified_main_executable == eligible &&
        p.isolation_opted_out == optedOut,
        [NSString stringWithFormat:@"%@ expected %d/%d/%d got %d/%d/%d", name,
            blacklisted, eligible, optedOut, p.blacklisted, p.verified_main_executable, p.isolation_opted_out]);
    // The legacy entry remains independent of new eligibility.
    require(isBlacklistedPath(path.fileSystemRepresentation) == blacklisted,
        [name stringByAppendingString:@" preserves effective blacklist"]);
    return p;
}

static void expectRoute(NSString *name, NSString *path, bool choicy, bool prewarm,
    bool closures, enum app_isolation_route expected)
{
    // Only platform/lifecycle facts are host fixtures. Eligibility, opt-out,
    // effective blacklist and extension classification execute production code.
    struct roothide_app_spawn_policy p = roothide_get_app_spawn_policy(path.fileSystemRepresentation);
    const struct app_isolation_context context = {
        .ios15_arm64e = true, .global_dyld_fix = true,
        .effective_blacklisted = p.blacklisted, .choicy_blocked = choicy,
        .ordinary_removable_app = p.verified_main_executable,
        .not_trollstore = true,
        .spinlock_safe_opt_in = p.verified_main_executable && !p.isolation_opted_out,
        .is_extension = app_isolation_path_is_extension(path.fileSystemRepresentation),
        .active_prewarm = prewarm, .dyld_use_closures = closures
    };
    require(app_isolation_policy_decide(&context) == expected, name);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        require(argc == 2, @"supply private fixture root");
        require(strlcpy(rootPath, argv[1], sizeof(rootPath)) < sizeof(rootPath), @"root length");
        NSString *root = [NSString stringWithUTF8String:rootPath];
        NSString *container = [@APP_PATH_PREFIX stringByAppendingPathComponent:@"12345678-1234-1234-1234-123456789012"];
        NSString *bundle = [container stringByAppendingPathComponent:@"App.app"];
        NSString *main = [bundle stringByAppendingPathComponent:@"Main"];
        NSString *helper = [bundle stringByAppendingPathComponent:@"Helpers/helper"];
        NSString *xpc = [bundle stringByAppendingPathComponent:@"XPCServices/Helper.xpc/Helper"];
        NSString *extension = [bundle stringByAppendingPathComponent:@"PlugIns/Widget.appex/Widget"];
        NSString *infoPath = [bundle stringByAppendingPathComponent:@"Info.plist"];
        NSString *configurationDir = [root stringByAppendingPathComponent:@"var/mobile/Library/RootHide"];
        NSString *configuration = [configurationDir stringByAppendingPathComponent:@"RootHideConfig.plist"];
        NSString *whitelist = [configurationDir stringByAppendingPathComponent:@"cn.zqbb.inject.plist"];
        NSString *systemWhitelist = [configurationDir stringByAppendingPathComponent:@"cn.zqbb.inject.system.plist"];
        NSString *wantsBlacklist = [configurationDir stringByAppendingPathComponent:@"cn.zqbb.inject.wantsblacklist.plist"];
        makeDirectory(configurationDir);
        for (NSString *path in @[main, helper, xpc, extension]) makeExecutable(path);
        writePlist(infoPath, info(bundleID, @"Main"));

        expectPolicy(@"missing root configuration", main, false, true, false);
        writePlist(configuration, config(@YES, @NO));
        expectPolicy(@"valid explicit false", main, true, true, true);
        require(appSpinlockIsolationOptedOut(main.fileSystemRepresentation), @"legacy opt-out getter");
        require(!appSpinlockIsolationRequested(main.fileSystemRepresentation), @"legacy opt-in getter");
        expectRoute(@"explicit false stays native", main, false, false, false, APP_ISOLATION_ROUTE_BLACKLIST_NATIVE);

        // Stable corruption, not merely a writer race: the old false opt-out
        // must remain paired with the cached true blacklist on every read.
        writeBytes(configuration, @"bad plist");
        for (unsigned n = 0; n < 20; n++)
            expectPolicy(@"stable corrupt file keeps both fields", main, true, true, true);
        writeBytes(configuration, @"");
        expectPolicy(@"empty file keeps both fields", main, true, true, true);
        writePlist(configuration, @[@"wrong root type"]);
        expectPolicy(@"wrong root type keeps both fields", main, true, true, true);
        if (geteuid() != 0) {
            require(chmod(configuration.fileSystemRepresentation, 0000) == 0, @"make config unreadable");
            expectPolicy(@"read failure keeps both fields", main, true, true, true);
            require(chmod(configuration.fileSystemRepresentation, 0600) == 0, @"restore config permissions");
        }
        writePlist(configuration, config(@YES, @YES));
        expectPolicy(@"atomic replacement true", main, true, true, false);
        expectRoute(@"eligible main goes strict", main, false, false, false, APP_ISOLATION_ROUTE_BLACKLIST_SPINLOCK);
        writePlist(configuration, config(@NO, @NO));
        expectPolicy(@"replacement blacklist false", main, false, true, true);
        expectRoute(@"opt-out never changes effective whitelist", main, false, false, false, APP_ISOLATION_ROUTE_NORMAL);
        removePath(configuration);
        expectPolicy(@"deletion clears both cached settings", main, false, true, false);
        writeBytes(configuration, @"invalid after deletion");
        expectPolicy(@"no last-good snapshot after deletion", main, false, true, false);

        writePlist(configuration, config(@YES, nil));
        expectPolicy(@"absent override retains automatic policy", main, true, true, false);
        for (id value in @[@0, @"false", @[], @{}]) {
            writePlist(configuration, config(@YES, value));
            expectPolicy(@"non-Boolean override is not false", main, true, true, false);
        }
        writePlist(configuration, @{ @"appconfig": @{ bundleID: @YES }, @"appconfigSpinlockSafe": @"wrong section" });
        expectPolicy(@"wrong override section is absent", main, true, true, false);
        writePlist(configuration, config(@"YES", @NO));
        expectPolicy(@"old blacklist boolValue preserved", main, true, true, true);

        writePlist(configuration, config(@YES, @YES));
        for (NSString *path in @[helper, xpc]) {
            expectPolicy(@"helper keeps blacklist but lacks main eligibility", path, true, false, false);
            expectRoute(@"helper stays native", path, false, false, false, APP_ISOLATION_ROUTE_BLACKLIST_NATIVE);
        }
        writePlist(configuration, config(@YES, @NO));
        expectPolicy(@"main opt-out remains false while helper stays legacy", main, true, true, true);
        expectRoute(@"helper under opted-out app stays native", helper, false, false, false, APP_ISOLATION_ROUTE_BLACKLIST_NATIVE);
        expectRoute(@"extension restriction unchanged", extension, false, false, false, APP_ISOLATION_ROUTE_REJECT);
        expectRoute(@"prewarm restriction unchanged", main, false, true, false, APP_ISOLATION_ROUTE_REJECT);
        expectRoute(@"closure restriction unchanged", main, false, false, true, APP_ISOLATION_ROUTE_REJECT);

        NSString *alias = [root stringByAppendingPathComponent:@"main-alias"];
        makeSymlink(main, alias);
        expectPolicy(@"alias resolves to actual regular main", alias, true, true, true);
        removePath(alias);
        makeSymlink(helper, alias);
        expectPolicy(@"alias to helper is not main", alias, true, false, false);
        removePath(alias);
        removePath(main);
        makeSymlink(helper, main);
        expectPolicy(@"declared main symlink to helper stays legacy", main, true, false, false);
        removePath(main);
        makeSymlink([bundle stringByAppendingPathComponent:@"Missing"], main);
        expectPolicy(@"broken main symlink stays legacy", main, false, false, false);
        removePath(main);
        makeExecutable(main);
        NSString *outside = [root stringByAppendingPathComponent:@"outside"];
        makeExecutable(outside);
        removePath(main);
        makeSymlink(outside, main);
        expectPolicy(@"escaping main symlink stays legacy", main, false, false, false);
        removePath(main);
        makeExecutable(main);
        require(chmod(main.fileSystemRepresentation, 0644) == 0, @"drop main execute bit");
        expectPolicy(@"nonexecutable main keeps blacklist", main, true, false, false);
        require(chmod(main.fileSystemRepresentation, 0755) == 0, @"restore execute bit");

        removePath(infoPath);
        expectPolicy(@"missing Info.plist", main, false, false, false);
        writeBytes(infoPath, @"broken plist");
        expectPolicy(@"broken Info.plist", main, false, false, false);
        writePlist(infoPath, @[@"wrong Info root"]);
        expectPolicy(@"wrong Info root", main, false, false, false);
        writePlist(infoPath, @{ @"CFBundleIdentifier": bundleID });
        expectPolicy(@"missing CFBundleExecutable keeps blacklist", main, true, false, false);
        for (id value in @[@3, @"", @"Helpers/helper", @"Missing", @"..", @"Ma\nin"]) {
            writePlist(infoPath, info(bundleID, value));
            expectPolicy(@"invalid CFBundleExecutable keeps blacklist", main, true, false, false);
        }
        writePlist(infoPath, @{ @"CFBundleIdentifier": @3, @"CFBundleExecutable": @"Main" });
        expectPolicy(@"wrong identifier type", main, false, false, false);
        writePlist(infoPath, info(bundleID, @"Main"));

        NSString *invalidContainer = [@APP_PATH_PREFIX stringByAppendingPathComponent:@"zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz/App.app"];
        NSString *invalidMain = [invalidContainer stringByAppendingPathComponent:@"Main"];
        makeExecutable(invalidMain);
        writePlist([invalidContainer stringByAppendingPathComponent:@"Info.plist"], info(bundleID, @"Main"));
        expectPolicy(@"non-UUID legacy blacklist is not main eligibility", invalidMain, true, false, false);
        NSString *nestedBundle = [container stringByAppendingPathComponent:@"Nested/App.app"];
        NSString *nestedMain = [nestedBundle stringByAppendingPathComponent:@"Main"];
        makeExecutable(nestedMain);
        writePlist([nestedBundle stringByAppendingPathComponent:@"Info.plist"], info(bundleID, @"Main"));
        expectPolicy(@"nested app is not ordinary top-level app", nestedMain, true, false, false);
        expectPolicy(@"outside path", outside, false, false, false);

        // Test actual production whitelist and wantsBlacklist readers too.
        writePlist(configuration, config(@YES, @NO));
        writePlist(whitelist, @{ @"Main": @YES });
        expectPolicy(@"whitelist wins absent wantsBlacklist", main, false, true, true);
        expectRoute(@"Choicy-only route unchanged", main, true, false, false, APP_ISOLATION_ROUTE_BLACKLIST_SPINLOCK);
        writePlist(wantsBlacklist, @{ @"Main": @YES });
        expectPolicy(@"wantsBlacklist uses same root snapshot", main, true, true, true);
        writeBytes(configuration, @"stable bad in whitelist mode");
        for (unsigned n = 0; n < 20; n++)
            expectPolicy(@"whitelist mode retains paired opt-out", main, true, true, true);
        writePlist(configuration, config(@NO, @YES));
        expectPolicy(@"wantsBlacklist false after atomic root replacement", main, false, true, false);
        writePlist(whitelist, @{});
        expectPolicy(@"missing exec in whitelist stays blacklisted", main, true, true, false);
        expectPolicy(@"outside helper blacklist preserved in whitelist mode", outside, true, false, false);
        writePlist(systemWhitelist, @{ @"App.app": @YES });
        expectPolicy(@"system whitelist precedence unchanged", main, false, true, false);
        removePath(systemWhitelist);
        removePath(whitelist);
        removePath(wantsBlacklist);
        writePlist(configuration, config(@YES, @YES));
        for (NSString *marker in @[@"_TrollStore", @"_TrollStoreLite"]) {
            NSString *path = [container stringByAppendingPathComponent:marker];
            writeBytes(path, @"");
            expectPolicy(@"TS/TSLite main eligibility unchanged", main, true, true, false);
            removePath(path);
        }
        writePlist(infoPath, info(@"com.doimty.dopamine", @"Main"));
        writePlist(configuration, @{ @"appconfig": @{ @"com.doimty.dopamine": @YES } });
        expectPolicy(@"builtin application exemption preserved", main, false, true, false);
        printf("app-isolation-integration: %u checks passed; production Foundation/path/XPC/config/whitelist code, no device execution\n", checks);
    }
    return 0;
}
