
#import "SwrveMessageController.h"
#import "SwrveMessageController+Private.h"
#import "SwrveButton.h"
#import "SwrveInAppCampaign.h"
#import "SwrveInAppMessageConfig.h"
#import "SwrveConversationCampaign.h"
#import "SwrveQAUser.h"
#if __has_include(<SwrveConversationSDK/SwrveConversationItemViewController.h>)
#import <SwrveConversationSDK/SwrveConversationItemViewController.h>
#else
#import "SwrveConversationItemViewController.h"
#endif
#import "Swrve+Private.h"

#if __has_include(<SwrveSDKCommon/SwrveLocalStorage.h>)
#import <SwrveSDKCommon/SwrveLocalStorage.h>
#import <SwrveSDKCommon/SwrveAssetsManager.h>
#import <SwrveSDKCommon/SwrveUtils.h>
#import <SwrveSDKCommon/SwrveQA.h>
#if TARGET_OS_IOS /** exclude tvOS **/
#import <SwrveSDKCommon/SwrvePermissions.h>
#endif //TARGET_OS_IOS
#else
#import "SwrveLocalStorage.h"
#import "SwrveAssetsManager.h"
#import "SwrveUtils.h"
#import "SwrveQA.h"
#if TARGET_OS_IOS /** exclude tvOS **/
#import "SwrvePermissions.h"
#endif //TARGET_OS_IOS
#endif
#import "SwrveCampaign+Private.h"

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

static NSArray* SUPPORTED_DEVICE_FILTERS;
static NSArray* SUPPORTED_STATIC_DEVICE_FILTERS;
static NSArray* ALL_SUPPORTED_DYNAMIC_DEVICE_FILTERS;

const static int DEFAULT_DELAY_FIRST_MESSAGE = 150;
const static int DEFAULT_MAX_SHOWS           = 99999;
const static int DEFAULT_MIN_DELAY           = 55;

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
@interface SwrvePush (SwrvePushInternalAccess)
- (void) registerForPushNotifications:(BOOL)provisional;
@end
#endif //!defined(SWRVE_NO_PUSH)

@interface Swrve(PrivateMethodsForMessageController)
@property BOOL campaignsAndResourcesInitialized;
@property (atomic) int locationSegmentVersion;
-(void) invalidateETag;
-(NSDate*) getNow;
@end

@interface Swrve (SwrveHelperMethods)
@property(atomic) SwrveRESTClient *restClient;
- (CGRect) deviceScreenBounds;
- (NSString*) signatureKey;
- (NSString *)userID;
@end

@interface SwrveCampaign(PrivateMethodsForMessageController)
-(void)messageWasShownToUser:(SwrveMessage*)message at:(NSDate*)timeShown;
@end

@interface SwrveMessageController()

@property (nonatomic, retain) SwrveAssetsManager*   assetsManager;
@property (nonatomic, retain) NSString*             user;
@property (nonatomic, retain) NSString*             apiKey;
@property (nonatomic, retain) NSArray*              campaigns; // List of campaigns available to the user.
@property (nonatomic, retain) NSMutableDictionary*  campaignsState; // Serializable state of the campaigns.
@property (nonatomic, retain) NSString*           	server;
@property (nonatomic, retain) SwrveSignatureProtectedFile* campaignFile;
@property (nonatomic, retain) NSString*             language; // ISO language code
@property (nonatomic, retain) NSFileManager*        manager;
@property (nonatomic, retain) NSMutableDictionary*  appStoreURLs;
@property (nonatomic, retain) NSMutableArray*       notifications;
@property (nonatomic, retain) NSString*             campaignsStateFilePath;
@property (nonatomic, retain) NSDate*               initialisedTime; // SDK init time
@property (nonatomic, retain) NSDate*               showMessagesAfterLaunch; // Only show messages after this time.
@property (nonatomic, retain) NSDate*               showMessagesAfterDelay; // Only show messages after this time.
#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS

@property (nonatomic)         bool                  pushEnabled; // Decide if push notification is enabled
@property (nonatomic, retain) NSSet*                provisionalPushNotificationEvents; // Events that trigger the provisional push permission request
@property (nonatomic, retain) NSSet*                pushNotificationEvents; // Events that trigger the push notification dialog
#endif //!defined(SWRVE_NO_PUSH)
@property (nonatomic)         bool                  autoShowMessagesEnabled;
@property (nonatomic, retain) UIWindow*             inAppMessageWindow;
@property (nonatomic, retain) UIWindow*             conversationWindow;
@property (nonatomic)         SwrveActionType       inAppMessageActionType;
@property (nonatomic, retain) NSString*             inAppMessageAction;
@property (nonatomic, retain) NSString*             inAppMessagePersonalisedAction;
@property (nonatomic, retain) NSString*             inAppButtonPressedName;
@property (nonatomic)         bool                  prefersIAMStatusBarHidden;
@property (nonatomic)         bool                  prefersConversationsStatusBarHidden;

// Current Device Properties
@property (nonatomic) int device_width;
@property (nonatomic) int device_height;
@property (nonatomic) SwrveInterfaceOrientation orientation;

// Only ever show this many messages. This number is decremented each time a message is shown.
@property (atomic) long messagesLeftToShow;
@property (atomic) NSTimeInterval minDelayBetweenMessage;

@property (nonatomic) SwrveQAUser* qaUser;

@end

@implementation SwrveMessageController

@synthesize server, apiKey;
@synthesize campaignFile;
@synthesize manager;
@synthesize campaignsStateFilePath;
@synthesize initialisedTime;
@synthesize showMessagesAfterLaunch;
@synthesize showMessagesAfterDelay;
@synthesize messagesLeftToShow;
@synthesize inAppMessageConfig;
@synthesize campaigns;
@synthesize campaignsState;
@synthesize assetsManager;
@synthesize user;
@synthesize notifications;
@synthesize language;
@synthesize appStoreURLs;
#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
@synthesize pushEnabled;
@synthesize provisionalPushNotificationEvents;
@synthesize pushNotificationEvents;
#endif //!defined(SWRVE_NO_PUSH)
@synthesize inAppMessageWindow;
@synthesize conversationWindow;
@synthesize inAppMessageActionType;
@synthesize inAppMessageAction;
@synthesize inAppMessagePersonalisedAction;
@synthesize inAppButtonPressedName;
@synthesize device_width;
@synthesize device_height;
@synthesize orientation;
@synthesize qaUser;
@synthesize autoShowMessagesEnabled;
@synthesize analyticsSDK;
@synthesize minDelayBetweenMessage;
@synthesize showMessageDelegate;
@synthesize customButtonCallback;
@synthesize dismissButtonCallback;
@synthesize installButtonCallback;
@synthesize clipboardButtonCallback;
@synthesize showMessageTransition;
@synthesize hideMessageTransition;
@synthesize swrveConversationItemViewController;
@synthesize prefersIAMStatusBarHidden;
@synthesize prefersConversationsStatusBarHidden;
@synthesize conversationsMessageQueue;

+ (void)initialize {

#if TARGET_OS_IOS /** exclude tvOS **/
    ALL_SUPPORTED_DYNAMIC_DEVICE_FILTERS = [NSArray arrayWithObjects:
        [[swrve_permission_location_always stringByAppendingString:swrve_permission_requestable] lowercaseString],
        [[swrve_permission_location_when_in_use stringByAppendingString:swrve_permission_requestable] lowercaseString],
        [[swrve_permission_photos stringByAppendingString:swrve_permission_requestable] lowercaseString],
        [[swrve_permission_camera stringByAppendingString:swrve_permission_requestable] lowercaseString],
        [[swrve_permission_contacts stringByAppendingString:swrve_permission_requestable] lowercaseString],
        [[swrve_permission_push_notifications stringByAppendingString:swrve_permission_requestable] lowercaseString], nil];
    SUPPORTED_STATIC_DEVICE_FILTERS = [NSArray arrayWithObjects:@"ios", nil];
    SUPPORTED_DEVICE_FILTERS = [NSMutableArray arrayWithArray:SUPPORTED_STATIC_DEVICE_FILTERS];
    [(NSMutableArray*)SUPPORTED_DEVICE_FILTERS addObjectsFromArray:ALL_SUPPORTED_DYNAMIC_DEVICE_FILTERS];
#endif //TARGET_OS_IOS
}

