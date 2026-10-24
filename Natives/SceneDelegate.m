#import "SceneDelegate.h"
#import "LauncherViewController.h"

extern void sk_gl_set_paused(BOOL paused);

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    LauncherViewController *launcher = [[LauncherViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:launcher];
    nav.navigationBarHidden = YES;

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    sk_gl_set_paused(NO);
}

- (void)sceneWillResignActive:(UIScene *)scene {
    sk_gl_set_paused(YES);
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    sk_gl_set_paused(YES);
}

@end
