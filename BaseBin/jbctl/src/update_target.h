#ifndef JBCTL_UPDATE_TARGET_H
#define JBCTL_UPDATE_TARGET_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const JBCTLDopamineBundleIdentifier;

// Validate the installed bundle before selecting its basebin for staging. Never
// fall back to another installed Dopamine fork when this target is absent.
FOUNDATION_EXPORT NSString * _Nullable jbctl_update_basebin_path(NSString * _Nullable bundlePath);

// Immutable facts parsed from the actual TIPA before invoking the installer.
@interface JBCTLUpdatePackage : NSObject
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *version;
@property (nonatomic, copy, readonly) NSData *basebinSHA256;
@property (nonatomic, readonly) uint64_t basebinSize;
@end

// Bounded, read-only ZIP streaming. No extracted bytes are executed or written.
FOUNDATION_EXPORT JBCTLUpdatePackage * _Nullable jbctl_update_preflight_tipa(NSString *path);
FOUNDATION_EXPORT NSString * _Nullable jbctl_update_bound_basebin_path(
    NSString * _Nullable bundlePath, JBCTLUpdatePackage * _Nullable package);

NS_ASSUME_NONNULL_END

#endif