- (id)initWithSwrve:(Swrve*)sdk
{
    self = [super init];

    if (sdk == nil) {
        return self;
    }
    NSString *cacheFolder = [SwrveLocalStorage swrveCacheFolder];
    self.assetsManager = [[SwrveAssetsManager alloc] initWithRestClient:sdk.restClient andCacheFolder:cacheFolder];
    self.campaignsStateFilePath = [SwrveLocalStorage campaignsStateFilePathForUserId:[sdk userID]];

    CGRect screen_bounds =  [SwrveUtils deviceScreenBounds];
    self.device_height = (int)screen_bounds.size.height;
    self.device_width  = (int)screen_bounds.size.width;
    self.orientation   = sdk.config.orientation;
    self.prefersIAMStatusBarHidden = sdk.config.prefersIAMStatusBarHidden;
    self.prefersConversationsStatusBarHidden = sdk.config.prefersConversationsStatusBarHidden;
    self.language           = sdk.config.language;
    self.user               = [sdk userID];
    self.apiKey             = sdk.apiKey;
    self.server             = sdk.config.contentServer;
    self.analyticsSDK       = sdk;
#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
    self.pushEnabled        = sdk.config.pushEnabled;
    self.provisionalPushNotificationEvents = sdk.config.provisionalPushNotificationEvents;
    self.pushNotificationEvents = sdk.config.pushNotificationEvents;
#endif //!defined(SWRVE_NO_PUSH)
    self.appStoreURLs       = [[NSMutableDictionary alloc] init];
    
    self.inAppMessageConfig = sdk.config.inAppMessageConfig;
    
    if (self.inAppMessageConfig.backgroundColor == nil) {
        // current workaround since this isn't a major version
        self.inAppMessageConfig.backgroundColor = sdk.config.inAppMessageBackgroundColor;
    }
    
    self.manager            = [NSFileManager defaultManager];
    self.notifications      = [[NSMutableArray alloc] init];
    self.autoShowMessagesEnabled = YES;

    // Game rule defaults
    self.initialisedTime = [sdk getNow];
    self.showMessagesAfterLaunch  = [sdk getNow];
    self.messagesLeftToShow = LONG_MAX;

    DebugLog(@"Swrve Messaging System initialised: Server: %@ Game: %@",
             self.server,
             self.apiKey);

    NSAssert1([self.language length] > 0, @"Invalid language specified %@", self.language);
    NSAssert1([self.user     length] > 0, @"Invalid username specified %@", self.user);
    NSAssert(self.analyticsSDK != NULL,   @"Swrve Analytics SDK is null", nil);

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
    NSData* device_token = [SwrveLocalStorage deviceToken];
    if (self.pushEnabled && device_token) {
        // Once we have a device token, ask for it every time as it may change under certain circumstances
        [SwrvePermissions refreshDeviceToken:(id<SwrveCommonDelegate>)analyticsSDK];
    }
#endif //!defined(SWRVE_NO_PUSH)

    self.campaignsState = [[NSMutableDictionary alloc] init];
    // Initialize campaign cache file
    [self initCampaignsFromCacheFile];

    self.showMessageTransition = [CATransition animation];
    self.showMessageTransition.type = kCATransitionPush;
    self.showMessageTransition.subtype = kCATransitionFromBottom;
    self.showMessageTransition.duration = 0.25;
    self.showMessageTransition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    self.showMessageTransition.removedOnCompletion = YES;

    self.hideMessageTransition = [CATransition animation];
    self.hideMessageTransition.type = kCATransitionPush;
    self.hideMessageTransition.subtype = kCATransitionFromTop;
    self.hideMessageTransition.duration = 0.25;
    self.hideMessageTransition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    self.hideMessageTransition.removedOnCompletion = YES;
    self.hideMessageTransition.delegate = self;
    self.conversationsMessageQueue = [NSMutableArray new];

    return self;
}

- (void)campaignsStateFromDisk:(NSMutableDictionary*)states
{
    NSData* data = [NSData dataWithContentsOfFile:self.campaignsStateFilePath];
    if(!data)
    {
        DebugLog(@"No campaigns states loaded. [Reading from %@]", self.campaignsStateFilePath);
        return;
    }

    NSError* error = NULL;
    NSArray* loadedStates = [NSPropertyListSerialization propertyListWithData:data
                                                                        options:NSPropertyListImmutable
                                                                         format:NULL
                                                                          error:&error];
    if (error) {
        DebugLog(@"Could not load campaign states from disk.\nError: %@\njson: %@", error, data);
    } else {
        @synchronized (states) {
            for (NSDictionary* dicState in loadedStates)
            {
                SwrveCampaignState* state = [[SwrveCampaignState alloc] initWithJSON:dicState];
                NSString* stateKey = [NSString stringWithFormat:@"%lu", (unsigned long)state.campaignID];
                [states setValue:state forKey:stateKey];
            }
        }
    }
}

- (void)campaignsStateFromDefaults:(NSMutableDictionary*)states {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:self.campaignsStateFilePath.lastPathComponent];
    if(!data)
    {
        DebugLog(@"No campaigns states loaded. [Reading from defaults %@]", self.campaignsStateFilePath.lastPathComponent);
        return;
    }

    NSError* error = NULL;
    NSArray* loadedStates = [NSPropertyListSerialization propertyListWithData:data
                                                                      options:NSPropertyListImmutable
                                                                       format:NULL
                                                                        error:&error];
    if (error) {
        DebugLog(@"Could not load campaign states from disk.\nError: %@\njson: %@", error, data);
    } else {
        @synchronized (states) {
            for (NSDictionary* dicState in loadedStates)
            {
                SwrveCampaignState* state = [[SwrveCampaignState alloc] initWithJSON:dicState];
                NSString* stateKey = [NSString stringWithFormat:@"%lu", (unsigned long)state.campaignID];
                [states setValue:state forKey:stateKey];
            }
        }
    }
}

- (void)saveCampaignsState {
#if TARGET_OS_IOS
    [self saveCampaignsStateToFile];
#else
    [self saveCampaignsStateToDefaults];
#endif
}

- (void)saveCampaignsStateToFile{
    NSMutableArray* newStates;
    @synchronized (self.campaignsState) {
        newStates = [[NSMutableArray alloc] initWithCapacity:self.campaignsState.count];
        [self.campaignsState enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop)
        {
    #pragma unused(key, stop)
            [newStates addObject:[value asDictionary]];
        }];
    }

    NSError*  error = NULL;
    NSData*   data = [NSPropertyListSerialization dataWithPropertyList:newStates
                                                                format:NSPropertyListXMLFormat_v1_0
                                                               options:0
                                                                 error:&error];

    if (error) {
        DebugLog(@"Could not serialize campaign states.\nError: %@\njson: %@", error, newStates);
    } else if(data)
    {
        BOOL success = [data writeToFile:self.campaignsStateFilePath atomically:YES];
        if (!success)
        {
            DebugLog(@"Error saving campaigns state to: %@", self.campaignsStateFilePath);
        }
    }
    else
    {
        DebugLog(@"Error saving campaigns state: %@ writing to %@", error, self.campaignsStateFilePath);
    }
}

