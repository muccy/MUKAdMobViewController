//
//  AdViewController.m
//  MUKAdMobViewControllerExample
//
//  Created by Marco on 11/07/13.
//  Copyright (c) 2013 MeLive. All rights reserved.
//

#import "AdViewController.h"

#define USES_INTERSTITIAL_ADS   0

@interface AdViewController ()

@end

@implementation AdViewController

- (GADRequest *)newInterstitialRequest {
    GADRequest *request = [super newInterstitialRequest];
    request.testDevices = @[ GAD_SIMULATOR_ID ];
    return request;
}

- (GADRequest *)newBannerAdRequest {
    GADRequest *request = [super newBannerAdRequest];
    request.testDevices = @[ GAD_SIMULATOR_ID ];
    return request;
}

static BOOL AppReceivedInterstitial = NO;

- (BOOL)shouldRequestInterstitialAd {
    return USES_INTERSTITIAL_ADS && !AppReceivedInterstitial;
}

- (void)interstitialDidReceiveAd:(GADInterstitial *)ad {
    [super interstitialDidReceiveAd:ad];
    AppReceivedInterstitial = YES;
}

@end
