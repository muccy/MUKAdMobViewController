#import <UIKit/UIKit.h>
#import <GoogleMobileAds/GADBannerView.h>
#import <GoogleMobileAds/GADInterstitial.h>
#import <CoreLocation/CoreLocation.h>

typedef NS_ENUM(NSInteger, MUKAdMobAdvertisingNetwork) {
    MUKAdMobAdvertisingNetworkAdMob = 0,
    MUKAdMobAdvertisingNetworkDFP
};

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
 Ad network used by bannerView.
 Default is MUKAdMobAdvertisingNetworkAdMob.
 */
@property (nonatomic) MUKAdMobAdvertisingNetwork bannerAdNetwork;

/**
 Ad network used by interstitial.
 Default is MUKAdMobAdvertisingNetworkAdMob.
 */
@property (nonatomic) MUKAdMobAdvertisingNetwork interstitialAdNetwork;

/**
 AdMob banner view.
 If bannerAdNetwork is MUKAdMobAdvertisingNetworkDFP, a DFPBannerView is alloc'd.
 */
@property (nonatomic, strong, readonly) GADBannerView *bannerView;

/**
 AdMob interstitial.
 If interstitialAdNetwork is MUKAdMobAdvertisingNetworkDFP, a DFPInterstitial is 
 alloc'd.
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
 Is advertising view hidden?
 */
@property (nonatomic, readonly, getter = isAdvertisingViewHidden) BOOL advertisingViewHidden;

/**
 Banner view did receive an ad.
 
 This property could be false if banner view has not received an ad yet, or
 if banner view has received an error.
 */
@property (nonatomic, readonly) BOOL bannerAdReceived;

/**
 Interstitial has been received in this session.
 
 This property will be set to NO when app goes background.
 */
@property (nonatomic, readonly) BOOL interstitialAdReceivedDuringCurrentSession;

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
 It returns nil if requested ad size is `kGADAdSizeInvalid`.
 */
- (GADBannerView *)newBannerView;

/**
 Removes bannerView.
 */
- (void)disposeBannerView;

/**
 The ad size for an orientation.
 This method is called with bannerView is instantiated and inside
 -viewWillLayoutSubviews to react to interface rotations. When ad size changes,
 this class hides banner view and it updates bannerView.adSize properly. This
 will make AdMob to request new ad for updated size.
 If you always return the same ad size, nothing happens on autorotations.
 If you return `kGADAdSizeInvalid`, banner view will be hidden and disposed.
 
 @param orientation The given orientation to use to calculate banner ad size.
 @return Banner size. Default returns `kGADAdSizeSmartBannerLandscape` when
 orientation is landscape, or `kGADAdSizeSmartBannerPortrait` for other cases.
 */
- (GADAdSize)bannerAdSizeForOrientation:(UIInterfaceOrientation)orientation;
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
- (BOOL)shouldRequestBannerAd;

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
 
 Content view controller is layed out horing extendedLayoutIncludesOpaqueBars and
 edgesForExtendedLayout. That means, for example:
 * On iOS 6, content view never goes under advertising view.
 * On iOS 7, content view doesn't go under advertising view if
   extendedLayoutIncludesOpaqueBars is set to NO (default) and no bottom translucent
   bar is displayed (e.g. tab bar).
 * On iOS 7, content view doesn't go under advertising view if
   edgesForExtendedLayout does not include UIRectEdgeBottom.
 * On iOS 7, content view does go under advertising view if, for example, everything
   is left as default (edgesForExtendedLayout == UIRectEdgeAll and
   extendedLayoutIncludesOpaqueBars == NO) and a bottom translucent view is displayed
   (e.g. a tab bar).
 
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
- (BOOL)shouldStopGeolocationForError:(NSError *)error;

/**
 Request authorization to user.
 
 By default it calls -requestWhenInUseAuthorization if available (iOS 8).
 This method is called before to start location manager.
 */
- (void)requestGeolocationAuthorization;
@end


@interface MUKAdMobViewController (InterstitialAd)
/**
 Interstitial should be shown?
 
 @return YES if interstitial request should start. Default returns NO.
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

/**
 An interstitial ad has been received and you could choose to display it.
 Using this method you have the chance to save received ad and to postpone its
 presentation.
 
 @param ad The received interstitial ad.
 @return YES if you want to present interstitial ad. Default is YES.
 */
- (BOOL)shouldPresentReceivedInterstitialAd:(GADInterstitial *)ad;

/**
 If -shouldPresentReceivedInterstitialAd: returns YES, this view controller is
 used to present interstitial ad.
 It defaults to self.
 
 @return View controller which presents interstitial ad.
 */
- (UIViewController *)interstitialAdRootViewController;
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
