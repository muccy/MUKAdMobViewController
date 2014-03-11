//
//  AppDelegate.m
//  MUKAdMobViewControllerExample
//
//  Created by Marco on 10/07/13.
//  Copyright (c) 2013 MeLive. All rights reserved.
//

#import "AppDelegate.h"
#import "MyViewController.h"

#define DEBUG_OPAQUE_TAB_BAR    1
#define DEBUG_OPAQUE_NAV_BAR    1

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UITabBarController *tabBarController = [[UITabBarController alloc] init];
    tabBarController.viewControllers = @[ [self newNavigationControllerWithAdvertisingViewControllerTitled:@"1"], [self newNavigationControllerWithAdvertisingViewControllerTitled:@"2"], [self newNavigationControllerWithAdvertisingViewControllerTitled:@"3"] ];
    tabBarController.tabBar.translucent = !DEBUG_OPAQUE_TAB_BAR;
    
    self.window.rootViewController = tabBarController;
    
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    return YES;
}

#pragma mark - Private 

- (UINavigationController *)newNavigationControllerWithAdvertisingViewControllerTitled:(NSString *)title
{
    MyViewController *contentViewController = [[MyViewController alloc] initWithNibName:nil bundle:nil];
    contentViewController.title = title;
    
    AdViewController *adViewController = [[AdViewController alloc] initWithContentViewController:contentViewController];
    adViewController.bannerAdUnitID = @"a14fc76ac9f3142";
    adViewController.interstitialAdUnitID = @"a14fc76ac9f3142";
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:adViewController];
    navController.navigationBar.translucent = !DEBUG_OPAQUE_NAV_BAR;
    navController.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:nil tag:-1];
    
    return navController;
}

@end