- (void)saveCampaignsStateToDefaults
{
    NSMutableArray* newStates;
    @synchronized (self.campaignsState) {
        newStates = [[NSMutableArray alloc] initWithCapacity:self.campaignsState.count];
        [self.campaignsState enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop)
         {
#pragma unused(key, stop)
             [newStates addObject:[value asDictionary]];
         }];
    }

    NSError*  error = NULL;
    NSData*   data = [NSPropertyListSerialization dataWithPropertyList:newStates
                                                                format:NSPropertyListXMLFormat_v1_0
                                                               options:0
                                                                 error:&error];

    if (error) {
        DebugLog(@"Could not serialize campaign states.\nError: %@\njson: %@", error, newStates);
    } else if(data && self.campaignsStateFilePath.lastPathComponent != nil) {
        [[NSUserDefaults standardUserDefaults] setValue:data forKey:self.campaignsStateFilePath.lastPathComponent];
    } else {
        DebugLog(@"Error saving campaigns state: %@ writing to %@", error, self.campaignsStateFilePath);
    }
}


- (void) initCampaignsFromCacheFile
{
    // Create campaign cache folder
    NSString *cacheFolder = [assetsManager cacheFolder];
    NSError* error;
    if (![manager createDirectoryAtPath:cacheFolder
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error])
    {
        DebugLog(@"Error creating %@: %@", cacheFolder, error);
    }
    // Create signature protected cache file
    campaignFile =  [[SwrveSignatureProtectedFile alloc] protectedFileType:SWRVE_CAMPAIGN_FILE
                                                                    userID:self.user
                                                              signatureKey:[self.analyticsSDK signatureKey]
                                                             errorDelegate:nil];
#if TARGET_OS_IOS
    // Read from cache the state of campaigns
    [self campaignsStateFromDisk:self.campaignsState];
#else
    [self campaignsStateFromDefaults:self.campaignsState];
#endif
    // Read content of campaigns file and update campaigns
    NSData* content = [campaignFile readWithRespectToPlatform];

    if (content != nil) {
        NSError* jsonError;
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:content options:0 error:&jsonError];
        if (!jsonError) {
            [self updateCampaigns:jsonDict];
        }
    } else {
        [self.analyticsSDK invalidateETag];
    }
}

static NSNumber* numberFromJsonWithDefault(NSDictionary* json, NSString* key, int defaultValue)
{
    NSNumber* result = [json objectForKey:key];
    if (result == nil) {
        result = [NSNumber numberWithInt:defaultValue];
    }
    return result;
}

-(void) writeToCampaignCache:(NSData*)campaignData {
    [self.campaignFile writeWithRespectToPlatform:campaignData];
}

-(BOOL) canSupportDeviceFilter:(NSString*)filter {
    // Used to check all global filters this SDK supports
    return [SUPPORTED_DEVICE_FILTERS containsObject:[filter lowercaseString]];
}

-(NSString*) supportsDeviceFilters:(NSArray*)filters {
    // Update device filters to the current status
    NSArray* currentFilters = [self currentlySupportedDeviceFilters];

    // Used to check the current enabled filters
    if (filters != nil) {
        for (NSString* filter in filters) {
            NSString* lowercaseFilter = [filter lowercaseString];
            if (![currentFilters containsObject:lowercaseFilter]) {
                return lowercaseFilter;
            }
        }
    }
    return nil;
}

- (BOOL)filtersOk:(NSArray *) filters {
    // Check device filters (permission requests, platform)
    if (filters != nil) {
        for (NSString *filter in filters) {
            if (![self canSupportDeviceFilter:filter]) {
                return false;
            }
        }
    }
    return true;
}

-(NSArray*)currentlySupportedDeviceFilters {
    NSMutableArray* supported = [NSMutableArray arrayWithArray:SUPPORTED_STATIC_DEVICE_FILTERS];
#if TARGET_OS_IOS /** exclude tvOS **/
    NSArray* currentPermissionFilters = [SwrvePermissions currentPermissionFilters];
    [supported addObjectsFromArray:currentPermissionFilters];
#endif
    return supported;
}
-(void) updateCampaigns:(NSDictionary*)campaignJson
{
    if (campaignJson == nil) {
        DebugLog(@"Error parsing campaign JSON", nil);
        return;
    }

    if ([campaignJson count] == 0) {
        DebugLog(@"Campaign JSON empty, no campaigns downloaded", nil);
        self.campaigns = [[NSArray alloc] init];
        return;
    }

    NSMutableSet* assetsQueue = [[NSMutableSet alloc] init];
    NSMutableArray* result    = [[NSMutableArray alloc] init];

    // Version check
    NSNumber* version = [campaignJson objectForKey:@"version"];
    if ([version integerValue] != CAMPAIGN_RESPONSE_VERSION){
        DebugLog(@"Campaign JSON has the wrong version. No campaigns loaded.", nil);
        return;
    }

    [self updateCdnPaths:campaignJson];

    // Game Data
    NSDictionary* gameData = [campaignJson objectForKey:@"game_data"];
    if (gameData){
        for (NSString* game  in gameData) {
            NSString* url = [(NSDictionary*)[gameData objectForKey:game] objectForKey:@"app_store_url"];
            [self.appStoreURLs setValue:url forKey:game];
            DebugLog(@"App Store link %@: %@", game, url);
        }
    }

    NSDictionary* rules = [campaignJson objectForKey:@"rules"];
    {
        NSNumber* delay    = numberFromJsonWithDefault(rules, @"delay_first_message", DEFAULT_DELAY_FIRST_MESSAGE);
        NSNumber* maxShows = numberFromJsonWithDefault(rules, @"max_messages_per_session", DEFAULT_MAX_SHOWS);
        NSNumber* minDelay = numberFromJsonWithDefault(rules, @"min_delay_between_messages", DEFAULT_MIN_DELAY);

        self.showMessagesAfterLaunch  = [self.initialisedTime dateByAddingTimeInterval:delay.doubleValue];
        self.minDelayBetweenMessage = minDelay.doubleValue;
        self.messagesLeftToShow = maxShows.longValue;

        DebugLog(@"Game rules OK: Delay Seconds: %@ Max shows: %@ ", delay, maxShows);
        DebugLog(@"Time is %@ show messages after %@", [self.analyticsSDK getNow], [self showMessagesAfterLaunch]);
    }

    // QA
    NSMutableDictionary* campaignsDownloaded = nil;

    BOOL wasPreviouslyQAUser = (self.qaUser != nil);
    NSDictionary* jsonQa = [campaignJson objectForKey:@"qa"];
    if(jsonQa) {
        DebugLog(@"You are a QA user!", nil);
        campaignsDownloaded = [[NSMutableDictionary alloc] init];
        self.qaUser = [[SwrveQAUser alloc] initWithJSON:jsonQa withAnalyticsSDK:self.analyticsSDK];
        //Location QA setup
        [SwrveQA updateQAUser:jsonQa];

        NSArray* json_qa_campaigns = [jsonQa objectForKey:@"campaigns"];
        if(json_qa_campaigns) {
            for (NSDictionary* json_qa_campaign in json_qa_campaigns) {
                NSNumber* campaign_id = [json_qa_campaign objectForKey:@"id"];
                NSString* campaign_reason = [json_qa_campaign objectForKey:@"reason"];

                DebugLog(@"Campaign %@ not downloaded because: %@", campaign_id, campaign_reason);

                // Add campaign for QA purposes
                [campaignsDownloaded setValue:campaign_reason forKey:[campaign_id stringValue]];
            }
        }

        // Process any remote notifications
        for (NSDictionary* notification in self.notifications) {
            [self.qaUser pushNotification:notification];
        }
    } else {
        self.qaUser = nil;
    }

    // Empty saved push notifications
    [self.notifications removeAllObjects];

    NSArray* jsonCampaigns = [campaignJson objectForKey:@"campaigns"];
    for (NSDictionary* dict in jsonCampaigns)
    {
        BOOL conversationCampaign = ([dict objectForKey:@"conversation"] != nil);
        SwrveCampaign* campaign = nil;
        if (conversationCampaign) {
            // Check device filters (permission requests, platform)
            NSArray* filters = [dict objectForKey:@"filters"];
            BOOL passesAllFilters = TRUE;
            NSString* lastCheckedFilter = nil;
            if (filters != nil) {
                for (NSString* filter in filters) {
                    lastCheckedFilter = filter;
                    if (![self canSupportDeviceFilter:filter]) {
                        passesAllFilters = NO;
                        break;
                    }
                }
            }

            if (passesAllFilters) {
                // Conversation version check
                NSNumber* conversationVersion = [dict objectForKey:@"conversation_version"];
                if (conversationVersion == nil || [conversationVersion integerValue] <= CONVERSATION_VERSION) {
                    campaign = [[SwrveConversationCampaign alloc] initAtTime:self.initialisedTime fromDictionary:dict withAssetsQueue:assetsQueue forController:self];
                } else {
                    DebugLog(@"Conversation version %@ cannot be loaded with this SDK.", conversationVersion);
                }
            } else {
                DebugLog(@"Not all requirements were satisfied for this campaign: %@", lastCheckedFilter);
            }
        } else {
            campaign = [[SwrveInAppCampaign alloc] initAtTime:self.initialisedTime fromDictionary:dict withAssetsQueue:assetsQueue forController:self];
        }

        if (campaign != nil) {
            @synchronized (self.campaignsState) {
                NSString* campaignIDStr = [NSString stringWithFormat:@"%lu", (unsigned long)campaign.ID];
                DebugLog(@"Got campaign with id %@", campaignIDStr);
                if(!(!wasPreviouslyQAUser && self.qaUser != nil && self.qaUser.resetDevice)) {
                    SwrveCampaignState* campaignState = [self.campaignsState objectForKey:campaignIDStr];
                    if(campaignState) {
                        [campaign setState:campaignState];
                    }
                }
                [self.campaignsState setValue:campaign.state forKey:campaignIDStr];
            }
            [result addObject:campaign];

            if(self.qaUser) {
                // Add campaign for QA purposes
                [campaignsDownloaded setValue:@"" forKey:[NSString stringWithFormat:@"%ld", (long)campaign.ID]];
            }
        }
    }

    // QA logging
    if (self.qaUser != nil) {
        [self.qaUser talkSession:campaignsDownloaded];
    }

    // Obtain assets we don't have yet
    [assetsManager downloadAssets:assetsQueue withCompletionHandler:^ {
        [self autoShowMessages];
    }];

    self.campaigns = [result copy];
}

