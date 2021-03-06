#import "MUKAdMobViewController.h"
#import "DFPBannerView.h"
#import "DFPInterstitial.h"

static NSTimeInterval const kAdvertisingAnimationDuration = 0.3;
static NSTimeInterval const kAdvertisingExpandingAnimationDuration = 0.3;

static NSTimeInterval const kMaxLocationTimestampInterval = 3600.0; // 1 hour
static NSTimeInterval const kLocationManagerTimeoutInterval = 15.0;

typedef NS_OPTIONS(NSInteger, MUKAdMobViewControllerGeolocationIntent) {
    MUKAdMobViewControllerGeolocationIntentNone         = 0,
    MUKAdMobViewControllerGeolocationIntentBanner       = 1 << 0,
    MUKAdMobViewControllerGeolocationIntentInterstitial = 1 << 1
};

@interface MUKAdMobViewController ()
@property (nonatomic, weak) UIView *contentWrapperView;
@property (nonatomic) GADAdSize lastRequestedAdSize;
@property (nonatomic) BOOL shouldRequestAdvertisingInViewDidAppear;
@property (nonatomic) NSArray *advertisingAndContentLayoutConstraints;
@property (nonatomic, strong, readwrite) UIScrollView *expandedAdViewContainer;
@property (nonatomic) NSTimer *locationManagerTimeoutTimer;
@property (nonatomic) BOOL lastLocationStoppedForTimeout, changingBannerViewAdSize, bannerAdRequested;
@property (nonatomic) MUKAdMobViewControllerGeolocationIntent geolocationIntent;

@property (nonatomic, strong, readwrite) GADBannerView *bannerView;
@property (nonatomic, strong, readwrite) GADInterstitial *interstitial;
@property (nonatomic, readwrite) BOOL bannerAdReceived;
@property (nonatomic, readwrite, getter = isAdViewExpanded) BOOL adViewExpanded;
@property (nonatomic, strong, readwrite) UIView *expandedAdView;
@property (nonatomic, readwrite) NSError *lastLocationManagerError;
@property (nonatomic, readwrite) BOOL interstitialAdReceivedDuringCurrentSession;
@property (nonatomic, readwrite, getter = isAdvertisingViewHidden) BOOL advertisingViewHidden;
@end

@implementation MUKAdMobViewController

- (instancetype)initWithContentViewController:(UIViewController *)contentViewController
{
    self = [super init];
    if (self) {
        _contentViewController = contentViewController;
        
        // Dummy advertising view will be resized by constraints
        _advertisingView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 320.f, 50.0f)];
        _advertisingView.translatesAutoresizingMaskIntoConstraints = NO;
        
        // Setup defaults
        _shouldRequestAdvertisingInViewDidAppear = YES;
        _lastRequestedAdSize = kGADAdSizeInvalid;
        _requiresValidLocationToRequestNewAd = YES;
        
        // Create location manager to get cached locations, eventually
        _locationManager = [self newLocationManager];
        
        // Notifications subscription
        [self registerToApplicationNotifications];
    }
    
    return self;
}

- (void)dealloc {
    self.locationManager.delegate = nil;
    self.interstitial.delegate = nil;
    
    [self cancelLocationManagerTimeoutTimer];
    
    [self unregisterFromApplicationNotifications];
    [self disposeBannerView];
    [self disposeExpandedAdView];
}

