/*
 * This is the source code of Telegram for iOS v. 1.1
 * It is licensed under GNU GPL v. 2 or later.
 * You should have received a copy of the license in this archive (see LICENSE).
 *
 * Copyright Peter Iakovlev, 2013.
 */

#import "TGNotificationSettingsController.h"

#import <LegacyComponents/ActionStage.h>
#import <LegacyComponents/SGraphObjectNode.h>

#import "TGAppDelegate.h"
#import "TGTelegraph.h"
#import "TGDatabase.h"

#import "TGHeaderCollectionItem.h"
#import "TGSwitchCollectionItem.h"
#import "TGVariantCollectionItem.h"
#import "TGButtonCollectionItem.h"
#import "TGCommentCollectionItem.h"

#import "TGCustomActionSheet.h"

#import "TGAlertSoundController.h"
#import "TGNotificationExceptionsController.h"
#import "TGNotificationException.h"

#import "TGAccountSignals.h"
#import "TGNotificationExceptionsSignal.h"
#import "TGUserSignal.h"
#import "TGConversationSignals.h"

#import "TGPresentation.h"

@interface TGNotificationSettingsController () <TGAlertSoundControllerDelegate>
{
    TGSwitchCollectionItem *_privateAlert;
    TGSwitchCollectionItem *_privatePreview;
    TGVariantCollectionItem *_privateSound;
    TGVariantCollectionItem *_privateExceptions;
    
    TGSwitchCollectionItem *_groupAlert;
    TGSwitchCollectionItem *_groupPreview;
    TGVariantCollectionItem *_groupSound;
    TGVariantCollectionItem *_groupExceptions;
    
    TGSwitchCollectionItem *_inAppSounds;
    TGSwitchCollectionItem *_inAppVibrate;
    TGSwitchCollectionItem *_inAppPreview;
    
    TGSwitchCollectionItem *_joinedContacts;
    
    NSMutableDictionary *_privateNotificationSettings;
    NSMutableDictionary *_groupNotificationSettings;
    
    NSArray *_privateExceptionItems;
    NSArray *_groupExceptionItems;
    NSDictionary *_exceptionsPeers;
    
    bool _selectingPrivateSound;
    
    id<SDisposable> _contactsJoinedDisposable;
    SMetaDisposable *_updateContactsJoinedDisposable;
    
    id<SDisposable> _exceptionsDisposable;
}

@end

@implementation TGNotificationSettingsController