-(void) updateCdnPaths:(NSDictionary*)campaignJson {
    NSDictionary *cdnPaths = [campaignJson objectForKey:@"cdn_paths"];
    if (cdnPaths) {
        NSString *cdnImages = [cdnPaths objectForKey:@"message_images"];
        [assetsManager setCdnImages:cdnImages];
        NSString *cdnFonts = [cdnPaths objectForKey:@"message_fonts"];
        [assetsManager setCdnFonts:cdnFonts];
        DebugLog(@"CDN URL images: %@ fonts:%@", cdnImages, cdnFonts);
    } else {
        NSString *cdnRoot = [campaignJson objectForKey:@"cdn_root"];
        [assetsManager setCdnImages:cdnRoot];
        DebugLog(@"CDN URL: %@", cdnRoot);
    }
}

-(void) appDidBecomeActive {
    // Obtain all assets required for the available campaigns
    NSMutableSet* assetsQ = [[NSMutableSet alloc] init];
    for (SwrveCampaign *campaign in self.campaigns) {
        if ([campaign isKindOfClass:[SwrveInAppCampaign class]]) {
            SwrveInAppCampaign *swrveCampaign = (SwrveInAppCampaign *) campaign;
            [swrveCampaign addAssetsToQueue:assetsQ];
        } else if ([campaign isKindOfClass:[SwrveConversationCampaign class]]) {
            SwrveConversationCampaign *swrveConversationCampaign = (SwrveConversationCampaign *) campaign;
            [swrveConversationCampaign addAssetsToQueue:assetsQ];
        }
    }

    // Obtain assets we don't have yet
    [assetsManager downloadAssets:assetsQ withCompletionHandler:^{
        [self autoShowMessages];
    }];
}

-(void)autoShowMessages {

    // Don't do anything if we've already shown a message or if it is too long after session start
    if (![self autoShowMessagesEnabled]) {
        return;
    }

    // Only execute if at least 1 call to the /user_content api endpoint has been completed
    if (![self.analyticsSDK campaignsAndResourcesInitialized]) {
        return;
    }

    for (SwrveCampaign* campaign in self.campaigns) {
        if ([campaign isKindOfClass:[SwrveInAppCampaign class]]) {
            SwrveInAppCampaign* specificCampaign = (SwrveInAppCampaign*)campaign;
            if ([specificCampaign hasMessageForEvent:AUTOSHOW_AT_SESSION_START_TRIGGER withPayload:nil]) {
                @synchronized(self) {
                    if ([self autoShowMessagesEnabled]) {
                        NSDictionary* event = @{@"type": @"event", @"name": AUTOSHOW_AT_SESSION_START_TRIGGER};
                        if ([self eventRaised:event]) {
                            // If a message was shown we want to disable autoshow
                            [self setAutoShowMessagesEnabled:NO];
                        }
                    }
                }
                break;
            }
        } else if ([campaign isKindOfClass:[SwrveConversationCampaign class]]) {
            SwrveConversationCampaign* specificCampaign = (SwrveConversationCampaign*)campaign;
            if ([specificCampaign hasConversationForEvent:AUTOSHOW_AT_SESSION_START_TRIGGER withPayload:nil]) {
                @synchronized(self) {
                    if ([self autoShowMessagesEnabled]) {
                        NSDictionary* event = @{@"type": @"event", @"name": AUTOSHOW_AT_SESSION_START_TRIGGER};
                        if ([self eventRaised:event]) {
                            // If a conversation was shown we want to disable autoshow
                            [self setAutoShowMessagesEnabled:NO];
                        }
                    }
                }
                break;
            }
        }
    }
}

-(BOOL)isTooSoonToShowMessageAfterLaunch:(NSDate*)now
{
    return [now compare:[self showMessagesAfterLaunch]] == NSOrderedAscending;
}

-(BOOL)isTooSoonToShowMessageAfterDelay:(NSDate*)now
{
    return [now compare:[self showMessagesAfterDelay]] == NSOrderedAscending;
}

-(BOOL)hasShowTooManyMessagesAlready
{
    return self.messagesLeftToShow <= 0;
}

-(BOOL)checkGlobalRules:(NSString *)event {
    NSDate* now = [self.analyticsSDK getNow];
    if ([self.campaigns count] == 0)
    {
        [self noMessagesWereShown:event withReason:@"No campaigns available"];
        return FALSE;
    }

    // Ignore delay after launch throttle limit for auto show messages
    if ([event caseInsensitiveCompare:AUTOSHOW_AT_SESSION_START_TRIGGER] != NSOrderedSame && [self isTooSoonToShowMessageAfterLaunch:now])
    {
        [self noMessagesWereShown:event withReason:[NSString stringWithFormat:@"{App throttle limit} Too soon after launch. Wait until %@", [[self class] formattedTime:self.showMessagesAfterLaunch]]];
        return FALSE;
    }

    if ([self isTooSoonToShowMessageAfterDelay:now])
    {
        [self noMessagesWereShown:event withReason:[NSString stringWithFormat:@"{App throttle limit} Too soon after last message. Wait until %@", [[self class] formattedTime:self.showMessagesAfterDelay]]];
        return FALSE;
    }

    if ([self hasShowTooManyMessagesAlready])
    {
        [self noMessagesWereShown:event withReason:@"{App throttle limit} Too many messages shown"];
        return FALSE;
    }
    return TRUE;
}

