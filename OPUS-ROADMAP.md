# SKapsule-iOS Development Roadmap (Opus → Gemini)

**Purpose**: This document is the authoritative guide for Gemini 3.5 to continue development of SKapsule-iOS. Each section is a self-contained, sequenced work item with exact files, error context, and acceptance criteria. **Work items MUST be completed in order** — each depends on the previous.

> [!IMPORTANT]
> **Gemini: Read this entire document before starting any work.** Understand the overall flow. Do NOT skip tickets or attempt tickets out of order. Each ticket's acceptance criteria must pass before moving to the next.

---

## Current State Summary

All critical startup/rendering issues and font crashes have been resolved:

- **Font NPE Fixed**: The application now successfully runs with `CTCFontManager` enabled, and all custom log outputs reach the Xcode console properly.
- **Render Thread SIGSEGV Fixed**: Resolved the `GLRResourceList::addResource` crash by dynamically binding the custom `gFramebuffer` on the render thread context and using it as the default target in `gl4es`.
- **Installer Caching Fixed**: `SKInstaller` is now version-aware, correctly re-staging updated JARs to the device documents container on every new build.
- **Prologue E2E Completed**: The entire prologue runs without errors, animations render full-screen at correct scale without freezing, and logon screen initialization is reached.

### Remaining Tasks

1. **🔴 glGetUniformLocation NULL Name Crash**: Fix the SIGSEGV crash occurring when `glGetUniformLocation` or `glGetAttribLocation` is called with a `NULL` name parameter after the prologue finishes.
2. **Input Bridge (Phase 3)** — Touch events → GLFW input buffer.
3. **Steam Login E2E (Phase 5)** — Credentials authentication testing.

### What's Working ✅

- JVM boots (61 args, cacio active, CTCFontManager forced) ✅
- gl4es initializes (GLES 2.0) + `gl4es_` function lookup restored ✅
- Retina viewport: `contentsScale = UIScreen.mainScreen.scale` ✅
- Game connects to `game.spiralknights.com:47624` ✅
- OpenAL audio works (intro music plays through to login) ✅
- Boot overlay dismisses (`[NativeBridge] renderReady`) ✅
- Prologue animation renders full-screen at correct scale and runs to completion ✅
- `end_prologue` reached, logon window initialization succeeded ✅
- Cacio jar version-aware staging and custom `CTCFontManager` execution ✅
- Java2D rendering pipeline works (native loops registered from libawt.dylib) ✅
- Prefs lock fixed ✅
- Screen sleep prevented ✅

### What's Broken ❌

- **glGetUniformLocation NULL crash** — glGetUniformLocation / glGetAttribLocation crash on NULL name parameter ❌

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

### TICKET 34: Fix Font NPE — fontNameMap Never Populated ⚠️ REOPENED

**Priority**: 🔴 CRITICAL — Login screen invisible, game appears frozen
**Difficulty**: Medium
**Files to modify**: [CTCFontConfiguration.java](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/external/caciocavallo17/cacio-tta/src/main/java/com/github/caciocavallosilano/cacio/ctc/CTCFontConfiguration.java), [CTCFontManager.java](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/external/caciocavallo17/cacio-tta/src/main/java/com/github/caciocavallosilano/cacio/ctc/CTCFontManager.java), `assets/fonts/fonts.dir` [NEW], `scripts/stage-app-assets.sh`
**Rebuild**: `./scripts/build-cacio-ios.sh` after Java changes, `make payload` after all

#### Root Cause (corrected — JDK 25 source trace)

The previous analysis (Round 15-16) incorrectly identified the failure point as `getFileNameFromComponentFontName()`. That method is only a FALLBACK. The actual failure chain:

```
SunFontManager constructor (line 299-434 of SunFontManager.java):
  1. registerFontsInDir(jreFontDirName)
     → Scans jre25/lib/fonts/ for .ttf files
     → Registers each as a PhysicalFont (TrueTypeFont) with FULL PATH as key
     → fontNameCache["dejavu sans"] = PhysicalFont("DejaVu Sans")

  2. if (FontUtilities.isLinux) {            ← LINE 331: THE BUG
         registerFontDir(jreFontDirName);    ← ONLY ON LINUX!
     }
     → On iOS: registerFontDir is NEVER called
     → fontNameMap stays EMPTY (no XLFD → filepath entries)

  3. fontConfig = createFontConfiguration()
     → CTCFontConfiguration constructor runs
     → init() reads fontconfig.properties → populates binary tables
     → This part works correctly

  4. initCompositeFonts(fontConfig, null)
     → For each platform font name (XLFD like "-dejavu-sans-bold-r-..."):
         getFileNameFromPlatformName(xlfd)
           → SunFontManager.getFileNameFromPlatformName()
             → fontConfig.getFileNameFromPlatformName()
               → filenamesMap.get(xlfd)
               → Returns mapFileName("DejaVuSans-Bold.ttf") = full path   ← THIS WORKS
           → CTCFontManager.getFileNameFromPlatformName() at line 189:
             fileName = super.getFileNameFromPlatformName(platName)
             → Returns the full path from step above                       ← THIS WORKS
           → Then at line 195: if (fileName.startsWith("/"))
             → Tries to add to xlfdMap
             → But never reaches fontNameMap.put()                         ← fontNameMap STAYS EMPTY

         registerFontFile(fontFileName, ...)
           → Registers file as deferred font                               ← THIS WORKS

     → fontConfig.get2DCompositeFontInfo()
       → For each logical font × style:
           componentFileNames[i] = mapFileName(getComponentFileName(fileNameID))
           → PRIMARY path: reads from binary table
           → Returns full path to .ttf                                      ← THIS WORKS

     → registerCompositeFont("dialog.bold", componentFileNames, ...)
       → Creates CompositeFont with deferred slots                          ← THIS SHOULD WORK
```

Wait — if the PRIMARY path works, why does `findFont2D("Dialog", BOLD)` return null? There are two possible remaining failure points:

1. **`fontConfigFile` is null** → `readFontConfigFile(null)` does nothing → binary tables are empty → `get2DCompositeFontInfo()` produces empty arrays → no composites registered
2. **CompositeFont deferred slot resolution fails** → The composite IS registered but its deferred physical font can't be loaded

**We need the `System.err` diagnostic logging (Round 17 Step 1-2) to determine which failure point is active.**

#### Solution (Three-pronged — execute ALL)

**Prong 1: Diagnostic logging with `System.err`** (see Round 17 Instructions above)

**Prong 2: Force `registerFontDir()` call from `CTCFontManager` constructor**

```java
// In CTCFontManager.java, add/modify constructor:
public CTCFontManager() {
    super();
    // Force font dir registration — normally Linux-only in SunFontManager
    String jreFonts = System.getProperty("java.home") + File.separator + "lib" + File.separator + "fonts";
    System.err.println("[CTCFontManager] Forcing registerFontDir for: " + jreFonts);
    registerFontDir(jreFonts);
}
```

AND create `assets/fonts/fonts.dir` so `registerFontDir()` has something to parse:

```
12
DejaVuSans.ttf -dejavu-sans-book-r-normal--0-0-0-0-p-0-iso10646-1
DejaVuSans-Bold.ttf -dejavu-sans-bold-r-normal--0-0-0-0-p-0-iso10646-1
DejaVuSans-Oblique.ttf -dejavu-sans-book-o-normal--0-0-0-0-p-0-iso10646-1
DejaVuSans-BoldOblique.ttf -dejavu-sans-bold-o-normal--0-0-0-0-p-0-iso10646-1
DejaVuSerif.ttf -dejavu-serif-book-r-normal--0-0-0-0-p-0-iso10646-1
DejaVuSerif-Bold.ttf -dejavu-serif-bold-r-normal--0-0-0-0-p-0-iso10646-1
DejaVuSerif-Italic.ttf -dejavu-serif-book-i-normal--0-0-0-0-p-0-iso10646-1
DejaVuSerif-BoldItalic.ttf -dejavu-serif-bold-i-normal--0-0-0-0-p-0-iso10646-1
DejaVuSansMono.ttf -dejavu-sans mono-book-r-normal--0-0-0-0-m-0-iso10646-1
DejaVuSansMono-Bold.ttf -dejavu-sans mono-bold-r-normal--0-0-0-0-m-0-iso10646-1
DejaVuSansMono-Oblique.ttf -dejavu-sans mono-book-o-normal--0-0-0-0-m-0-iso10646-1
DejaVuSansMono-BoldOblique.ttf -dejavu-sans mono-bold-o-normal--0-0-0-0-m-0-iso10646-1
```

AND update `stage-app-assets.sh` to copy `fonts.dir` alongside the `.ttf` files.

