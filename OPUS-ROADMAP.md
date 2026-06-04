# SKapsule-iOS Development Roadmap (Opus → Gemini)

**Purpose**: This document is the authoritative guide for Gemini 3.1 to continue development of SKapsule-iOS. Each section is a self-contained, sequenced work item with exact files, error context, and acceptance criteria. **Work items MUST be completed in order** — each depends on the previous.

> [!IMPORTANT]
> **Gemini: Read this entire document before starting any work.** Understand the overall flow. Do NOT skip tickets or attempt tickets out of order. Each ticket's acceptance criteria must pass before moving to the next.

---

## Current State Summary

The app **successfully boots the JVM**, runs `SkBootstrap`, downloads/validates game assets via Getdown, and launches `ProjectXApp.main()`. The game client then initializes its OpenGL context via gl4es (which works!) and begins loading game resources. **It crashes during font initialization.**

### What's Working ✅

- JVM boots via `JLI_Launch` (JRE 25, built from `openjdk/mobile`)
- JNI bridge for `SkBootstrap` natives registers successfully
- Getdown downloads and validates all game assets (20 resources, 117MB)
- GLFW shadow class loads and `nativeMakeContextCurrent` works
- gl4es initializes successfully (GLES 2.0 backend, OpenGL 2.1 target)
- LWJGL `liblwjgl.dylib` and `liblwjgl_opengl.dylib` load successfully
- `EAGLContext` + `CAEAGLLayer` + renderbuffer setup works
- Caciocavallo AWT bridge loads (`cacio-shared.jar`, `cacio-tta.jar`)

### What's Failing ❌ (Two distinct crashes in the log)

**Crash 1 (line 432-448)**: LWJGL `Library.<clinit>` tries to `System.load()` a path containing `AngelAuraAmethyst` — a hardcoded path from the Amethyst-iOS LWJGL build. This crashes with `UnsatisfiedLinkError` but **does not kill the process** because LWJGL falls through to loading `liblwjgl.dylib` from `Frameworks/` (which succeeds at line 456).

**Crash 2 (line 1896-1934) — THE FATAL ONE**: `sun.awt.FontConfiguration.getVersion()` throws `RuntimeException: Fontconfig head is null`. This kills `ProjectXApp.main()` with an `InvocationTargetException`.

### Root Cause Analysis

The JRE has **no `fontconfig.properties` file** and **no `lib/fonts/` directory**. When `CFontManager` initializes (the macOS/iOS font manager), it tries to read `FontConfiguration` which needs a valid `fontconfig.properties` or system fontconfig. On iOS, there's no system fontconfig library, so this always returns null, and the "head is null" check in `FontConfiguration.getVersion()` throws.

This is solvable: we need to provide a `fontconfig.properties` file that maps Java logical fonts to physical font files bundled in the app.

---

## Ticket Sequence

### TICKET 1: Fix Fontconfig — Bundle `fontconfig.properties` + Fonts

**Priority**: 🔴 CRITICAL — This is the current blocker  
**Difficulty**: Medium  
**Files to modify**: `scripts/stage-app-assets.sh`, possibly `Natives/JavaLauncher.m`  
**Files to create**: `assets/fontconfig.properties`, `assets/fonts/` directory

#### Problem

`sun.awt.FontConfiguration.getVersion()` throws because `fontconfig.properties` is missing from the JRE's `lib/` directory. The JRE has `libfontmanager.dylib` and `libfreetype.dylib` but no font configuration or font files.

#### Solution

**Step 1**: Create `assets/fontconfig.properties` with minimal mappings. This file maps Java's logical fonts (Dialog, Serif, SansSerif, Monospaced) to physical `.ttf` files. Use the standard OpenJDK macOS format:

```properties
# Minimal fontconfig.properties for iOS (no system fontconfig)
# Maps logical fonts to bundled DejaVu fonts

version=1

# Logical font name mappings
allfonts.plain.latin-1=-dejavu-sans-book-r-normal--*-%d-*-*-*-*-iso10646-1
allfonts.bold.latin-1=-dejavu-sans-bold-r-normal--*-%d-*-*-*-*-iso10646-1
allfonts.italic.latin-1=-dejavu-sans-book-o-normal--*-%d-*-*-*-*-iso10646-1
allfonts.bolditalic.latin-1=-dejavu-sans-bold-o-normal--*-%d-*-*-*-*-iso10646-1

serif.plain.latin-1=-dejavu-serif-book-r-normal--*-%d-*-*-*-*-iso10646-1
serif.bold.latin-1=-dejavu-serif-bold-r-normal--*-%d-*-*-*-*-iso10646-1
serif.italic.latin-1=-dejavu-serif-book-i-normal--*-%d-*-*-*-*-iso10646-1
serif.bolditalic.latin-1=-dejavu-serif-bold-i-normal--*-%d-*-*-*-*-iso10646-1

sansserif.plain.latin-1=-dejavu-sans-book-r-normal--*-%d-*-*-*-*-iso10646-1
sansserif.bold.latin-1=-dejavu-sans-bold-r-normal--*-%d-*-*-*-*-iso10646-1
sansserif.italic.latin-1=-dejavu-sans-book-o-normal--*-%d-*-*-*-*-iso10646-1
sansserif.bolditalic.latin-1=-dejavu-sans-bold-o-normal--*-%d-*-*-*-*-iso10646-1

monospaced.plain.latin-1=-dejavu-sans mono-book-r-normal--*-%d-*-*-*-*-iso10646-1
monospaced.bold.latin-1=-dejavu-sans mono-bold-r-normal--*-%d-*-*-*-*-iso10646-1
monospaced.italic.latin-1=-dejavu-sans mono-book-o-normal--*-%d-*-*-*-*-iso10646-1
monospaced.bolditalic.latin-1=-dejavu-sans mono-bold-o-normal--*-%d-*-*-*-*-iso10646-1

dialog.plain.latin-1=-dejavu-sans-book-r-normal--*-%d-*-*-*-*-iso10646-1
dialog.bold.latin-1=-dejavu-sans-bold-r-normal--*-%d-*-*-*-*-iso10646-1
dialog.italic.latin-1=-dejavu-sans-book-o-normal--*-%d-*-*-*-*-iso10646-1
dialog.bolditalic.latin-1=-dejavu-sans-bold-o-normal--*-%d-*-*-*-*-iso10646-1

dialoginput.plain.latin-1=-dejavu-sans mono-book-r-normal--*-%d-*-*-*-*-iso10646-1
dialoginput.bold.latin-1=-dejavu-sans mono-bold-r-normal--*-%d-*-*-*-*-iso10646-1
dialoginput.italic.latin-1=-dejavu-sans mono-book-o-normal--*-%d-*-*-*-*-iso10646-1
dialoginput.bolditalic.latin-1=-dejavu-sans mono-bold-o-normal--*-%d-*-*-*-*-iso10646-1

# Font file mappings
filename.-dejavu-sans-book-r-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSans.ttf
filename.-dejavu-sans-bold-r-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSans-Bold.ttf
filename.-dejavu-sans-book-o-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSans-Oblique.ttf
filename.-dejavu-sans-bold-o-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSans-BoldOblique.ttf
filename.-dejavu-serif-book-r-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSerif.ttf
filename.-dejavu-serif-bold-r-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSerif-Bold.ttf
filename.-dejavu-serif-book-i-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSerif-Italic.ttf
filename.-dejavu-serif-bold-i-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSerif-BoldItalic.ttf
filename.-dejavu-sans mono-book-r-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSansMono.ttf
filename.-dejavu-sans mono-bold-r-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSansMono-Bold.ttf
filename.-dejavu-sans mono-book-o-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSansMono-Oblique.ttf
filename.-dejavu-sans mono-bold-o-normal--*-%d-*-*-*-*-iso10646-1=DejaVuSansMono-BoldOblique.ttf
```

> [!TIP]
> **Alternative approach (simpler, recommended first attempt):** Instead of the full XLFD format above, try a simpler `fontconfig.properties` modeled after what Amethyst-iOS / PojavLauncher uses. The key is just having a valid version line and font file mappings. If the first attempt doesn't work, consult the [OpenJDK fontconfig documentation](https://docs.oracle.com/en/java/javase/21/intl/font-configuration-files.html) and the Amethyst-iOS codebase for reference.

