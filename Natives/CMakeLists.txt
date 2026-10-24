cmake_minimum_required(VERSION 3.14)
project(SKapsule)

# Normally passed by the Makefile from the latest git tag; a bare cmake invocation
# (or a tagless clone) falls back rather than stamping an empty version.
if(NOT CONFIG_VERSION)
  set(CONFIG_VERSION "1.0.0")
endif()

configure_file(${CMAKE_CURRENT_LIST_DIR}/config.h.in ${CMAKE_CURRENT_LIST_DIR}/config.h)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fcommon -fobjc-arc -ObjC")
set(CMAKE_C_FLAGS_DEBUG "-funwind-tables -g")

if("${CMAKE_HOST_SYSTEM_NAME}" MATCHES "Linux|^GNU$|Android")
set(GLOBAL_LDFLAGS "-isysroot ${CMAKE_OSX_SYSROOT} -Wl,-syslibroot,${CMAKE_OSX_SYSROOT} -fuse-ld=lld")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${GLOBAL_LDFLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${GLOBAL_LDFLAGS}")
endif()

include_directories(
  "."
)

# rpath for loading dylibs from Frameworks/ and JRE lib/
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -rpath @loader_path -rpath @executable_path/jre25/lib")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -rpath @executable_path/Frameworks -rpath @loader_path/Frameworks -Wl,-export_dynamic")




# SKapsule executable
add_executable(SKapsule
  main.m
  AppDelegate.m
  SceneDelegate.m
  LauncherViewController.m
  SKZipUtils.m
  SKModManager.m
  GameViewController.m
  SKTouchControls.m
  SKTouchControlOverlay.m
  SKControlsEditorViewController.m
  SKKeyboardBridge.m
  JavaLauncher.m
  glfw_ios.m
  NativeBridge.m
  SKInstaller.m
  SKNewsFeed.m
  SKBuiltinJIT.m
  SKReporter.m
  utils.m
  Assets.xcassets
)

# Compile awt_stubs.c into a shared library that replaces the JRE's empty libawt_headless.dylib
add_library(awt_headless SHARED awt_stubs.c)
set_target_properties(awt_headless PROPERTIES PREFIX "lib")

# Compile prefs_stubs.c into a shared library that replaces the JRE's libprefs.dylib
add_library(prefs SHARED prefs_stubs.c)
set_target_properties(prefs PROPERTIES PREFIX "lib")


target_compile_options(SKapsule PRIVATE -fobjc-arc -Wno-deprecated-declarations -DGLES_SILENCE_DEPRECATION=1)

# SK_ASAN=ON links the AddressSanitizer runtime into the app itself, so it is loaded and
# interposing malloc from process start rather than whenever LWJGL dlopens libgl4es.
# Diagnostic build only; pair with SK_ASAN=1 on scripts/build-gl4es-ios.sh.
option(SK_ASAN "Link the AddressSanitizer runtime for heap diagnosis" OFF)
if(SK_ASAN)
  execute_process(
    COMMAND bash -c "find $(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang -name libclang_rt.asan_ios_dynamic.dylib | head -1"
    OUTPUT_VARIABLE SK_ASAN_LIB OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(SK_ASAN_LIB)
    message(STATUS "AddressSanitizer runtime: ${SK_ASAN_LIB}")
    target_link_libraries(SKapsule "${SK_ASAN_LIB}")
  else()
    message(FATAL_ERROR "SK_ASAN=ON but libclang_rt.asan_ios_dynamic.dylib was not found")
  endif()
endif()

target_link_libraries(SKapsule
  "-framework CoreFoundation"
  "-framework CoreGraphics"
  "-framework QuartzCore"
  "-framework OpenGLES"
  "-framework UIKit"
  "-framework GameController"
  "-framework IOKit"
  "-framework Security"
  "-framework SafariServices"
  "-framework UniformTypeIdentifiers"
  "-ldl"
  "-lz"
)

set_target_properties(SKapsule PROPERTIES
  ENABLE_EXPORTS TRUE
  MACOSX_BUNDLE TRUE
  MACOSX_FRAMEWORK_IDENTIFIER com.skonstruct.skapsule
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_LIST_DIR}/Info.plist"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