**Prong 3: Null-safe `findFont2D` fallback in `CTCFontManager`**

```java
@Override
public sun.font.Font2D findFont2D(String name, int style, int fallback) {
    sun.font.Font2D font = super.findFont2D(name, style, fallback);
    if (font == null) {
        System.err.println("[CTCFontManager] findFont2D null for '" + name + "' style=" + style);
        font = super.findFont2D("DejaVu Sans", style, NO_FALLBACK);
        if (font == null) {
            font = super.findFont2D("DejaVu Sans", java.awt.Font.PLAIN, NO_FALLBACK);
        }
        if (font != null) {
            System.err.println("[CTCFontManager] Recovered with: " + font);
        }
    }
    return font;
}
```

#### Acceptance Criteria

- [ ] `System.err` diagnostic output visible in Xcode console
- [ ] `[CTCFontConfig] init() returned: true` visible in logs
- [ ] No Font NPE at `findFont2D`
- [ ] Login screen text renders (buttons, labels visible)
- [x] `./scripts/build-cacio-ios.sh` succeeds
- [x] `make native` compiles

---

### TICKET 35: Fix Framebuffer Incomplete — Render Thread Binding

**Priority**: ⚠️ Medium — Visual glitch, not fatal
**Difficulty**: Easy
**Files to modify**: [glfw_ios.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/glfw_ios.m)

#### Solution

Re-bind the OpenGL ES framebuffer and re-attach the depth/stencil renderbuffer inside the render thread's context in `nativeMakeContextCurrent` right after `[EAGLContext setCurrentContext:gEAGLContext]`.

#### Acceptance Criteria

- [x] Re-bind framebuffer and re-attach depth/stencil renderbuffer in `nativeMakeContextCurrent`
- [ ] No `Framebuffer incomplete` warning in logs
- [ ] `depth?=true` when status is checked

---

### TICKET 36: Input Bridge — Touch to GLFW Events

**Priority**: 🔴 CRITICAL — Needed for game interaction
**Difficulty**: Medium
**Files to modify**: [glfw_ios.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/glfw_ios.m), [GameViewController.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/GameViewController.m), [GLFW.java](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/external/bootstrap/src/main/java/org/lwjgl/glfw/GLFW.java)

#### Solution

- Implement a thread-safe touch event ring buffer in `glfw_ios.m`.
- Override touch methods in `GameViewController.m` to push mouse position and click events to the buffer (mapping UIKit touch coordinates to framebuffer pixels).
- Implement `nativeDrainInput()` in `glfw_ios.m` to poll and trigger GLFW callbacks on the JVM thread.

#### Acceptance Criteria

- [ ] Implement input ring buffer in `glfw_ios.m`
- [ ] Touch events mapped and pushed from `GameViewController.m`
- [ ] JVM thread processes touches correctly via `glfwPollEvents()`

---

### TICKET 37: Steam Login End-to-End Test

**Priority**: 🟡 MEDIUM — For complete feature set
**Difficulty**: Medium

#### Solution

Test Frenchpress launcher mode with credentials and verify that Steam Guard prompts (TOTP / Email) correctly present themselves and resume the game thread asynchronously.

#### Acceptance Criteria

- [ ] Steam login succeeds using valid credentials
- [ ] Steam Guard prompt displays, submits successfully, and resumes the JVM

---

## Architecture Reference

### The Font Resolution Chain (Corrected — from JDK 25 source analysis)

```
SunFontManager constructor:
  1. registerFontsInDir(jreFontDirName)      ← registers .ttf files as PhysicalFont objects
  2. fontConfig = createFontConfiguration()  ← CTCFontConfiguration constructor:
       super(fm)                             ← findFontConfigFile() → finds fontconfig.properties
       init()                                ← readFontConfigFile() → loadProperties()
                                               → populates internal binary tables:
                                                 compFontNameIDs, table_fontfileNameIDs, etc.
                                               initFontConfig() → builds lookup structures
       loadFilenameMappings()                ← reads filename.* keys (REDUNDANT — already in binary table)
  3. initCompositeFonts(fontConfig, null)
       → fontConfig.getNumberCoreFonts()     ← populates filenamesMap (XLFD → file path)
       → for each platform font name:
           getFileNameFromPlatformName(xlfd) ← checks filenamesMap FIRST, then fontNameMap
           registerFontFile(path, ...)       ← registers as deferred font
       → fontConfig.get2DCompositeFontInfo() ← builds CompositeFontDescriptor[]
           → for each logical font × style:
               mapFileName(getComponentFileName(fileNameID))  ← PRIMARY path (binary table)
               if null → getFileNameFromComponentFontName()   ← FALLBACK only!
       → registerCompositeFont("dialog.bold", ...) ← registers logical→physical mapping

Later, when SK renders text:
  Font.getFont2D()
    → SunFontManager.findFont2D("Dialog", BOLD, LOGICAL_FALLBACK)
    → Looks in FontFamily → finds CompositeFont registered at step 3
    → Returns CompositeFont (which lazily loads PhysicalFont slots)
    → If step 3 failed silently → NO composite registered → returns null → NPE
```

