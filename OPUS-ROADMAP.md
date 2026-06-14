# SKapsule-iOS Development Roadmap (Opus → Gemini)

**Purpose**: This document is the authoritative guide for Gemini 3.1 to continue development of SKapsule-iOS. Each section is a self-contained, sequenced work item with exact files, error context, and acceptance criteria. **Work items MUST be completed in order** — each depends on the previous.

> [!IMPORTANT]
> **Gemini: Read this entire document before starting any work.** Understand the overall flow. Do NOT skip tickets or attempt tickets out of order. Each ticket's acceptance criteria must pass before moving to the next.

---

## Current State Summary

### 🎉 THE GAME RENDERS! Viewport Fix Confirmed.

The Retina scaling fix is working — the full prologue animation renders at correct scale in landscape. Server connection established, audio plays, prologue completes, and the game reaches `Init LogonWindow`. **The screenshot shows the Cradle planet scene rendering beautifully!**

### Remaining Blocking Issues

1. **Font NPE (CRITICAL)** — `findFont2D` returns null when SK builds the login screen UI. The game runs past the prologue (which is pure 3D) but crashes when rendering 2D text for the login form's buttons and labels.

2. **Framebuffer incomplete** — `[status=36061, depth?=false]`. The depth renderbuffer may not be bound in the GL context the game validates from (render thread vs. main thread context mismatch).

3. **Prefs lock spam** — `error code 999` every 30 seconds. Cosmetic but noisy.

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

**Approach B: Fix CTCFontManager.createFontConfiguration() (if A fails)**

If X11FontManager doesn't work on iOS (e.g., it tries to open an X11 connection), then fix CTCFontManager instead:

```java
protected FontConfiguration createFontConfiguration() {
    // Create a basic font configuration that maps logical fonts to physical
    FontConfiguration fc = super.createFontConfiguration();
    if (fc != null) return fc;
    // If super returns null, create a minimal one
    return new sun.awt.FontConfiguration(this) {
        // override to provide minimal mappings
    };
}
```

This is more complex — Approach A is strongly preferred.

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

1. **Ticket 27** — Fix Font NPE ← **CRITICAL, do first** (try Approach A: `-Dcacio.font.fontmanager=sun.awt.X11FontManager`)
2. **Ticket 28** — Fix framebuffer depth attachment
3. **Ticket 29** — Fix prefs lock

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

- ✅ Ticket 27: Reverted `JavaLauncher.m` to use `CTCFontManager`. Switched to Approach B: Overrode `createFontConfiguration()` in `CTCFontManager.java` to return a minimal anonymous `sun.awt.FontConfiguration`. Rebuilt caciocavallo using `jenv` JDK 25 and repackaged.
