#import "SKZipUtils.h"
#import <libkern/OSByteOrder.h>
#import <CommonCrypto/CommonDigest.h>
#import <zlib.h>

#pragma pack(push, 1)
typedef struct {
    uint32_t signature;  // 0x04034b50
    uint16_t version_needed;
    uint16_t flags;
    uint16_t compression_method;
    uint16_t last_mod_time;
    uint16_t last_mod_date;
    uint32_t crc32;
    uint32_t compressed_size;
    uint32_t uncompressed_size;
    uint16_t filename_length;
    uint16_t extra_field_length;
} iOSLocalFileHeader;

typedef struct {
    uint32_t signature;  // 0x02014b50
    uint16_t version_made;
    uint16_t version_needed;
    uint16_t flags;
    uint16_t compression_method;
    uint16_t last_mod_time;
    uint16_t last_mod_date;
    uint32_t crc32;
    uint32_t compressed_size;
    uint32_t uncompressed_size;
    uint16_t filename_length;
    uint16_t extra_field_length;
    uint16_t comment_length;
    uint16_t disk_start;
    uint16_t internal_attrs;
    uint32_t external_attrs;
    uint32_t local_header_offset;
} iOSCentralHeader;

typedef struct {
    uint32_t signature;  // 0x06054b50
    uint16_t disk_number;
    uint16_t disk_with_cd;
    uint16_t disk_entries;
    uint16_t total_entries;
    uint32_t cd_size;
    uint32_t cd_offset;
    uint16_t comment_length;
} iOSEOCD;
#pragma pack(pop)

/// Ceilings on declared uncompressed size, per entry and per archive: generous for mods and
/// the base game jars, but finite, so a forged header cannot ask for gigabytes.
static const size_t kSKZipMaxEntrySize = 512u << 20;
static const size_t kSKZipMaxTotalSize = 2048u << 20;

/// Resolves a zip entry against the extraction root, or nil if it escapes it.
///
/// Zip entry names are attacker-controlled -- mod archives come from a third-party GitHub
/// repo -- and nothing in the format stops one being "../../jre25/lib/libjvm.dylib". The
/// sandbox keeps that inside our container, which is still where the JRE, the game jars,
/// the preferences and the Steam credentials live.
static NSString *SKZipSafeDestination(NSString *targetDir, NSString *entryName) {
    if (entryName.length == 0 || [entryName hasPrefix:@"/"]) return nil;

    // Validate the entry name itself rather than the resolved destination. Standardizing
    // the destination cannot work here: it resolves symlinks only for paths that exist, so
    // the (existing) root became /private/var/... while the (not-yet-written) entry stayed
    // /var/..., and every ordinary entry failed the prefix test.
    for (NSString *component in entryName.pathComponents) {
        if ([component isEqualToString:@".."]) {
            NSLog(@"[SKZipUtils] Rejected entry escaping the extraction root: %@", entryName);
            return nil;
        }
    }
    return [targetDir stringByAppendingPathComponent:entryName];
}

@implementation SKZipUtils

/**
 * Enumerates a zip through its central directory, the way java.util.zip does, and hands
 * each entry to @c handler.
 *
 * The previous implementation walked local file headers front to back and trusted their
 * size fields. Any entry written with a data descriptor (general-purpose bit 3) stores
 * zeros there, so the walk desynchronised and every entry after it was silently dropped --
 * which is why rebuilding a jar from an extracted tree produced one that Java could not
 * read, and why applied mods came back looking vanilla. The central directory always
 * carries the real sizes.
 *
 * Mod archives are third-party input, so the declared sizes are capped before anything is
 * allocated. The entry count is not capped below the format's own 16-bit field: the base
 * game jars unpacked here can hold far more than a few thousand entries, and the loop is
 * already bounded by the central directory's bytes.
 *
 * @param filter if given, entries it rejects are skipped without being inflated.
 * @param handler receives each entry name and its decompressed bytes; return NO to stop.
 */
