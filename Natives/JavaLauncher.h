#pragma once

#include <Foundation/Foundation.h>

typedef int JLI_Launch_func(int argc, const char **argv,
    int jargc, const char **jargv,
    int appclassc, const char **appclassv,
    const char *fullversion,
    const char *dotversion,
    const char *pname,
    const char *lname,
    int javaargs,
    int cpwildcard,
    int javaw,
    int ergo);

extern JLI_Launch_func *pJLI_Launch;

int launchJVM(NSString *steamUser, NSString *steamPass, BOOL isSteam, int width, int height);