#pragma mark - View Events

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // View controller containment
    if (self.contentViewController) {
        // Also calls -willMoveToParentViewController: automatically.
        [self addChildViewController:self.contentViewController];
        
        // Constraints will be set
        UIView *wrapperView = [[UIView alloc] initWithFrame:self.view.bounds];
        wrapperView.translatesAutoresizingMaskIntoConstraints = NO;
        wrapperView.backgroundColor = [UIColor clearColor];
        
        // Insert content controller's view
        self.contentViewController.view.frame = wrapperView.bounds;
        self.contentViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [wrapperView addSubview:self.contentViewController.view];
        
        // Insert wrapper
        [self.view addSubview:wrapperView];
        self.contentWrapperView = wrapperView;
        
        // Complete containment
        [self.contentViewController didMoveToParentViewController:self];
    }
    
    // Insert advertising view
    if (self.advertisingView) {
        [self.view addSubview:self.advertisingView];
    }
    
    // Hide banner
    // Also applies autolayout constraints
    [self setAdvertisingViewHidden:YES animated:NO completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.contentViewController beginAppearanceTransition:YES animated:animated];
    
    // Hide advertising if not appropriate
    if ([self shouldRequestBannerAd] == NO) {
        [self setAdvertisingViewHidden:YES animated:NO completion:^(BOOL finished)
         {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
             [self disposeBannerView];
             [self disposeExpandedAdView];
#pragma clang diagnostic pop
         }];
    }
    
    // Request interstitial if needed
    if ([self shouldRequestInterstitialAd]) {
        [self requestNewInterstitialAd];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (self.shouldRequestAdvertisingInViewDidAppear) {
        self.shouldRequestAdvertisingInViewDidAppear = NO;
        [self toggleAdvertisingViewVisibilityAnimated:YES completion:nil];
    }
    
    [self.contentViewController endAppearanceTransition];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.contentViewController beginAppearanceTransition:NO animated:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.contentViewController endAppearanceTransition];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    // Orientation is changing
    // If banner is not expanded, request new ad size if needed
    if (self.bannerAdRequested && !self.isAdViewExpanded && !self.changingBannerViewAdSize)
    {
        UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
        GADAdSize adSize = [self bannerAdSizeForOrientation:orientation];
        
        // Size has changed
        if (!GADAdSizeEqualToSize(adSize, self.lastRequestedAdSize)) {
            // Hide banner view
            __weak MUKAdMobViewController *weakSelf = self;
            self.changingBannerViewAdSize = YES;
            [self setAdvertisingViewHidden:YES animated:YES completion:^(BOOL finished)
            {
                MUKAdMobViewController *strongSelf = weakSelf;
                
                // If side is invalid, dispose banner view.
                // Otherwise update ad size
                if (GADAdSizeEqualToSize(adSize, kGADAdSizeInvalid)) {
                    [strongSelf disposeBannerView];
                }
                else {
                    // If banner is already alloc'd just update.
                    // Otherwise make a brand new allocation and request.
                    if (strongSelf.bannerView) {
                        strongSelf.bannerView.adSize = adSize;
                    }
                    else {
                        [strongSelf requestNewBannerAd];
                    }
                }
               
                strongSelf.lastRequestedAdSize = adSize;
                strongSelf.changingBannerViewAdSize = NO;
            }]; // setAdvertisingViewHidden
        } // if size has changed
    } // if banner is not expanded
}

#pragma mark - Overrides

// Useful when embedding in UINavigationController
- (UINavigationItem *)navigationItem {
    return self.contentViewController.navigationItem;
}

// Useful when embedding in UITabBarController
- (UITabBarController *)tabBarController {
    return self.contentViewController.tabBarController;
}

// Useful when embedding in UITabBarController
- (UITabBarItem *)tabBarItem {
    return self.contentViewController.tabBarItem;
}

- (BOOL)shouldAutomaticallyForwardAppearanceMethods {
    return NO;
}

- (UIViewController *)childViewControllerForStatusBarHidden {
    return self.contentViewController;
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return self.contentViewController;
}

#pragma mark - Banner

- (void)setAdvertisingViewHidden:(BOOL)hidden animated:(BOOL)animated completion:(void (^)(BOOL finished))completionHandler
{
    // Check if view controller is ready to apply constraints
    if (self.advertisingView.superview != self.view &&
        self.contentWrapperView.superview != self.view)
    {
        return;
    }
    
    self.advertisingViewHidden = hidden;
    
    // Apply new constraints
    [self updateLayoutConstraintsForAdvertisingViewHidden:hidden expanded:NO toTargetSize:CGSizeZero];
    
    // Set visible if needed
    if (!hidden) {
        self.advertisingView.hidden = NO;
    }
    
    // Animate if needed
    [UIView animateWithDuration:(animated ? kAdvertisingAnimationDuration : 0.0) delay:0.0f options:UIViewAnimationOptionAllowUserInteraction animations:^
     {
         [self.view layoutIfNeeded];
     } completion:^(BOOL finished) {
         if (finished && hidden) {
             self.advertisingView.hidden = YES;
         }
         
         if (completionHandler) {
             completionHandler(finished);
         }
     }];
}

