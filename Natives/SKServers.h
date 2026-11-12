#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// What is wrong with a server as typed.
typedef NS_ENUM(NSInteger, SKServerProblem) {
    SKServerProblemNone = 0,
    SKServerProblemName,
    SKServerProblemDuplicate,
    SKServerProblemHost,
    SKServerProblemPort,
    SKServerProblemKey,
    SKServerProblemURL,
};

extern NSString *const SKServerIdKey;         ///< string
extern NSString *const SKServerNameKey;       ///< string
extern NSString *const SKServerHostKey;       ///< string
extern NSString *const SKServerPortKey;       ///< NSNumber
extern NSString *const SKServerPublicKeyKey;  ///< string, "modulus#exponent" in hex; blank uses Official's
extern NSString *const SKServerClientURLKey;  ///< string, optional; blank uses Official's
extern NSString *const SKServerContentURLKey; ///< string, optional; blank uses Official's

/// Where the game connects, besides Official. A server is only connection settings: the stock
/// client is pointed at it by rewriting the connection keys in code/config.jar's
/// deployment.properties, the same keys KnightLauncher writes.
@interface SKServers : NSObject

+ (NSArray<NSDictionary *> *)servers;
/// The selected server, or nil for Official (also when the selected one was deleted).
+ (nullable NSDictionary *)selectedServer;
/// Selects @c serverId, or Official for nil.
+ (void)selectServerWithId:(nullable NSString *)serverId;
/// Adds the server, or replaces the one with the same id.
+ (void)saveServer:(NSDictionary *)server;
+ (void)deleteServerWithId:(NSString *)serverId;
+ (NSString *)newServerId;

/// Fields are expected trimmed. @c others are the saved servers, for the duplicate-name check.
+ (SKServerProblem)validateServer:(NSDictionary *)server against:(NSArray<NSDictionary *> *)others;

/// The game wants "scheme://host[:port]", not the full client path a user pastes in.
+ (NSString *)clientRootForURL:(NSString *)url;

/// The connection keys for @c server, or for Official when nil; blank fields fall back to Official's.
+ (NSDictionary<NSString *, NSString *> *)connectionPropertiesForServer:(nullable NSDictionary *)server;

/// @c text (a Java .properties file) with @c values set: existing lines for those keys are replaced
/// in place, missing ones appended, every other line kept as it was.
+ (NSString *)propertiesText:(NSString *)text withValues:(NSDictionary<NSString *, NSString *> *)values;
/// The value of @c key in @c text, or nil.
+ (nullable NSString *)valueForKey:(NSString *)key inPropertiesText:(NSString *)text;

/// The "version = " value of a getdown manifest, or nil.
+ (nullable NSString *)manifestVersionInText:(nullable NSString *)text;

/// Whether Official has a newer game than the one installed under @c skPath. The game's updater would then
/// replace config.jar after we edit it, and the game would silently connect to Official. An unreachable or
/// unreadable manifest counts as no update, so an offline private server still launches. Blocks: call off the main queue.
+ (BOOL)updatePendingForGameAtPath:(NSString *)skPath;

/// Writes @c server's settings (Official's when nil) into the config.jar at @c jarPath, leaving every
/// other entry as it was. An untouched jar is not rewritten. Error code 1 means the jar is missing
/// (the game isn't installed yet); the original is left as it was on any failure. Call off the main queue.
+ (BOOL)applyServer:(nullable NSDictionary *)server toConfigJar:(NSString *)jarPath error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
