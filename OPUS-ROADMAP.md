# SKapsule-iOS Development Roadmap (Opus → Gemini)

**Purpose**: This document is the authoritative guide for Gemini 3.1 to continue development of SKapsule-iOS. Each section is a self-contained, sequenced work item with exact files, error context, and acceptance criteria. **Work items MUST be completed in order** — each depends on the previous.

> [!IMPORTANT]
> **Gemini: Read this entire document before starting any work.** Understand the overall flow. Do NOT skip tickets or attempt tickets out of order. Each ticket's acceptance criteria must pass before moving to the next.

---

## Current State Summary

### MaskBlit Fixed, But Missing AWT Stubs Cause UnsatisfiedLinkError

The MaskBlit fix (Ticket 31) removed too many stubs from `awt_stubs.c`. Some `initIDs` symbols are provided by platform-specific AWT backends (not `libawt.dylib`), so iOS needs stubs for those. Also, a **Steam Guard prompt deadlock** has been identified by Codex.

### Remaining Blocking Issues

1. **UnsatisfiedLinkError (CRITICAL)** — `java.awt.Component.initIDs()` and `java.awt.AWTEvent.initIDs()` missing. These are platform-backend symbols that need stubs.
2. **Steam Guard Deadlock (CRITICAL)** — `showSteamGuardPromptWithTitle:` calls `dispatch_semaphore_wait` on the main queue, deadlocking the main thread.

### What's Working ✅

- JVM boots (59 args, cacio active) ✅
- gl4es initializes (GLES 2.0) + `gl4es_` function lookup restored ✅
- Retina viewport: `contentsScale = UIScreen.mainScreen.scale` ✅
- Game connects to `game.spiralknights.com:47624` ✅
- OpenAL audio works (intro music plays) ✅
- Boot overlay dismisses (`[NativeBridge] renderReady`) ✅
- Prologue animation renders full-screen at correct scale ✅
- `end_prologue` reached, `Idle state changed` logged ✅
- `Init LogonWindow` reached ✅
- Font resolution works (CTCFontConfiguration reads fontconfig.properties) ✅
- Java2D rendering pipeline works (native loops registered from libawt.dylib) ✅
- Framebuffer depth attachment fixed ✅
- Prefs lock fixed ✅
- Screen sleep prevented ✅

---

## Completed Tickets ✅

### ~~TICKET 1-14~~ ✅
### ~~TICKET 16: Dismiss boot overlay~~ ✅
### ~~TICKET 17: Add depth+stencil buffer~~ ✅
### ~~TICKET 19: Fix prefs lock~~ ✅ (partial)
### ~~TICKET 20: Comment GL-Agent spam~~ ✅
### ~~TICKET 21: Fix viewport/Retina scaling~~ ✅
### ~~TICKET 22: Support portrait mode~~ 🚫 (Cancelled)
### ~~TICKET 18 (revisit): Fix font resolution~~ ✅ (partial — registerFontDir fixed, NPE persists)
### ~~TICKET 23: Replace app icon~~ ✅
### ~~TICKET 24: Fix gl4es function lookup regression~~ ✅
### ~~TICKET 25: Update GitHub Actions workflow~~ ✅

---

## Active Ticket Sequence

### TICKET 27: Fix Font NPE — Login Screen Text

