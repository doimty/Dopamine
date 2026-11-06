#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
static void require(BOOL condition, NSString *name)
{
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", name.UTF8String);
        exit(1);
    }
}

static NSString *translated(NSBundle *bundle, NSString *key)
{
    NSString *value = [bundle localizedStringForKey:key value:@"__MISSING_TRANSLATION__" table:@"Localizable"];
    require(![value isEqualToString:@"__MISSING_TRANSLATION__"], [@"Missing resource: " stringByAppendingString:key]);
    return value;
}

static void checkTwoArguments(NSBundle *bundle, NSString *key)
{
    NSString *identifier = @"org.example.ID-FIRST";
    NSString *directory = @"/private/var/jb/APPS-DIRECTORY-SECOND";
    NSString *message = [NSString stringWithFormat:translated(bundle, key), identifier, directory];
    NSRange idRange = [message rangeOfString:identifier];
    NSRange dirRange = [message rangeOfString:directory];
    require(idRange.location != NSNotFound && dirRange.location != NSNotFound && idRange.location < dirRange.location,
            [@"Identifier/directory positions: " stringByAppendingString:key]);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        require(argc == 2, @"Repository path required");
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        for (NSString *language in @[@"en", @"zh-CN", @"zh-Hans", @"zh-HK", @"zh-TW"]) {
            NSString *path = [root stringByAppendingPathComponent:
                [NSString stringWithFormat:@"Application/Dopamine/%@.lproj", language]];
            NSBundle *bundle = [NSBundle bundleWithPath:path];
            require(bundle != nil, [@"Load real language bundle " stringByAppendingString:language]);
            NSString *authors = translated(bundle, @"Credits_Made_By");
            require([authors containsString:@"opa334"] && [authors containsString:@"évelyne"], @"Attribution retained");
            if ([language hasPrefix:@"zh"]) require([authors hasPrefix:@"作者："], @"Short localized author prefix");
            checkTwoArguments(bundle, @"Duplicate_Apps_Error_Dopamine_App");
            checkTwoArguments(bundle, @"Duplicate_Apps_Error_User_App");
            NSString *ids = @"org.example.ONE\norg.example.TWO";
            NSString *dir = @"/APPLICATION-DIR";
            NSString *listMessage = [NSString stringWithFormat:translated(bundle, @"Duplicate_Apps_Error_User_App"), ids, dir];
            require([listMessage containsString:ids] && [listMessage containsString:dir], @"Entire ID list preserved as first argument");
            NSString *cache = @"/CACHE-DIR-THIRD";
            NSString *cacheMessage = [NSString stringWithFormat:translated(bundle, @"Duplicate_Apps_Error_Icon_Cache"), ids, dir, cache];
            NSRange first = [cacheMessage rangeOfString:ids], second = [cacheMessage rangeOfString:dir], third = [cacheMessage rangeOfString:cache];
            require(first.location != NSNotFound && second.location != NSNotFound && third.location != NSNotFound &&
                    first.location < second.location && second.location < third.location, @"ID/directory/cachePath order retained");
            NSString *failure = [NSString stringWithFormat:translated(bundle, @"Jailbreak_Failed_With_Error"), @"ERROR-SENTINEL"];
            require([failure containsString:@"ERROR-SENTINEL"], @"Failure log argument retained");
            for (NSString *key in @[@"Exploiting Kernel (%@)", @"Bypassing PAC (%@)", @"Bypassing PPL (%@)", @"Bypassing SPTM (%@)"]) {
                NSString *value = [NSString stringWithFormat:translated(bundle, key), @"EXPLOIT-SENTINEL"];
                require([value containsString:@"EXPLOIT-SENTINEL"], @"Exploit display name retained");
            }
            NSString *spinlock = translated(bundle, @"Spinlock_Fix_Warning");
            require(![spinlock containsString:@"插件扩展"] && ![spinlock containsString:@"外掛擴充"], @"App extension differs from tweak injection");
            NSString *jetsam = translated(bundle, @"Jetsam_Description");
            for (NSString *number in @[@"10 MB", @"1024 MB", @"48 MB", @"16 MB", @"cn.zqbb.jetsam.addend.plist"])
                require([jetsam containsString:number], @"Per-process Jetsam addends retained");
            printf("PASS NSBundle actual resources/formatting: %s\n", language.UTF8String);
        }
        printf("PASS official-home localization: %u checks\n", checks);
    }
    return 0;
}
