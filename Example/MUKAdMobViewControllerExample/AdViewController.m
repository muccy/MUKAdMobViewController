//
//  AdViewController.m
//  MUKAdMobViewControllerExample
//
//  Created by Marco on 11/07/13.
//  Copyright (c) 2013 MeLive. All rights reserved.
//

#import "AdViewController.h"

@interface AdViewController ()

@end

@implementation AdViewController

- (GADRequest *)newInterstitialRequest {
    GADRequest *request = [super newInterstitialRequest];
    request.testDevices = @[ @"GAD_SIMULATOR_ID" ];
    return request;
}

- (GADRequest *)newBannerAdRequest {
    GADRequest *request = [super newBannerAdRequest];
    request.testDevices = @[ @"GAD_SIMULATOR_ID" ];
    return request;
}

@end