**Key insight**: `getFileNameFromComponentFontName()` (which Gemini's Round 16 overrode) is the FALLBACK path at the `if null →` branch. The PRIMARY path uses `mapFileName(getComponentFileName(fileNameID))` which reads from the internal binary table built by `loadProperties()`. If `loadProperties()` failed, the binary table is empty and BOTH paths fail.

**Why the debug logging was invisible**: All `[CTCFontConfig]` logging used `System.out.println`. On iOS, `System.out` (Java stdout) does NOT appear in the Xcode console. Only `System.err` (Java stderr) does. Evidence: the JVM Unsafe warnings (which go to stderr) appear, but none of the `[CTCFontConfig]` stdout lines appear.

**Android workaround**: Uses `sun.awt.X11FontManager` (via `-Dcacio.font.fontmanager`) which has a working `createFontConfiguration()` that reads `fontconfig.properties` and also populates `fontNameMap` via `registerFontDir()` → `fonts.dir` parsing.

**iOS current path**: Uses `CTCFontManager` which DOES create a `CTCFontConfiguration` (not null). However, `SunFontManager` only calls `registerFontDir(jreFontDirName)` when `FontUtilities.isLinux == true` (line 331-333 of SunFontManager.java). On iOS, `registerFontDir` is never called → `fontNameMap` stays empty → `getFileNameFromPlatformName()` can't resolve XLFDs to file paths → `initCompositeFonts` registers composites with broken/missing file references → `findFont2D()` returns null.

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
- ~~Ticket 34: Fix Font NPE (fontNameMap never populated)~~ ✅
- ~~Ticket 35: Fix Framebuffer Incomplete — Render Thread Binding~~ ✅
- Ticket 36: Input Bridge — Touch to GLFW Events
- Ticket 37: Steam Login End-to-End Test

### Phase 3: Input Bridge

Touch events → GLFW `nativeDrainInput` ring buffer. Modeled after Android's `NativeBridge.onTouchEvent`. See Ticket 36.

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
8. ~~**Ticket 34** — Fix Font NPE (fontNameMap never populated)~~ ✅
9. ~~**Ticket 35** — Fix Framebuffer Incomplete — Render Thread Binding~~ ✅
10. **Ticket 36** — Input Bridge — Touch to GLFW Events
11. **Ticket 37** — Steam Login End-to-End Test

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

### Round 15 — Test Results (June 23 2026 00:35 IST)

- ✅ **No UnsatisfiedLinkError** — AWT stubs fixed
- ✅ **No MaskBlit InternalError** — native loops registered
- ✅ **Prologue renders + completes** — `end_prologue` reached
- ✅ **Audio plays** — intro music
- ✅ **Server connected** — `game.spiralknights.com:47624`
- ✅ **Game loop continues** — FPS, disk, network active in Xcode sidebar
- ✅ **`Idle state changed`** — game logic running
- ❌ **Font NPE returns** — `findFont2D("Dialog", BOLD, LOGICAL_FALLBACK)` returns null → login screen text/buttons invisible → screen appears frozen on last prologue frame
- ⚠️ **Framebuffer incomplete** — `[status=36061, depth?=false]` still appears
- 📝 **Root cause analysis complete** — diffed Android vs iOS `CTCFontManager`: `fontNameMap` is never populated because iOS has no `fonts.dir` file and `SunFontManager.registerFontsInDir()` doesn't populate it. Android works because it uses `FcFontManager` with system fontconfig.

### Round 16 (June 28, Gemini)

- ✅ **Ticket 34**: Implemented robust logging inside `CTCFontConfiguration.java` to debug `fontconfig.properties` resolution on the device.
- ✅ **Font Fallback**: Added a pattern-based DejaVu font matching fallback in `CTCFontConfiguration.getFileNameFromComponentFontName()` to guarantee logical-to-physical font mapping on iOS.
- ✅ **Ticket 35**: Synchronized the GLES framebuffer and depth/stencil renderbuffer inside the render thread's context in `glfw_ios.m` (`nativeMakeContextCurrent`).
- ✅ Rebuilt Cacio module and assembled the payload via `make payload`.

### Round 16 — Test Results (June 28 2026 18:35 IST)

- ✅ **JVM boots** — 59 args, cacio active
- ✅ **Cacio jar staged** — `[SKInstaller] Staged cacio-tta.jar` confirmed in log
- ✅ **CTCPreloadAgent runs** — Unsafe warnings prove cacio-tta.jar IS loaded
- ✅ **Prologue renders + completes** — `end_prologue` reached
- ✅ **Audio plays** — music continues through login
- ✅ **Server connected** — `game.spiralknights.com:47624`
- ✅ **`Idle state changed`** — game logic running
- ❌ **Font NPE PERSISTS** — identical NPE at `Font.getFont2D()` line 525. `findFont2D` still returns null.
- ❌ **Zero `[CTCFontConfig]` debug output** — `System.out.println` does NOT reach Xcode console on iOS. Only `System.err` works.
- ❌ **Framebuffer incomplete persists** — `[status=36061, depth?=false]` at line 358
- 📝 **Root cause corrected (Opus analysis)**: Round 16's fix targeted `getFileNameFromComponentFontName()` which is only a FALLBACK path in the JDK font chain. The PRIMARY path uses internal binary tables from `FontConfiguration.loadProperties()`. Either `loadProperties()` is failing silently, or `initCompositeFonts()` is not producing valid composite fonts. See corrected Architecture Reference above.

### Round 17 Instructions (for Gemini)

> [!IMPORTANT]
> The Round 16 fix was ineffective because it targeted the wrong code path.
> Round 17 must fix the ACTUAL root cause. Follow these steps IN ORDER.

**Step 1: Switch ALL debug logging to `System.err.println`**

In `CTCFontConfiguration.java`, replace every `System.out.println` with `System.err.println`. This is critical — `System.out` does NOT reach the Xcode console on iOS.

**Step 2: Add diagnostic logging at the REAL failure points**

Add `System.err.println` logging at these critical points:

a) In `CTCFontConfiguration` constructor — log whether `init()` succeeded and what `fontConfigFile` was found:

```java
public CTCFontConfiguration(SunFontManager fm) {
    super(fm);
    System.err.println("[CTCFontConfig] constructor: super(fm) complete");
    boolean initResult = init();
    System.err.println("[CTCFontConfig] init() returned: " + initResult);
    loadFilenameMappings();
    System.err.println("[CTCFontConfig] constructor complete, mappings=" + filenameMappings.size());
}
```

b) Override `getVersion()` to log whether the internal tables were populated:

```java
@Override
public String getVersion() {
    System.err.println("[CTCFontConfig] getVersion() called — tables loaded");
    return "1";
}
```

c) In `mapFileName` — log each call to verify path resolution:

```java
@Override
protected String mapFileName(String fileName) {
    if (fileName != null && !fileName.startsWith("/")) {
        String result = SunFontManager.jreFontDirName + java.io.File.separator + fileName;
        System.err.println("[CTCFontConfig] mapFileName: " + fileName + " → " + result);
        return result;
    }
    System.err.println("[CTCFontConfig] mapFileName: " + fileName + " (passthrough)");
    return fileName;
}
```

**Step 3: Add a null-safe fallback in `CTCFontManager.findFont2D()`**

This is a safety net to prevent the NPE while we diagnose. In `CTCFontManager.java`, override `findFont2D`:

```java
@Override
public sun.font.Font2D findFont2D(String name, int style, int fallback) {
    sun.font.Font2D font = super.findFont2D(name, style, fallback);
    if (font == null) {
        System.err.println("[CTCFontManager] findFont2D returned null for '" + name + "' style=" + style + " fallback=" + fallback);
        // Try the default physical font as fallback
        font = super.findFont2D("DejaVu Sans", style, NO_FALLBACK);
        if (font == null) {
            font = super.findFont2D("DejaVu Sans", java.awt.Font.PLAIN, NO_FALLBACK);
        }
        if (font != null) {
            System.err.println("[CTCFontManager] Recovered with fallback: " + font);
        } else {
            System.err.println("[CTCFontManager] FATAL: No fonts available at all!");
        }
    }
    return font;
}
```

