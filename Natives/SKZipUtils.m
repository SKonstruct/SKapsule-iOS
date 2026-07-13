#import "SKZipUtils.h"
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

@implementation SKZipUtils

+ (BOOL)extractZipFile:(NSString *)zipPath
           toDirectory:(NSString *)targetDir
        checkProtected:(BOOL)checkProtected
        protectedFiles:(nullable NSSet<NSString *> *)protectedFiles {
    FILE *f = fopen([zipPath UTF8String], "rb");
    if (!f)
        return NO;

    iOSLocalFileHeader header;
    while (fread(&header, 1, sizeof(iOSLocalFileHeader), f) == sizeof(iOSLocalFileHeader)) {
        if (header.signature != 0x04034b50) {
            break;
        }

        char *filename = malloc(header.filename_length + 1);
        if (fread(filename, 1, header.filename_length, f) != header.filename_length) {
            free(filename);
            fclose(f);
            return NO;
        }
        filename[header.filename_length] = '\0';

        fseek(f, header.extra_field_length, SEEK_CUR);

        NSString *entryName = [NSString stringWithUTF8String:filename];
        free(filename);

        if (!entryName) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        if ([entryName hasSuffix:@"/"] || [entryName isEqualToString:@"mod.json"] ||
            [entryName hasSuffix:@"/mod.json"] || [entryName isEqualToString:@"mod.png"] ||
            [entryName hasSuffix:@"/mod.png"]) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        if (checkProtected && protectedFiles && [protectedFiles containsObject:entryName]) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        NSString *destPath = [targetDir stringByAppendingPathComponent:entryName];
        [[NSFileManager defaultManager] createDirectoryAtPath:[destPath stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        uint8_t *compData = malloc(header.compressed_size);
        if (fread(compData, 1, header.compressed_size, f) != header.compressed_size) {
            free(compData);
            fclose(f);
            return NO;
        }

        if (header.compression_method == 0) {
            NSData *data = [NSData dataWithBytesNoCopy:compData length:header.compressed_size freeWhenDone:YES];
            [data writeToFile:destPath atomically:YES];
        } else if (header.compression_method == 8) {
            uint8_t *uncompData = malloc(header.uncompressed_size);

            z_stream strm;
            memset(&strm, 0, sizeof(strm));
            strm.next_in = (Bytef *)compData;
            strm.avail_in = header.compressed_size;
            strm.next_out = (Bytef *)uncompData;
            strm.avail_out = header.uncompressed_size;

            int ret = inflateInit2(&strm, -15);
            if (ret == Z_OK) {
                ret = inflate(&strm, Z_FINISH);
                inflateEnd(&strm);
            }

            free(compData);

            if (ret == Z_STREAM_END || ret == Z_OK) {
                NSData *data = [NSData dataWithBytesNoCopy:uncompData length:header.uncompressed_size freeWhenDone:YES];
                [data writeToFile:destPath atomically:YES];
            } else {
                free(uncompData);
                fclose(f);
                return NO;
            }
        } else {
            free(compData);
            fclose(f);
            return NO;
        }
    }

    fclose(f);
    return YES;
}

+ (BOOL)extractJarWithoutOverwrite:(NSString *)jarPath toDirectory:(NSString *)targetDir {
    FILE *f = fopen([jarPath UTF8String], "rb");
    if (!f)
        return NO;

    iOSLocalFileHeader header;
    while (fread(&header, 1, sizeof(iOSLocalFileHeader), f) == sizeof(iOSLocalFileHeader)) {
        if (header.signature != 0x04034b50) {
            break;
        }

        char *filename = malloc(header.filename_length + 1);
        if (fread(filename, 1, header.filename_length, f) != header.filename_length) {
            free(filename);
            fclose(f);
            return NO;
        }
        filename[header.filename_length] = '\0';

        fseek(f, header.extra_field_length, SEEK_CUR);

        NSString *entryName = [NSString stringWithUTF8String:filename];
        free(filename);

        if (!entryName || [entryName hasSuffix:@"/"]) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        NSString *destPath = [targetDir stringByAppendingPathComponent:entryName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        [[NSFileManager defaultManager] createDirectoryAtPath:[destPath stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        uint8_t *compData = malloc(header.compressed_size);
        if (fread(compData, 1, header.compressed_size, f) != header.compressed_size) {
            free(compData);
            fclose(f);
            return NO;
        }

        if (header.compression_method == 0) {
            NSData *data = [NSData dataWithBytesNoCopy:compData length:header.compressed_size freeWhenDone:YES];
            [data writeToFile:destPath atomically:YES];
        } else if (header.compression_method == 8) {
            uint8_t *uncompData = malloc(header.uncompressed_size);
            z_stream strm;
            memset(&strm, 0, sizeof(strm));
            strm.next_in = (Bytef *)compData;
            strm.avail_in = header.compressed_size;
            strm.next_out = (Bytef *)uncompData;
            strm.avail_out = header.uncompressed_size;

            int ret = inflateInit2(&strm, -15);
            if (ret == Z_OK) {
                ret = inflate(&strm, Z_FINISH);
                inflateEnd(&strm);
            }
            free(compData);

            if (ret == Z_STREAM_END || ret == Z_OK) {
                NSData *data = [NSData dataWithBytesNoCopy:uncompData length:header.uncompressed_size freeWhenDone:YES];
                [data writeToFile:destPath atomically:YES];
            } else {
                free(uncompData);
                fclose(f);
                return NO;
            }
        } else {
            free(compData);
            fclose(f);
            return NO;
        }
    }

    fclose(f);
    return YES;
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

+ (BOOL)createZipFileFromDirectory:(NSString *)sourceDir toZipPath:(NSString *)zipPath {
    NSMutableArray *files = [NSMutableArray array];
    collectFiles(sourceDir, sourceDir, files);

    FILE *f = fopen([zipPath UTF8String], "wb");
    if (!f)
        return NO;

    NSMutableArray *centralHeaders = [NSMutableArray array];
    uint32_t currentOffset = 0;

    for (NSString *filePath in files) {
        NSString *relPath = [filePath substringFromIndex:sourceDir.length + 1];
        if ([relPath isEqualToString:@"mod.json"] || [relPath isEqualToString:@"mod.png"]) {
            continue;
        }

        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (!data)
            continue;

        uLong crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, [data bytes], (uInt)[data length]);

        NSMutableData *compressed = [NSMutableData data];
        z_stream strm;
        memset(&strm, 0, sizeof(strm));
        int ret = deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
        if (ret != Z_OK) {
            fclose(f);
            return NO;
        }

        uint8_t outBuffer[8192];
        strm.next_in = (Bytef *)[data bytes];
        strm.avail_in = (uInt)[data length];

        do {
            strm.next_out = outBuffer;
            strm.avail_out = sizeof(outBuffer);
            ret = deflate(&strm, Z_FINISH);
            NSInteger compressedBytes = sizeof(outBuffer) - strm.avail_out;
            [compressed appendBytes:outBuffer length:compressedBytes];
        } while (strm.avail_out == 0);

        deflateEnd(&strm);

        NSData *nameData = [relPath dataUsingEncoding:NSUTF8StringEncoding];

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

        fwrite(&localHeader, 1, sizeof(iOSLocalFileHeader), f);
        fwrite([nameData bytes], 1, [nameData length], f);
        fwrite([compressed bytes], 1, [compressed length], f);

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
        cdHeader.local_header_offset = currentOffset;

        [cdRecord appendBytes:&cdHeader length:sizeof(iOSCentralHeader)];
        [cdRecord appendData:nameData];
        [centralHeaders addObject:cdRecord];

        currentOffset += sizeof(iOSLocalFileHeader) + [nameData length] + [compressed length];
    }

    uint32_t cdOffset = currentOffset;
    uint32_t cdSize = 0;

    for (NSData *cdRecord in centralHeaders) {
        fwrite([cdRecord bytes], 1, [cdRecord length], f);
        cdSize += [cdRecord length];
    }

    iOSEOCD eocd;
    eocd.signature = 0x06054b50;
    eocd.disk_number = 0;
    eocd.disk_with_cd = 0;
    eocd.disk_entries = (uint16_t)[centralHeaders count];
    eocd.total_entries = (uint16_t)[centralHeaders count];
    eocd.cd_size = cdSize;
    eocd.cd_offset = cdOffset;
    eocd.comment_length = 0;

    fwrite(&eocd, 1, sizeof(iOSEOCD), f);

    fclose(f);
    return YES;
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

+ (nullable NSDictionary *)readModMetadataFromZip:(NSString *)zipPath {
    FILE *f = fopen([zipPath UTF8String], "rb");
    if (!f)
        return nil;

    iOSLocalFileHeader header;
    while (fread(&header, 1, sizeof(iOSLocalFileHeader), f) == sizeof(iOSLocalFileHeader)) {
        if (header.signature != 0x04034b50) {
            break;
        }

        char *filename = malloc(header.filename_length + 1);
        if (fread(filename, 1, header.filename_length, f) != header.filename_length) {
            free(filename);
            fclose(f);
            return nil;
        }
        filename[header.filename_length] = '\0';

        fseek(f, header.extra_field_length, SEEK_CUR);

        NSString *entryName = [NSString stringWithUTF8String:filename];
        free(filename);

        if (!entryName) {
            fseek(f, header.compressed_size, SEEK_CUR);
            continue;
        }

        if ([entryName isEqualToString:@"mod.json"] || [entryName hasSuffix:@"/mod.json"]) {
            uint8_t *compData = malloc(header.compressed_size);
            if (fread(compData, 1, header.compressed_size, f) != header.compressed_size) {
                free(compData);
                fclose(f);
                return nil;
            }

            NSData *uncompressedData = nil;
            if (header.compression_method == 0) {
                uncompressedData = [NSData dataWithBytesNoCopy:compData length:header.compressed_size freeWhenDone:YES];
            } else if (header.compression_method == 8) {
                uint8_t *uncompData = malloc(header.uncompressed_size);

                z_stream strm;
                memset(&strm, 0, sizeof(strm));
                strm.next_in = (Bytef *)compData;
                strm.avail_in = header.compressed_size;
                strm.next_out = (Bytef *)uncompData;
                strm.avail_out = header.uncompressed_size;

                int ret = inflateInit2(&strm, -15);
                if (ret == Z_OK) {
                    ret = inflate(&strm, Z_FINISH);
                    inflateEnd(&strm);
                }

                free(compData);

                if (ret == Z_STREAM_END || ret == Z_OK) {
                    uncompressedData = [NSData dataWithBytesNoCopy:uncompData
                                                            length:header.uncompressed_size
                                                      freeWhenDone:YES];
                } else {
                    free(uncompData);
                    fclose(f);
                    return nil;
                }
            } else {
                free(compData);
                fclose(f);
                return nil;
            }

            if (uncompressedData) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:uncompressedData options:0 error:nil];
                fclose(f);
                return json;
            }
        } else {
            fseek(f, header.compressed_size, SEEK_CUR);
        }
    }

    fclose(f);
    return nil;
}

@end
