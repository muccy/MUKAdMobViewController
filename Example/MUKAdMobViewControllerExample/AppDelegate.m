//
//  AppDelegate.m
//  MUKAdMobViewControllerExample
//
//  Created by Marco on 10/07/13.
//  Copyright (c) 2013 MeLive. All rights reserved.
//

#import "AppDelegate.h"
#import "MyViewController.h"

#define USES_OPAQUE_TAB_BAR                     1
#define USES_OPAQUE_NAV_BAR                     1
#define USES_NAV_CONTROLLER                     1
#define USES_NAV_CONTROLLER_IN_ADV_CONTROLLER   1

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UITabBarController *tabBarController = [[UITabBarController alloc] init];
    tabBarController.viewControllers = @[ [self newViewControllerWithAdvertisingViewControllerTitled:@"1"], [self newViewControllerWithAdvertisingViewControllerTitled:@"2"], [self newViewControllerWithAdvertisingViewControllerTitled:@"3"] ];
    tabBarController.tabBar.translucent = !USES_OPAQUE_TAB_BAR;
    
    self.window.rootViewController = tabBarController;
    
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    return YES;
}

#pragma mark - Private

- (UIViewController *)newViewControllerWithAdvertisingViewControllerTitled:(NSString *)title
{
    UIViewController *viewController;
    MyViewController *contentViewController = [[MyViewController alloc] initWithNibName:nil bundle:nil];
    contentViewController.title = title;
    
#if USES_NAV_CONTROLLER_IN_ADV_CONTROLLER
    UINavigationController *navController = USES_NAV_CONTROLLER ? [[UINavigationController alloc] initWithRootViewController:contentViewController] : nil;
    AdViewController *adViewController = [[AdViewController alloc] initWithContentViewController:navController ?: contentViewController];
    viewController = adViewController;
    
#else
    AdViewController *adViewController = [[AdViewController alloc] initWithContentViewController:contentViewController];
    UINavigationController *navController = USES_NAV_CONTROLLER ? [[UINavigationController alloc] initWithRootViewController:adViewController] : nil;
    viewController = navController ?: adViewController;
#endif
    
    navController.navigationBar.translucent = !USES_OPAQUE_NAV_BAR;
    navController.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:nil tag:-1];
    
    adViewController.bannerAdUnitID = @"a14fc76ac9f3142";
    adViewController.interstitialAdUnitID = @"a14fc76ac9f3142";

    return viewController;
}

@end