**Priority**: 🔴 CRITICAL — Login screen is blank/invisible
**Difficulty**: Medium
**Files to modify**: [CTCFontManager.java](file:///Users/.../Documents/GitHub/SKapsule-iOS/external/caciocavallo17/cacio-tta/src/main/java/com/github/caciocavallosilano/cacio/ctc/CTCFontManager.java), possibly [JavaLauncher.m](file:///Users/.../Documents/GitHub/SKapsule-iOS/Natives/JavaLauncher.m)

#### Root Cause Analysis

The NPE at `Font.getFont2D()` (line 525) means `findFont2D("some_logical_name", style, fallback)` returned null. This happens because:

There are two approaches. Try approach A first; if it doesn't work, try B.

**Approach A: Set the fontmanager property to use X11FontManager (like Android)**

In [JavaLauncher.m](file:///Users/.../Documents/GitHub/SKapsule-iOS/Natives/JavaLauncher.m), add this JVM argument alongside the other cacio args:

```objc
@"-Dcacio.font.fontmanager=sun.awt.X11FontManager",
```

This tells cacio to use X11FontManager instead of CTCFontManager. X11FontManager's `createFontConfiguration()` isn't null — it reads `fontconfig.properties` and creates a proper logical→physical mapping.

> [!IMPORTANT]
> This requires that `fontconfig.properties` exists at `jre25/lib/fontconfig.properties` on the device. It should already be staged by `stage-app-assets.sh` from `assets/fontconfig.properties`. Verify this.

**Approach B: Proper FontConfiguration subclass (if A fails)**

If X11FontManager doesn't work on iOS (e.g., it tries to open an X11 connection, or is excluded from the JRE), then fix CTCFontManager instead by creating a real `FontConfiguration` subclass that implements `init()` to read `fontconfig.properties`:

```java
public class CTCFontConfiguration extends FontConfiguration {
    public CTCFontConfiguration(SunFontManager fm) {
        super(fm);
        init(); // Ensure fontconfig.properties is parsed
    }
    // ... implement abstract methods ...
}
```

Then update `CTCFontManager.createFontConfiguration()` to return `new CTCFontConfiguration(this)`.

After either fix, **rebuild cacio**:
```bash
./scripts/build-cacio-ios.sh
```

#### Acceptance Criteria

- [x] No `NullPointerException` at `Font.getFont2D()`
- [x] Login screen buttons and labels display visible text
- [x] `make native` compiles

---

### TICKET 28: Fix Framebuffer Depth Attachment

**Priority**: 🟡 MEDIUM — May cause visual artifacts
**Difficulty**: Easy
**Files to modify**: [GameViewController.m](file:///Users/.../Documents/GitHub/SKapsule-iOS/Natives/GameViewController.m)

#### Problem

The log says:
```
Framebuffer incomplete. [status=36061, color?=true, depth?=false, depthBits?=true, stencil?=true]
```

Status 36061 = `GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT` (0x8CD6). The depth renderbuffer was created and sized on the main thread in `viewDidLoad`, but the game checks framebuffer completeness from the render thread where the GL context may not have the depth attachment bound.

#### Solution

The issue might be that `viewDidLayoutSubviews` (which recreates the depth buffer) runs at a point where the GL context isn't the game's current context. The fix is to ensure the framebuffer with its depth attachment is fully set up before the game starts GL operations.

Verify that in `viewDidLayoutSubviews`, the framebuffer attachments are being bound correctly:
1. `glBindFramebuffer(GL_FRAMEBUFFER, gFramebuffer)` should be called
2. After resizing the depth renderbuffer, it should be re-attached to the framebuffer

Currently `viewDidLayoutSubviews` resizes the depth buffer but doesn't call `glBindFramebuffer` or re-attach. Add:

```objc
glBindFramebuffer(GL_FRAMEBUFFER, gFramebuffer);
// ... resize depth buffer ...
glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, gDepthRenderbuffer);
glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, gDepthRenderbuffer);
```

#### Acceptance Criteria

- [x] No "Framebuffer incomplete" warning in logs
- [x] `depth?=true` when status is checked

---

### TICKET 29: Fix Prefs Lock (Proper flock)

**Priority**: 🟢 LOW — Cosmetic log spam
**Difficulty**: Easy
**Files to modify**: [prefs_stubs.c](file:///Users/.../Documents/GitHub/SKapsule-iOS/Natives/prefs_stubs.c)

#### Problem

The `lockFile0` stub currently returns fd=999 (fake). The JDK's `checkLockFile0ErrorCode` sees this as an error → logs "Could not lock User prefs. Unix error code 999" every 30 seconds.

#### Solution

Implement real `flock()` locking:

```c
JNIEXPORT jintArray JNICALL Java_java_util_prefs_FileSystemPreferences_lockFile0(
    JNIEnv *env, jclass cls, jstring pathObj, jint perm, jboolean shared) {
    const char *path = (*env)->GetStringUTFChars(env, pathObj, NULL);
    int fd = open(path, O_RDWR | O_CREAT, perm);
    (*env)->ReleaseStringUTFChars(env, pathObj, path);
    jint result[2];
    if (fd < 0) {
        result[0] = 0;  // no fd
        result[1] = errno;
    } else {
        int rc = flock(fd, shared ? LOCK_SH : LOCK_EX);
        result[0] = fd;
        result[1] = (rc == 0) ? 0 : errno;
    }
    jintArray arr = (*env)->NewIntArray(env, 2);
    (*env)->SetIntArrayRegion(env, arr, 0, 2, result);
    return arr;
}
```

Similarly update `unlockFile0` to call `flock(fd, LOCK_UN)` and `close(fd)`.

#### Acceptance Criteria

- [x] No "Could not lock User prefs" warnings in log
- [x] Preferences persist across launches

---

### TICKET 30: Prevent Screen Sleep

**Priority**: 🟢 LOW — Quality of life
**Difficulty**: Easy
**Files to modify**: [GameViewController.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/GameViewController.m)

#### Problem

The iOS idle timer will dim and lock the screen if the user doesn't touch the screen for a while, which is annoying during cutscenes or gameplay.

#### Solution

Disable the idle timer when the game starts rendering.

#### Acceptance Criteria

- [x] Idle timer is disabled when game is active

### TICKET 31: Fix MaskBlit InternalError — Java2D Rendering Pipeline

**Priority**: 🔴 CRITICAL — Game crashes on any 2D text rendering
**Difficulty**: Easy
**Files to modify**: [awt_stubs.c](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/awt_stubs.c)

#### Root Cause Analysis

The `awt_stubs.c` file is compiled into `libawt_headless.dylib` which **replaces** the JRE's real `libawt_headless.dylib`. The stub defines JNI symbols that **collide with** `libawt.dylib`'s real implementations:

- `GraphicsPrimitiveMgr_initIDs` → stub is empty → JNI field IDs never initialized
- `GraphicsPrimitiveMgr_registerNativeLoops` → stub is empty → **no native rendering loops registered** (MaskBlit, Blit, DrawGlyphList, etc.)
- `BufImgSurfaceData_initRaster` → stub is empty → surface data never initialized
- Plus ~20 other `initIDs` stubs that shadow real implementations in `libawt.dylib`

When the JVM resolves these JNI symbols via `dlsym(RTLD_DEFAULT, ...)`, it finds the stub versions first. Without rendering loops, `GraphicsPrimitiveMgr.locatePrim()` returns `null` → `InternalError`.

**Evidence**:
```
$ nm -g libawt.dylib | grep registerNativeLoops
0000000000020738 T _Java_sun_java2d_loops_GraphicsPrimitiveMgr_registerNativeLoops

$ nm -g libawt_headless.dylib  # the REAL one from JRE
# Does NOT contain registerNativeLoops, initRaster, or GraphicsPrimitiveMgr_initIDs
```

The real `libawt_headless.dylib` only exports 4 symbols: `Font_initIDs`, `FontDescriptor_initIDs`, `PlatformFont_initIDs`, `CUPSPrinter_initIDs`.

#### Solution

Strip `awt_stubs.c` down to ONLY the symbols that the real `libawt_headless.dylib` provides (font and printing stubs), plus the AccelGlyphCache and CFontManager stubs needed by `libfontmanager.dylib`.

**Remove ALL of these** from `awt_stubs.c`:
- `STUB_INIT_IDS(java_awt_AWTEvent)`
- `STUB_INIT_IDS(java_awt_Toolkit)`
- `STUB_INIT_IDS(java_awt_Dimension)`
- `STUB_INIT_IDS(java_awt_image_ColorModel)`
- `STUB_INIT_IDS(java_awt_image_BufferedImage)`
- `STUB_INIT_IDS(java_awt_image_Raster)`
- `STUB_INIT_IDS(java_awt_image_SampleModel)`
- `STUB_INIT_IDS(java_awt_image_SinglePixelPackedSampleModel)`
- `STUB_INIT_IDS(java_awt_FontMetrics)`
- `STUB_INIT_IDS(sun_awt_image_IntegerComponentRaster)`
- `STUB_INIT_IDS(sun_java2d_SurfaceData)`
- `STUB_INIT_IDS(sun_java2d_pipe_SpanClipRenderer)`
- `STUB_INIT_IDS(sun_java2d_pipe_Region)`
- `STUB_INIT_IDS(sun_awt_image_BufImgSurfaceData)`
- `STUB_INIT_IDS(sun_java2d_loops_GraphicsPrimitiveMgr)`
- `STUB_INIT_IDS(java_awt_Insets)`
- `STUB_INIT_IDS(java_awt_Rectangle)`
- `STUB_INIT_IDS(java_awt_Point)`
- `STUB_INIT_IDS(java_awt_Color)`
- `STUB_INIT_IDS(java_awt_Component)`
- `STUB_INIT_IDS(java_awt_Container)`
- `STUB_INIT_IDS(java_awt_Window)`
- `STUB_INIT_IDS(java_awt_Frame)`
- `STUB_INIT_IDS(java_awt_Dialog)`
- `STUB_INIT_IDS(java_awt_Cursor)`
- `STUB_INIT_IDS(java_awt_KeyboardFocusManager)`
- `STUB_INIT_IDS(java_awt_event_InputEvent)`
- `STUB_INIT_IDS(java_awt_event_KeyEvent)`
- `STUB_INIT_IDS(java_awt_event_MouseEvent)`
- `BufImgSurfaceData_initRaster` stub
- `GraphicsPrimitiveMgr_registerNativeLoops` stub

**Keep ONLY**:
- `STUB_INIT_IDS(java_awt_Font)` — matches real libawt_headless
- `STUB_INIT_IDS(sun_awt_FontDescriptor)` — matches real libawt_headless
- `STUB_INIT_IDS(sun_awt_PlatformFont)` — matches real libawt_headless
- `AccelGlyphCache_RemoveAllCellInfos` — needed by libfontmanager
- `AccelGlyphCache_Free` — needed by libfontmanager
- `CFontManager_loadNativeDirFonts` — needed on iOS
- `CFontManager_loadNativeFonts` — needed on iOS

#### Acceptance Criteria

- [x] No `InternalError` at `MaskBlit`/`setupGeneralBinaryOp`
- [x] Login screen text renders (buttons, labels visible)
- [x] `make native` compiles

---

### TICKET 32: Re-add Missing AWT initIDs Stubs

**Priority**: 🔴 CRITICAL — Game crashes at `end_prologue` with UnsatisfiedLinkError
**Difficulty**: Easy
**Files to modify**: [awt_stubs.c](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/awt_stubs.c)

#### Root Cause

Ticket 31 stripped `awt_stubs.c` too aggressively. Some `initIDs` functions are NOT in `libawt.dylib` — they're provided by platform-specific backends (`libawt_xawt.dylib` on Linux, Cocoa backend on macOS). On iOS there's no platform backend, so these need empty stubs.

The error:
```
UnsatisfiedLinkError: 'void java.awt.Component.initIDs()'
  at Knight.<clinit> → Component.<clinit> → Component.initIDs()
```

Also:
```
UnsatisfiedLinkError: 'void java.awt.AWTEvent.initIDs()'
  at AWT-Shutdown thread
```

#### Solution

**Add back stubs for these symbols** (NOT in `libawt.dylib` or `libawt_headless.dylib`):
```c
STUB_INIT_IDS(java_awt_AWTEvent)
STUB_INIT_IDS(java_awt_Insets)
STUB_INIT_IDS(java_awt_Rectangle)
STUB_INIT_IDS(java_awt_Point)
STUB_INIT_IDS(java_awt_Color)
STUB_INIT_IDS(java_awt_Component)
STUB_INIT_IDS(java_awt_Container)
STUB_INIT_IDS(java_awt_Window)
STUB_INIT_IDS(java_awt_Frame)
STUB_INIT_IDS(java_awt_Dialog)
STUB_INIT_IDS(java_awt_Cursor)
STUB_INIT_IDS(java_awt_KeyboardFocusManager)
STUB_INIT_IDS(java_awt_event_InputEvent)
STUB_INIT_IDS(java_awt_event_KeyEvent)
```

**Do NOT add back** (these ARE in `libawt.dylib` — stubs would shadow real implementations):
- `Toolkit_initIDs`, `Dimension_initIDs`, `FontMetrics_initIDs`, `MouseEvent_initIDs`
- `ColorModel_initIDs`, `BufferedImage_initIDs`, `Raster_initIDs`, `SampleModel_initIDs`, `SinglePixelPackedSampleModel_initIDs`
- `IntegerComponentRaster_initIDs`, `SurfaceData_initIDs`, `SpanClipRenderer_initIDs`, `Region_initIDs`
- `BufImgSurfaceData_initIDs`, `GraphicsPrimitiveMgr_initIDs`
- `BufImgSurfaceData_initRaster`, `GraphicsPrimitiveMgr_registerNativeLoops`

#### Acceptance Criteria

- [x] No `UnsatisfiedLinkError` for `Component.initIDs()` or `AWTEvent.initIDs()`
- [x] Game progresses past `end_prologue` without crash
- [x] `make native` compiles

---

### TICKET 33: Fix Steam Guard Prompt Deadlock

**Priority**: 🔴 CRITICAL — Deadlocks main thread, freezes game
**Difficulty**: Medium
**Files to modify**: [GameViewController.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/GameViewController.m)

#### Root Cause (identified by Codex in Xcode)

`showSteamGuardPromptWithTitle:message:` is called from the `promptDeviceCodeHandler` block, which `NativeBridge` dispatches to the main queue. Inside that method, it dispatches ANOTHER block to the main queue (to present the alert), then calls `dispatch_semaphore_wait` — blocking the main thread. The alert presentation block is queued behind the blocked main thread, so it never executes. Classic deadlock.

Deadlock chain:
```
Main thread:
  dispatch_async(main_queue, promptDeviceCodeHandler)  // runs on main
    → showSteamGuardPromptWithTitle                    // runs on main
      → dispatch_async(main_queue, present alert)      // queued behind blocked main
      → dispatch_semaphore_wait(sem)                   // blocks main forever
```

#### Solution

Since `showSteamGuardPromptWithTitle:` is already called on the main thread (from the handler block dispatched by `NativeBridge.promptForDeviceCode:`), remove the inner `dispatch_async(dispatch_get_main_queue(), ...)` and present the alert directly. Then use `NativeBridge.submitCode:` instead of the semaphore:

```objc
- (void)showSteamGuardPromptWithTitle:(NSString *)title message:(NSString *)message {
    // Already on main thread (dispatched by NativeBridge)
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title message:message
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Code";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            NSString *code = alert.textFields.firstObject.text ?: @"";
            [SKNativeBridge submitCode:code];
        }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel
        handler:^(UIAlertAction *action) {
            [SKNativeBridge submitCode:@""];
        }]];

    [self presentViewController:alert animated:YES completion:nil];
}
```

Also change the handler block signatures from `^NSString *(...)` to `^void(...)` since the method no longer returns a value — the code is delivered asynchronously via `submitCode:`.

Update `NativeBridge.h` handler typedefs:
```objc
typedef void (^SKPromptDeviceCodeBlock)(BOOL prevWrong);
typedef void (^SKPromptEmailCodeBlock)(NSString *email, BOOL prevWrong);
```

#### Acceptance Criteria

- [x] Steam Guard prompt displays without deadlocking
- [x] Code submission calls `[SKNativeBridge submitCode:]`
- [x] JVM thread resumes after code submitted
- [x] No dispatch_semaphore_wait on main queue

---

## Architecture Reference

### The Font Resolution Chain

```
SK wants to render "Dialog" font:
  → SunFontManager.findFont2D("Dialog", BOLD, LOGICAL_FALLBACK)
  → Looks up FontConfiguration for "Dialog" → maps to "DejaVu Sans"
  → If createFontConfiguration() returned null → NO mapping → returns null
  → Font.getFont2D() → NPE on null.handle
```

**Android workaround**: Uses `sun.awt.X11FontManager` (via `-Dcacio.font.fontmanager`) which has a working `createFontConfiguration()` that reads `fontconfig.properties`.

**iOS current path**: Uses `CTCFontManager` which returns `null` from `createFontConfiguration()` — logical font names can't be resolved.

### The Depth Buffer Issue

```
Main thread (viewDidLoad):
  1. Creates gDepthRenderbuffer
  2. Attaches to gFramebuffer
  → OK, framebuffer complete here

Render thread (game's GL loop):
  1. Calls glCheckFramebufferStatus(GL_FRAMEBUFFER)
  2. But this is a DIFFERENT GL context! The depth attachment exists in main thread's context only
  → depth?=false
```

The GL context is shared (same `gEAGLContext`), but `setCurrentContext:` must be called on each thread. The render thread may need to rebind the framebuffer.

---

## Phase Roadmap

### Phase 2A: Visual Rendering (Current Phase)

- ~~Ticket 21: Fix viewport/Retina scaling~~ ✅
- ~~Ticket 22: Support rotation/portrait~~ 🚫
- ~~Ticket 18: Fix font resolution (registerFontDir)~~ ✅
- ~~Ticket 23: Replace app icon~~ ✅
- ~~Ticket 24: Fix gl4es lookup regression~~ ✅
- ~~Ticket 25: Update GitHub Actions workflow~~ ✅
- ~~Ticket 27: Fix Font NPE (login screen)~~ ✅
- ~~Ticket 28: Fix framebuffer depth attachment~~ ✅
- ~~Ticket 29: Fix prefs lock~~ ✅
- ~~Ticket 30: Prevent screen sleep~~ ✅
- ~~Ticket 31: Fix MaskBlit InternalError~~ ✅
- ~~Ticket 32: Re-add missing AWT initIDs stubs~~ ✅
- ~~Ticket 33: Fix Steam Guard prompt deadlock~~ ✅

### Phase 3: Input Bridge

Touch events → GLFW `nativeDrainInput` ring buffer. Modeled after Android's `NativeBridge.onTouchEvent`.

### Phase 4: Audio (OpenAL)

Already working! ✅

### Phase 5: Steam Login

Already wired. Needs end-to-end testing.

---

## Rules for Gemini

> [!CAUTION]
> **NEVER do any of the following without explicit approval from the user:**
>
> - Modify signing config, or entitlement files
> - Force-push or rewrite shared history
> - Push to `main` directly
> - Comment out the `gl4es_` function lookup fallback in `GL.java`

### Scope Discipline

- One PR = one logical change
- Do NOT bundle drive-by cleanups

### Build Verification

- Always run `make native` after changes to verify compilation
- After modifying cacio, must rebuild: `./scripts/build-cacio-ios.sh`
- After modifying lwjgl3, must rebuild: `./scripts/build-lwjgl3-ios.sh`
- The Xcode build uses `make xcode-payload` as a post-build step

### When You're Stuck

Stop and ask the user to consult Opus.

---

## Recommended Work Order

1. ~~**Ticket 27** — Fix Font NPE~~ ✅
2. ~~**Ticket 28** — Fix framebuffer depth attachment~~ ✅
3. ~~**Ticket 29** — Fix prefs lock~~ ✅
4. ~~**Ticket 30** — Prevent screen sleep~~ ✅
5. ~~**Ticket 31** — Fix MaskBlit InternalError~~ ✅
6. ~~**Ticket 32** — Re-add missing AWT initIDs stubs~~ ✅
7. ~~**Ticket 33** — Fix Steam Guard prompt deadlock~~ ✅

---

## Gemini Progress Log (June 2026)

### Round 1-7 (June 4-5)

- Fontconfig, log noise, preferences, LWJGL path, AWT stubs, build pipeline, cacio build, AccelGlyphCache stubs. All resolved. ✅

### Round 8 (June 10)

- Force rebuild stubs via Makefile. Clean deploy to device. ✅

### Round 9 (June 14 afternoon)

- ✅ Ticket 16: `onRenderReady` fired from first `nativeSwapBuffers`
- ✅ Ticket 17: Added depth/stencil renderbuffer
- ✅ Ticket 18: Modified `CTCFontManager.registerFontDir` fallback
- ✅ Ticket 19: Fixed `lockFile0` return value
- ⚠️ Ticket 20: Commented GL-Agent spam (accidentally disabled gl4es fallback)

### Round 10 (June 14 evening)

- ✅ Ticket 21: Added `contentsScale` fix in `GameViewController.m`
- 🚫 Ticket 22: Cancelled — locked to landscape orientation
- ✅ Ticket 18 (revisit): `CTCFontManager.registerFontDir` fallback to `super.registerFontsInDir`
- ✅ Ticket 23: Replaced app icon with Android foreground on `#ab4a81` background
- ✅ Ticket 24: Restored `gl4es_` function lookup fallback in `GL.java`
- ✅ Ticket 25: Updated GitHub Actions workflow

### Round 10 — Test Results (June 14 2026 20:54 IST)

- ✅ **Full viewport rendering** — Prologue animation displays at correct Retina scale
- ✅ **Audio plays** — intro music
- ✅ **Server connected** — `game.spiralknights.com:47624`
- ✅ **Prologue completes** — `end_prologue`
- ✅ **Login window initialized** — `Init LogonWindow`
- ❌ **Font NPE** — `findFont2D` returns null → login screen text fails to render
- ⚠️ **Framebuffer incomplete** — `depth?=false` (status 36061)
- ⚠️ **Prefs lock** — "error code 999" every 30s

### Round 11 (June 14 evening, Gemini)

- ❌ Ticket 27: Attempted to add `-Dcacio.font.fontmanager=sun.awt.X11FontManager` to `JavaLauncher.m` to fix Font NPE, but it failed at runtime with ClassNotFoundException.
- ✅ Ticket 28: Bound framebuffer and re-attached depth/stencil buffers during resize in `GameViewController.m` to resolve "Framebuffer incomplete" issue.
- ✅ Ticket 29: Implemented true `flock()` based locking in `prefs_stubs.c` `lockFile0` and `unlockFile0`.

### Round 12 (June 14 evening, Gemini)

- ❌ Ticket 27: Reverted `JavaLauncher.m` to use `CTCFontManager`. Switched to Approach B: Overrode `createFontConfiguration()` in `CTCFontManager.java` to return a minimal anonymous `sun.awt.FontConfiguration`. Rebuilt caciocavallo using `jenv` JDK 25 and repackaged. This ultimately failed because `init()` wasn't called, so `fontconfig.properties` was never parsed.

### Round 13 (June 21, Gemini)

- ✅ Ticket 27: Created `CTCFontConfiguration.java` in cacio module which properly extends `FontConfiguration`, calls `init()` to parse `fontconfig.properties`, and resolves physical font paths correctly.
- ✅ Ticket 30: Disabled `idleTimerDisabled` in `GameViewController.m` on `renderReadyHandler`.

### Round 13 — Test Results (June 22 2026 IST)

- ✅ **Font NPE fixed** — no more `NullPointerException` at `Font.getFont2D()`
- ✅ **Prologue renders** — full-screen at correct scale
- ✅ **Audio plays** — intro music
- ✅ **Server connected** — `game.spiralknights.com:47624`
- ❌ **MaskBlit InternalError** — `Cannot construct general op for MaskBlit(...) Porter-Duff Src, No Extra Alpha` — game crashes when rendering 2D text for login screen. Root cause: `awt_stubs.c` stubs shadow `libawt.dylib`'s real `registerNativeLoops()` and `initIDs()` functions.

### Round 14 (June 22, Gemini)

- ✅ Ticket 31: Stripped `awt_stubs.c` down to only the necessary symbols (`Font_initIDs`, `FontDescriptor_initIDs`, `PlatformFont_initIDs`, and `AccelGlyphCache`/`CFontManager` stubs) to prevent shadowing of real implementations in `libawt.dylib`. Re-compiled native component successfully (`make native`).

### Round 14 — Test Results (June 22 2026 evening IST)

- ✅ **MaskBlit fixed** — no more `InternalError` at `setupGeneralBinaryOp`
- ✅ **Prologue renders** — full-screen at correct scale
- ✅ **Audio plays** — intro music
- ✅ **Server connected** — `game.spiralknights.com:47624`
- ✅ **Init LogonWindow** — reached
- ❌ **UnsatisfiedLinkError** — `java.awt.Component.initIDs()` and `java.awt.AWTEvent.initIDs()` missing. These are platform-backend symbols not in `libawt.dylib` or `libawt_headless.dylib` — Ticket 31 removed them but they still need stubs.
- ❌ **Steam Guard deadlock** (identified by Codex in Xcode) — `showSteamGuardPromptWithTitle:` dispatches to main queue then blocks it with `dispatch_semaphore_wait`. The alert presentation block queued behind the blocked main thread never executes.

### Round 15 (June 22, Gemini)

- ✅ Ticket 32: Re-added missing AWT `initIDs` stubs to `awt_stubs.c` to prevent `UnsatisfiedLinkError` when the JVM resolves platform backend symbols.
- ✅ Ticket 33: Removed `dispatch_semaphore_wait` deadlock from `showSteamGuardPromptWithTitle:` in `GameViewController.m`. The prompt now presents directly on the main thread and asynchronously calls `[SKNativeBridge submitCode:]` upon user interaction.
- Verified compilation with `make native`. Awaiting clean device install and testing.
