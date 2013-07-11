#import <UIKit/UIKit.h>
#import "GADBannerView.h"
#import <CoreLocation/CoreLocation.h>

/**
 View controller which manages AdMob interactions.
 */
@interface MUKAdMobViewController : UIViewController <GADBannerViewDelegate, CLLocationManagerDelegate>

/**
 View controller which displays content above advertising.
 */
@property (nonatomic, strong, readonly) UIViewController *contentViewController;

/**
 AdMob banner view.
 */
@property (nonatomic, strong, readonly) GADBannerView *bannerView;

/**
 AdMob Ad Unit ID which will be used to create new banner views.
 */
@property (nonatomic, copy) NSString *bannerAdUnitID;

/**
 View where bannerView is embedded.
 */
@property (nonatomic, strong, readonly) UIView *advertisingView;

/**
 View expanded from bannerView.
 */
@property (nonatomic, strong, readonly) UIView *expandedAdView;

/**
 Is banner view expanded? You should check this boolean to know, not expandedAdView.
 */
@property (nonatomic, readonly, getter = isAdViewExpanded) BOOL adViewExpanded;

/**
 Banner view did receive an ad.
 
 This property could be false if banner view has not received an ad yet, or
 if banner view has received an error.
 */
@property (nonatomic, readonly) BOOL bannerAdReceived;

/**
 Location manager used to retrieve a coordinate for ad request.
 */
@property (nonatomic, readonly) CLLocationManager *locationManager;

/**
 If true, ad request is sent only if there is a valid location inside location
 manager. If there isn't and this property is set to YES, if start updating
 location. Another -requestNewAd message will be sent after locationManager
 finishes geolocation.
 */
@property (nonatomic) BOOL requiresValidLocationToRequestNewAd;

/**
 Stores last location manager error.
 
 This property is nilled out when application goes background.
 */
@property (nonatomic, readonly) NSError *lastLocationManagerError;

/**
 Default initializer.
 
 @param contentViewController View controller used to display contents.
 @return New instance.
 */
- (instancetype)initWithContentViewController:(UIViewController *)contentViewController;
@end


@interface MUKAdMobViewController (Banner)
/**
 Set advertising view onscreen/offscreen.
 
 @param hidden If `YES` advertisingView is set offscreen.
 @param animated If `YES` transition is animated.
 @param completionHandler An handler called after transition is completed. If
 `animated` is `NO`, `completionHandler` is called immediately.
 */
- (void)setAdvertisingViewHidden:(BOOL)hidden animated:(BOOL)animated completion:(void (^)(BOOL finished))completionHandler;

/**
 Shortend to show/hide a banner.
 
 This methods checks if ads could be shown by invoking shouldShowAds.
 If ads are permitted, it tests adReceived to discover if advertising
 is already inside banner and it shows it. If adReceived is false, it
 hides banner view and tries to request another banner.
 If ads are not permitted, banner is hidden and disposed.
 
 @param animated If `YES` transition is animated.
 @param completionHandler An handler called after transition is completed.
 */
- (void)toggleAdvertisingViewVisibilityAnimated:(BOOL)animated completion:(void (^)(BOOL finished))completionHandler;

/**
 Creates new banner view.
 
 @return `GADBannerView` instance with `kGADAdSizeBanner` ad size. What is more,
 this method set banner view delegate to `self` and it setups other view defaults.
 */
- (GADBannerView *)newBannerView;

/**
 Removes bannerView.
 */
- (void)disposeBannerView;
@end


@interface MUKAdMobViewController (InlineBannerExpansion)
/**
 Extracts mediated ad view, disposes banner view and expands advertising above
 contents view.
 
 When you unexpand advertising, it is hidden (calling
 setAdvertisingViewHidden:animated:completion:) and a new request is performed.
 
 @param expanded If `YES` advertisingView is set to overlap contentsView.
 @param targetSize Suggested size for expansion. This parameter is ignored if
 expanded is `NO`. It is passed to advertisingViewFrameWhenExpandedToSize: in order
 to calculate a frame which does not exceed available pixels.
 @param animated If `YES` transition is animated.
 @param completionHandler An handler called after transition is completed.
 */
- (void)setAdvertisingViewExpanded:(BOOL)expanded toSize:(CGSize)targetSize animated:(BOOL)animated completion:(void (^)(BOOL finished))completionHandler;

/**
 A chance to retain expanded advertising view's delegate.
 
 This method is called while expandedAdView is being extracted from bannerView.
 
 @param expandedAdView Extracted mediated ad view.
 */
- (void)retainDelegateOfExpandedAdView:(UIView *)expandedAdView;

/**
 A chance to release expanded advertising view's delegate.
 
 This method is called while expandedAdView is being disposed because bannerView
 is ready to take the stage again.
 
 @param expandedAdView Extracted mediated ad view.
 */
- (void)releaseDelegateOfExpandableAdView:(UIView *)expandedAdView;

/**
 Destroys expanded ad view if needed.
 
 This method calls releaseDelegateOfExpandableAdView: and removes expanded ad view.
 */
- (void)disposeExpandedAdView;
@end


@interface MUKAdMobViewController (Request)
/**
 Ads should be shown?
 
 @return It returns YES when both contentViewController and advertisingView 
 are not nil.
 */
- (BOOL)shouldShowAds;

/**
 Requests new ad.
 */
- (void)requestNewAd;

/**
 Creates new ad request.
 
 @return A plain `GADRequest` instance.
 */
- (GADRequest *)newAdRequest;
@end


@interface MUKAdMobViewController (Layout)
/**
 Creates autolayout constraints to arrange views.
 
 @param hidden Is banner hidden?
 @param expanded Is banner expanded inline?
 @param targetSize What size is needed after expansion?
 
 @return An array on NSLayoutConstraint objects.
 */
- (NSArray *)layoutConstraintsForAdvertisingViewHidden:(BOOL)hidden expanded:(BOOL)expanded toTargetSize:(CGSize)targetSize;
@end


@interface MUKAdMobViewController (Geolocation)
/**
 Builds location manager created on initialization.
 @return New location manager instance.
 */
- (CLLocationManager *)newLocationManager;

/**
 The location is to request advertising.
 
 @param location The location to be inspected.
 @return YES is location is recent and accurate enough.
 */
- (BOOL)isValidLocation:(CLLocation *)location;

/**
 Decide to start geolocation before to request new ad.
 @return YES if you want to geolocate before to request new ad. Default returns
 YES only if there isn't a valid cached location and
 requiresValidLocationToRequestNewAd is true. It returns NO also if last location
 manager error can not be resolved.
 */
- (BOOL)shouldStartGeolocation;

/** 
 Decide if location manager error is critical.
 
 @param error Location manager generated error.
 @return YES if error can not be recovered. Default returns YES when error code
 is not kCLErrorLocationUnknown.
 */
- (BOOL)shouldStopGeolocationOnError:(NSError *)error;
@end
