#pragma once

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

extern BOOL isJailbroken;
extern BOOL debugLogEnabled;

BOOL isJITEnabled(BOOL checkCSFlags);
id getEntitlementValue(NSString *key);
void init_bypassDyldLibValidation(void);

// Device JIT capability flags (ported from AngelAuraMC / Amethyst-iOS).
typedef enum {
    JIT_FLAG_IS_IOS_26 = 1 << 0,
    JIT_FLAG_FORCE_MIRRORED = 1 << 1,  // process can't self-create RX pages (TXM/W^X)
    JIT_FLAG_HAS_TXM = 1 << 2,         // device has a Trusted Execution Monitor
} JITFlags;
JITFlags DeviceGetJITFlags(BOOL refresh);
BOOL DeviceHasJITFlags(JITFlags flags);
// Exported so the AngelAuraMC libjvm can dlsym it to pick its codegen strategy.
BOOL DeviceHasTXM(void);
// Heuristic: is a debugger (StikDebug) still attached to service JIT syscalls?
BOOL JIT26IsLikelyDebuggerKeepAttached(void);
// Builds the stikjit:// URL that asks StikJIT to enable JIT for this process.
NSURL *skJITEnableURL(void);
// Copies the bundled UniversalJIT26.js into the app's Documents folder (visible
// in Files) so it can be imported/assigned in StikJIT. Returns its path.
NSString *skStageJITScriptToDocuments(void);

NSString *getSelectedJavaHome(int minVersion);
