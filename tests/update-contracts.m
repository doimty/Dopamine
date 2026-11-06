#import <Foundation/Foundation.h>
#import "NSString+Version.h"
#import "update_target.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
static void require(BOOL condition, const char *name)
{
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", name);
        exit(1);
    }
}

static void expectUpdate(NSString *bundle, NSString *base, NSString *revision,
                         BOOL expected, const char *name)
{
    require(DOEnvironmentVersionNeedsUpdate(bundle, base, revision) == expected, name);
}

static BOOL writeTestPlist(NSString *path, NSDictionary *info)
{
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:info
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static NSString *makeBundle(NSString *root, NSString *name, id identifier)
{
    NSString *path = [root stringByAppendingPathComponent:name];
    NSError *error = nil;
    require([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES
                                                      attributes:nil error:&error], "create test bundle");
    NSDictionary *info = identifier ? @{ @"CFBundleIdentifier": identifier,
        @"CFBundleShortVersionString": @"3.0.13-31" } : @{};
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:info
                            format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    require(plist != nil && [plist writeToFile:[path stringByAppendingPathComponent:@"Info.plist"]
                                       options:NSDataWritingAtomic error:&error], "write binary Info.plist");
    require([[@"test archive" dataUsingEncoding:NSUTF8StringEncoding]
                writeToFile:[path stringByAppendingPathComponent:@"basebin.tar"] atomically:YES], "write archive fixture");
    return path;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        require(argc == 2, "explicit temporary directory required");
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        expectUpdate(@"3.0.13-31", @"3.0.12", @"30", YES, "old doimty 30 is upgraded");
        expectUpdate(@"3.0.13-29", @"3.0.12", @"30", YES, "main version wins over smaller upstream revision");
        expectUpdate(@"3.0.13-31", @"3.0.13", @"29", YES, "previous merge build upgrades");
        expectUpdate(@"3.0.13-31", @"3.0.13", @"30", YES, "same main newer revision upgrades");
        expectUpdate(@"3.0.13-31", @"3.0.13", @"31", NO, "same version is not an update");
        expectUpdate(@"3.0.13-31", @"3.0.13", @"32", NO, "older revision is not an update");
        expectUpdate(@"3.0.13-31", @"3.0.14", @"1", NO, "never downgrade newer main version");
        expectUpdate(@"3.0.13-31\n", @"3.0.12\n", @"30\n", YES, "version-file trailing newline");
        expectUpdate(@"3.0.13-31", @"3.0.12", nil, YES, "known older main version with missing legacy suffix");
        expectUpdate(@"3.0.13-31", @"3.0.13", nil, NO, "same main missing revision is not fabricated as zero");
        expectUpdate(nil, @"3.0.12", @"30", NO, "missing bundled version");
        expectUpdate(@"3.0.13-31", nil, @"30", NO, "no running environment");
        expectUpdate(@"3.0.13-31", @"", @"30", NO, "empty running version");
        expectUpdate(@"3.0.13-31", @"invalid", @"30", NO, "invalid running version");
        expectUpdate(@"3.0.13", @"3.0.12", @"30", NO, "bundled revision required");
        expectUpdate(@"3.0.13-", @"3.0.12", @"30", NO, "empty bundled revision");
        expectUpdate(@"3.0.13-31-git", @"3.0.12", @"30", NO, "unexpected suffix is rejected without assertion");
        expectUpdate(@"3.0.13--1", @"3.0.12", @"30", NO, "negative revision");
        expectUpdate(@"3.0.13-31", @"3.0.13", @"30garbage", NO, "partial numeric parse is rejected");
        expectUpdate(@"3.0.13-18446744073709551616", @"3.0.12", @"30", NO, "uint64 revision overflow");
        expectUpdate(@"18446744073709551616.0.0-31", @"3.0.12", @"30", NO, "uint64 main overflow");
        expectUpdate(@"3.0.256-1", @"3.0.255", @"99", YES, "main components are not packed into eight bits");
        expectUpdate(@"3.0.13-300", @"3.0.13", @"299", YES, "revision above 255");
        puts("PASS production environment-version comparison");

        NSString *good = makeBundle(root, @"Doimty.app", JBCTLDopamineBundleIdentifier);
        NSString *other = makeBundle(root, @"Upstream.app", @"cn.zqbb.dopaRH");
        NSString *missingID = makeBundle(root, @"NoID.app", nil);
        NSString *invalidID = makeBundle(root, @"InvalidID.app", @123);
        require([jbctl_update_basebin_path(good) isEqualToString:[good stringByAppendingPathComponent:@"basebin.tar"]],
                "exact doimty bundle resolves");
        require(jbctl_update_basebin_path(other) == nil, "coinstalled upstream bundle is never selected");
        require(jbctl_update_basebin_path(missingID) == nil, "missing identifier rejected");
        require(jbctl_update_basebin_path(invalidID) == nil, "wrong identifier type rejected");
        require(jbctl_update_basebin_path(nil) == nil, "nil path rejected");
        require(jbctl_update_basebin_path(@"relative.app") == nil, "relative bundle path rejected");

        JBCTLUpdatePackage *package = jbctl_update_preflight_tipa([root stringByAppendingPathComponent:@"good.tipa"]);
        require(package != nil && [package.bundleIdentifier isEqual:JBCTLDopamineBundleIdentifier] &&
            [package.version isEqual:@"3.0.13-31"] && package.basebinSize == 12 && package.basebinSHA256.length == 32,
            "metadata and digest come from actual input ZIP");
        require(jbctl_update_bound_basebin_path(good, package) != nil, "matching installed bundle bound to parsed TIPA");
        for (NSString *name in @[@"other.tipa", @"missing-info.tipa", @"missing-basebin.tipa",
            @"empty-basebin.tipa", @"duplicate-info.tipa", @"duplicate-basebin.tipa", @"two-apps.tipa",
            @"traversal.tipa", @"parent-file.tipa", @"oversized-info.tipa", @"many-entries.tipa", @"symlink-basebin.tipa"]) {
            JBCTLUpdatePackage *invalid = jbctl_update_preflight_tipa([root stringByAppendingPathComponent:name]);
            require(invalid == nil, name.UTF8String);
            require(jbctl_update_bound_basebin_path(good, invalid) == nil,
                "old installed doimty does not rescue invalid or foreign input TIPA");
        }
        JBCTLUpdatePackage *old = jbctl_update_preflight_tipa([root stringByAppendingPathComponent:@"old-version.tipa"]);
        require(old != nil && jbctl_update_bound_basebin_path(good, old) == nil, "installed version must match input version");
        require(jbctl_update_bound_basebin_path(other, package) == nil, "installed foreign bundle never stages");
        NSString *installedInfo = [good stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *oldInfo = @{ @"CFBundleIdentifier": JBCTLDopamineBundleIdentifier,
            @"CFBundleShortVersionString": @"3.0.12-30" };
        require(writeTestPlist(installedInfo, oldInfo), "write old installed version");
        require(jbctl_update_bound_basebin_path(good, package) == nil, "unchanged old installation cannot be staged for new input");
        require(writeTestPlist(installedInfo, @{ @"CFBundleIdentifier": JBCTLDopamineBundleIdentifier,
            @"CFBundleShortVersionString": @"3.0.13-31" }), "restore installed version");
        NSString *installedArchive = [good stringByAppendingPathComponent:@"basebin.tar"];
        require([[ @"xxxx archive" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:installedArchive atomically:YES], "write same-size different content");
        require(jbctl_update_bound_basebin_path(good, package) == nil, "same size and version with different SHA256 does not stage");
        require([[ @"test archive" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:installedArchive atomically:YES], "restore bound archive");
        require(jbctl_update_bound_basebin_path(good, package) != nil, "restored exact input content stages");
        puts("PASS real ZIP preflight, bounds, ambiguity rejection and post-install content binding");
        NSString *archive = [good stringByAppendingPathComponent:@"basebin.tar"];
        require([NSFileManager.defaultManager removeItemAtPath:archive error:nil], "remove archive fixture");
        require(jbctl_update_basebin_path(good) == nil, "missing archive rejected");
        require([[NSData data] writeToFile:archive atomically:YES], "write empty archive fixture");
        require(jbctl_update_basebin_path(good) == nil, "empty archive rejected");
        require([NSFileManager.defaultManager removeItemAtPath:archive error:nil], "remove empty archive fixture");
        require([NSFileManager.defaultManager createDirectoryAtPath:archive withIntermediateDirectories:NO
                                                       attributes:nil error:nil], "directory masquerading as archive");
        require(jbctl_update_basebin_path(good) == nil, "directory is not an archive");
        require([NSFileManager.defaultManager removeItemAtPath:archive error:nil], "remove fake directory");
        require([NSFileManager.defaultManager createSymbolicLinkAtPath:archive
                                        withDestinationPath:[other stringByAppendingPathComponent:@"basebin.tar"]
                                                      error:nil], "create archive symlink fixture");
        require(jbctl_update_basebin_path(good) == nil, "symlink to another fork archive rejected");
        puts("PASS production post-install bundle/archive selection");
        printf("PASS update contracts: %u checks\n", checks);
    }
    return 0;
}