+ (BOOL)enumerateZip:(NSString *)zipPath
            matching:(nullable BOOL (^)(NSString *entryName))filter
          usingBlock:(BOOL (^)(NSString *entryName, NSData *contents))handler {
    NSData *file = [NSData dataWithContentsOfFile:zipPath
                                          options:NSDataReadingMappedIfSafe
                                            error:nil];
    if (file.length < 22) return NO;

    const uint8_t *bytes = file.bytes;
    size_t length = file.length;

    size_t searchStart = length > 66000 ? length - 66000 : 0;
    NSInteger eocd = -1;
    for (NSInteger i = (NSInteger)length - 22; i >= (NSInteger)searchStart; i--) {
        if (OSReadLittleInt32(bytes, i) == 0x06054b50) {
            eocd = i;
            break;
        }
    }
    if (eocd < 0) return NO;

    uint16_t entryCount = OSReadLittleInt16(bytes, eocd + 10);
    size_t cursor = OSReadLittleInt32(bytes, eocd + 16);
    size_t totalSize = 0;

    for (uint16_t i = 0; i < entryCount; i++) {
        if (cursor > length || length - cursor < 46 || OSReadLittleInt32(bytes, cursor) != 0x02014b50) return NO;

        uint16_t method = OSReadLittleInt16(bytes, cursor + 10);
        uint32_t compressedSize = OSReadLittleInt32(bytes, cursor + 20);
        uint32_t uncompressedSize = OSReadLittleInt32(bytes, cursor + 24);
        uint16_t nameLength = OSReadLittleInt16(bytes, cursor + 28);
        uint16_t extraLength = OSReadLittleInt16(bytes, cursor + 30);
        uint16_t commentLength = OSReadLittleInt16(bytes, cursor + 32);
        size_t localOffset = OSReadLittleInt32(bytes, cursor + 42);
        size_t nameStart = cursor + 46;
        if (nameLength > length - nameStart) return NO;

        NSString *entryName = [[NSString alloc] initWithBytes:bytes + nameStart
                                                       length:nameLength
                                                     encoding:NSUTF8StringEncoding];
        cursor = nameStart + nameLength + extraLength + commentLength;
        if (!entryName || [entryName hasSuffix:@"/"]) continue;
        if (filter && !filter(entryName)) continue;

        if (uncompressedSize > kSKZipMaxEntrySize || compressedSize > kSKZipMaxEntrySize) {
            NSLog(@"[SKZipUtils] Rejected %@: entry %@ is too large", zipPath.lastPathComponent, entryName);
            return NO;
        }
        totalSize += uncompressedSize;
        if (totalSize > kSKZipMaxTotalSize) {
            NSLog(@"[SKZipUtils] Rejected %@: contents are too large", zipPath.lastPathComponent);
            return NO;
        }

        // The local header repeats the name and extra fields, and its extra field can be a
        // different length from the central one, so the data offset has to be read here.
        if (localOffset > length || length - localOffset < 30 ||
            OSReadLittleInt32(bytes, localOffset) != 0x04034b50) {
            continue;
        }
        size_t dataStart = localOffset + 30 + OSReadLittleInt16(bytes, localOffset + 26) +
                           OSReadLittleInt16(bytes, localOffset + 28);
        if (dataStart > length || compressedSize > length - dataStart) continue;

        NSData *contents = nil;
        if (uncompressedSize == 0) {
            // An empty entry has nothing to inflate, and inflate() with avail_out == 0
            // reports a buffer error rather than Z_STREAM_END, which would drop the file.
            contents = NSData.data;
        } else if (method == 0) {
            contents = [file subdataWithRange:NSMakeRange(dataStart, compressedSize)];
        } else if (method == 8) {
            NSMutableData *out = [NSMutableData dataWithLength:uncompressedSize];
            z_stream strm;
            memset(&strm, 0, sizeof(strm));
            strm.next_in = (Bytef *)(bytes + dataStart);
            strm.avail_in = compressedSize;
            strm.next_out = out.mutableBytes;
            strm.avail_out = uncompressedSize;
            if (out && inflateInit2(&strm, -15) == Z_OK) {
                if (inflate(&strm, Z_FINISH) == Z_STREAM_END && strm.total_out == uncompressedSize) contents = out;
                inflateEnd(&strm);
            }
        }
        if (!contents) continue;
        if (!handler(entryName, contents)) return NO;
    }
    return YES;
}

+ (BOOL)enumerateZip:(NSString *)zipPath
           usingBlock:(BOOL (^)(NSString *entryName, NSData *contents))handler {
    return [self enumerateZip:zipPath matching:nil usingBlock:handler];
}

+ (nullable NSString *)safeDestinationForEntry:(NSString *)entryName inDirectory:(NSString *)directory {
    return SKZipSafeDestination(directory, entryName);
}