- (id)init
{
    self = [super init];
    if (self)
    {
        _privateNotificationSettings = [[NSMutableDictionary alloc] initWithDictionary:@{@"muteUntil": @(0), @"soundId": @(1), @"previewText": @(true)}];
        _groupNotificationSettings = [[NSMutableDictionary alloc] initWithDictionary:@{@"muteUntil": @(0), @"soundId": @(1), @"previewText": @(true)}];
        
        _actionHandle = [[ASHandle alloc] initWithDelegate:self releaseOnMainThread:true];
        
        [self setTitleText:TGLocalized(@"Notifications.Title")];
        self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:TGLocalized(@"Common.Back") style:UIBarButtonItemStylePlain target:self action:@selector(backPressed)];
        
        _privateAlert = [[TGSwitchCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.MessageNotificationsAlert") isOn:true];
        _privateAlert.interfaceHandle = _actionHandle;
        _privatePreview = [[TGSwitchCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.MessageNotificationsPreview") isOn:true];
        _privatePreview.interfaceHandle = _actionHandle;
        
        NSString *currentPrivateSound = [TGAppDelegateInstance modernAlertSoundTitles][1];
        NSString *currentGroupSound = [TGAppDelegateInstance modernAlertSoundTitles][1];
        
        _privateSound = [[TGVariantCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.MessageNotificationsSound") variant:currentPrivateSound action:@selector(privateSoundPressed)];
        _privateSound.deselectAutomatically = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
        
        _privateExceptions = [[TGVariantCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.MessageNotificationsExceptions") variant:@"" action:@selector(privateExceptionsPressed)];
        _privateExceptions.enabled = false;
        _privateExceptions.deselectAutomatically = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
        
        TGCollectionMenuSection *messageNotificationsSection = [[TGCollectionMenuSection alloc] initWithItems:@[
            [[TGHeaderCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.MessageNotifications")],
            _privateAlert,
            _privatePreview,
            _privateSound,
            _privateExceptions,
            [[TGCommentCollectionItem alloc] initWithText:TGLocalized(@"Notifications.MessageNotificationsHelp")]
        ]];
        UIEdgeInsets topSectionInsets = messageNotificationsSection.insets;
        topSectionInsets.top = 32.0f;
        messageNotificationsSection.insets = topSectionInsets;
        [self.menuSections addSection:messageNotificationsSection];
        
        _groupSound = [[TGVariantCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.MessageNotificationsSound") variant:currentGroupSound action:@selector(groupSoundPressed)];
        _groupSound.deselectAutomatically = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
        
        _groupAlert = [[TGSwitchCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.GroupNotificationsAlert") isOn:true];
        _groupAlert.interfaceHandle = _actionHandle;
        _groupPreview = [[TGSwitchCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.GroupNotificationsPreview") isOn:true];
        _groupPreview.interfaceHandle = _actionHandle;
        
        _groupExceptions = [[TGVariantCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.GroupNotificationsExceptions") variant:@"" action:@selector(groupExceptionsPressed)];
        _groupExceptions.enabled = false;
        _groupExceptions.deselectAutomatically = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
        
        TGCollectionMenuSection *groupNotificationsSection = [[TGCollectionMenuSection alloc] initWithItems:@[
            [[TGHeaderCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.GroupNotifications")],
            _groupAlert,
            _groupPreview,
            _groupSound,
            _groupExceptions,
            [[TGCommentCollectionItem alloc] initWithText:TGLocalized(@"Notifications.GroupNotificationsHelp")]
        ]];
        [self.menuSections addSection:groupNotificationsSection];
        
        _inAppSounds = [[TGSwitchCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.InAppNotificationsSounds") isOn:TGAppDelegateInstance.soundEnabled];
        _inAppSounds.interfaceHandle = _actionHandle;
        _inAppVibrate = [[TGSwitchCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.InAppNotificationsVibrate") isOn:TGAppDelegateInstance.vibrationEnabled];
        _inAppVibrate.interfaceHandle = _actionHandle;
        _inAppPreview = [[TGSwitchCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.InAppNotificationsPreview") isOn:TGAppDelegateInstance.bannerEnabled];
        _inAppPreview.interfaceHandle = _actionHandle;
        
        NSMutableArray *inAppNotificationsSectionItems = [[NSMutableArray alloc] init];
        
        [inAppNotificationsSectionItems addObject:[[TGHeaderCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.InAppNotifications")]];
        [inAppNotificationsSectionItems addObject:_inAppSounds];
        
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
            [inAppNotificationsSectionItems addObject:_inAppVibrate];

        [inAppNotificationsSectionItems addObject:_inAppPreview];
        
        TGCollectionMenuSection *inAppNotificationsSection = [[TGCollectionMenuSection alloc] initWithItems:inAppNotificationsSectionItems];
        [self.menuSections addSection:inAppNotificationsSection];
        
        _joinedContacts = [[TGSwitchCollectionItem alloc] initWithTitle:TGLocalized(@"NotificationSettings.ContactJoined") isOn:true];
        //TGCollectionMenuSection *contactsSection = [[TGCollectionMenuSection alloc] initWithItems:@[_joinedContacts]];
        //[self.menuSections addSection:contactsSection];

        TGButtonCollectionItem *resetItem = [[TGButtonCollectionItem alloc] initWithTitle:TGLocalized(@"Notifications.ResetAllNotifications") action:@selector(resetAllNotifications)];
        resetItem.titleColor = TGPresentation.current.pallete.collectionMenuDestructiveColor;
        resetItem.deselectAutomatically = true;
        TGCollectionMenuSection *resetSection = [[TGCollectionMenuSection alloc] initWithItems:@[
            resetItem,
            [[TGCommentCollectionItem alloc] initWithText:TGLocalized(@"Notifications.ResetAllNotificationsHelp")],
        ]];
        [self.menuSections addSection:resetSection];
        
        [ActionStageInstance() dispatchOnStageQueue:^
        {
            [ActionStageInstance() watchForPaths:@[
                [NSString stringWithFormat:@"/tg/peerSettings/(%d)", INT_MAX - 1],
                [NSString stringWithFormat:@"/tg/peerSettings/(%d)", INT_MAX - 2]
            ] watcher:self];
            
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/peerSettings/(%d,cached)", INT_MAX - 1] options:[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:INT_MAX - 1] forKey:@"peerId"] watcher:self];
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/peerSettings/(%d,cached)", INT_MAX - 2] options:[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:INT_MAX - 2] forKey:@"peerId"] watcher:self];
        }];
        
        __weak TGNotificationSettingsController *weakSelf = self;
        
        _updateContactsJoinedDisposable = [[SMetaDisposable alloc] init];
        _joinedContacts.toggled = ^(bool value, __unused TGSwitchCollectionItem *item) {
            __strong TGNotificationSettingsController *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf->_updateContactsJoinedDisposable setDisposable:[[TGAccountSignals updateContactsJoinedNotificationSettings:value] startWithNext:nil]];
            }
        };
        
        _contactsJoinedDisposable = [[[TGAccountSignals currentContactsJoinedNotificationSettings] deliverOn:[SQueue mainQueue]] startWithNext:^(id next) {
            __strong TGNotificationSettingsController *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf->_joinedContacts setIsOn:[next boolValue] animated:true];
            }
        }];
                
        _exceptionsDisposable = [[[TGNotificationSettingsController notificatonsExceptionsSignal] deliverOn:[SQueue mainQueue]] startWithNext:^(NSDictionary *next) {
            __strong TGNotificationSettingsController *strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf->_privateExceptionItems = next[@"private"];
                strongSelf->_groupExceptionItems = next[@"group"];
                strongSelf->_exceptionsPeers = next[@"peers"];
                [strongSelf updateExceptions];
            }
        }];
        
    }
    return self;
}

- (void)dealloc
{
    [_actionHandle reset];
    [ActionStageInstance() removeWatcher:self];
    [_contactsJoinedDisposable dispose];
    [_updateContactsJoinedDisposable dispose];
}

- (void)updateExceptions
{
    _privateExceptions.enabled = true;
    _privateExceptions.variant = _privateExceptionItems.count > 0 ? [effectiveLocalization() getPluralized:@"Notifications.Exceptions" count:(int32_t)_privateExceptionItems.count] : TGLocalized(@"Notifications.ExceptionsNone");
    
    _groupExceptions.enabled = true;
    _groupExceptions.variant = _groupExceptionItems.count > 0 ? [effectiveLocalization() getPluralized:@"Notifications.Exceptions" count:(int32_t)_groupExceptionItems.count] : TGLocalized(@"Notifications.ExceptionsNone");
}

+ (SSignal *)notificatonsExceptionsSignal
{
    return [[TGNotificationExceptionsSignal notificationExceptionsSignal] mapToSignal:^SSignal *(NSDictionary *dict)
    {
        NSMutableArray *peerSignals = [[NSMutableArray alloc] init];
        for (TGNotificationException *exception in dict[@"private"])
        {
            if (exception.peerId == 0)
                continue;
            [peerSignals addObject:[[[TGUserSignal userWithUserId:(int32_t)exception.peerId] catch:^SSignal *(__unused id error) {
                return [SSignal single:[NSNull null]];
            }] take:1]];
        }
        for (TGNotificationException *exception in dict[@"group"])
        {
            if (exception.peerId == 0)
                continue;
            [peerSignals addObject:[[[TGConversationSignals conversationWithPeerId:exception.peerId full:false] catch:^SSignal *(__unused id error) {
                return [SSignal single:[NSNull null]];
            }] take:1]];
        }
        
        return [[SSignal combineSignals:peerSignals] map:^id(NSArray *peers)
        {
            NSMutableDictionary *peersMap = [[NSMutableDictionary alloc] init];
            for (id peer in peers)
            {
                if ([peer isKindOfClass:[TGUser class]])
                    peersMap[@(((TGUser *)peer).uid)] = peer;
                else if ([peer isKindOfClass:[TGConversation class]])
                    peersMap[@(((TGConversation *)peer).conversationId)] = peer;
            }
            
            NSMutableIndexSet *indexesToRemove = [[NSMutableIndexSet alloc] init];
            NSMutableArray *private = [[NSMutableArray alloc] initWithArray:dict[@"private"]];
            [private enumerateObjectsUsingBlock:^(TGNotificationException *exception, NSUInteger index, __unused BOOL *stop) {
                TGUser *user = peersMap[@(exception.peerId)];
                if (user.isDeleted || user.restrictionReason.length > 0 || user.uid == TGTelegraphInstance.clientUserId)
                    [indexesToRemove addIndex:index];
            }];
            [private removeObjectsAtIndexes:indexesToRemove];
            
            [indexesToRemove removeAllIndexes];
            NSMutableArray *group = [[NSMutableArray alloc] initWithArray:dict[@"group"]];
            [group enumerateObjectsUsingBlock:^(TGNotificationException *exception, NSUInteger index, __unused BOOL *stop) {
                TGConversation *conversation = peersMap[@(exception.peerId)];
                if (conversation.isDeleted || conversation.isDeactivated || conversation.leftChat || conversation.kickedFromChat || conversation.restrictionReason.length > 0 || conversation.chatTitle.length == 0)
                    [indexesToRemove addIndex:index];
            }];
            [group removeObjectsAtIndexes:indexesToRemove];
            
            return @{@"private": private, @"group": group, @"peers": peersMap};
        }];
    }];
}

#pragma mark -

- (void)backPressed
{
    [self.navigationController popViewControllerAnimated:true];
}

- (void)resetAllNotifications
{
    [[[TGCustomActionSheet alloc] initWithTitle:TGLocalized(@"Notifications.ResetAllNotificationsHelp") actions:@[
        [[TGActionSheetAction alloc] initWithTitle:TGLocalized(@"Notifications.Reset") action:@"reset" type:TGActionSheetActionTypeDestructive],
        [[TGActionSheetAction alloc] initWithTitle:TGLocalized(@"Common.Cancel") action:@"cancel" type:TGActionSheetActionTypeCancel]
    ] actionBlock:^(TGNotificationSettingsController *controller, NSString *action)
    {
        if ([action isEqualToString:@"reset"])
            [controller _commitResetAllNotitications];
    } target:self] showInView:self.view];
}

- (void)_commitResetAllNotitications
{
    TGAppDelegateInstance.soundEnabled = true;
    TGAppDelegateInstance.vibrationEnabled = false;
    TGAppDelegateInstance.bannerEnabled = true;
    [TGAppDelegateInstance saveSettings];
    
    _privateNotificationSettings = [[NSMutableDictionary alloc] initWithDictionary:@{@"muteUntil": @(0), @"soundId": @(1), @"previewText": @(true)}];
    _groupNotificationSettings = [[NSMutableDictionary alloc] initWithDictionary:@{@"muteUntil": @(0), @"soundId": @(1), @"previewText": @(true)}];
    
    _privateExceptionItems = @[];
    _groupExceptionItems = @[];
    _exceptionsPeers = @{};
    
    [self _updateItems:true];
    [self updateExceptions];
    
    [ActionStageInstance() requestActor:@"/tg/resetPeerSettings" options:nil watcher:TGTelegraphInstance];
}

- (NSArray *)_soundInfoListForSelectedSoundId:(int)selectedSoundId
{
    NSMutableArray *infoList = [[NSMutableArray alloc] init];
    
    int index = -1;
    for (NSString *soundName in [TGAppDelegateInstance modernAlertSoundTitles])
    {
        index++;
        
        int soundId = 0;
        
        if (index == 1)
            soundId = 1;
        else if (index == 0)
            soundId = 0;
        else
            soundId = index + 100 - 1;
        
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
        dict[@"title"] = soundName;
        dict[@"selected"] = @(selectedSoundId == soundId);
        dict[@"soundName"] =  [[NSString alloc] initWithFormat:@"%d", soundId];
        dict[@"soundId"] = @(soundId);
        dict[@"groupId"] = @(0);
        [infoList addObject:dict];
    }
    
    index = -1;
    for (NSString *soundName in [TGAppDelegateInstance classicAlertSoundTitles])
    {
        index++;
        
        int soundId = index + 2;
        
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
        dict[@"title"] = soundName;
        dict[@"selected"] = @(selectedSoundId == soundId);
        dict[@"soundName"] =  [[NSString alloc] initWithFormat:@"%d", soundId];
        dict[@"soundId"] = @(soundId);
        dict[@"groupId"] = @(1);
        [infoList addObject:dict];
    }
    
    return infoList;
}

- (void)privateSoundPressed
{
    _selectingPrivateSound = true;
    TGAlertSoundController *alertSoundController = [[TGAlertSoundController alloc] initWithTitle:TGLocalized(@"Notifications.TextTone") soundInfoList:[self _soundInfoListForSelectedSoundId:[_privateNotificationSettings[@"soundId"] intValue]] defaultId:nil];
    alertSoundController.delegate = self;
    TGNavigationController *navigationController = [TGNavigationController navigationControllerWithControllers:@[alertSoundController]];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        navigationController.presentationStyle = TGNavigationControllerPresentationStyleInFormSheet;
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [self presentViewController:navigationController animated:true completion:nil];
}

- (void)groupSoundPressed
{
    _selectingPrivateSound = false;
    TGAlertSoundController *alertSoundController = [[TGAlertSoundController alloc] initWithTitle:TGLocalized(@"Notifications.TextTone") soundInfoList:[self _soundInfoListForSelectedSoundId:[_groupNotificationSettings[@"soundId"] intValue]] defaultId:nil];
    alertSoundController.delegate = self;
    TGNavigationController *navigationController = [TGNavigationController navigationControllerWithControllers:@[alertSoundController]];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        navigationController.presentationStyle = TGNavigationControllerPresentationStyleInFormSheet;
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [self presentViewController:navigationController animated:true completion:nil];
}

- (void)alertSoundController:(TGAlertSoundController *)__unused alertSoundController didFinishPickingWithSoundInfo:(NSDictionary *)soundInfo
{
    int soundId = [soundInfo[@"soundId"] intValue];
    
    if (soundId >= 0)
    {
        if ((_selectingPrivateSound && [_privateNotificationSettings[@"soundId"] intValue] != soundId) || (!_selectingPrivateSound && [_groupNotificationSettings[@"soundId"] intValue] != soundId))
        {
            int64_t peerId = 0;
            
            if (_selectingPrivateSound)
            {
                peerId = INT_MAX - 1;
                _privateNotificationSettings[@"soundId"] = @(soundId);
            }
            else
            {
                peerId = INT_MAX - 2;
                _groupNotificationSettings[@"soundId"] = @(soundId);
            }
            
            [self _updateItems:false];
            
            static int actionId = 0;
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/changePeerSettings/(%" PRId64 ")/(pc%d)", peerId, actionId++] options:@{
                @"peerId": @(peerId),
                @"soundId": @(soundId)
            } watcher:TGTelegraphInstance];
        }
    }
}

- (void)privateExceptionsPressed
{
    TGNotificationExceptionsController *controller = [[TGNotificationExceptionsController alloc] initWithExceptions:_privateExceptionItems peers:_exceptionsPeers group:false];
    controller.presentation = self.presentation;
    __weak TGNotificationSettingsController *weakSelf = self;
    controller.updatedExceptions = ^(NSArray *exceptions, NSDictionary *peers)
    {
        __strong TGNotificationSettingsController *strongSelf = weakSelf;
        if (strongSelf != nil)
        {
            strongSelf->_privateExceptionItems = exceptions;
            strongSelf->_exceptionsPeers = peers;
            [strongSelf updateExceptions];
        }
    };
    [self.navigationController pushViewController:controller animated:true];
}

- (void)groupExceptionsPressed
{
    TGNotificationExceptionsController *controller = [[TGNotificationExceptionsController alloc] initWithExceptions:_groupExceptionItems peers:_exceptionsPeers group:true];
    controller.presentation = self.presentation;
    __weak TGNotificationSettingsController *weakSelf = self;
    controller.updatedExceptions = ^(NSArray *exceptions, NSDictionary *peers)
    {
        __strong TGNotificationSettingsController *strongSelf = weakSelf;
        if (strongSelf != nil)
        {
            strongSelf->_groupExceptionItems = exceptions;
            strongSelf->_exceptionsPeers = peers;
            [strongSelf updateExceptions];
        }
    };
    [self.navigationController pushViewController:controller animated:true];
}

#pragma mark -

- (void)_updateItems:(bool)animated
{
    [_privateAlert setIsOn:[[_privateNotificationSettings objectForKey:@"muteUntil"] intValue] == 0 animated:animated];
    [_privatePreview setIsOn:[[_privateNotificationSettings objectForKey:@"previewText"] boolValue] animated:animated];
    
    int privateSoundId = [[_privateNotificationSettings objectForKey:@"soundId"] intValue];
    if (privateSoundId == 1)
        privateSoundId = 100;
    
    _privateSound.variant = [TGAlertSoundController soundNameFromId:privateSoundId];
    
    [_groupAlert setIsOn:[[_groupNotificationSettings objectForKey:@"muteUntil"] intValue] == 0 animated:animated];
    [_groupPreview setIsOn:[[_groupNotificationSettings objectForKey:@"previewText"] boolValue] animated:animated];
    
    int groupSoundId = [[_groupNotificationSettings objectForKey:@"soundId"] intValue];
    if (groupSoundId == 1)
        groupSoundId = 100;
    
    _groupSound.variant = [TGAlertSoundController soundNameFromId:groupSoundId];
    
    [_inAppSounds setIsOn:TGAppDelegateInstance.soundEnabled animated:animated];
    [_inAppVibrate setIsOn:TGAppDelegateInstance.vibrationEnabled animated:animated];
    [_inAppPreview setIsOn:TGAppDelegateInstance.bannerEnabled animated:animated];
}

#pragma mark -

- (void)actionStageActionRequested:(NSString *)action options:(id)options
{
    if ([action isEqualToString:@"switchItemChanged"])
    {
        TGSwitchCollectionItem *switchItem = options[@"item"];
        
        if (switchItem == _privateAlert)
        {
            int muteUntil = switchItem.isOn ? 0 : INT_MAX;
            _privateNotificationSettings[@"muteUntil"] = @(muteUntil);
            
            static int actionId = 0;
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/changePeerSettings/(%d)/(pc%d)", INT_MAX - 1, actionId++] options:@{
                @"peerId": @(INT_MAX - 1),
                @"muteUntil": @(muteUntil)
            } watcher:TGTelegraphInstance];
        }
        else if (switchItem == _privatePreview)
        {
            bool previewText = switchItem.isOn;
            _privateNotificationSettings[@"previewText"] = @(previewText);
            
            static int actionId = 0;
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/changePeerSettings/(%d)/(pc%d)", INT_MAX - 1, actionId++] options:@{
                @"peerId": @(INT_MAX - 1),
                @"previewText": @(previewText)
            } watcher:TGTelegraphInstance];
        }
        else if (switchItem == _groupAlert)
        {
            int muteUntil = switchItem.isOn ? 0 : INT_MAX;
            _groupNotificationSettings[@"muteUntil"] = @(muteUntil);

            static int actionId = 0;
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/changePeerSettings/(%d)/(pc%d)", INT_MAX - 2, actionId++] options:@{
                @"peerId": @(INT_MAX - 2),
                @"muteUntil": @(muteUntil)
            } watcher:TGTelegraphInstance];
        }
        else if (switchItem == _groupPreview)
        {
            bool previewText = switchItem.isOn;
            _groupNotificationSettings[@"previewText"] = @(previewText);

            static int actionId = 0;
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/changePeerSettings/(%d)/(pc%d)", INT_MAX - 2, actionId++] options:@{
                @"peerId": @(INT_MAX - 2),
                @"previewText": @(previewText)
            } watcher:TGTelegraphInstance];
        }
        else if (switchItem == _inAppSounds)
        {
            TGAppDelegateInstance.soundEnabled = switchItem.isOn;
            [TGAppDelegateInstance saveSettings];
        }
        else if (switchItem == _inAppVibrate)
        {
            TGAppDelegateInstance.vibrationEnabled = switchItem.isOn;
            [TGAppDelegateInstance saveSettings];
        }
        if (switchItem == _inAppPreview)
        {
            TGAppDelegateInstance.bannerEnabled = switchItem.isOn;
            [TGAppDelegateInstance saveSettings];
        }
    }
}

- (void)actionStageResourceDispatched:(NSString *)path resource:(id)resource arguments:(id)__unused arguments
{
    if ([path hasPrefix:@"/tg/peerSettings"])
    {
        [self actorCompleted:ASStatusSuccess path:path result:resource];
    }
}

- (void)actorCompleted:(int)resultCode path:(NSString *)path result:(id)result
{
    if ([path hasPrefix:@"/tg/peerSettings/"])
    {
        if (resultCode == ASStatusSuccess)
        {
            NSDictionary *notificationSettings = ((SGraphObjectNode *)result).object;
            
            TGDispatchOnMainThread(^
            {
                if ([path hasPrefix:[NSString stringWithFormat:@"/tg/peerSettings/(%d", INT_MAX - 1]])
                {
                    _privateNotificationSettings = [notificationSettings mutableCopy];
                    [self _updateItems:false];
                }
                else if ([path hasPrefix:[NSString stringWithFormat:@"/tg/peerSettings/(%d", INT_MAX - 2]])
                {
                    _groupNotificationSettings = [notificationSettings mutableCopy];
                    [self _updateItems:false];
                }
            });
        }
    }
}

@end
