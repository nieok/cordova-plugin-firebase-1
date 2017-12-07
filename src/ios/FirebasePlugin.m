#import "FirebasePlugin.h"
#import <Cordova/CDV.h>
#import "AppDelegate.h"
#import "Firebase.h"
#import "NSFileManager+NRFileManager.h"
#import <Crashlytics/Crashlytics.h>
#import <FirebasePerformance/FirebasePerformance.h>
#import <Fabric/Fabric.h>
@import FirebaseInstanceID;
@import FirebaseMessaging;
@import FirebaseAnalytics;
@import FirebaseRemoteConfig;
@import FirebaseAuth;

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
@import UserNotifications;
#endif

#ifndef NSFoundationVersionNumber_iOS_9_x_Max
#define NSFoundationVersionNumber_iOS_9_x_Max 1299
#endif

@implementation FirebasePlugin

@synthesize notificationCallbackId;
@synthesize tokenRefreshCallbackId;
@synthesize notificationStack;

static NSInteger const kNotificationStackSize = 10;
static FirebasePlugin *firebasePlugin;

+ (FirebasePlugin *) firebasePlugin {
    return firebasePlugin;
}

- (void)pluginInitialize {
    NSLog(@"Starting Firebase plugin");
    firebasePlugin = self;
    _performanceTracesByName = [NSMutableDictionary dictionary];
}

// DEPRECATED - alias of getToken
- (void)getInstanceId:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:
                    [[FIRInstanceID instanceID] token]];

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getToken:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:
                    [[FIRInstanceID instanceID] token]];

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
- (void)hasPermission:(CDVInvokedUrlCommand *)command
{
    BOOL enabled = NO;
    UIApplication *application = [UIApplication sharedApplication];
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        enabled = application.currentUserNotificationSettings.types != UIUserNotificationTypeNone;
    } else {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        enabled = application.enabledRemoteNotificationTypes != UIRemoteNotificationTypeNone;
#pragma GCC diagnostic pop
    }
    
    NSMutableDictionary* message = [NSMutableDictionary dictionaryWithCapacity:1];
    [message setObject:[NSNumber numberWithBool:enabled] forKey:@"isEnabled"];
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
    [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
}
- (void)grantPermission:(CDVInvokedUrlCommand *)command {
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
        if ([[UIApplication sharedApplication]respondsToSelector:@selector(registerUserNotificationSettings:)]) {
            UIUserNotificationType notificationTypes =
            (UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge);
            UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:notificationTypes categories:nil];
            [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        } else {
            #pragma GCC diagnostic push
            #pragma GCC diagnostic ignored "-Wdeprecated-declarations"
            [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound)];
            #pragma GCC diagnostic pop
        }
		
		CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
		[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
		return;
    }
	
	
	
	#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
	BOOL isIOS10 = TRUE;
	#else
	BOOL isIOS10 = FALSE;
	#endif
	
	
	if ( !isIOS10 ) {
		[[UIApplication sharedApplication] registerForRemoteNotifications];
		CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
		[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
		return;
	}
	
	
	
	// IOS 10
	UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert|UNAuthorizationOptionSound|UNAuthorizationOptionBadge;
	[[UNUserNotificationCenter currentNotificationCenter]
		requestAuthorizationWithOptions:authOptions
	 				  completionHandler:^(BOOL granted, NSError * _Nullable error) {
			
			if ( ![NSThread isMainThread] ) {
				dispatch_sync(dispatch_get_main_queue(), ^{
					[[UNUserNotificationCenter currentNotificationCenter] setDelegate:self];
					[[FIRMessaging messaging] setRemoteMessageDelegate:self];
					[[UIApplication sharedApplication] registerForRemoteNotifications];
					
					CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus: granted ? CDVCommandStatus_OK : CDVCommandStatus_ERROR];
					[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
				});
			}
			else {
				[[UNUserNotificationCenter currentNotificationCenter] setDelegate:self];
				[[FIRMessaging messaging] setRemoteMessageDelegate:self];
				[[UIApplication sharedApplication] registerForRemoteNotifications];
				CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
				[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
			}
	  }
	];
	
	return;
}

- (void)setBadgeNumber:(CDVInvokedUrlCommand *)command {
    int number = [[command.arguments objectAtIndex:0] intValue];

    [self.commandDelegate runInBackground:^{
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:number];

        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}


- (void)getVerificationID:(CDVInvokedUrlCommand *)command {
    NSString* number = [command.arguments objectAtIndex:0];

    [[FIRPhoneAuthProvider provider]
    verifyPhoneNumber:number
           completion:^(NSString *_Nullable verificationID,
                        NSError *_Nullable error) {
NSDictionary *message;
  if (error) {

    // Verification code not sent.
    message = @{
                @"code": [NSNumber numberWithInteger:error.code],
                @"description": error.description == nil ? [NSNull null] : error.description
                };

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:message];
                                                                                                        
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId]; 
    
  } else {
    // Successful.
CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:verificationID];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId]; 
  }
}];

     
    
}

