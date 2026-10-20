#pragma once

#import <Foundation/Foundation.h>

@interface SKInstaller : NSObject
+ (BOOL)isInstalled;
+ (BOOL)installWithProgress:(void (^)(NSString *status))progress;

/// Copies any bundled jar that differs from its staged copy. Cheap; call every launch
/// so an app update replaces jars even when the version marker has not moved.
+ (void)refreshStagedJars;

/// Deletes any getdown-managed jar that no longer yields its resources, so the next
/// getdown pass refetches it. Cheap; call before starting the JVM.
+ (void)repairGameJars;

/// Clears the getdown markers for the rsrc bundles when their unpacked tree is missing,
/// so the next getdown pass re-extracts them without re-downloading.
+ (void)repairUnpackedResources;

/// Removes a resource plus its getdown ".jarv" marker, forcing a refetch.
+ (void)dropGetdownResource:(NSString *)path;
+ (NSString *)credFilePath;
@end