**Step 4: Create `fonts.dir` as a belt-and-suspenders fix**

Create `assets/fonts/fonts.dir` that maps each DejaVu TTF to its XLFD. This makes `registerFontDir()` populate `fontNameMap` — providing a second resolution path independent of `fontconfig.properties` parsing.

The file format is: first line = number of entries, then each line is `filename XLFD`.

```
12
DejaVuSans.ttf -dejavu-sans-book-r-normal--0-0-0-0-p-0-iso10646-1
DejaVuSans-Bold.ttf -dejavu-sans-bold-r-normal--0-0-0-0-p-0-iso10646-1
DejaVuSans-Oblique.ttf -dejavu-sans-book-o-normal--0-0-0-0-p-0-iso10646-1
DejaVuSans-BoldOblique.ttf -dejavu-sans-bold-o-normal--0-0-0-0-p-0-iso10646-1
DejaVuSerif.ttf -dejavu-serif-book-r-normal--0-0-0-0-p-0-iso10646-1
DejaVuSerif-Bold.ttf -dejavu-serif-bold-r-normal--0-0-0-0-p-0-iso10646-1
DejaVuSerif-Italic.ttf -dejavu-serif-book-i-normal--0-0-0-0-p-0-iso10646-1
DejaVuSerif-BoldItalic.ttf -dejavu-serif-bold-i-normal--0-0-0-0-p-0-iso10646-1
DejaVuSansMono.ttf -dejavu-sans mono-book-r-normal--0-0-0-0-m-0-iso10646-1
DejaVuSansMono-Bold.ttf -dejavu-sans mono-bold-r-normal--0-0-0-0-m-0-iso10646-1
DejaVuSansMono-Oblique.ttf -dejavu-sans mono-book-o-normal--0-0-0-0-m-0-iso10646-1
DejaVuSansMono-BoldOblique.ttf -dejavu-sans mono-bold-o-normal--0-0-0-0-m-0-iso10646-1
```

Then update `stage-app-assets.sh` to also copy `fonts.dir` alongside the `.ttf` files.

AND — override `registerFontDir` in `CTCFontManager` to actually call it for the JRE fonts directory. Currently `SunFontManager` only calls `registerFontDir(jreFontDirName)` on Linux. Add this to `CTCFontManager`:

```java
// Force registration of JRE font directory (normally Linux-only in SunFontManager)
@Override
protected void registerFontDir(String path) {
    System.err.println("[CTCFontManager] registerFontDir: " + path);
    super.registerFontDir(path);
}
```

And call it explicitly by adding to the CTCFontManager constructor or init path:

```java
registerFontDir(System.getProperty("java.home") + "/lib/fonts");
```

Wait — `CTCFontManager` already overrides `registerFontDir()` (it reads `fonts.dir`). The issue is that `SunFontManager`'s constructor only calls `registerFontDir(jreFontDirName)` when `FontUtilities.isLinux` is true. On iOS, it's never called. So the `fonts.dir` file will never be read unless we force it.

The proper fix: add `registerFontDir(jreFontDirName)` call. The best place is in `CTCFontManager.getFontPath()` or add it to the constructor via an override.

Actually, the cleanest approach: override `SunFontManager`'s init to force `registerFontDir` call. In `CTCFontManager`, override `registerFontsInDir` or call `registerFontDir` after construction. Since `CTCFontManager` extends `SunFontManager` and the constructor is `protected`, you can:

```java
public CTCFontManager() {
    super();
    // Force font directory registration (normally Linux-only in SunFontManager)
    String jreFonts = System.getProperty("java.home") + File.separator + "lib" + File.separator + "fonts";
    registerFontDir(jreFonts);
    System.err.println("[CTCFontManager] Forced registerFontDir for: " + jreFonts);
}
```

This makes `registerFontDir()` read `fonts.dir`, populate `fontNameMap`, and ensure `getFileNameFromPlatformName()` can resolve XLFDs to file paths.

**Step 5: Rebuild and test**

```bash
./scripts/build-cacio-ios.sh && make payload
```

Deploy to device via Xcode (clean install — delete app first). Check Xcode console for `[CTCFontConfig]` and `[CTCFontManager]` stderr output.