- (SwrveMessage*)messageForEvent:(NSString*) eventName withPayload:(NSDictionary *)payload
{
    if (analyticsSDK == nil) {
        return nil;
    }

    NSDate* now = [self.analyticsSDK getNow];
    SwrveMessage* result = nil;
    SwrveCampaign* campaign = nil;

    if (self.campaigns != nil) {
        if (![self checkGlobalRules:eventName]) {
            return nil;
        }

        NSMutableDictionary* campaignReasons = nil;
        NSMutableDictionary* campaignMessages = nil;
        if (self.qaUser != nil) {
            campaignReasons = [[NSMutableDictionary alloc] init];
            campaignMessages = [[NSMutableDictionary alloc] init];
        }

        NSMutableArray* availableMessages = [[NSMutableArray alloc] init];
        // Select messages with higher priority that have the current orientation
        NSNumber* minPriority = [NSNumber numberWithInteger:INT_MAX];
        NSMutableArray* candidateMessages = [[NSMutableArray alloc] init];
        for (SwrveCampaign* baseCampaignIt in self.campaigns)
        {
            if ([baseCampaignIt isKindOfClass:[SwrveInAppCampaign class]]) {
                SwrveInAppCampaign* campaignIt = (SwrveInAppCampaign*)baseCampaignIt;
                NSSet* assetsOnDisk = [assetsManager assetsOnDisk];
                SwrveMessage* nextMessage = [campaignIt messageForEvent:eventName withPayload:payload withAssets:assetsOnDisk atTime:now withReasons:campaignReasons];
                if (nextMessage != nil) {
                    // Add to list of returned messages
                    [availableMessages addObject:nextMessage];
                    // Check if it is a candidate to be shown
                    long nextMessagePriorityLong = [nextMessage.priority longValue];
                    long minPriorityLong = [minPriority longValue];
                    if (nextMessagePriorityLong <= minPriorityLong) {
                        if (nextMessagePriorityLong < minPriorityLong) {
                            // If it is lower than any of the previous ones
                            // remove those from being candidates
                            [candidateMessages removeAllObjects];
                        }
                        minPriority = nextMessage.priority;
                        [candidateMessages addObject:nextMessage];
                    }
                }
            }
        }

        NSArray* shuffledCandidates = [SwrveMessageController shuffled:candidateMessages];
        if ([shuffledCandidates count] > 0) {
            result = [shuffledCandidates objectAtIndex:0];
            campaign = result.campaign;
        }

        if (self.qaUser != nil && campaign != nil && result != nil) {
            // A message was chosen, set the reason for the others
            for (SwrveMessage* otherMessage in availableMessages)
            {
                if (result != otherMessage)
                {
                    SwrveCampaign* c = otherMessage.campaign;
                    if (c != nil)
                    {
                        NSString* campaignIdString = [[NSNumber numberWithUnsignedInteger:c.ID] stringValue];
                        [campaignMessages setValue:otherMessage.messageID forKey:campaignIdString];
                        [campaignReasons setValue:[NSString stringWithFormat:@"Campaign %ld was selected for display ahead of this campaign", (long)campaign.ID] forKey:campaignIdString];
                    }
                }
            }
        }

        // If QA enabled, send message selection information
        if(self.qaUser != nil) {
            [self.qaUser trigger:eventName withMessage:result withReason:campaignReasons withMessages:campaignMessages];
        }
    }

    if (result == nil) {
        DebugLog(@"Not showing message: no candidate messages for %@", eventName);
    } else {
        // Notify message has been returned
        NSDictionary *returningPayload = [NSDictionary dictionaryWithObjectsAndKeys:[result.messageID stringValue], @"id", nil];
        NSString *returningEventName = @"Swrve.Messages.message_returned";
        [self.analyticsSDK eventInternal:returningEventName payload:returningPayload triggerCallback:false];
    }
    return result;
}

-(SwrveMessage*)messageForEvent:(NSString *)event
{
    // By default does a simple by name look up.
    return [self messageForEvent:event withPayload:nil];
}

- (SwrveConversation*)conversationForEvent:(NSString*) eventName withPayload:(NSDictionary *)payload {

    if (analyticsSDK == nil) {
        return nil;
    }

    NSDate* now = [self.analyticsSDK getNow];
    SwrveConversation* result = nil;
    SwrveConversationCampaign* campaign = nil;

    if (self.campaigns != nil) {
        if (![self checkGlobalRules:eventName])
        {
            return nil;
        }

        NSMutableDictionary* campaignReasons = nil;
        NSMutableDictionary* campaignMessages = nil;
        if (self.qaUser != nil) {
            campaignReasons = [[NSMutableDictionary alloc] init];
            campaignMessages = [[NSMutableDictionary alloc] init];
        }

        NSMutableArray* availableConversations = [[NSMutableArray alloc] init];
        // Select conversations with higher priority
        NSNumber* minPriority = [NSNumber numberWithInteger:INT_MAX];
        NSMutableArray* candidateConversations = [[NSMutableArray alloc] init];
        for (SwrveCampaign* baseCampaignIt in self.campaigns)
        {
            if ([baseCampaignIt isKindOfClass:[SwrveConversationCampaign class]]) {
                SwrveConversationCampaign* campaignIt = (SwrveConversationCampaign*)baseCampaignIt;
                NSSet* assetsOnDisk = [assetsManager assetsOnDisk];
                SwrveConversation* nextConversation = [campaignIt conversationForEvent:eventName withPayload:payload withAssets:assetsOnDisk atTime:now withReasons:campaignReasons];
                if (nextConversation != nil) {
                    [availableConversations addObject:nextConversation];
                    // Check if it is a candidate to be shown
                    long nextMessagePriorityLong = [nextConversation.priority longValue];
                    long minPriorityLong = [minPriority longValue];
                    if (nextMessagePriorityLong <= minPriorityLong) {
                        if (nextMessagePriorityLong < minPriorityLong) {
                            // If it is lower than any of the previous ones
                            // remove those from being candidates
                            [candidateConversations removeAllObjects];
                        }
                        minPriority = nextConversation.priority;
                        [candidateConversations addObject:nextConversation];
                    }
                }
            }
        }

        NSArray* shuffledCandidates = [SwrveMessageController shuffled:candidateConversations];
        if ([shuffledCandidates count] > 0) {
            result = [shuffledCandidates objectAtIndex:0];
            campaign = result.campaign;
        }

        if (self.qaUser != nil && campaign != nil && result != nil) {
            // A message was chosen, set the reason for the others
            for (SwrveConversation* otherConversation in availableConversations)
            {
                if (result != otherConversation)
                {
                    SwrveConversationCampaign* c = otherConversation.campaign;
                    if (c != nil)
                    {
                        NSString* campaignIdString = [[NSNumber numberWithUnsignedInteger:c.ID] stringValue];
                        [campaignMessages setValue:otherConversation.conversationID forKey:campaignIdString];
                        [campaignReasons setValue:[NSString stringWithFormat:@"Campaign %ld was selected for display ahead of this campaign", (long)campaign.ID] forKey:campaignIdString];
                    }
                }
            }
        }

        // If QA enabled, send message selection information
        if(self.qaUser != nil) {
            [self.qaUser trigger:eventName withConversation:result withReason:campaignReasons];
        }
    }

    if (result == nil) {
        DebugLog(@"Not showing conversation: no candidate conversations for %@", eventName);
    }
    return result;
}

-(SwrveConversation*)conversationForEvent:(NSString *)event {

    return [self conversationForEvent:event withPayload:nil];
}