- (void)toggleAdvertisingViewVisibilityAnimated:(BOOL)animated completion:(void (^)(BOOL finished))completionHandler
{
    if ([self shouldRequestBannerAd]) {
        // Should show ads
        
        if (self.bannerAdReceived) {
            // An ad has been already received
            // Show banner view
            [self setAdvertisingViewHidden:NO animated:animated completion:completionHandler];
        }
        else {
            // Ad not received
            // Hide banner view
            [self setAdvertisingViewHidden:YES animated:animated completion:^(BOOL finished)
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                if ([self shouldRequestBannerAd]) {
                    [self requestNewBannerAd];
                }
                 
                if (completionHandler) {
                    completionHandler(finished);
                }
#pragma clang diagnostic pop
            }];
        }
    }
    else {
        // Should not show ads
        // Hide and dispose
        [self setAdvertisingViewHidden:YES animated:animated completion:^(BOOL finished)
         {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
             if (finished) {
                 [self disposeBannerView];
                 [self disposeExpandedAdView];
             }
             
             if (completionHandler) {
                 completionHandler(finished);
             }
#pragma clang diagnostic pop
         }];
    }
}

- (GADBannerView *)newBannerView {
    GADAdSize adSize = [self bannerAdSizeForOrientation:self.interfaceOrientation];
    if (GADAdSizeEqualToSize(adSize, kGADAdSizeInvalid)) {
        return nil;
    }
    
    Class bannerViewClass;
    
    if (self.bannerAdNetwork == MUKAdMobAdvertisingNetworkDFP) {
        bannerViewClass = [DFPBannerView class];
    }
    else {
        bannerViewClass = [GADBannerView class];
    }
    
    GADBannerView *bannerView = [[bannerViewClass alloc] initWithAdSize:adSize];
    self.lastRequestedAdSize = adSize;
    
    bannerView.delegate = self;
    bannerView.backgroundColor = [UIColor clearColor];
    bannerView.rootViewController = self;
    bannerView.adUnitID = self.bannerAdUnitID;
    
    return bannerView;
}

- (void)disposeBannerView {
    self.bannerAdReceived = NO;
    [self.bannerView removeFromSuperview];
    
    self.bannerView.delegate = nil;
    self.bannerView = nil;
    
    if (self.isAdViewExpanded == NO) {
        self.shouldRequestAdvertisingInViewDidAppear = YES;
    }
}

- (GADAdSize)bannerAdSizeForOrientation:(UIInterfaceOrientation)orientation {
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        return kGADAdSizeSmartBannerLandscape;
    }
    
    return kGADAdSizeSmartBannerPortrait;
}

#pragma mark - Inline Banner Expansion

- (void)setAdvertisingViewExpanded:(BOOL)expanded toSize:(CGSize)targetSize animated:(BOOL)animated completion:(void (^)(BOOL finished))completionHandler
{
    // Check if view controller is ready to apply constraints
    if (self.advertisingView.superview != self.view &&
        self.contentWrapperView.superview != self.view)
    {
        return;
    }
    
    // Apply new constraints
    [self updateLayoutConstraintsForAdvertisingViewHidden:NO expanded:expanded toTargetSize:targetSize];
    
    if (expanded) {
        // Extract mediated ad view and destroy banner view
        [self extractExpandedAdViewToOriginalTargetSize:targetSize];
        
        // Put advertising view on top
        [self.view bringSubviewToFront:self.advertisingView];
    }
    
    [UIView animateWithDuration:(animated ? kAdvertisingExpandingAnimationDuration : 0.0) animations:^
    {
        // Layout new constraints
        [self.view layoutIfNeeded];
        
        if (expanded == NO) {
            // Fade out
            self.advertisingView.alpha = 0.0f;
            
            // And hide
            [self setAdvertisingViewHidden:YES animated:animated completion:^(BOOL finished)
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                // Fade in when offscreen
                self.advertisingView.alpha = 1.0f;
                 
                if (completionHandler) {
                    completionHandler(finished);
                }
                 
                // Dispose expanded banner view after ad is received
                // Look at -adViewDidReceiveAd: (or in completion handler)
#pragma clang diagnostic pop
            }];
        }
     } completion:(expanded ? completionHandler : nil)];
}

