cmake_minimum_required(VERSION 3.14)
project(SKapsule)

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
  "external/fishhook"
)

# rpath for loading dylibs from Frameworks/ and JRE lib/
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -rpath @loader_path -rpath @executable_path/jre25/lib")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -rpath @executable_path/Frameworks -rpath @loader_path/Frameworks")



# SKapsule executable
add_executable(SKapsule
  main.m
  AppDelegate.m
  SceneDelegate.m
  LauncherViewController.m
  GameViewController.m
  JavaLauncher.m
  glfw_ios.m
  NativeBridge.m
  SKInstaller.m
  utils.m
  dyld_bypass_validation.m
  external/fishhook/fishhook.c
  Assets.xcassets
)

target_compile_options(SKapsule PRIVATE -fobjc-arc -Wno-deprecated-declarations -DGLES_SILENCE_DEPRECATION=1)

target_link_libraries(SKapsule
  "-framework CoreFoundation"
  "-framework CoreGraphics"
  "-framework QuartzCore"
  "-framework OpenGLES"
  "-framework UIKit"
  "-framework GameController"
  "-framework IOKit"
  "-framework Security"
  "-ldl"
)

set_target_properties(SKapsule PROPERTIES
  MACOSX_BUNDLE TRUE
  MACOSX_FRAMEWORK_IDENTIFIER com.skonstruct.skapsule
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_LIST_DIR}/Info.plist"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
