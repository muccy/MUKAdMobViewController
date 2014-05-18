//
//  MyViewController.m
//  MUKAdMobViewControllerExample
//
//  Created by Marco on 10/07/13.
//  Copyright (c) 2013 MeLive. All rights reserved.
//

#import "MyViewController.h"
#import "AdViewController.h"

@interface MyViewController ()
@property (nonatomic) NSTimer *titleTimer;
@property (nonatomic) BOOL constraintsAdded;
@property (nonatomic) NSLayoutConstraint *bottomConstraint;
@property (nonatomic, readonly) AdViewController *parentAdViewController;
@end

@implementation MyViewController
@dynamic parentAdViewController;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = @"My View Controller";
    }
    
    return self;
}

- (void)dealloc {
    [self.titleTimer invalidate];
    self.titleTimer = nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Title changes every second
    if (self.titleTimer == nil) {
        self.titleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(titleTimerFired:) userInfo:nil repeats:YES];
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    if (!self.constraintsAdded) {
        self.constraintsAdded = YES;
        
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-[label]-|" options:0 metrics:nil views:@{ @"label" : self.contentsLabel }]];
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[label]" options:0 metrics:nil views:@{ @"label" : self.contentsLabel }]];
    }
    
    AdViewController *adViewController = self.parentAdViewController;
    
    if (self.bottomConstraint) {
        [adViewController.view removeConstraint:self.bottomConstraint];
    }
    
    id referencedItem;
    if (adViewController.isAdvertisingViewHidden) {
        if ([adViewController respondsToSelector:@selector(bottomLayoutGuide)]) {
            referencedItem = [adViewController bottomLayoutGuide];
        }
        else {
            referencedItem = adViewController.advertisingView;
        }
    }
    else {
        referencedItem = adViewController.advertisingView;
    }
    
    self.bottomConstraint = [NSLayoutConstraint constraintWithItem:self.contentsLabel attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:referencedItem attribute:NSLayoutAttributeTop multiplier:1.0f constant:-20.0f];
    [adViewController.view addConstraint:self.bottomConstraint];
}

- (IBAction)pushAnotherPressed:(id)sender {
    MyViewController *contentViewController = [[MyViewController alloc] initWithNibName:nil bundle:nil];
    
    if ([contentViewController respondsToSelector:@selector(setExtendedLayoutIncludesOpaqueBars:)])
    {
        contentViewController.extendedLayoutIncludesOpaqueBars = self.extendedLayoutIncludesOpaqueBars;
    }
    
    if ([contentViewController respondsToSelector:@selector(setEdgesForExtendedLayout:)])
    {
        contentViewController.edgesForExtendedLayout = self.edgesForExtendedLayout;
    }
    
    AdViewController *adViewController = [[AdViewController alloc] initWithContentViewController:contentViewController];
    
    AdViewController *parentAdViewController = self.parentAdViewController;
    adViewController.bannerAdUnitID = parentAdViewController.bannerAdUnitID;
    adViewController.interstitialAdUnitID = parentAdViewController.interstitialAdUnitID;
    
    [self.navigationController pushViewController:adViewController animated:YES];
}

#pragma mark - Accessors

- (AdViewController *)parentAdViewController {
    UIViewController *inspectedViewController = self.parentViewController;
    AdViewController *foundViewController = nil;
    
    do {
        if ([inspectedViewController isKindOfClass:[AdViewController class]])
        {
            foundViewController = (AdViewController *)inspectedViewController;
        }
        else {
            inspectedViewController = inspectedViewController.parentViewController;
        }
    } while (!foundViewController && inspectedViewController);
    
    return foundViewController;
}

#pragma mark - Private

- (void)titleTimerFired:(NSTimer *)timer {
    self.title = [[NSDate date] description];
}

@end
