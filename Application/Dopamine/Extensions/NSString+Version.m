//
//  NSString+Version.h
//  Dopamine
//
//  Created by Lars Fröder on 12.06.24.
//

#import "NSString+Version.h"
#include <stdint.h>

static NSString *DOTrimVersion(NSString *value)
{
    if (![value isKindOfClass:NSString.class]) return nil;
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL DOParseVersionNumber(NSString *value, uint64_t *number)
{
    if (value.length == 0 || value.length > 20) return NO;
    uint64_t result = 0;
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar ch = [value characterAtIndex:i];
        if (ch < '0' || ch > '9') return NO;
        uint64_t digit = ch - '0';
        if (result > (UINT64_MAX - digit) / 10) return NO;
        result = result * 10 + digit;
    }
    *number = result;
    return YES;
}

static BOOL DOParseBaseVersion(NSString *value, uint64_t components[3])
{
    NSArray<NSString *> *parts = [DOTrimVersion(value) componentsSeparatedByString:@"."];
    if (parts.count == 0 || parts.count > 3) return NO;
    for (NSUInteger i = 0; i < 3; i++) {
        components[i] = 0;
        if (i < parts.count && !DOParseVersionNumber(parts[i], &components[i])) return NO;
    }
    return YES;
}

BOOL DOEnvironmentVersionNeedsUpdate(NSString *bundledVersion,
                                     NSString *installedBaseVersion,
                                     NSString *installedRootHideRevision)
{
    NSArray<NSString *> *bundled = [DOTrimVersion(bundledVersion) componentsSeparatedByString:@"-"];
    if (bundled.count != 2) return NO;
    uint64_t newBase[3], oldBase[3], newRevision, oldRevision;
    if (!DOParseBaseVersion(bundled[0], newBase) ||
        !DOParseVersionNumber(bundled[1], &newRevision) ||
        !DOParseBaseVersion(installedBaseVersion, oldBase)) return NO;

    // A newer main version still needs updating when an upstream rebase used a
    // smaller RootHide suffix. Conversely, never suggest a main-version downgrade.
    for (NSUInteger i = 0; i < 3; i++) {
        if (newBase[i] != oldBase[i]) return newBase[i] > oldBase[i];
    }
    if (!DOParseVersionNumber(DOTrimVersion(installedRootHideRevision), &oldRevision)) return NO;
    return newRevision > oldRevision;
}

@implementation NSString (Version)

- (NSInteger)numericalVersionRepresentation
{
    NSInteger numericalRepresentation = 0;

    NSArray *components = [self componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
    
    components = [components filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != ''"]];
    assert(components.count <= 3);
    
    while (components.count < 3)
        components = [components arrayByAddingObject:@"0"];

    numericalRepresentation |= [components[0] integerValue] << 16;
    numericalRepresentation |= [components[1] integerValue] << 8;
    numericalRepresentation |= [components[2] integerValue];
    return numericalRepresentation;
}

@end