- (void)retainDelegateOfExpandedAdView:(UIView *)expandedAdView {
    //
}

- (void)releaseDelegateOfExpandableAdView:(UIView *)expandedAdView {
    //
}

- (void)disposeExpandedAdView {
    if (self.isAdViewExpanded) {
        // Release delegate
        [self releaseDelegateOfExpandableAdView:self.expandedAdView];
        
        // Remove
        [self.expandedAdView removeFromSuperview];
        self.expandedAdView = nil;
        
        [self.expandedAdViewContainer removeFromSuperview];
        self.expandedAdViewContainer = nil;
        
        self.adViewExpanded = NO;
        self.shouldRequestAdvertisingInViewDidAppear = YES;
    }
}

#pragma mark - Banner Request

- (BOOL)shouldRequestBannerAd {
    return self.contentViewController && self.advertisingView;
}

- (void)requestNewBannerAd {
    // Invalidate postponed requests
    self.shouldRequestAdvertisingInViewDidAppear = NO;
    
    if (!self.bannerView) {
        self.bannerView = [self newBannerView];
        
        if (!self.bannerView) {
            return;
        }
    }
    
    if ([self shouldStartGeolocation]) {
        [self startLocationManagerWithIntent:MUKAdMobViewControllerGeolocationIntentBanner withTimeoutTimer:YES];
    }
    else {
        // No new geolocation is needed
        self.bannerAdRequested = YES;
        GADRequest *request = [self newBannerAdRequest];
        [self.bannerView loadRequest:request];
    }
}

- (GADRequest *)newBannerAdRequest {
    GADRequest *request = [GADRequest request];
    
    CLLocation *location = self.locationManager.location;
    if ([self isValidLocation:location]) {
        [request setLocationWithLatitude:location.coordinate.latitude longitude:location.coordinate.longitude accuracy:location.horizontalAccuracy];
    }
    
    return request;
}

#pragma mark - Layout

- (NSArray *)layoutConstraintsForAdvertisingViewHidden:(BOOL)hidden expanded:(BOOL)expanded toTargetSize:(CGSize)targetSize
{
    NSMutableArray *constraints = [NSMutableArray array];
    
    [constraints addObjectsFromArray:[self advertisingViewLayoutConstraintsForAdvertisingViewHidden:hidden expanded:expanded toTargetSize:targetSize]];

    [constraints addObjectsFromArray:[self contentViewLayoutConstraintsForAdvertisingViewHidden:hidden expanded:expanded toTargetSize:targetSize bottomHookedToAdvertisingView:[self shouldHookContentViewBottomToAdvertisingView]]];
    
    return constraints;
}

#pragma mark - Geolocation

- (CLLocationManager *)newLocationManager {
    CLLocationManager *locationManager = [[CLLocationManager alloc] init];
    locationManager.delegate = self;

    // Save power
    locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
    locationManager.activityType = CLActivityTypeOther;
    
    return locationManager;
}