-(void)noMessagesWereShown:(NSString*)event withReason:(NSString*)reason
{
    DebugLog(@"Not showing message for %@: %@", event, reason);
    if (self.qaUser != nil) {
        [self.qaUser triggerFailure:event withReason:reason];
    }
}

+(NSString*)formattedTime:(NSDate*)date
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSLocale *enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    [dateFormatter setLocale:enUSPOSIXLocale];
    [dateFormatter setDateFormat:@"HH:mm:ss Z"];

    return [dateFormatter stringFromDate:date];
}

+(NSArray*)shuffled:(NSArray*)source;
{
    unsigned long count = [source count];

    // Early out if there is 0 or 1 elements.
    if (count < 2)
    {
        return source;
    }

    // Copy
    NSMutableArray* result = [NSMutableArray arrayWithArray:source];

    for (unsigned long i = 0; i < count; i++)
    {
        unsigned long remain = count - i;
        unsigned long n = (arc4random() % remain) + i;
        [result exchangeObjectAtIndex:i withObjectAtIndex:n];
    }

    return result;
}

-(void)setMessageMinDelayThrottle
{
    NSDate* now = [self.analyticsSDK getNow];
    [self setShowMessagesAfterDelay:[now dateByAddingTimeInterval:[self minDelayBetweenMessage]]];
}

-(void)messageWasShownToUser:(SwrveMessage*)message
{
    NSDate* now = [self.analyticsSDK getNow];
    // The message was shown. Take the current time so that we can throttle messages
    // from being shown too quickly.
    [self setMessageMinDelayThrottle];
    [self setMessagesLeftToShow:self.messagesLeftToShow - 1];

    SwrveCampaign* c = message.campaign;
    if (c != nil) {
        [c messageWasShownToUser:message at:now];
    }
    [self saveCampaignsState];

    NSString* viewEvent = [NSString stringWithFormat:@"Swrve.Messages.Message-%d.impression", [message.messageID intValue]];
    DebugLog(@"Sending view event: %@", viewEvent);

    [self.analyticsSDK eventInternal:viewEvent payload:nil triggerCallback:false];
}

-(void)conversationWasShownToUser:(SwrveConversation*)conversation
{
    NSDate* now = [self.analyticsSDK getNow];
    // The message was shown. Take the current time so that we can throttle messages
    // from being shown too quickly.
    [self setMessageMinDelayThrottle];
    [self setMessagesLeftToShow:self.messagesLeftToShow - 1];

    SwrveConversationCampaign* c = conversation.campaign;
    if (c != nil) {
        [c conversationWasShownToUser:conversation at:now];
    }
    [self saveCampaignsState];
}

-(void)buttonWasPressedByUser:(SwrveButton*)button
{
    if (button.actionType != kSwrveActionDismiss) {
        NSString *clickEvent = [NSString stringWithFormat:@"Swrve.Messages.Message-%ld.click", button.messageID];
        DebugLog(@"Sending click event: %@", clickEvent);
        [self.analyticsSDK eventInternal:clickEvent payload:@{@"name" : button.name} triggerCallback:false];
    } else {
        // Save button name for processing later
        self.inAppButtonPressedName = button.name;
    }
}

-(NSString*)appStoreURLForAppId:(long)appID
{
    return [self.appStoreURLs objectForKey:[NSString stringWithFormat:@"%ld", appID]];
}

-(NSString*) eventName:(NSDictionary*)eventParameters
{
    NSString* eventName = @"";

    NSString* eventType = [eventParameters objectForKey:@"type"];
    if( [eventType isEqualToString:@"session_start"])
    {
        eventName = @"Swrve.session.start";
    }
    else if( [eventType isEqualToString:@"session_end"])
    {
        eventName = @"Swrve.session.end";
    }
    else if( [eventType isEqualToString:@"buy_in"])
    {
        eventName = @"Swrve.buy_in";
    }
    else if( [eventType isEqualToString:@"iap"])
    {
        eventName = @"Swrve.iap";
    }
    else if( [eventType isEqualToString:@"event"])
    {
        eventName = [eventParameters objectForKey:@"name"];
    }
    else if( [eventType isEqualToString:@"purchase"])
    {
        eventName = @"Swrve.user_purchase";
    }
    else if( [eventType isEqualToString:@"currency_given"])
    {
        eventName = @"Swrve.currency_given";
    }
    else if( [eventType isEqualToString:@"user"])
    {
        eventName = @"Swrve.user_properties_changed";
    }

    return eventName;
}

- (void)showMessage:(SwrveMessage *)message {
    [self showMessage:message queue:false withPersonalisation:nil];
}

- (void)showMessage:(SwrveMessage *)message queue:(bool)isQueued {
    [self showMessage:message queue:isQueued withPersonalisation:nil];
}

- (void)showMessage:(SwrveMessage *)message withPersonalisation:(NSDictionary *)personalisation {
    [self showMessage:message queue:false withPersonalisation:personalisation];
}

- (void)showMessage:(SwrveMessage *)message queue:(bool)isQueued withPersonalisation:(NSDictionary *)personalisation {
    if (message == nil) {
        return;
    }
    @synchronized(self) {
        if (self.inAppMessageWindow == nil && self.conversationWindow == nil) {
            SwrveMessageViewController *messageViewController = [[SwrveMessageViewController alloc] init];
            messageViewController.view.backgroundColor = self.inAppMessageConfig.backgroundColor;
            messageViewController.messageController = self;
            messageViewController.message = message;
            messageViewController.prefersIAMStatusBarHidden = self.prefersIAMStatusBarHidden;
            messageViewController.personalisationDict = personalisation;
            messageViewController.inAppConfig = self.inAppMessageConfig;
            
            messageViewController.block = ^(SwrveActionType type, NSString* action, NSInteger appId) {
    #pragma unused(appId)
                // Save button type and action for processing later
                self.inAppMessageActionType = type;
                self.inAppMessageAction = action;

                id <SwrveMessageDelegate> strongMessageDelegate = self.showMessageDelegate;
                if( [strongMessageDelegate respondsToSelector:@selector(beginHideMessageAnimation:)]) {
                    [strongMessageDelegate beginHideMessageAnimation:(SwrveMessageViewController*)self.inAppMessageWindow.rootViewController];
                }
                else {
                    [self beginHideMessageAnimation:(SwrveMessageViewController*)self.inAppMessageWindow.rootViewController];
                }
            };

#if TARGET_OS_TV
            UITapGestureRecognizer *menuPress = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(menuButtonPressed)];
            menuPress.allowedPressTypes = @[[NSNumber numberWithInteger:UIPressTypeMenu]];
            [messageViewController.view addGestureRecognizer:menuPress];
            [messageViewController setRestoresFocusAfterTransition:YES];
            [self showMessageWindow:messageViewController];
            [messageViewController setNeedsFocusUpdate];
            [messageViewController updateFocusIfNeeded];
#else
            [self showMessageWindow:messageViewController];
#endif

        } else if (isQueued && ![self.conversationsMessageQueue containsObject:message]) {
            [self.conversationsMessageQueue addObject:message];
        }
    }
}

#if TARGET_OS_TV
- (void)menuButtonPressed {
    [self dismissMessageWindow];
}
#endif

- (UIWindow *)createUIWindow {
    // Check if using Swift UI
    if (@available(iOS 13.0,tvOS 13.0, *)) {
        for (UIWindowScene *wScene in [UIApplication sharedApplication].connectedScenes) {
            if (wScene.activationState == UISceneActivationStateForegroundActive) {
                UIWindow *window = wScene.windows.firstObject;
                return [[UIWindow alloc] initWithWindowScene:window.windowScene];
            }
        }
    }
    return [[UIWindow alloc] init];
}

- (void)showConversation:(SwrveConversation *)conversation {
    [self showConversation:conversation queue:false];
}

