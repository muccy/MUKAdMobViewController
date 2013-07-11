#import <UIKit/UIKit.h>
#import "GADBannerView.h"
#import "GADInterstitial.h"
#import <CoreLocation/CoreLocation.h>

/**
 View controller which manages AdMob interactions.
 
 Implements those delegate methods (so call super implementation if you are 
 subclassing):
 
 - (void)adViewDidReceiveAd:(GADBannerView *)view;
 - (void)adView:(GADBannerView *)view didFailToReceiveAdWithError:(GADRequestError *)error
 
 - (void)interstitialDidReceiveAd:(GADInterstitial *)ad;
 - (void)interstitial:(GADInterstitial *)ad didFailToReceiveAdWithError:(GADRequestError *)error;
 
 - (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations;
 - (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error;
 
 
 ## Expandable banner expaination
 
 AdMob mediation banner events can not manage expandable banners alone, because
 AdMob mediation does not contemplate this size.
 
 So, AdMob mediation banner event instances should post some notification when
 an expand event is sent by mediated ad view, and another notification
 when a shrink event is sent by mediated view.
 
 What is more, if you change GADBannerView size at runtime and you try to access
 mediatedView everything crashes (I suppose because it can not find a mediated
 view with a matching size).
 
 I succeeded with this workaround:
 1) Banner expanded notification received
 2) Test if banner is not expanded: if not, you can access mediatedView safely
 3) If mediatedView == notification's view set advertising expanded
 4) Extract mediated view
    a) Retain mediated view in an ivar
    b) Retain its delegate
    c) Dispose GADBannerView
    d) Insert retained expanded view into advertisingView (to fill it). Expanded
       view is actually inserted in a scroll view in order not to cut out parts
       of advertising.
 This way I blocked mediation and I can set mediated view size freely.
 
 To shrink it:
 1) Set advertising view hidden to YES, in order to hide banner and restore canonical
 size (e.g.: 320x50)
 2) As animation finishes I recreate a GADBannerView, I add it above extended view
 3) You have to implement completion block and to call disposeExpandedAdView
 (anyway it is disposed also in next `adViewDidReceiveAd:` invocation for security
 reasons) and to load another request with requestNewAd.
 This way I restored normal banner mediation.
 
 So you do need to subclass MUKAdMobViewController and to provide notifications
 handling and an implementation for retainDelegateOfExpandedAdView: and
 releaseDelegateOfExpandableAdView:.
 */
@interface MUKAdMobViewController : UIViewController <GADBannerViewDelegate, GADInterstitialDelegate, CLLocationManagerDelegate>

/**
 View controller which displays content above advertising.
 */
@property (nonatomic, strong, readonly) UIViewController *contentViewController;

/**
 AdMob banner view.
 */
@property (nonatomic, strong, readonly) GADBannerView *bannerView;

/**
 AdMob interstitial.
 */
@property (nonatomic, strong, readonly) GADInterstitial *interstitial;

/**
 AdMob Ad Unit ID which will be used to create new banner views.
 */
@property (nonatomic, copy) NSString *bannerAdUnitID;

/**
 AdMob Ad Unit ID which will ne used to create new interstitials.
 */
@property (nonatomic, copy) NSString *interstitialAdUnitID;

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
 Interstitial has been presented in this session.
 
 This property will be set to false when app goes background.
 */
@property (nonatomic, readonly) BOOL interstitialPresentedInCurrentSession;

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
- (BOOL)shouldRequestBannerAds;

/**
 Requests new ad.
 */
- (void)requestNewBannerAd;

/**
 Creates new ad request.
 
 @return A plain `GADRequest` instance.
 */
- (GADRequest *)newBannerAdRequest;
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


@interface MUKAdMobViewController (InterstitialAd)
/**
 Interstitial should be shown?
 
 @return YES if interstital request should start. Default returns YES if no
 interstitial has been presented in current session.
 */
- (BOOL)shouldRequestInterstitialAd;

/**
 Starts interstitial request.
 */
- (void)requestNewInterstitialAd;

/**
 Creates new interstitial.
 
 @return New interstitial instance.
 */
- (GADInterstitial *)newInterstitial;

/**
 Creates new ad request for interstitial.
 
 @return New ad request.
 */
- (GADRequest *)newInterstitialRequest;
@end


@interface MUKAdMobViewController (ApplicationNotifications)
/**
 UIApplicationDidEnterBackgroundNotification handler. Default implementation
 hides advertising view, disposes expanded ad view, dismisses interstitial object
 and stops geolocation.
 
 @param notification Notification object.
 */
- (void)applicationDidEnterBackground:(NSNotification *)notification;

/**
 UIApplicationWillEnterForegroundNotification handler. Default implementation
 restarts or disposes banner and interstitial ads (after a tiny interval).
 
 @param notification Notification object.
 */
- (void)applicationWillEnterForeground:(NSNotification *)notification;
@end