- (BOOL)isValidLocation:(CLLocation *)location {
    if (location) {
        if (location.horizontalAccuracy <= self.locationManager.desiredAccuracy &&
            ABS([location.timestamp timeIntervalSinceNow]) <= kMaxLocationTimestampInterval)
        {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)shouldStartGeolocation {
    // Last error can not be resolved
    if ([self shouldStopGeolocationForError:self.lastLocationManagerError]) {
        return NO;
    }
    
    // Last location has a timeout
    if (self.lastLocationStoppedForTimeout) {
        return NO;
    }
    
    // Geolocalization is not available
    if ([CLLocationManager locationServicesEnabled] == NO ||
        [CLLocationManager authorizationStatus] == kCLAuthorizationStatusRestricted ||
        [CLLocationManager authorizationStatus] == kCLAuthorizationStatusDenied)
    {
        return NO;
    }
    
    // Invalid location with required location configuration
    if (self.requiresValidLocationToRequestNewAd &&
        ![self isValidLocation:self.locationManager.location])
    {
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldStopGeolocationForError:(NSError *)error {
    if ([error.domain isEqualToString:kCLErrorDomain] == NO) {
        return NO;
    }
    
    if (error.code == kCLErrorLocationUnknown) {
        return NO;
    }
    
    return YES;
}

#pragma mark - Interstitial Ad

- (BOOL)shouldRequestInterstitialAd {
    return NO;
}

- (void)requestNewInterstitialAd {
    // Old one
    self.interstitial.delegate = nil;
    
    // Create new one
    self.interstitial = [self newInterstitial];

    if ([self shouldStartGeolocation]) {
        [self startLocationManagerWithIntent:MUKAdMobViewControllerGeolocationIntentInterstitial withTimeoutTimer:YES];
    }
    else {
        // No new geolocation is needed
        GADRequest *request = [self newInterstitialRequest];
        [self.interstitial loadRequest:request];
    }
}

- (GADInterstitial *)newInterstitial {
    Class interstitialClass;
    
    if (self.interstitialAdNetwork == MUKAdMobAdvertisingNetworkDFP) {
        interstitialClass = [DFPInterstitial class];
    }
    else {
        interstitialClass = [GADInterstitial class];
    }
    
    GADInterstitial *interstitial = [[interstitialClass alloc] init];
    interstitial.adUnitID = self.interstitialAdUnitID;
    interstitial.delegate = self;
    return interstitial;
}

- (GADRequest *)newInterstitialRequest {
    GADRequest *request = [GADRequest request];
    
    CLLocation *location = self.locationManager.location;
    if ([self isValidLocation:location]) {
        [request setLocationWithLatitude:location.coordinate.latitude longitude:location.coordinate.longitude accuracy:location.horizontalAccuracy];
    }
    
    return request;
}

- (BOOL)shouldPresentReceivedInterstitialAd:(GADInterstitial *)ad {
    return YES;
}

- (UIViewController *)interstitialAdRootViewController {
    return self;
}

#pragma mark - Application Notifications

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    // Prepare GUI
    [self setAdvertisingViewHidden:YES animated:NO completion:nil];
    
    // Reduce memory usage
    
    // I would like to dispose entire banner view, but I can't due to a
    // AdMob SDK bug "documented" here:
    // https://developers.google.com/mobile-ads-sdk/community/?place=msg%2Fgoogle-admob-ads-sdk%2FunOZt-_BnOw%2FSNhtiGEN4wcJ
    // -disposeBannerView call is postponed to -applicationWillEnterForeground
    
    [self disposeExpandedAdView];
    
    self.interstitialAdReceivedDuringCurrentSession = NO;
    self.interstitial.delegate = nil;
    self.interstitial = nil;
    
    // Stop geolocation
    [self stopLocationManager];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    // It's not enough to postpone to -applicationWillEnterForeground: because
    // sometimes apps crash on -[GADObjectPrivate appDidBecomeInactive:] in
    // response of a notification. I'll try to dispose banner view after
    // notifications are dispatched.
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        // Restart ads or dispose
        if ([self shouldRequestBannerAd]) {
            [self requestNewBannerAd];
        }
        else {
            [self disposeBannerView];
        }
    });
    
    // Request interstitial if needed
    if ([self shouldRequestInterstitialAd]) {
        [self requestNewInterstitialAd];
    }
}

#pragma mark - Private — Application Notifications

- (void)registerToApplicationNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)unregisterFromApplicationNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
}

#pragma mark - Private — Inline Banner Expansion

- (void)extractExpandedAdViewToOriginalTargetSize:(CGSize)originalTargetSize {
    if (self.isAdViewExpanded == NO) {
        self.adViewExpanded = YES;
        
        // Retain view
        self.expandedAdView = self.bannerView.mediatedAdView;
        
        // Retain delegate
        [self retainDelegateOfExpandedAdView:self.expandedAdView];
        
        // Dispose mediation banner
        [self.expandedAdView removeFromSuperview];
        [self disposeBannerView];
        
        // Create container
        self.expandedAdViewContainer = [[UIScrollView alloc] initWithFrame:self.advertisingView.bounds];
        self.expandedAdViewContainer.backgroundColor = [UIColor clearColor];
        
        // Insert expanded view in container
        self.expandedAdView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        CGRect frame = self.expandedAdView.frame;
        frame.origin = CGPointZero;
        self.expandedAdView.frame = frame;
        [self.expandedAdViewContainer addSubview:self.expandedAdView];
        
        // Set content size
        self.expandedAdViewContainer.contentSize = originalTargetSize;
        
        // Insert expanded view container directly in the hierarchy
        self.expandedAdViewContainer.autoresizingMask = UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
        self.expandedAdViewContainer.frame = self.advertisingView.bounds;
        [self.advertisingView addSubview:self.expandedAdViewContainer];
    }
}