**Step 2**: Download DejaVu font files and place them in `assets/fonts/`:

```bash
# Download DejaVu fonts (open source, standard Java fallback)
curl -L "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip" -o /tmp/dejavu.zip
unzip /tmp/dejavu.zip -d /tmp/dejavu
cp /tmp/dejavu/dejavu-fonts-ttf-2.37/ttf/DejaVuSans*.ttf assets/fonts/
cp /tmp/dejavu/dejavu-fonts-ttf-2.37/ttf/DejaVuSerif*.ttf assets/fonts/
```

**Step 3**: Update [stage-app-assets.sh](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/scripts/stage-app-assets.sh) to copy fonts and fontconfig into the JRE:

```bash
echo "=== Fonts ==="
mkdir -p "$APP_DIR/jre25/lib/fonts"
cp "$REPO_ROOT/assets/fonts/"*.ttf "$APP_DIR/jre25/lib/fonts/" 2>/dev/null || \
    echo "  (place .ttf font files in assets/fonts/)"

echo "=== fontconfig.properties ==="
stage "$REPO_ROOT/assets/fontconfig.properties" \
      "$APP_DIR/jre25/lib/fontconfig.properties" || \
    echo "  (create assets/fontconfig.properties)"
```

**Step 4**: In [JavaLauncher.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/JavaLauncher.m), add a JVM arg to tell Java where fonts live:

```objc
margv[++margc] = [NSString stringWithFormat:@"-Dsun.java2d.fontpath=%@/jre25/lib/fonts", bundlePath].UTF8String;
```