- (void)showConversation:(SwrveConversation *)conversation queue:(bool)isQueued {
    @synchronized (self) {
        if (conversation && self.inAppMessageWindow == nil && self.conversationWindow == nil) {
            self.conversationWindow = [self createUIWindow];
            self.conversationWindow.frame = [[UIScreen mainScreen] bounds];
            self.swrveConversationItemViewController = [SwrveConversationItemViewController initConversation];
            bool success = [SwrveConversationItemViewController showConversation:conversation
                                  withItemController:self.swrveConversationItemViewController
                                    withEventHandler:(id<SwrveMessageEventHandler>)self
                                            inWindow:self.conversationWindow
                                 withMessageDelegate:self.showMessageDelegate
                                                         withStatusBarHidden:self.analyticsSDK.config.prefersConversationsStatusBarHidden];
            if(!success) {
                self.conversationWindow = nil;
            }
        }  else if (isQueued && ![self.conversationsMessageQueue containsObject:conversation]) {
            [self.conversationsMessageQueue addObject:conversation];
        }
    }
}

- (void) cleanupConversationUI {
    if (self.swrveConversationItemViewController != nil) {
        [self.swrveConversationItemViewController dismiss];
    }
}

- (void) conversationClosed {
    if (self.conversationWindow != nil) {
        id <SwrveMessageDelegate> strongMessageDelegate = self.showMessageDelegate;
        if ([strongMessageDelegate respondsToSelector:@selector(messageWillBeHidden:)]) {
            [strongMessageDelegate messageWillBeHidden:self.conversationWindow.rootViewController];
        }

        self.conversationWindow.hidden = YES;
        self.conversationWindow = nil;
    }
    self.swrveConversationItemViewController = nil;

    [self handleNextConversation:self.conversationsMessageQueue];
}

-(void)handleNextConversation:(NSMutableArray*)queue {
    if ([queue count] > 0) {
        id messageOrConversation = [queue objectAtIndex:0];
        [messageOrConversation isKindOfClass:[SwrveConversation class]] ? [self showConversation:messageOrConversation queue:false] : [self showMessage:messageOrConversation queue:false withPersonalisation:nil];
        [queue removeObjectAtIndex:0];
    }
}

- (void) showMessageWindow:(SwrveMessageViewController*) messageViewController {
    if (messageViewController == nil ) {
        DebugLog(@"Cannot show a nil view.", nil);
        return;
    }

    if (self.inAppMessageWindow != nil ) {
        DebugLog(@"A message is already displayed, ignoring second message.", nil);
        return;
    }

    id <SwrveMessageDelegate> strongMessageDelegate = self.showMessageDelegate;
    if ([strongMessageDelegate respondsToSelector:@selector(messageWillBeShown:)]) {
        [strongMessageDelegate messageWillBeShown:messageViewController];
    }

    self.inAppMessageWindow = [self createUIWindow];
    self.inAppMessageWindow.frame = [[UIScreen mainScreen] bounds];
    self.inAppMessageWindow.rootViewController.view.alpha = 0.0f;
    self.inAppMessageWindow.rootViewController = messageViewController;
    self.inAppMessageWindow.windowLevel = UIWindowLevelAlert + 1;
    [self.inAppMessageWindow makeKeyAndVisible];

    if ([strongMessageDelegate respondsToSelector:@selector(beginShowMessageAnimation:)]) {
        [strongMessageDelegate beginShowMessageAnimation:messageViewController];
    }
    else {
        [self beginShowMessageAnimation:messageViewController];
    }
}

- (void) dismissMessageWindow {
    if(self.inAppMessageWindow == nil) {
        DebugLog(@"No message to dismiss.", nil);
        return;
    }
    [self setMessageMinDelayThrottle];
    NSDate *now = [self.analyticsSDK getNow];
    SwrveInAppCampaign *dismissedCampaign = ((SwrveMessageViewController*)self.inAppMessageWindow.rootViewController).message.campaign;
    [dismissedCampaign messageDismissed:now];

    id <SwrveMessageDelegate> strongMessageDelegate = self.showMessageDelegate;
    if ([strongMessageDelegate respondsToSelector:@selector(messageWillBeHidden:)]) {
        [strongMessageDelegate messageWillBeHidden:self.inAppMessageWindow.rootViewController];
    }

    NSString *action = self.inAppMessageAction;
    NSString *nonProcessedAction = nil;
    switch(self.inAppMessageActionType)
    {
        case kSwrveActionDismiss:
            if (self.dismissButtonCallback != nil) {
                self.dismissButtonCallback(dismissedCampaign.subject, inAppButtonPressedName);
            }
            break;
        case kSwrveActionInstall:
        {
            BOOL standardEvent = true;
            if (self.installButtonCallback != nil) {
                standardEvent = self.installButtonCallback(action);
            }

            if (standardEvent) {
                nonProcessedAction = action;
            }
        }
            break;
        case kSwrveActionCustom:
        {

            if (self.customButtonCallback != nil) {
                self.customButtonCallback(action);
            } else {
                nonProcessedAction = action;
            }
        }
            break;
        case kSwrveActionClipboard:
        {
#if TARGET_OS_IOS /** exclude tvOS **/
            if (action != nil) {
                UIPasteboard *pb = [UIPasteboard generalPasteboard];
                [pb setString:action];
            }
#endif /*TARGET_OS_IOS*/
            
            if (self.clipboardButtonCallback != nil) {
                self.clipboardButtonCallback(action);
            }
        }
            break;
    }

    if(nonProcessedAction != nil) {
        NSURL *url = [NSURL URLWithString:nonProcessedAction];
        if (url != nil) {
            if (@available(iOS 10.0, *)) {
                DebugLog(@"Action - %@ - handled.  Sending to application as URL", nonProcessedAction);
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                    DebugLog(@"Opening url [%@] successfully: %d", url, success);
                }];
            } else {
                DebugLog(@"Action not handled, not supported (should not reach this code)");
            }
        } else {
            DebugLog(@"Action - %@ -  not handled. Override the customButtonCallback to customize message actions", nonProcessedAction);
        }
    }

    self.inAppMessageWindow.hidden = YES;
    self.inAppMessageWindow = nil;
    self.inAppMessageAction = nil;

    [self handleNextConversation:self.conversationsMessageQueue];
}

- (void) beginShowMessageAnimation:(SwrveMessageViewController*) viewController {
    viewController.view.alpha = 0.0f;
    [UIView animateWithDuration:0.25
                          delay:0
                        options: UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         self.inAppMessageWindow.rootViewController.view.alpha = 1.0f;
                     }
                     completion:nil];
}

- (void) beginHideMessageAnimation:(SwrveMessageViewController*) viewController {
#pragma unused(viewController)
    [UIView animateWithDuration:0.25
                          delay:0
                        options: UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         self.inAppMessageWindow.rootViewController.view.alpha = 0.0f;
                     }
                     completion:^(BOOL finished){
#pragma unused(finished)
                         [self dismissMessageWindow];
                     }];
}

-(void) userPressedButton:(SwrveActionType) actionType action:(NSString*) action {
#pragma unused(actionType, action)
    if( self.inAppMessageWindow != nil && self.inAppMessageWindow.hidden == YES ) {
        self.inAppMessageWindow.hidden = YES;
        self.inAppMessageWindow = nil;
    }
}