- (void)getBadgeNumber:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        long badge = [[UIApplication sharedApplication] applicationIconBadgeNumber];

        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:badge];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)subscribe:(CDVInvokedUrlCommand *)command {
    NSString* topic = [NSString stringWithFormat:@"/topics/%@", [command.arguments objectAtIndex:0]];
    
    [[FIRMessaging messaging] subscribeToTopic: topic];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)unsubscribe:(CDVInvokedUrlCommand *)command {
    NSString* topic = [NSString stringWithFormat:@"/topics/%@", [command.arguments objectAtIndex:0]];
    
    [[FIRMessaging messaging] unsubscribeFromTopic: topic];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)unregister:(CDVInvokedUrlCommand *)command {
    [[FIRInstanceID instanceID] deleteIDWithHandler:^void(NSError *_Nullable error){
        if (error) {
            NSLog(@"Unable to delete instance");
        } else {            
            NSString* currentToken = [[FIRInstanceID instanceID] token];
            if (currentToken != nil) {
                [self sendToken:currentToken];
            }
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

- (void)onNotificationOpen:(CDVInvokedUrlCommand *)command {
    self.notificationCallbackId = command.callbackId;

    if (self.notificationStack != nil && [self.notificationStack count]) {
        for (NSDictionary *userInfo in self.notificationStack) {
            [self sendNotification:userInfo];
        }
        [self.notificationStack removeAllObjects];
    }
}

- (void)onTokenRefresh:(CDVInvokedUrlCommand *)command {
    self.tokenRefreshCallbackId = command.callbackId;
    NSString* currentToken = [[FIRInstanceID instanceID] token];
    if (currentToken != nil) {
        [self sendToken:currentToken];
    }
}

- (void)sendNotification:(NSDictionary *)userInfo {
    if (self.notificationCallbackId != nil) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:userInfo];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.notificationCallbackId];
    } else {
        if (!self.notificationStack) {
            self.notificationStack = [[NSMutableArray alloc] init];
        }
        
        // stack notifications until a callback has been registered
        [self.notificationStack addObject:userInfo];

        if ([self.notificationStack count] >= kNotificationStackSize) {
            [self.notificationStack removeLastObject];
        }
    }
}

- (void)sendToken:(NSString *)token {
    if (self.tokenRefreshCallbackId != nil) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:token];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.tokenRefreshCallbackId];
    }
}

- (void)logEvent:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString* name = [command.arguments objectAtIndex:0];
        NSDictionary* parameters = [command.arguments objectAtIndex:1];
        
        [FIRAnalytics logEventWithName:name parameters:parameters];
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)setScreenName:(CDVInvokedUrlCommand *)command {
    NSString* name = [command.arguments objectAtIndex:0];

    [FIRAnalytics setScreenName:name screenClass:NULL];

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setUserId:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString* id = [command.arguments objectAtIndex:0];
        
        [FIRAnalytics setUserID:id];
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)setUserProperty:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString* name = [command.arguments objectAtIndex:0];
        NSString* value = [command.arguments objectAtIndex:1];
        
        [FIRAnalytics setUserPropertyString:value forName:name];
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)fetch:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        FIRRemoteConfig* remoteConfig = [FIRRemoteConfig remoteConfig];

        if ([command.arguments count] > 0){
            int expirationDuration = [[command.arguments objectAtIndex:0] intValue];

            [remoteConfig fetchWithExpirationDuration:expirationDuration completionHandler:^(FIRRemoteConfigFetchStatus status, NSError * _Nullable error) {
                if (status == FIRRemoteConfigFetchStatusSuccess) {
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                } else {
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
            }];
        } else {
            [remoteConfig fetchWithCompletionHandler:^(FIRRemoteConfigFetchStatus status, NSError * _Nullable error) {
                if (status == FIRRemoteConfigFetchStatusSuccess) {
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                } else {
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
            }];
        }
    }];
}

- (void)activateFetched:(CDVInvokedUrlCommand *)command {
     [self.commandDelegate runInBackground:^{
        FIRRemoteConfig* remoteConfig = [FIRRemoteConfig remoteConfig];
         BOOL activated = [remoteConfig activateFetched];
         CDVPluginResult *pluginResult;
         if (activated) {
             pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
         } else {
             pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
         }
         
         [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
     }];
}

- (void)getValue:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        NSString* key = [command.arguments objectAtIndex:0];
        FIRRemoteConfig* remoteConfig = [FIRRemoteConfig remoteConfig];
        NSString* value = remoteConfig[key].stringValue;
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:value];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}