Also change the cacio font manager from `sun.awt.X11FontManager` (which doesn't exist on macOS/iOS builds) to `sun.font.CFontManager` (or remove the `-Dcacio.font.fontmanager` property entirely so the JRE uses its default macOS font manager):

In [JavaLauncher.m line 165](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/JavaLauncher.m#L165):

```diff
-        margv[++margc] = "-Dcacio.font.fontmanager=sun.awt.X11FontManager";
+        // Use the default macOS/iOS font manager (CFontManager)
+        // X11FontManager doesn't exist in this JRE build
```

#### Acceptance Criteria

- [ ] `make native` builds with 0 errors
- [ ] App launches past the "Fontconfig head is null" crash
- [ ] The Xcode log shows `ProjectXApp.didInit` progressing past font initialization
- [ ] New errors will likely appear (expected — proceed to next ticket)

#### Debugging Tips

- If you still get "Fontconfig head is null": add `-Dsun.java2d.debugfonts=true` to JVM args in `JavaLauncher.m` to see what paths the font manager is scanning
- If the issue is specifically `CFontManager` not finding the configuration: try `-Djava.awt.fonts=/path/to/fonts` as well
- The JRE uses `CFontManager` (macOS font manager). If this still fails because it tries to use Core Text and iOS's Core Text doesn't expose fonts the same way, you may need to patch cacio's font manager or switch to `-Dcacio.font.fontmanager=sun.font.SunFontManager` (the platform-independent base class)

---

### TICKET 2: Fix LWJGL Native Library Loading Path

**Priority**: 🟡 HIGH (non-fatal currently, but will cause issues later)  
**Difficulty**: Easy  
**Files to investigate**: LWJGL build output, `external/lwjgl3/`

#### Problem

Line 432 in the log:

```
java.lang.UnsatisfiedLinkError: Can't load library: .../SKapsule.app/AngelAuraAmethyst
```

LWJGL's `Library.<clinit>` has a hardcoded path `AngelAuraAmethyst` baked into the LWJGL build from Amethyst-iOS. This fails but doesn't crash because LWJGL falls through to `liblwjgl.dylib` from `java.library.path`.

#### Solution

The LWJGL binaries were built using the Amethyst-iOS build scripts which hardcode an "AngelAuraAmethyst" library name. Two approaches:

**Option A (Recommended)**: Add a JVM system property in [JavaLauncher.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/JavaLauncher.m) to override LWJGL's native library name:

```objc
margv[++margc] = [NSString stringWithFormat:@"-Dorg.lwjgl.system.SharedLibraryExtractPath=%@/Frameworks", bundlePath].UTF8String;
```

**Option B**: Rebuild LWJGL with a patched library name. Only do this if Option A doesn't work.

#### Acceptance Criteria

- [ ] The "Can't load library: AngelAuraAmethyst" error disappears from the log
- [ ] LWJGL `liblwjgl.dylib` still loads successfully

---

### TICKET 3: Fix AWT `initIDs` UnsatisfiedLinkErrors

**Priority**: 🟡 HIGH (non-fatal currently, but accumulated errors will cause issues)  
**Difficulty**: Medium  
**Files to modify**: `Natives/CMakeLists.txt`, potentially a new `Natives/awt_stubs.c`

#### Problem

Throughout the log, hundreds of `Symbol Java_java_awt_*_initIDs not found` errors appear. These are `initIDs()` native methods that the JRE's `libawt.dylib` and `libawt_headless.dylib` expect but can't find. The stub dylibs in `Natives/CMakeLists.txt` used to provide empty versions, but the current CMakeLists.txt **doesn't build stub AWT libraries** — this was removed at some point.

The error at line 353 is directly caused by this:

```
Exception in thread "AWT-Shutdown" java.lang.UnsatisfiedLinkError: 'void java.awt.AWTEvent.initIDs()'
```

#### Solution

The JRE bundles its own real `libawt.dylib` and `libawt_headless.dylib`, but these dylibs expect `initIDs` JNI symbols to be linked into the process. The symbols need to be provided as no-op stubs.

**Approach**: Create a `Natives/awt_stubs.c` file that defines empty implementations of all the `initIDs` functions. These are all `void` functions that take `(JNIEnv*, jclass)` and do nothing:

```c
#include "jni.h"

// AWT initIDs stubs — these are normally provided by platform-specific
// AWT backends. On iOS we use cacio which handles everything in Java,
// but the JRE's libawt.dylib still calls these during class loading.

#define STUB_INIT_IDS(name) \
    JNIEXPORT void JNICALL Java_##name##_initIDs(JNIEnv *env, jclass cls) {}

STUB_INIT_IDS(java_awt_AWTEvent)
STUB_INIT_IDS(java_awt_Toolkit)
STUB_INIT_IDS(java_awt_Dimension)
STUB_INIT_IDS(java_awt_image_ColorModel)
STUB_INIT_IDS(java_awt_image_BufferedImage)
STUB_INIT_IDS(java_awt_image_Raster)
STUB_INIT_IDS(java_awt_image_SampleModel)
STUB_INIT_IDS(java_awt_image_SinglePixelPackedSampleModel)
STUB_INIT_IDS(java_awt_Font)
STUB_INIT_IDS(java_awt_FontMetrics)
STUB_INIT_IDS(sun_awt_image_IntegerComponentRaster)
STUB_INIT_IDS(sun_java2d_SurfaceData)
STUB_INIT_IDS(sun_java2d_pipe_SpanClipRenderer)
STUB_INIT_IDS(sun_java2d_pipe_Region)
STUB_INIT_IDS(sun_awt_image_BufImgSurfaceData)
STUB_INIT_IDS(sun_java2d_loops_GraphicsPrimitiveMgr)

// BufImgSurfaceData also needs initRaster
JNIEXPORT void JNICALL Java_sun_awt_image_BufImgSurfaceData_initRaster(
    JNIEnv *env, jobject obj, jobject img, jint type, jint x, jint y,
    jint w, jint h, jobject sData, jobject icm) {}

// GraphicsPrimitiveMgr also needs registerNativeLoops
JNIEXPORT void JNICALL Java_sun_java2d_loops_GraphicsPrimitiveMgr_registerNativeLoops(
    JNIEnv *env, jclass cls) {}
```

Add `awt_stubs.c` to [CMakeLists.txt](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/CMakeLists.txt) in the `add_executable(SKapsule ...)` list.

> [!WARNING]
> The exact function signatures for `initRaster` and `registerNativeLoops` must match the JNI declarations in the JRE source. If in doubt, leave those two out and only stub the `initIDs` functions — the `initIDs` ones are the most critical.

#### Acceptance Criteria

- [ ] `make native` builds with 0 errors
- [ ] The `UnsatisfiedLinkError: 'void java.awt.AWTEvent.initIDs()'` exception disappears
- [ ] The hundreds of "Symbol not found" debug messages for `initIDs` are gone

---

### TICKET 4: Fix PreferencesFactory (Non-Critical but Noisy)

**Priority**: 🟢 LOW  
**Difficulty**: Easy  
**Files to modify**: [JavaLauncher.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/JavaLauncher.m)

#### Problem

Line 101 sets `-Djava.util.prefs.PreferencesFactory=java.util.prefs.MacOSXPreferencesFactory`. This factory uses native `MacOSXPreferencesFile` JNI methods that aren't linked, producing hundreds of "symbol not found" debug messages.

#### Solution

Switch to the file-based preferences factory:

```diff
-    margv[++margc] = @"-Djava.util.prefs.PreferencesFactory=java.util.prefs.MacOSXPreferencesFactory".UTF8String;
+    margv[++margc] = @"-Djava.util.prefs.PreferencesFactory=java.util.prefs.FileSystemPreferencesFactory".UTF8String;
```

#### Acceptance Criteria

- [ ] All `MacOSXPreferencesFile` symbol-not-found messages disappear from the log
- [ ] Game preferences still save/load correctly (to the file system)

---

### TICKET 5: Reduce Log Noise — Remove `-Xlog:os=trace`

**Priority**: 🟢 LOW  
**Difficulty**: Trivial  
**Files to modify**: [JavaLauncher.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/JavaLauncher.m)

#### Problem

The `-Xlog:os=trace` flag at [line 150](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/JavaLauncher.m#L150) dumps every `dlsym` lookup to the console, producing ~1900 lines of noise. This was useful during initial JVM bring-up but now makes it hard to spot real errors.

#### Solution

Remove or reduce the log level:

```diff
-    margv[++margc] = "-Xlog:os=trace";
+    // Remove verbose OS tracing — re-enable with -Xlog:os=trace for debugging
```

#### Acceptance Criteria

- [ ] Log output is drastically shorter (< 100 lines for a typical run)
- [ ] Real exceptions are still visible

---

### TICKET 6: Verify Game Startup Past Font Init

**Priority**: 🔴 CRITICAL  
**Difficulty**: Unknown (depends on tickets 1-3)

After tickets 1-5 are applied, the app should progress further. The expected behavior at this point:

1. JVM boots ✅ (already works)
2. Getdown validates/downloads ✅ (already works)
3. `ProjectXApp.main()` starts ✅ (already works)
4. OpenGL context via gl4es ✅ (already works)
5. Font system initializes ← **This is where ticket 1 fixes**
6. Game GUI renders ← **New frontier after ticket 1**

New errors will almost certainly appear. The most likely ones:

- **More missing font files**: SK loads `ui/font/arial.ttf` (line 1851) from its own assets. This might still fail if Getdown didn't download it or the path is wrong.
- **OpenGL rendering issues**: gl4es → GLES2 translation may have quirks
- **More missing JNI natives**: Other AWT/Java2D natives beyond `initIDs`

**When new errors appear, report them back to Opus for analysis and a new ticket.**

---

## Architecture Decisions (For Gemini's Reference)

### Why We Can't Use `sun.awt.X11FontManager`

The JRE was built from `openjdk/mobile` which is a macOS/iOS-targeted build. It ships with `CFontManager` (the macOS font manager), not `X11FontManager` (which was for Linux). Setting `-Dcacio.font.fontmanager=sun.awt.X11FontManager` causes a `ClassNotFoundException` because that class literally doesn't exist in this JRE. The cacio property should either be removed or set to `sun.font.CFontManager`.

### The LWJGL Loading Path

LWJGL's loading sequence is: `System.loadLibrary("lwjgl")` → looks for "AngelAuraAmethyst" (Amethyst hardcode) → fails → falls through to `dlopen("liblwjgl.dylib")` from `java.library.path` → succeeds. The first failure is harmless but ugly. Fixing it (Ticket 2) is cosmetic.

### Why `libawt_headless.dylib` Is a Stub

The JRE expects `libawt_headless.dylib` to exist and be loadable. The real implementation (for X11/Wayland headless rendering) makes no sense on iOS. The Makefile builds and deploys an empty stub so `dlopen` succeeds, but the JNI functions it's supposed to export (`initIDs` etc.) are missing from the main executable. Ticket 3 fixes this.

### The OpenGL Surface

[GameViewController.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/GameViewController.m) already creates a proper `EAGLContext` + `CAEAGLLayer` + renderbuffer. The globals `gEAGLContext`, `gEAGLLayer`, `gRenderbuffer` are accessed by [glfw_ios.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/glfw_ios.m) for `nativeMakeContextCurrent` and `nativeSwapBuffers`. This plumbing is **already done**.

---

## Phase Roadmap (After Current Crash Is Fixed)

### Phase 2A: Font & Text Rendering Validation

After Ticket 1, verify that:

- Java AWT can create `Font` objects
- `FontMetrics` works
- SK's `TextFactory` initializes
- The game's login screen renders text

### Phase 2B: OpenGL Rendering Validation

- Verify gl4es translates SK's OpenGL calls to GLES correctly
- Check for missing GL extensions or unsupported calls
- Watch for "LIBGL:" warnings in the log

### Phase 3: Input Bridge

[GameViewController.m](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/Natives/GameViewController.m) needs touch event handlers:

```objc
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
```

These should feed events into the GLFW shadow's native ring buffer (the `nativeDrainInput` mechanism in [GLFW.java](file:///Users/rayhan/Documents/GitHub/SKapsule-iOS/external/bootstrap/src/main/java/org/lwjgl/glfw/GLFW.java)).

### Phase 4: Audio (OpenAL)

`libopenal.dylib` is bundled. The LWJGL OpenAL module should load it via `-Dorg.lwjgl.openal.libname`. Verify it works with iOS's `AVAudioSession`.

### Phase 5: Steam Login

Already mostly wired. Just needs end-to-end testing once the game renders.

---

## Rules for Gemini

> [!CAUTION]
> **NEVER do any of the following without explicit approval from the user:**
>
> - Modify `.github/workflows/`, signing config, or entitlement files
> - Update submodule pointers (`git submodule update`)
> - Add new top-level files or directories
> - Introduce new third-party dependencies
> - Force-push or rewrite shared history
> - Push to `main` directly

### Scope Discipline

- **One PR = one logical change** (matches one ticket above)
- Do NOT bundle drive-by cleanups
- Do NOT refactor code you aren't changing
- Do NOT add abstractions that weren't asked for

### Commit Format

```
feat: add initial launcher UI
fix: resolve JRE path lookup on sideloaded installs
chore: bump gl4es submodule
```

### Build Verification

- Always run `make native` after changes to verify compilation
- Never claim a change is verified if you can't build it
- The user builds and tests on-device via Xcode

### When You're Stuck

If a ticket produces unexpected results or you need architectural guidance, **stop and ask the user** to consult Opus. Do not guess on architectural decisions.

---

## Development Workflow Optimization

### Recommended: Reduce `-Xlog` noise FIRST

Before debugging further, apply Ticket 5 so the logs are readable. The current 1942-line log is ~90% dlsym noise.

### Recommended: Work Order

1. **Ticket 5** (trivial — remove log noise)
2. **Ticket 4** (easy — fix preferences factory)
3. **Ticket 1** (critical — fontconfig) ← The big one
4. **Ticket 3** (medium — AWT stubs)
5. **Ticket 2** (easy — LWJGL path)
6. **Ticket 6** (verification checkpoint)

### After Ticket 6

Report the new Xcode log to the user. The user will consult Opus for the next set of tickets.

---

## Open Questions for User

> [!IMPORTANT]
>
> 1. **Font files**: Do you already have DejaVu fonts somewhere, or should Gemini download them? They're ~5MB total, open source (SIL license), and the standard Java fallback font.
> 2. **Uncommitted changes**: You have uncommitted changes in `external/caciocavallo17`, `external/gl4es`, `external/lwjgl3`, and `openjdk-mobile`. Should these be committed to their respective forks before proceeding? (The roadmap doesn't depend on this, but it's good hygiene.)
> 3. **Previous conversations**: You mentioned wanting to delete old conversations. The three linked conversations contain useful context that's now captured in this roadmap and `GEMINI-RESEARCH.md`. Safe to delete after you verify this roadmap covers everything.