#pragma mark - Private — Layout

- (void)disposeAdvertisingAndContentLayoutConstraints {
    if ([self.advertisingAndContentLayoutConstraints count]) {
        [self.view removeConstraints:self.advertisingAndContentLayoutConstraints];
    }
    
    self.advertisingAndContentLayoutConstraints = nil;
}

- (void)updateLayoutConstraintsForAdvertisingViewHidden:(BOOL)hidden expanded:(BOOL)expanded toTargetSize:(CGSize)targetSize
{
    // Reset all constraints
    [self disposeAdvertisingAndContentLayoutConstraints];
    
    // Create new constraints
    self.advertisingAndContentLayoutConstraints = [self layoutConstraintsForAdvertisingViewHidden:hidden expanded:expanded toTargetSize:targetSize];
    
    // Apply them
    [self.view addConstraints:self.advertisingAndContentLayoutConstraints];
}

- (CGSize)estimatedAdSize {
    CGSize adSize = CGSizeFromGADAdSize(self.bannerView.adSize);
    
    if (CGSizeEqualToSize(adSize, CGSizeZero)) {
        adSize = CGSizeFromGADAdSize(self.lastRequestedAdSize);
    }
    
    if (CGSizeEqualToSize(adSize, CGSizeZero)) {
        adSize = CGSizeFromGADAdSize(kGADAdSizeBanner);
    }
    
    return adSize;
}

- (NSArray *)advertisingViewLayoutConstraintsForAdvertisingViewHidden:(BOOL)hidden expanded:(BOOL)expanded toTargetSize:(CGSize)targetSize
{
    NSMutableArray *constraints = [NSMutableArray array];
    
    // Horizontal (adv view)
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.advertisingView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeRight multiplier:1.0f constant:0.0f]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.advertisingView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeft multiplier:1.0f constant:0.0f]];
    
    // Bottom hook (adv view)
    NSLayoutAttribute attribute = hidden ? NSLayoutAttributeTop : NSLayoutAttributeBottom;
    
    id referencedItem;
    NSLayoutAttribute referencedAttribute;
    if ([self respondsToSelector:@selector(bottomLayoutGuide)]) {
        referencedItem = [self bottomLayoutGuide];
        referencedAttribute = hidden ? NSLayoutAttributeBottom : NSLayoutAttributeTop;
    }
    else {
        referencedItem = self.view;
        referencedAttribute = NSLayoutAttributeBottom;
    }
    
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.advertisingView attribute:attribute relatedBy:NSLayoutRelationEqual toItem:referencedItem attribute:referencedAttribute multiplier:1.0f constant:0.0f]];
    
    
    // Height (adv view)
    if (expanded) {
        NSLayoutConstraint *superviewConstraint = [NSLayoutConstraint constraintWithItem:self.advertisingView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1.0f constant:0.0f];
        [constraints addObject:superviewConstraint];
        
        if (targetSize.height > 0.0f) {
            NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:self.advertisingView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0f constant:targetSize.height];
            constraint.priority = superviewConstraint.priority - 1;
            [constraints addObject:constraint];
        }
    }
    else {
        CGSize estimatedAdSize = [self estimatedAdSize];
        [constraints addObject:[NSLayoutConstraint constraintWithItem:self.advertisingView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0f constant:estimatedAdSize.height]];
    }
    
    return constraints;
}

