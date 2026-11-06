//
//  NSString+Version.h
//  Dopamine
//
//  Created by Lars Fröder on 12.06.24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (Version)

- (NSInteger)numericalVersionRepresentation;

@end

// Compare the bundled base version first, then its RootHide revision. The
// release-tag helpers above intentionally keep their existing semantics.
FOUNDATION_EXPORT BOOL DOEnvironmentVersionNeedsUpdate(
    NSString * _Nullable bundledVersion,
    NSString * _Nullable installedBaseVersion,
    NSString * _Nullable installedRootHideRevision);

NS_ASSUME_NONNULL_END
