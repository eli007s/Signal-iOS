//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AdvancedSettingsTableViewController.h"
#import "DebugLogger.h"
#import "DomainFrontingCountryViewController.h"
#import "Environment.h"
#import "OWSCountryMetadata.h"
#import "Pastelog.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "Signal-Swift.h"
#import "TSAccountManager.h"
#import <PromiseKit/AnyPromise.h>
#import <Reachability/Reachability.h>
#import <SignalServiceKit/OWSSignalService.h>

NS_ASSUME_NONNULL_BEGIN

@interface AdvancedSettingsTableViewController ()

@property (nonatomic) Reachability *reachability;

@end

#pragma mark -

@implementation AdvancedSettingsTableViewController

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");

    self.reachability = [Reachability reachabilityForInternetConnection];

    [self observeNotifications];

    [self updateTableContents];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketStateDidChange)
                                                 name:kNSNotification_SocketManagerStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged)
                                                 name:kReachabilityChangedNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)socketStateDidChange
{
    OWSAssert([NSThread isMainThread]);

    [self updateTableContents];
}

- (void)reachabilityChanged
{
    OWSAssert([NSThread isMainThread]);

    [self updateTableContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak AdvancedSettingsTableViewController *weakSelf = self;

    OWSTableSection *loggingSection = [OWSTableSection new];
    loggingSection.headerTitle = NSLocalizedString(@"LOGGING_SECTION", nil);
    [loggingSection addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_DEBUGLOG", @"")
                                                        isOn:[PropertyListPreferences loggingIsEnabled]
                                                      target:weakSelf
                                                    selector:@selector(didToggleEnableLogSwitch:)]];


    if ([PropertyListPreferences loggingIsEnabled]) {
        [loggingSection
            addItem:[OWSTableItem actionItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", @"")
                                         actionBlock:^{
                                             DDLogInfo(@"%@ Submitting debug logs", weakSelf.tag);
                                             [DDLog flushLog];
                                             [Pastelog submitLogs];
                                         }]];
    }

    [contents addSection:loggingSection];

    OWSTableSection *pushNotificationsSection = [OWSTableSection new];
    pushNotificationsSection.headerTitle
        = NSLocalizedString(@"PUSH_REGISTER_TITLE", @"Used in table section header and alert view title contexts");
    [pushNotificationsSection addItem:[OWSTableItem actionItemWithText:NSLocalizedString(@"REREGISTER_FOR_PUSH", nil)
                                                           actionBlock:^{
                                                               [weakSelf syncPushTokens];
                                                           }]];
    [contents addSection:pushNotificationsSection];

    // Censorship circumvention has certain disadvantages so it should only be
    // used if necessary.  Therefore:
    //
    // * We disable this setting if the user has a phone number from a censored region -
    //   censorship circumvention will be auto-activated for this user.
    // * We disable this setting if the user is already connected; they're not being
    //   censored.
    // * We continue to show this setting so long as it is set to allow users to disable
    //   it, for example when they leave a censored region.
    OWSTableSection *censorshipSection = [OWSTableSection new];
    censorshipSection.headerTitle = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_HEADER",
        @"Table header for the 'censorship circumvention' section.");
    if (OWSSignalService.sharedInstance.hasCensoredPhoneNumber) {
        censorshipSection.footerTitle
            = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_AUTO_ENABLED",
                @"Table footer for the 'censorship circumvention' section shown when censorship circumvention has been "
                @"auto-enabled based on local phone number.");
    } else if ([TSSocketManager sharedManager].state == SocketManagerStateOpen) {
        censorshipSection.footerTitle
            = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_WEBSOCKET_CONNECTED",
                @"Table footer for the 'censorship circumvention' section shown when the app is connected to the "
                @"Signal service.");
    } else if (!self.reachability.isReachable) {
        censorshipSection.footerTitle
            = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_NO_CONNECTION",
                @"Table footer for the 'censorship circumvention' section shown when the app is not connected to the "
                @"internet.");
    } else {
        censorshipSection.footerTitle = NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER",
            @"Table footer for the 'censorship circumvention' section when censorship circumvention can be manually "
            @"enabled.");
    }

    // Do enable if :
    //
    // * ...Censorship circumvention is already manually enabled (to allow users to disable it).
    //
    // Otherwise, don't enable if:
    //
    // * ...Censorship circumvention is already enabled based on the local phone number.
    // * ...The websocket is connected, since that demonstrates that no censorship is in effect.
    // * ...The internet is not reachable, since we don't want to let users to activate
    //      censorship circumvention unnecessarily, e.g. if they just don't have a valid
    //      internet connection.
    BOOL isManualCensorshipCircumventionOnEnabled
        = (OWSSignalService.sharedInstance.isCensorshipCircumventionManuallyActivated
            || (!OWSSignalService.sharedInstance.hasCensoredPhoneNumber &&
                   [TSSocketManager sharedManager].state != SocketManagerStateOpen
                   && weakSelf.reachability.isReachable));
    BOOL isCensorshipCircumventionOn = NO;
    if (OWSSignalService.sharedInstance.hasCensoredPhoneNumber) {
        isCensorshipCircumventionOn = YES;
    } else {
        isCensorshipCircumventionOn = OWSSignalService.sharedInstance.isCensorshipCircumventionManuallyActivated;
    }
    [censorshipSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION",
                                                     @"Label for the  'manual censorship circumvention' switch.")
                                            isOn:isCensorshipCircumventionOn
                                       isEnabled:isManualCensorshipCircumventionOnEnabled
                                          target:weakSelf
                                        selector:@selector(didToggleEnableCensorshipCircumventionSwitch:)]];

    if (OWSSignalService.sharedInstance.isCensorshipCircumventionManuallyActivated) {
        OWSCountryMetadata *manualCensorshipCircumventionCountry =
            [weakSelf ensureManualCensorshipCircumventionCountry];
        OWSAssert(manualCensorshipCircumventionCountry);
        NSString *text = [NSString
            stringWithFormat:NSLocalizedString(@"SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_COUNTRY_FORMAT",
                                 @"Label for the 'manual censorship circumvention' country. Embeds {{the manual "
                                 @"censorship circumvention country}}."),
            manualCensorshipCircumventionCountry.localizedCountryName];
        [censorshipSection addItem:[OWSTableItem disclosureItemWithText:text
                                                            actionBlock:^{
                                                                [weakSelf showDomainFrontingCountryView];
                                                            }]];
    }
    [contents addSection:censorshipSection];

    self.contents = contents;
}