- (NSArray *)contentViewLayoutConstraintsForAdvertisingViewHidden:(BOOL)hidden expanded:(BOOL)expanded toTargetSize:(CGSize)targetSize bottomHookedToAdvertisingView:(BOOL)bottomHookedToAdvertisingView
{
    NSMutableArray *constraints = [NSMutableArray array];
    
    // Horizontal (content view)
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.contentWrapperView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeRight multiplier:1.0f constant:0.0f]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.contentWrapperView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeft multiplier:1.0f constant:0.0f]];
    
    // Vertical (content view)
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.contentWrapperView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1.0f constant:0.0f]];
    
    // Bottom hook
    id referencedItem;
    NSLayoutAttribute referencedAttribute;
    
    if (expanded) {
        if (bottomHookedToAdvertisingView) {
            // Should not overlap with bottom bars
            if ([self respondsToSelector:@selector(bottomLayoutGuide)]) {
                referencedItem = [self bottomLayoutGuide];
                referencedAttribute = NSLayoutAttributeTop;
            }
            else {
                referencedItem = self.view;
                referencedAttribute = NSLayoutAttributeBottom;
            }
        }
        else {
            referencedItem = self.view;
            referencedAttribute = NSLayoutAttributeBottom;
        }
    }
    else {
        if (bottomHookedToAdvertisingView) {
            if (hidden) {
                // Advertising view may go under bottom layout guide
                if (NO && [self respondsToSelector:@selector(bottomLayoutGuide)]) {
                    referencedItem = [self bottomLayoutGuide];
                    referencedAttribute = NSLayoutAttributeTop;
                }
                else {
                    referencedItem = self.advertisingView;
                    referencedAttribute = NSLayoutAttributeTop;
                }
            }
            else {
                referencedItem = self.advertisingView;
                referencedAttribute = NSLayoutAttributeTop;
            }
        }
        else {
            referencedItem = self.view;
            referencedAttribute = NSLayoutAttributeBottom;
        }
    }
    
    [constraints addObject:[NSLayoutConstraint constraintWithItem:self.contentWrapperView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:referencedItem attribute:referencedAttribute multiplier:1.0f constant:0.0f]];
    
    return constraints;
}

- (BOOL)hasBottomTranslucentBar {
    if (self.tabBarController.tabBar &&
        self.tabBarController.tabBar.hidden == NO &&
        self.tabBarController.tabBar.isTranslucent)
    {
        return YES;
    }
    
    if (self.navigationController.toolbar &&
        self.navigationController.isToolbarHidden == NO &&
        self.navigationController.toolbar.isTranslucent)
    {
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldHookContentViewBottomToAdvertisingView {
    BOOL bottomHookedToAdvertisingView = NO;
    
    if ([self.contentViewController respondsToSelector:@selector(edgesForExtendedLayout)])
    {
        // iOS 7
        
        // Content layout not extended under bottom
        if ((self.contentViewController.edgesForExtendedLayout & UIRectEdgeBottom) != UIRectEdgeBottom)
        {
            bottomHookedToAdvertisingView = YES;
        }
        
        // Extends layout under bottom, excluding opaque bars (and advertising view
        // is an opaque bar). Maybe we have a bar under advertising view? Check
        // it out!
        else if (![self hasBottomTranslucentBar] && self.contentViewController.extendedLayoutIncludesOpaqueBars == NO)
        {
            bottomHookedToAdvertisingView = YES;
        }
    }
    else {
        // iOS 6
        bottomHookedToAdvertisingView = YES;
    }

    return bottomHookedToAdvertisingView;
}

#pragma mark - Private — Location Manager

- (void)startLocationManagerWithIntent:(MUKAdMobViewControllerGeolocationIntent)intent withTimeoutTimer:(BOOL)useTimeoutTimer
{
    self.geolocationIntent |= intent;
    [self.locationManager startUpdatingLocation];
    
    if (useTimeoutTimer) {
        [self startLocationManagerTimeoutTimer];
    }
}

- (void)stopLocationManager {
    self.geolocationIntent = MUKAdMobViewControllerGeolocationIntentNone;
    [self.locationManager stopUpdatingLocation];
    [self cancelLocationManagerTimeoutTimer];
    self.lastLocationManagerError = nil;
    self.lastLocationStoppedForTimeout = NO;
}

- (BOOL)locationManagerHasIntent:(MUKAdMobViewControllerGeolocationIntent)intent
{
    return (self.geolocationIntent & intent) == intent;
}

- (void)removeLocationManagerIntent:(MUKAdMobViewControllerGeolocationIntent)intent
{
    self.geolocationIntent &= ~intent;
}

- (void)startLocationManagerTimeoutTimer {
    [self cancelLocationManagerTimeoutTimer];
    
    self.locationManagerTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kLocationManagerTimeoutInterval target:self selector:@selector(locationManagerTimeoutTimerFired:) userInfo:nil repeats:NO];
}

- (void)cancelLocationManagerTimeoutTimer {
    if ([self.locationManagerTimeoutTimer isValid]) {
        [self.locationManagerTimeoutTimer invalidate];
        self.locationManagerTimeoutTimer = nil;
    }
}

- (void)locationManagerTimeoutTimerFired:(NSTimer *)timer {
    self.lastLocationManagerError = nil;
    self.lastLocationStoppedForTimeout = YES;
    
    // Request ad if needed
    [self requestNewBannerAdCheckingLocationManagerIntent];
    [self requestNewInterstitialAdCheckingLocationManagerIntent];
}

#pragma mark - Private — Banner Request

- (void)requestNewBannerAdCheckingLocationManagerIntent {
    if ([self locationManagerHasIntent:MUKAdMobViewControllerGeolocationIntentBanner])
    {
        [self removeLocationManagerIntent:MUKAdMobViewControllerGeolocationIntentBanner];
        [self requestNewBannerAd];
    }
}

#pragma mark - Private — Interstitial Ad

- (void)requestNewInterstitialAdCheckingLocationManagerIntent {
    if ([self locationManagerHasIntent:MUKAdMobViewControllerGeolocationIntentInterstitial])
    {
        [self removeLocationManagerIntent:MUKAdMobViewControllerGeolocationIntentInterstitial];
        [self requestNewInterstitialAd];
    }
}

#pragma mark - <GADBannerViewDelegate>

- (void)adViewDidReceiveAd:(GADBannerView *)view {
    // Insert in view hierarchy if needed
    if (self.bannerView.superview != self.advertisingView) {
        [self.advertisingView addSubview:self.bannerView];
    }
    
    self.bannerAdReceived = YES;
    [self toggleAdvertisingViewVisibilityAnimated:YES completion:nil];
    
    // Dispose expanded view
    [self disposeExpandedAdView];
}

- (void)adView:(GADBannerView *)view didFailToReceiveAdWithError:(GADRequestError *)error
{
    self.bannerAdReceived = NO;
    
    [self setAdvertisingViewHidden:YES animated:YES completion:^(BOOL finished)
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
        if (finished) {
            [self.bannerView removeFromSuperview];
        }
#pragma clang diagnostic pop
     }];
    
    // Dispose expanded view
    [self disposeExpandedAdView];
}