#### Expected outcomes:

- If `fonts.dir` + forced `registerFontDir` works → Font NPE is fixed, login screen renders
- If it doesn't → the `System.err` diagnostic logging will show EXACTLY where the chain breaks

### Round 17 (June 30, Gemini)

- ✅ **Ticket 34 (Reopened)**: Addressed the Font NullPointerException using the three-pronged approach:
    - Switched all `System.out.println` debug outputs to `System.err.println` in `CTCFontConfiguration` so that logs correctly route to the Xcode console on iOS.
    - Implemented an explicit constructor override in `CTCFontManager.java` to force the invocation of `registerFontDir()` for the JRE font directory (bypassing the Linux-only restriction inside `SunFontManager.java`'s constructor).
    - Created a new `fonts.dir` mapping file inside `assets/fonts/` and updated `scripts/stage-app-assets.sh` to stage it alongside the `.ttf` font files in the device bundle.
    - Overrode `findFont2D()` inside `CTCFontManager.java` to return a safe physical font fallback (`DejaVu Sans`) instead of `null` if composite font resolution fails, preventing crashes.
- ✅ Recompiled Cacio and rebuilt payload via `make payload`. Checked staging output to verify `fonts.dir` deployment.

### Round 18 (July 05, Gemini)

- ✅ **Forced FontManager Fix**: Added `-Dsun.font.fontmanager=com.github.caciocavallosilano.cacio.ctc.CTCFontManager` and `-Dcacio.font.fontmanager=com.github.caciocavallosilano.cacio.ctc.CTCFontManager` to the JVM arguments in `JavaLauncher.m` to force-enable cacio's custom `CTCFontManager` instead of letting the JRE fall back to the macOS/iOS default `CFontManager`. This guarantees that our font configuration and fallback logic gets executed.
- ✅ **NPE in CTCFontManager Fixed**: Added a null-safety check for `fontConfigDirs` inside `CTCFontManager.addFontToPlatformFontPath()` to prevent a startup `NullPointerException` (since `fontConfigDirs` resolves to `null` due to empty `awtfontpath` properties on iOS).
- ✅ **Version-Aware Installer Staging Fix**: Modified `SKInstaller.m` to write the build version and commit hash to `.skapsule_installed_v2` and compare it on launch. This guarantees that new JAR updates inside the app bundle (like the Cacio NPE fix) are automatically re-staged on the next launch rather than being skipped/ignored due to installer caching.
- ✅ **SIGSEGV Crash Fix (Render Thread)**: Fixed a SIGSEGV crash inside `GLRResourceList::addResource` (Metal translation layer for OpenGL ES on iOS) occurring when `glClear` or draw commands were executed on an unattached FBO 0.
    - Updated `nativeMakeContextCurrent` (`glfw_ios.m`) to dynamically resolve `glBindFramebuffer` from the native `OpenGLES` framework and bind `gFramebuffer` to the thread context prior to gl4es initialization.
    - Modified `glstate.c` in `gl4es` to query the currently bound `GL_FRAMEBUFFER_BINDING` on initialization and set `mainfbo_fbo` to it, ensuring gl4es correctly redirects FBO 0 draw/clear calls to our custom EAGL-backed framebuffer.
- ✅ **glGetUniformLocation/glGetAttribLocation Null Crash Fix**: Added null checks for the `name` argument inside `gl4es_glGetUniformLocation()` and `gl4es_glGetAttribLocation()` inside `program.c` (`gl4es`) to prevent SIGSEGV crashes when uniform/attribute locations are queried with a `NULL` name.
    - Adjusted null check placement to be at the very top of both functions, before the `DBG` logging macros are executed. This prevents `printf` from dereferencing `NULL` names and corrupting the print/heap buffer.
- ✅ **Malloc Free/Heap Corruption Fix**: Updated `nativeMakeContextCurrent` (`glfw_ios.m`) to cache the dynamically resolved `glBindFramebuffer` function pointer using a static `dispatch_once` block and removed the `dlclose()` call on the system OpenGLES framework. This prevents library unmapping/refcount anomalies that cause malloc zone allocator corruption (`EXC_BREAKPOINT` in `_xzm_xzone_malloc_freelist_outlined`) during subsequent class loading.
- ✅ Recompiled gl4es, rebuilt native target, and packaged IPA via `make package`.