- (void)showDomainFrontingCountryView
{
    DomainFrontingCountryViewController *vc = [DomainFrontingCountryViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (OWSCountryMetadata *)ensureManualCensorshipCircumventionCountry
{
    OWSAssert([NSThread isMainThread]);

    OWSCountryMetadata *countryMetadata = nil;
    NSString *countryCode = OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode;
    if (countryCode) {
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
    }

    if (!countryMetadata) {
        countryCode = [NSLocale.currentLocale objectForKey:NSLocaleCountryCode];
        if (countryCode) {
            countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
        }
    }

    if (!countryMetadata) {
        countryCode = @"US";
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
        OWSAssert(countryMetadata);
    }

    if (countryMetadata) {
        // Ensure the "manual censorship circumvention" country state is in sync.
        OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode = countryCode;
        OWSSignalService.sharedInstance.manualCensorshipCircumventionDomain = countryMetadata.googleDomain;
    }

    return countryMetadata;
}

#pragma mark - Actions

- (void)syncPushTokens
{
    OWSSyncPushTokensJob *job =
        [[OWSSyncPushTokensJob alloc] initWithPushManager:[PushManager sharedManager]
                                           accountManager:[Environment getCurrent].accountManager
                                              preferences:[Environment preferences]];
    job.uploadOnlyIfStale = NO;
    [job run]
        .then(^{
            [OWSAlerts showAlertWithTitle:NSLocalizedString(@"PUSH_REGISTER_SUCCESS",
                                              @"Title of alert shown when push tokens sync job succeeds.")];
        })
        .catch(^(NSError *error) {
            [OWSAlerts showAlertWithTitle:NSLocalizedString(@"REGISTRATION_BODY",
                                              @"Title of alert shown when push tokens sync job fails.")];
        });
}

- (void)didToggleEnableLogSwitch:(UISwitch *)sender {
    if (!sender.isOn) {
        [[DebugLogger sharedLogger] wipeLogs];
        [[DebugLogger sharedLogger] disableFileLogging];
    } else {
        [[DebugLogger sharedLogger] enableFileLogging];
    }
    
    [PropertyListPreferences setLoggingEnabled:sender.isOn];

    [self updateTableContents];
}

- (void)didToggleEnableCensorshipCircumventionSwitch:(UISwitch *)sender
{
    OWSSignalService.sharedInstance.isCensorshipCircumventionManuallyActivated = sender.isOn;

    [self updateTableContents];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