#pragma mark - <GADInterstitialDelegate>

- (void)interstitialDidReceiveAd:(GADInterstitial *)ad {
    self.interstitialAdReceivedDuringCurrentSession = YES;
    
    if ([self shouldPresentReceivedInterstitialAd:ad]) {
        [ad presentFromRootViewController:[self interstitialAdRootViewController]];
    }
}

#pragma mark - <CLLocationManagerDelegate>

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    if ([self isValidLocation:manager.location]) {
        // Get only one valid location
        [manager stopUpdatingLocation];
        
        [self cancelLocationManagerTimeoutTimer];
        self.lastLocationStoppedForTimeout = NO;
        
        // Request ad if needed
        if (self.isAdViewExpanded) {
            [self setAdvertisingViewExpanded:NO toSize:CGSizeZero animated:YES completion:^ (BOOL finished)
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                // Dispose expanded view
                [self disposeExpandedAdView];

                // Request new ad
                [self requestNewBannerAdCheckingLocationManagerIntent];
#pragma clang diagnostic pop
            }]; // setAdvertisingViewExpanded:toSize:animated:completion:
        }
        else {
            [self requestNewBannerAdCheckingLocationManagerIntent];
        } // if/else isAdViewExpanded
        
        [self requestNewInterstitialAdCheckingLocationManagerIntent];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    if ([self shouldStopGeolocationForError:error]) {
        // At kCLErrorLocationUnknown it keeps trying
        // Otherwise you should stop
        [manager stopUpdatingLocation];
        [self cancelLocationManagerTimeoutTimer];
        
        self.lastLocationManagerError = error;
        self.lastLocationStoppedForTimeout = NO;
        
        // Request ad if needed
        [self requestNewBannerAdCheckingLocationManagerIntent];
        [self requestNewInterstitialAdCheckingLocationManagerIntent];
    }
}

@end
