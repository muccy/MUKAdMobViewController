//
//  AppDelegate.m
//  MUKAdMobViewControllerExample
//
//  Created by Marco on 10/07/13.
//  Copyright (c) 2013 MeLive. All rights reserved.
//

#import "AppDelegate.h"
#import "MyViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UITabBarController *tabBarController = [[UITabBarController alloc] init];
    tabBarController.viewControllers = @[ [self newNavigationControllerWithAdvertisingViewControllerTitled:@"1"], [self newNavigationControllerWithAdvertisingViewControllerTitled:@"2"], [self newNavigationControllerWithAdvertisingViewControllerTitled:@"3"] ];
    
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
    navController.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:nil tag:-1];
    
    return navController;
}

@end
