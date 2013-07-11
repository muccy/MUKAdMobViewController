//
//  MyViewController.m
//  MUKAdMobViewControllerExample
//
//  Created by Marco on 10/07/13.
//  Copyright (c) 2013 MeLive. All rights reserved.
//

#import "MyViewController.h"

@interface MyViewController ()
@property (nonatomic) NSTimer *titleTimer;
@end

@implementation MyViewController

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

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Title changes every second
    if (self.titleTimer == nil) {
        self.titleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(titleTimerFired:) userInfo:nil repeats:YES];
    }
}

- (IBAction)pushAnotherPressed:(id)sender {
    MyViewController *contentViewController = [[MyViewController alloc] initWithNibName:nil bundle:nil];
    
    AdViewController *adViewController = [[AdViewController alloc] initWithContentViewController:contentViewController];
    adViewController.bannerAdUnitID = @"REPLACE ME";
    adViewController.interstitialAdUnitID = @"REPLACE ME";
    
    [self.navigationController pushViewController:adViewController animated:YES];
}

#pragma mark - Private

- (void)titleTimerFired:(NSTimer *)timer {
    self.title = [[NSDate date] description];
}

@end
