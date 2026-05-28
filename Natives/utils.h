#pragma once

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

extern BOOL isJailbroken;
extern BOOL debugLogEnabled;

BOOL isJITEnabled(BOOL checkCSFlags);
id getEntitlementValue(NSString *key);
void init_bypassDyldLibValidation(void);

NSString *getSelectedJavaHome(int minVersion);
