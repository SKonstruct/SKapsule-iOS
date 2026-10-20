#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SKZipUtils : NSObject

/// Walks a zip through its central directory and hands each file entry's name and
/// decompressed bytes to handler; return NO from it to stop. NO if the archive is unreadable.
+ (BOOL)enumerateZip:(NSString *)zipPath usingBlock:(BOOL (^)(NSString *entryName, NSData *contents))handler;

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

/// @return YES if the zip's central directory is readable and contains @c entryName.
/// Used to prove a getdown-managed jar still yields its resources before the JVM starts.
+ (BOOL)zipFile:(NSString *)zipPath containsEntry:(NSString *)entryName;

@end

NS_ASSUME_NONNULL_END