+ (BOOL)extractZipFile:(NSString *)zipPath
           toDirectory:(NSString *)targetDir
        checkProtected:(BOOL)checkProtected
        protectedFiles:(nullable NSSet<NSString *> *)protectedFiles {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    return [self enumerateZip:zipPath
                   usingBlock:^BOOL(NSString *entryName, NSData *contents) {
                     if ([entryName isEqualToString:@"mod.json"] ||
                         [entryName hasSuffix:@"/mod.json"] ||
                         [entryName isEqualToString:@"mod.png"] ||
                         [entryName hasSuffix:@"/mod.png"]) {
                         return YES;
                     }
                     if (checkProtected && protectedFiles &&
                         [protectedFiles containsObject:entryName.lowercaseString]) {
                         return YES;
                     }

                     NSString *destPath = SKZipSafeDestination(targetDir, entryName);
                     if (!destPath) return YES;

                     [fileManager createDirectoryAtPath:[destPath stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
                     return [contents writeToFile:destPath atomically:YES];
                   }];
}

+ (BOOL)extractJarWithoutOverwrite:(NSString *)jarPath toDirectory:(NSString *)targetDir {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    return [self enumerateZip:jarPath
                   usingBlock:^BOOL(NSString *entryName, NSData *contents) {
                     NSString *destPath = SKZipSafeDestination(targetDir, entryName);
                     // "Without overwrite": whatever is already there wins, which is how a
                     // mod's files survive the base jar being unpacked over them.
                     if (!destPath || [fileManager fileExistsAtPath:destPath]) return YES;

                     [fileManager createDirectoryAtPath:[destPath stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
                     return [contents writeToFile:destPath atomically:YES];
                   }];
}

static void collectFiles(NSString *baseDir, NSString *currentDir, NSMutableArray *filePaths) {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:currentDir error:nil];
    for (NSString *file in files) {
        NSString *fullPath = [currentDir stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir]) {
            if (isDir) {
                collectFiles(baseDir, fullPath, filePaths);
            } else {
                [filePaths addObject:fullPath];
            }
        }
    }
}

static BOOL SKWriteAll(FILE *f, const void *bytes, size_t length) {
    return length == 0 || fwrite(bytes, 1, length, f) == length;
}

+ (BOOL)createZipFileFromDirectory:(NSString *)sourceDir toZipPath:(NSString *)zipPath {
    NSMutableArray *files = [NSMutableArray array];
    collectFiles(sourceDir, sourceDir, files);

    FILE *f = fopen([zipPath UTF8String], "wb");
    if (!f)
        return NO;

    NSMutableArray *centralHeaders = [NSMutableArray array];
    uint64_t currentOffset = 0;
    BOOL ok = YES;

    for (NSString *filePath in files) {
        NSString *relPath = [filePath substringFromIndex:sourceDir.length + 1];
        if ([relPath isEqualToString:@"mod.json"] || [relPath isEqualToString:@"mod.png"]) {
            continue;
        }

        // A file that cannot be read is an error, not something to leave out of the jar.
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        NSData *nameData = [relPath dataUsingEncoding:NSUTF8StringEncoding];
        if (!data || data.length > kSKZipMaxEntrySize || !nameData || nameData.length > UINT16_MAX) {
            ok = NO;
            break;
        }

        uLong crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, [data bytes], (uInt)[data length]);

        NSMutableData *compressed = [NSMutableData data];
        z_stream strm;
        memset(&strm, 0, sizeof(strm));
        int ret = deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
        if (ret != Z_OK) {
            ok = NO;
            break;
        }

        uint8_t outBuffer[8192];
        strm.next_in = (Bytef *)[data bytes];
        strm.avail_in = (uInt)[data length];

        do {
            strm.next_out = outBuffer;
            strm.avail_out = sizeof(outBuffer);
            ret = deflate(&strm, Z_FINISH);
            [compressed appendBytes:outBuffer length:sizeof(outBuffer) - strm.avail_out];
        } while (ret == Z_OK);

        deflateEnd(&strm);
        if (ret != Z_STREAM_END) {
            ok = NO;
            break;
        }

        iOSLocalFileHeader localHeader;
        localHeader.signature = 0x04034b50;
        localHeader.version_needed = 20;
        localHeader.flags = 0;
        localHeader.compression_method = 8;
        localHeader.last_mod_time = 0;
        localHeader.last_mod_date = 0;
        localHeader.crc32 = (uint32_t)crc;
        localHeader.compressed_size = (uint32_t)[compressed length];
        localHeader.uncompressed_size = (uint32_t)[data length];
        localHeader.filename_length = (uint16_t)[nameData length];
        localHeader.extra_field_length = 0;

        if (!SKWriteAll(f, &localHeader, sizeof(iOSLocalFileHeader)) ||
            !SKWriteAll(f, [nameData bytes], [nameData length]) ||
            !SKWriteAll(f, [compressed bytes], [compressed length])) {
            ok = NO;
            break;
        }

        NSMutableData *cdRecord = [NSMutableData data];
        iOSCentralHeader cdHeader;
        cdHeader.signature = 0x02014b50;
        cdHeader.version_made = 20;
        cdHeader.version_needed = 20;
        cdHeader.flags = 0;
        cdHeader.compression_method = 8;
        cdHeader.last_mod_time = 0;
        cdHeader.last_mod_date = 0;
        cdHeader.crc32 = (uint32_t)crc;
        cdHeader.compressed_size = (uint32_t)[compressed length];
        cdHeader.uncompressed_size = (uint32_t)[data length];
        cdHeader.filename_length = (uint16_t)[nameData length];
        cdHeader.extra_field_length = 0;
        cdHeader.comment_length = 0;
        cdHeader.disk_start = 0;
        cdHeader.internal_attrs = 0;
        cdHeader.external_attrs = 0;
        cdHeader.local_header_offset = (uint32_t)currentOffset;

        [cdRecord appendBytes:&cdHeader length:sizeof(iOSCentralHeader)];
        [cdRecord appendData:nameData];
        [centralHeaders addObject:cdRecord];

        currentOffset += sizeof(iOSLocalFileHeader) + [nameData length] + [compressed length];
        // 32-bit offsets and a 16-bit count: this writer has no ZIP64.
        if (currentOffset > UINT32_MAX || centralHeaders.count >= UINT16_MAX) {
            ok = NO;
            break;
        }
    }

    uint64_t cdSize = 0;
    if (ok) {
        for (NSData *cdRecord in centralHeaders) {
            if (!SKWriteAll(f, [cdRecord bytes], [cdRecord length])) {
                ok = NO;
                break;
            }
            cdSize += [cdRecord length];
        }
    }

    if (ok) {
        iOSEOCD eocd;
        eocd.signature = 0x06054b50;
        eocd.disk_number = 0;
        eocd.disk_with_cd = 0;
        eocd.disk_entries = (uint16_t)[centralHeaders count];
        eocd.total_entries = (uint16_t)[centralHeaders count];
        eocd.cd_size = (uint32_t)cdSize;
        eocd.cd_offset = (uint32_t)currentOffset;
        eocd.comment_length = 0;
        ok = SKWriteAll(f, &eocd, sizeof(iOSEOCD));
    }

    // fclose flushes, so a full disk can surface only here.
    if (fclose(f) != 0) ok = NO;
    if (!ok) unlink([zipPath fileSystemRepresentation]);
    return ok;
}

+ (nullable NSString *)calculateGitBlobShaOfFile:(NSString *)filePath {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:filePath];
    if (!stream)
        return nil;
    [stream open];

    unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] fileSize];
    CC_SHA1_CTX sha1;
    CC_SHA1_Init(&sha1);

    NSString *header = [NSString stringWithFormat:@"blob %llu", fileSize];
    const char *headerStr = [header UTF8String];
    NSMutableData *headerData = [NSMutableData dataWithBytes:headerStr
                                                      length:[header lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    char nullChar = '\0';
    [headerData appendBytes:&nullChar length:1];

    CC_SHA1_Update(&sha1, [headerData bytes], (CC_LONG)[headerData length]);

    uint8_t buffer[8192];
    while ([stream hasBytesAvailable]) {
        NSInteger bytesRead = [stream read:buffer maxLength:sizeof(buffer)];
        if (bytesRead > 0) {
            CC_SHA1_Update(&sha1, buffer, (CC_LONG)bytesRead);
        } else if (bytesRead < 0) {
            [stream close];
            return nil;
        }
    }
    [stream close];

    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &sha1);

    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

/**
 * Reads the central directory, the way java.util.zip does.
 *
 * Deliberately not the sequential local-header walk the rest of this file uses: the point
 * is to answer "would URLClassLoader find this entry", and it reads the central directory.
 * A jar whose central directory is missing or truncated yields no resources at all and no
 * error, which is exactly the failure this is meant to catch.
 */
+ (BOOL)zipFile:(NSString *)zipPath containsEntry:(NSString *)entryName {
    NSData *data = [NSData dataWithContentsOfFile:zipPath options:NSDataReadingMappedIfSafe
                                            error:nil];
    if (data.length < sizeof(iOSEOCD)) return NO;

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;

    // The EOCD sits at the end, after a comment of up to 64 KB.
    NSUInteger searchStart = length > 66000 ? length - 66000 : 0;
    NSInteger eocdOffset = -1;
    for (NSInteger i = (NSInteger)(length - 4); i >= (NSInteger)searchStart; i--) {
        if (OSReadLittleInt32(bytes, i) == 0x06054b50) {
            eocdOffset = i;
            break;
        }
    }
    if (eocdOffset < 0 || (NSUInteger)eocdOffset + 22 > length) return NO;

    uint16_t entryCount = OSReadLittleInt16(bytes, eocdOffset + 10);
    uint32_t directoryOffset = OSReadLittleInt32(bytes, eocdOffset + 16);
    if (directoryOffset >= length) return NO;

    NSUInteger cursor = directoryOffset;
    for (uint16_t i = 0; i < entryCount; i++) {
        if (cursor + 46 > length) return NO;
        if (OSReadLittleInt32(bytes, cursor) != 0x02014b50) return NO;

        uint16_t nameLength = OSReadLittleInt16(bytes, cursor + 28);
        uint16_t extraLength = OSReadLittleInt16(bytes, cursor + 30);
        uint16_t commentLength = OSReadLittleInt16(bytes, cursor + 32);
        if (cursor + 46 + nameLength > length) return NO;

        NSString *name = [[NSString alloc] initWithBytes:bytes + cursor + 46
                                                  length:nameLength
                                                encoding:NSUTF8StringEncoding];
        if ([name isEqualToString:entryName]) return YES;
        cursor += 46 + nameLength + extraLength + commentLength;
    }
    return NO;
}

/// Drops a comma that directly precedes a closing brace or bracket, outside strings. Mod authors
/// write `"version": "1.0",` before the final `}`; the desktop launcher's JSON library accepts
/// it and NSJSONSerialization does not.
+ (NSString *)stripTrailingCommas:(NSString *)json {
    NSMutableString *out = [NSMutableString stringWithCapacity:json.length];
    BOOL inString = NO, escaped = NO;
    for (NSUInteger i = 0; i < json.length; i++) {
        unichar c = [json characterAtIndex:i];
        if (inString) {
            [out appendFormat:@"%C", c];
            if (escaped) escaped = NO;
            else if (c == '\\') escaped = YES;
            else if (c == '"') inString = NO;
        } else if (c == '"') {
            inString = YES;
            [out appendFormat:@"%C", c];
        } else if (c == ',') {
            NSUInteger j = i + 1;
            while (j < json.length && [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[json characterAtIndex:j]]) j++;
            unichar next = j < json.length ? [json characterAtIndex:j] : 0;
            if (next != '}' && next != ']' && next != 0) [out appendFormat:@"%C", c];
        } else {
            [out appendFormat:@"%C", c];
        }
    }
    return out;
}

+ (nullable NSDictionary *)readModMetadataFromZip:(NSString *)zipPath {
    __block NSDictionary *metadata = nil;
    [self enumerateZip:zipPath
              matching:^BOOL(NSString *name) {
                return [name isEqualToString:@"mod.json"] || [name hasSuffix:@"/mod.json"];
              }
            usingBlock:^BOOL(NSString *name, NSData *contents) {
              NSString *text = [[NSString alloc] initWithData:contents encoding:NSUTF8StringEncoding];
              NSData *cleaned = text ? [[SKZipUtils stripTrailingCommas:text] dataUsingEncoding:NSUTF8StringEncoding] : contents;
              id json = [NSJSONSerialization JSONObjectWithData:cleaned options:0 error:nil];
              if ([json isKindOfClass:NSDictionary.class]) metadata = json;
              return NO;
            }];
    return metadata;
}

@end
