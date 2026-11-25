#pragma once

#import <Foundation/Foundation.h>

// When the launcher applies the mods by itself. Header-only and Foundation-only so `make test` runs it; the
// same rule and cases as Android's ModsSync.kt (keep them in step).
//
// The inputs are two fingerprints: the mods folder (name, size and time of each mod) and the game's own file list
// (digest2.txt, it changes when the game updates and puts its jars back). They are saved after every apply or reset.
// Applying again is needed when either changed. Removing every mod restores the game
// once. After "Reset Game Files" the current fingerprints are saved, so the mods already in the folder stay
// unapplied until the folder changes.

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SKModSyncAction) {
    SKModSyncNone,
    SKModSyncApply,
    SKModSyncRestore,
};

/// `jars` is the game fingerprint. `storedMods` / `storedJars` are nil before anything was ever applied or reset; `storedMods` is "" after a restore
/// with no mods.
static inline SKModSyncAction SKModSyncDecide(BOOL gameInstalled, NSString *mods, NSString *jars,
                                               NSString *_Nullable storedMods, NSString *_Nullable storedJars) {
    if (!gameInstalled) return SKModSyncNone;
    BOOL haveMods = mods.length > 0;
    if (storedMods == nil) return haveMods ? SKModSyncApply : SKModSyncNone;
    if (!haveMods) return storedMods.length > 0 ? SKModSyncRestore : SKModSyncNone;
    return ([mods isEqualToString:storedMods] && [jars isEqualToString:storedJars ?: @""]) ? SKModSyncNone : SKModSyncApply;
}

NS_ASSUME_NONNULL_END
