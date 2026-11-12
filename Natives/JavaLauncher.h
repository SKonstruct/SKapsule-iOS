#pragma once

#include <Foundation/Foundation.h>

typedef int JLI_Launch_func(int argc, const char **argv, int jargc, const char **jargv, int appclassc,
                            const char **appclassv, const char *fullversion, const char *dotversion, const char *pname,
                            const char *lname, int javaargs, int cpwildcard, int javaw, int ergo);

extern JLI_Launch_func *pJLI_Launch;

/// webUser, webPass and loginHost are the optional quick login for Web mode and the server it belongs to;
/// SkBootstrap withholds the login if the game is set up for a different server.
int launchJVM(NSString *steamUser, NSString *steamPass, NSString *webUser, NSString *webPass, NSString *loginHost,
              BOOL isSteam, int width, int height);
