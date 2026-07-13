#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SKZipUtils : NSObject

/**
 Extracts a ZIP/JAR file to a target directory.
 Optional file filter supports preventing overwrites of protected game files.
 */
+ (BOOL)extractZipFile:(NSString *)zipPath
           toDirectory:(NSString *)targetDir
        checkProtected:(BOOL)checkProtected
        protectedFiles:(nullable NSSet<NSString *> *)protectedFiles;

/**
 Extracts a JAR archive without overwriting files that already exist at the destination path.
 */
+ (BOOL)extractJarWithoutOverwrite:(NSString *)jarPath toDirectory:(NSString *)targetDir;

/**
 Compresses a directory contents into a ZIP file.
 */
+ (BOOL)createZipFileFromDirectory:(NSString *)sourceDir toZipPath:(NSString *)zipPath;

/**
 Calculates the Git blob SHA-1 hash of a file for remote sync verification.
 */
+ (nullable NSString *)calculateGitBlobShaOfFile:(NSString *)filePath;

/**
 Reads the mod.json metadata dictionary directly from a ZIP file without extracting other contents.
 */
+ (nullable NSDictionary *)readModMetadataFromZip:(NSString *)zipPath;

@end

NS_ASSUME_NONNULL_END