#pragma mark - Crashlytics

- (void)sendJavascriptError:(CDVInvokedUrlCommand *)command {
    NSString *message = [command.arguments objectAtIndex:0];
//    NSString *fileName = [command.arguments objectAtIndex:1];
    NSArray *stackTrace = [command.arguments objectAtIndex:2];
    
    NSMutableArray<CLSStackFrame*> *stackFrames = [NSMutableArray array];
    
    if (stackTrace) {
        for (NSDictionary *stackItem in stackTrace) {
            NSString *functionName = [stackItem objectForKey:@"functionName"];
            NSString *fileName = [stackItem objectForKey:@"fileName"];
            uint32_t lineNumber = [[stackItem objectForKey:@"lineNumber"] intValue];
            uint32_t columnNumber = [[stackItem objectForKey:@"columnNumber"] intValue];
            
            CLSStackFrame *stackFrame = [CLSStackFrame stackFrameWithSymbol:functionName];
            stackFrame.fileName = fileName;
            stackFrame.lineNumber = lineNumber;
            stackFrame.offset = columnNumber;
            
            [stackFrames addObject:stackFrame];
        }
    }
    
    [[Crashlytics sharedInstance] recordCustomExceptionName:@"JavascriptError" reason:message frameArray:stackFrames];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)sendUserError:(CDVInvokedUrlCommand *)command {
    NSString *message = [command.arguments objectAtIndex:1];
    NSDictionary *userInfo = [command.arguments objectAtIndex:1];
    
    NSError *error = [NSError errorWithDomain:message code:0 userInfo:userInfo];
    [[Crashlytics sharedInstance] recordError:error];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)setCrashlyticsValue:(CDVInvokedUrlCommand *)command {
    NSString *key = [command.arguments objectAtIndex:0];
    NSObject *value = [command.arguments objectAtIndex:1];
    
    if (key && value) {
        [[Crashlytics sharedInstance] setObjectValue:value forKey:key];
    }
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)logCrashlytics:(CDVInvokedUrlCommand *)command {
    NSString *message = [command.arguments objectAtIndex:0];
    
    CLSLog(@"%@", message);
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


#pragma mark - Performance

- (void)sendImmediateTraceCounter:(CDVInvokedUrlCommand *)command {
    
    NSString *traceName = [command.arguments objectAtIndex:0];
    NSString *counterName = [command.arguments objectAtIndex:1];
    NSInteger counterValue = [[command.arguments objectAtIndex:2] intValue];
    
    FIRTrace *trace = [FIRPerformance startTraceWithName:traceName];
    [trace incrementCounterNamed:counterName by:counterValue];
    [trace stop];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)startTrace:(CDVInvokedUrlCommand *)command {
    
    NSString *traceName = [command.arguments objectAtIndex:0];
    
    if ([_performanceTracesByName objectForKey:traceName]) {
        // Trace already exist, report error
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_INVALID_ACTION messageAsString:@"Trace already started"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    FIRTrace *trace = [FIRPerformance startTraceWithName:traceName];
    [_performanceTracesByName setObject:trace forKey:traceName];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stopTrace:(CDVInvokedUrlCommand *)command {
    
    NSString *traceName = [command.arguments objectAtIndex:0];
    
    FIRTrace *trace = [_performanceTracesByName objectForKey:traceName];
    [trace stop];
    
    [_performanceTracesByName removeObjectForKey:traceName];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)traceIncrementCounterByValue:(CDVInvokedUrlCommand *)command {
    
    NSString *traceName = [command.arguments objectAtIndex:0];
    NSString *counterName = [command.arguments objectAtIndex:1];
    NSInteger counterValue = [[command.arguments objectAtIndex:2] intValue];
    
    FIRTrace *trace = [_performanceTracesByName objectForKey:traceName];
    [trace incrementCounterNamed:counterName by:counterValue];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)reportCacheSize:(CDVInvokedUrlCommand *)command {
    
    NSFileManager *fm = [NSFileManager defaultManager];
    unsigned long long cache = ([fm calculateCacheSize]) / (1000 * 1000);
    unsigned long long docs = ([fm calculateDocsSize]) / (1000 * 1000);
    unsigned long long library = ([fm calculateLibrarySize]) / (1000 * 1000);

    FIRTrace *trace = [FIRPerformance startTraceWithName:@"cache_size_report"];
    [trace incrementCounterNamed:@"cache_size_mo" by:cache];
    [trace incrementCounterNamed:@"docs_size_mo" by:docs];
    [trace incrementCounterNamed:@"library_size_mo" by:library];
    [trace stop];
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end