-(BOOL) eventRaised:(NSDictionary*)event;
{
    if (analyticsSDK == nil) {
        return NO;
    }

    // Get event name
    NSString* eventName = [self eventName:event];
    NSDictionary *payload = [event objectForKey:@"payload"];

#if !defined(SWRVE_NO_PUSH) && TARGET_OS_IOS
    if (self.pushEnabled) {
        if (self.pushNotificationEvents != nil && [self.pushNotificationEvents containsObject:eventName]) {
            // Ask for push notification permission (can display a dialog to the user)
            [analyticsSDK.push registerForPushNotifications:NO];
        } else if (self.provisionalPushNotificationEvents != nil && [self.provisionalPushNotificationEvents containsObject:eventName]) {
            // Ask for provisioanl push notification permission
            [analyticsSDK.push registerForPushNotifications:YES];
        }
    }
#endif //!defined(SWRVE_NO_PUSH)

    // Find a conversation that should be displayed
    SwrveConversation* conversation = nil;

    id <SwrveMessageDelegate> strongMessageDelegate = self.showMessageDelegate;
    if ([strongMessageDelegate respondsToSelector:@selector(conversationForEvent: withPayload:)]) {
        conversation = [strongMessageDelegate conversationForEvent:eventName withPayload:payload];
    }
    else {
        conversation = [self conversationForEvent:eventName withPayload:payload];
    }

    if (conversation != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([strongMessageDelegate respondsToSelector:@selector(showConversation:)]) {
                [self.showMessageDelegate showConversation:conversation];
            } else {
                [self showConversation:conversation];
            }
        });
        return YES;
    } else {
        // Find a message that should be displayed
        SwrveMessage* message = nil;
        if ([strongMessageDelegate respondsToSelector:@selector(messageForEvent: withPayload:)]) {
            message = [strongMessageDelegate messageForEvent:eventName withPayload:payload];
        } else {
            message = [self messageForEvent:eventName withPayload:payload];
        }

        // Show the message if it exists
        if( message != nil ) {
            dispatch_block_t showMessageBlock = ^{
                if ([strongMessageDelegate respondsToSelector:@selector(showMessage:)]) {
                    [self.showMessageDelegate showMessage:message];
                }
                else {
                    [self showMessage:message];
                }
            };


            if ([NSThread isMainThread]) {
                showMessageBlock();
            } else {
                // Run in the main thread as we have been called from other thread
                dispatch_async(dispatch_get_main_queue(), showMessageBlock);
            }
        }

        return ( message != nil );
    }
}

- (BOOL) isQaUser
{
    return self.qaUser != nil;
}

- (NSString*) orientationName
{
    switch (orientation) {
        case SWRVE_ORIENTATION_LANDSCAPE:
            return @"landscape";
        case SWRVE_ORIENTATION_PORTRAIT:
            return @"portrait";
        default:
            return @"both";
    }
}

- (NSString*) campaignQueryString API_AVAILABLE(ios(7.0))
{
    const NSString* orientationName = [self orientationName];
    UIDevice* device = [UIDevice currentDevice];
    NSString* encodedDeviceName = [[device model] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString* encodedSystemName = [[device systemName] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

    return [NSString stringWithFormat:@"version=%d&orientation=%@&language=%@&app_store=%@&device_width=%d&device_height=%d&os_version=%@&device_name=%@&conversation_version=%d&location_version=%d",
            CAMPAIGN_VERSION, orientationName, self.language, @"apple", self.device_width, self.device_height, encodedSystemName, encodedDeviceName, CONVERSATION_VERSION, self.analyticsSDK.locationSegmentVersion];
}

-(NSArray*) messageCenterCampaigns
{
#if TARGET_OS_IOS /** exclude tvOS **/
    return [self messageCenterCampaignsThatSupportOrientation:UIInterfaceOrientationUnknown];
#else
    return [self messageCenterCampaignsForTvOS];
#endif

}

#if TARGET_OS_IOS /** exclude tvOS **/
-(NSArray*) messageCenterCampaignsThatSupportOrientation:(UIInterfaceOrientation)messageOrientation
{
    NSMutableArray* result = [[NSMutableArray alloc] init];
    if (analyticsSDK == nil) {
        return result;
    }

    NSDate* now = [self.analyticsSDK getNow];
    for(SwrveCampaign* campaign in self.campaigns) {
        NSSet* assetsOnDisk = [assetsManager assetsOnDisk];
        if (campaign.messageCenter && campaign.state.status != SWRVE_CAMPAIGN_STATUS_DELETED && [campaign isActive:now withReasons:nil] && [campaign supportsOrientation:messageOrientation] && [campaign assetsReady:assetsOnDisk]) {
            [result addObject:campaign];
        }
    }
    return result;
}
#elif TARGET_OS_TV
-(NSArray*) messageCenterCampaignsForTvOS {

    NSMutableArray* result = [[NSMutableArray alloc] init];
    if (analyticsSDK == nil) {
        return result;
    }

    NSDate* now = [self.analyticsSDK getNow];
    for(SwrveCampaign* campaign in self.campaigns) {
        NSSet* assetsOnDisk = [assetsManager assetsOnDisk];
        if (campaign.messageCenter && campaign.state.status != SWRVE_CAMPAIGN_STATUS_DELETED && [campaign isActive:now withReasons:nil] && [campaign assetsReady:assetsOnDisk]) {
            [result addObject:campaign];
        }
    }
    return result;
}
#endif

-(BOOL)showMessageCenterCampaign:(SwrveCampaign*)campaign {
    return [self showMessageCenterCampaign:campaign withPersonalisation:nil];
}

-(BOOL)showMessageCenterCampaign:(SwrveCampaign *)campaign withPersonalisation:(NSDictionary *)personalisation
{
    if (analyticsSDK == nil) {
        return NO;
    }

    NSSet* assetsOnDisk = [assetsManager assetsOnDisk];
    if (!campaign.messageCenter || ![campaign assetsReady:assetsOnDisk]) {
        return NO;
    }
    
    id <SwrveMessageDelegate> strongMessageDelegate = self.showMessageDelegate;
    if ([campaign isKindOfClass:[SwrveConversationCampaign class]]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SwrveConversation* conversation = ((SwrveConversationCampaign*)campaign).conversation;
            if ([strongMessageDelegate respondsToSelector:@selector(showConversation:)]) {
                [strongMessageDelegate showConversation:conversation];
            } else {
                [self showConversation:conversation];
            }
        });
        return YES;
    } else if ([campaign isKindOfClass:[SwrveInAppCampaign class]]) {
        SwrveMessage* message = [((SwrveInAppCampaign*)campaign).messages objectAtIndex:0];

        if (![message canResolvePersonalisation:personalisation]) {
            return NO;
        }
        
        // Show the message if it exists
        if( message != nil ) {
            dispatch_block_t showMessageBlock = ^{
                if ([strongMessageDelegate respondsToSelector:@selector(showMessage:withPersonalisation:)]) {
                    [strongMessageDelegate showMessage:message withPersonalisation:personalisation];
                } else if ([strongMessageDelegate respondsToSelector:@selector(showMessage:)]) {
                    [self.showMessageDelegate showMessage:message];
                } else {
                    [self showMessage:message withPersonalisation:personalisation];
                }
            };

            if ([NSThread isMainThread]) {
                showMessageBlock();
            } else {
                // Run in the main thread as we have been called from other thread
                dispatch_async(dispatch_get_main_queue(), showMessageBlock);
            }
        }

        return YES;
    }

    return NO;
}

-(void)removeMessageCenterCampaign:(SwrveCampaign*)campaign
{
    if (analyticsSDK == nil) {
        return;
    }
    if (campaign.messageCenter) {
        [campaign.state setStatus:SWRVE_CAMPAIGN_STATUS_DELETED];
        [self saveCampaignsState];
    }
}

-(void)deviceTokenUpdated
{
    // If we are a QA user then send a device info update
    if (self.qaUser) {
        [self.qaUser updateDeviceInfo];
    }
}

- (void) pushNotificationReceived:(NSDictionary*)userInfo
{
    if (self.qaUser) {
        [self.qaUser pushNotification:userInfo];
    } else {
        DebugLog(@"Queuing push notification for later", nil);
        [self.notifications addObject:userInfo];
    }
}

@end
