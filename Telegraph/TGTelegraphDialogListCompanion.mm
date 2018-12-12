#import "TGTelegraphDialogListCompanion.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TGAppDelegate.h"
#import "TGModernConversationController.h"
#import "TGGenericModernConversationCompanion.h"

#import "TGDialogListController.h"

#import <LegacyComponents/SGraphObjectNode.h>
#import <LegacyComponents/SGraphListNode.h>

#import "TGDatabase.h"
#import "TGDialogListItem.h"

#import "TGInterfaceManager.h"
#import "TGInterfaceAssets.h"

#import "TGSelectContactController.h"

#import "TGTelegramNetworking.h"
#import "TGTelegraph.h"

#import "TGForwardTargetController.h"

#import "TGTelegraphConversationMessageAssetsSource.h"

#import "TGModernConversationCompanion.h"

#import <LegacyComponents/TGProgressWindow.h>

#include <map>
#include <set>

#import <libkern/OSAtomic.h>

#import "TGCustomAlertView.h"

#import "TGChannelManagementSignals.h"
#import "TGFeedManagementSignals.h"

#import "TGCreateGroupController.h"

#import "TGLiveLocationSignals.h"
#import "TGLiveLocationManager.h"

#import "TGLegacyComponentsContext.h"
#import <LegacyComponents/TGMenuSheetController.h>
#import <LegacyComponents/TGLocationLiveSessionItemView.h>
#import "TGLiveLocationTitlePanel.h"
#import <LegacyComponents/TGLocationViewController.h>

#import "TGPresentation.h"

#import "TGAdSignals.h"

@interface TGTelegraphDialogListCompanion ()
{
    volatile int32_t _conversationsUpdateTaskId;
    
    TGProgressWindow *_progressWindow;
    
    SMetaDisposable *_stateDisposable;
    
    bool _canLoadMore;
    SMetaDisposable *_liveLocationDisposable;
    TGLiveLocationTitlePanel *_liveLocationPanel;
    
    SMetaDisposable *_adItemDisposable;
    bool _loadedAd;
    
    SMetaDisposable *_unreadDialogsDisposable;
}

@property (nonatomic, strong) NSMutableArray *conversationList;
@property (nonatomic, strong) TGConversation *adConversation;

@property (nonatomic, strong) NSString *searchString;

@property (nonatomic) TGDialogListState state;

@end

@implementation TGTelegraphDialogListCompanion

- (id)init
{
    self = [super init];
    if (self != nil)
    {
        _conversationList = [[NSMutableArray alloc] init];
        
        _actionHandle = [[ASHandle alloc] initWithDelegate:self releaseOnMainThread:false];
        
        self.showSecretInForwardMode = true;
        self.showListEditingControl = true;

        [self resetWatchedNodePaths];
        
        _stateDisposable = [[SMetaDisposable alloc] init];
        _liveLocationDisposable = [[SMetaDisposable alloc] init];
        _adItemDisposable = [[SMetaDisposable alloc] init];
        _unreadDialogsDisposable = [[SMetaDisposable alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_actionHandle reset];
    [ActionStageInstance() removeWatcher:self];
    [_liveLocationDisposable dispose];
    [_stateDisposable dispose];
    [_adItemDisposable dispose];
    
    TGProgressWindow *progressWindow = _progressWindow;
    TGDispatchOnMainThread(^
    {
        [progressWindow dismiss:false];
    });
}

- (id<TGDialogListCellAssetsSource>)dialogListCellAssetsSource
{
    return [TGInterfaceAssets instance];
}

- (void)dialogListReady
{
    [[TGInterfaceManager instance] preload];
    
    SSignal *liveLocationsSignal = [[TGTelegraphInstance.liveLocationManager sessions] map:^id(NSArray *sessions)
    {
        NSMutableArray *liveLocations = [[NSMutableArray alloc] init];
        
        for (TGLiveLocationSession *session in sessions)
        {
            id peer = nil;
            if (TGPeerIdIsUser(session.peerId))
                peer = [TGDatabaseInstance() loadUser:(int32_t)session.peerId];
            else
                peer = [TGDatabaseInstance() loadConversationWithId:session.peerId];
            
            TGMessage *message = [TGDatabaseInstance() loadMessageWithMid:session.messageId peerId:session.peerId];
            [liveLocations addObject:[[TGLiveLocation alloc] initWithMessage:message peer:peer]];
        }
        
        return liveLocations;
    }];
    
    __weak TGTelegraphDialogListCompanion *weakSelf = self;
    [_liveLocationDisposable setDisposable:[[liveLocationsSignal deliverOn:[SQueue mainQueue]] startWithNext:^(NSArray *next)
    {
        __strong TGTelegraphDialogListCompanion *strongSelf = weakSelf;
        if (strongSelf != nil)
            [strongSelf setLiveLocations:next];
    }]];
    
//    NSArray *signals = @[ [self.dialogListController atTopSignal], [[TGDatabaseInstance() unreadDialogsCountSignal] mapToSignal:^SSignal *(NSNumber *total) {
//        return [[[self.dialogListController visibleUnreadDialogsCountSignal] delay:0.1 onQueue:[SQueue mainQueue]] mapToSignal:^SSignal *(NSNumber *visible)
//        {
//            int32_t totalUnreadCount = [total int32Value];
//            int32_t visibleUnreadCount = [visible int32Value];
//            return [SSignal single:@(visibleUnreadCount < totalUnreadCount)];
//        }];
//    }]];
//
//    [_unreadDialogsDisposable setDisposable:[[[SSignal combineSignals:signals] deliverOn:[SQueue mainQueue]] startWithNext:^(NSArray *next) {
//        bool atTop = [next[0] boolValue];
//        bool downArrow = [next[1] boolValue];
//
//        NSNumber *arrow = nil;
//        if (atTop) {
//            if (downArrow)
//                arrow = @false;
//            else
//                arrow = nil;
//        }
//        else if (!atTop) {
//            arrow = @true;
//        }
//
//        [TGAppDelegateInstance.rootController.mainTabsController setUnreadArrow:arrow];
//    }]];
}

- (void)setLiveLocations:(NSArray *)liveLocations
{
    __weak TGTelegraphDialogListCompanion *weakSelf = self;
    if (liveLocations.count > 0)
    {
        if (_liveLocationPanel == nil)
            _liveLocationPanel = [[TGLiveLocationTitlePanel alloc] init];
        
        _liveLocationPanel.tapped = ^
        {
            __strong TGTelegraphDialogListCompanion *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            [strongSelf presentLiveLocationsMenu:liveLocations];
        };
        _liveLocationPanel.closed = ^
        {
            __strong TGTelegraphDialogListCompanion *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            [strongSelf presentLiveLocationsMenu:liveLocations];
        };
    
        [_liveLocationPanel setSessions:liveLocations];
        [self.dialogListController setCurrentTitlePanel:_liveLocationPanel];
    }
    else
    {
        [self.dialogListController setCurrentTitlePanel:nil];
    }
}

- (void)resetWatchedNodePaths
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [ActionStageInstance() removeWatcher:self];

        [ActionStageInstance() watchForPath:@"/tg/conversations" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/broadcastConversations" watcher:self];
        [ActionStageInstance() watchForGenericPath:@"/tg/dialoglist/@" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/userdatachanges" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/unreadCount" watcher:self];
        //[ActionStageInstance() watchForPath:@"/tg/unreadChatsCount" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/conversation/*/typing" watcher:self];
        [ActionStageInstance() watchForPath:@"/tg/contactlist" watcher:self];
        [ActionStageInstance() watchForPath:@"/databasePasswordChanged" watcher:self];
        [ActionStageInstance() watchForGenericPath:@"/tg/conversationsGrouped/@" watcher:self];
        
        [ActionStageInstance() watchForGenericPath:@"/tg/peerSettings/@" watcher:self];
        
        [ActionStageInstance() watchForPath:@"/tg/service/synchronizationstate" watcher:self];
        [ActionStageInstance() requestActor:@"/tg/service/synchronizationstate" options:nil watcher:self];
        
        int unreadCount = [TGDatabaseInstance() databaseState].unreadCount;
        [self actionStageResourceDispatched:@"/tg/unreadCount" resource:[[SGraphObjectNode alloc] initWithObject:[NSNumber numberWithInt:unreadCount]] arguments:@{@"previous": @true}];
        
//        int unreadCount = [TGDatabaseInstance() databaseState].unreadCount;
//        [self actionStageResourceDispatched:@"/tg/unreadCount" resource:[[SGraphObjectNode alloc] initWithObject:@(unreadCount)] arguments:@{@"previous": @true}];
//
//        int unreadChatsCount = [TGDatabaseInstance() unreadChatsCount];
//        [self actionStageResourceDispatched:@"/tg/unreadChatsCount" resource:[[SGraphObjectNode alloc] initWithObject:@(unreadChatsCount)] arguments:@{@"previous": @true}];
        
        [_adItemDisposable setDisposable:nil];
        _loadedAd = false;
    }];
}

- (void)clearData
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [_conversationList removeAllObjects];
        _adConversation = nil;
        
        [self resetWatchedNodePaths];
        
        _canLoadMore = false;
        
        dispatch_async(dispatch_get_main_queue(), ^
        {
            TGDialogListController *controller = self.dialogListController;
            if (controller != nil)
            {
                controller.canLoadMore = false;
                [controller dialogListFullyReloaded:[[NSArray alloc] init]];
                [controller resetState];
            }
        });
    }];
}

- (void)composeMessageAndOpenSearch:(bool)openSearch
{
    if ([TGAppDelegateInstance isDisplayingPasscodeWindow])
        return;
    
    TGDialogListController *controller = self.dialogListController;
    [controller selectConversationWithId:0];
    
    TGSelectContactController *selectController = [[TGSelectContactController alloc] initWithCreateGroup:false createEncrypted:false createBroadcast:false createChannel:false inviteToChannel:false showLink:false];
    selectController.shouldOpenSearch = openSearch;
    [TGAppDelegateInstance.rootController pushContentController:selectController];
}

- (void)navigateToBroadcastLists
{
    TGCreateGroupController *controller = [[TGCreateGroupController alloc] initWithCreateChannel:true createChannelGroup:false];
    [TGAppDelegateInstance.rootController pushContentController:controller];
}

- (void)navigateToNewGroup
{
    __autoreleasing NSString *disabledMessage = nil;
    if (![TGApplicationFeatures isGroupCreationEnabled:&disabledMessage])
    {
        [TGCustomAlertView presentAlertWithTitle:TGLocalized(@"FeatureDisabled.Oops") message:disabledMessage cancelButtonTitle:TGLocalized(@"Common.OK") okButtonTitle:nil completionBlock:nil];
        return;
    }
    
    TGDialogListController *controller = self.dialogListController;
    [controller selectConversationWithId:0];
    
    TGSelectContactController *selectController = [[TGSelectContactController alloc] initWithCreateGroup:true createEncrypted:false createBroadcast:false createChannel:false inviteToChannel:false showLink:false];
    [TGAppDelegateInstance.rootController pushContentController:selectController];
}

- (void)conversationSelected:(TGConversation *)conversation
{    
    if (self.forwardMode || self.privacyMode || self.showPrivateOnly || self.showGroupsAndChannelsOnly)
    {
        [_conversatioSelectedWatcher requestAction:@"conversationSelected" options:[[NSDictionary alloc] initWithObjectsAndKeys:conversation, @"conversation", nil]];
    }
    else
    {
        if ([conversation isKindOfClass:[TGFeed class]])
        {
            [[TGInterfaceManager instance] navigateToChannelsFeed:((TGFeed *)conversation).fid animated:true];
        }
        else
        {
            if (conversation.isBroadcast)
            {
                
            }
            else
            {
                int64_t conversationId = conversation.conversationId;
                if (TGPeerIdIsChannel(conversationId) && conversation.kind == TGConversationKindTemporaryChannel) {
                    TGProgressWindow *progressWindow = [[TGProgressWindow alloc] init];
                    [progressWindow showWithDelay:0.1];
                    [[[[TGChannelManagementSignals preloadedChannel:conversationId] deliverOn:[SQueue mainQueue]] onDispose:^{
                        TGDispatchOnMainThread(^{
                            [progressWindow dismiss:true];
                        });
                    }] startWithNext:nil completed:^{
                        [[TGInterfaceManager instance] navigateToConversationWithId:conversationId conversation:conversation performActions:nil atMessage:nil clearStack:true openKeyboard:false canOpenKeyboardWhileInTransition:true animated:true];
                    }];
                } else {
                    [[TGInterfaceManager instance] navigateToConversationWithId:conversationId conversation:conversation performActions:nil atMessage:nil clearStack:true openKeyboard:false canOpenKeyboardWhileInTransition:true animated:true];
                }
            }
        }
    }
}

- (void)searchResultSelectedConversation:(TGConversation *)conversation
{
    [self conversationSelected:conversation];
}

- (void)searchResultSelectedConversation:(TGConversation *)conversation atMessageId:(int)messageId
{
    if (!self.forwardMode && !self.privacyMode)
    {
        if ([TGDatabaseInstance() loadMessageWithMid:messageId peerId:conversation.conversationId] != nil)
        {
            int64_t conversationId = conversation.conversationId;
            [[TGInterfaceManager instance] navigateToConversationWithId:conversationId conversation:conversation performActions:nil atMessage:@{@"mid": @(messageId)} clearStack:true openKeyboard:false canOpenKeyboardWhileInTransition:false animated:true];
        }
        else
        {
            _progressWindow = [[TGProgressWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            [_progressWindow show:true];
            
            [ActionStageInstance() requestActor:[[NSString alloc] initWithFormat:@"/tg/loadConversationAndMessageForSearch/(%" PRId64 ", %" PRId32 ")", conversation.conversationId, messageId] options:@{@"peerId": @(conversation.conversationId), @"accessHash": @(conversation.accessHash), @"messageId": @(messageId)} flags:0 watcher:self];
        }
    }
}

- (void)searchResultSelectedMessage:(TGMessage *)__unused message
{
    
}

- (bool)shouldDisplayEmptyListPlaceholder
{
    return TGTelegraphInstance.clientUserId != 0;
}

- (void)wakeUp
{
}

- (void)resetLocalization
{
    
}

- (int64_t)openedConversationId
{
    UIViewController *topViewController = [TGAppDelegateInstance.rootController.viewControllers lastObject];

    if ([topViewController isKindOfClass:[TGModernConversationController class]])
    {
        return ((TGGenericModernConversationCompanion *)((TGModernConversationController *)(topViewController)).companion).conversationId;
    }
    
    return 0;
}

- (void)scrollToNextUnreadChat {
    [[self.dialogListController.atTopSignal take:1] startWithNext:^(NSNumber *atTop)
    {
        if (atTop.boolValue)
        {
            [TGDatabaseInstance() loadUnreadConversationListFromDate:0 limit:400 completion:^(NSArray<TGConversation *> *result) {
                TGDispatchOnMainThread(^{
                    int64_t earliestUnreadConversationId = result.firstObject.conversationId;
                    if (earliestUnreadConversationId != 0) {
                        [self.dialogListController scrollToConversationWithId:earliestUnreadConversationId];
                    }
                    else {
                        [self.dialogListController scrollToTop];
                        
                        int unreadCount = [TGDatabaseInstance() unreadChatsCount] + [TGDatabaseInstance() unreadChannelsCount];
                        if (unreadCount > 0)
                            [TGDatabaseInstance() transactionCalculateUnreadChats];
                    }
                });
            }];
        }
        else
        {
            int64_t anchorConversationId = self.dialogListController.currentVisibleUnreadConversation;
            
            TGConversation *conversation = [TGDatabaseInstance() loadConversationWithId:anchorConversationId];
            [TGDatabaseInstance() loadUnreadConversationListFromDate:conversation.date limit:1 completion:^(NSArray<TGConversation *> *result) {
                TGDispatchOnMainThread(^{
                    int64_t nextUnreadConversationId = result.firstObject.conversationId;
                    if (nextUnreadConversationId != 0)
                        [self.dialogListController scrollToConversationWithId:nextUnreadConversationId];
                    else
                        [self.dialogListController scrollToTop];
                });
            }];
        }
    }];
}

- (void)hintMoveConversationAtIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex
{
    [ActionStageInstance() dispatchOnStageQueue:^{
        NSMutableArray *previousConversationIds = [[NSMutableArray alloc] init];
        for (TGConversation *conversation in _conversationList) {
            [previousConversationIds addObject:@(conversation.conversationId)];
        }
        
        id object = [_conversationList objectAtIndex:fromIndex];
        [_conversationList removeObjectAtIndex:fromIndex];
        [_conversationList insertObject:object atIndex:toIndex];
        
        NSMutableArray *conversationIds = [[NSMutableArray alloc] init];
        int32_t nextPinnedDate = TGConversationPinnedDateBase;
        for (NSUInteger i = 0; i < _conversationList.count; i++) {
            TGConversation *conversation = _conversationList[i];
            if (conversation.pinnedDate != 0) {
                nextPinnedDate += 1;
            }
        }
        for (NSUInteger i = 0; i < _conversationList.count; i++) {
            TGConversation *conversation = _conversationList[i];
            if (conversation.pinnedDate != 0) {
                nextPinnedDate -= 1;
                
                conversation = [conversation copy];
                conversation.pinnedDate = nextPinnedDate;
                [_conversationList replaceObjectAtIndex:i withObject:conversation];
            }
            [conversationIds addObject:@(conversation.conversationId)];
        }
        
        //TGLog(@"move %@ to %@", [previousConversationIds subarrayWithRange:NSMakeRange(0, 6)], [conversationIds subarrayWithRange:NSMakeRange(0, 6)]);
    }];
}

- (bool)isConversationOpened:(int64_t)conversationId
{
    UIViewController *topViewController = [TGAppDelegateInstance.rootController.viewControllers lastObject];
    
    if ([topViewController isKindOfClass:[TGModernConversationController class]])
    {
        return ((TGGenericModernConversationCompanion *)((TGModernConversationController *)(topViewController)).companion).conversationId == conversationId;
    }
    
    return false;
}

- (void)deleteItem:(TGConversation *)conversation animated:(bool)animated
{
    [self deleteItem:conversation animated:animated interfaceOnly:false];
}

- (void)deleteItem:(TGConversation *)conversation animated:(bool)animated interfaceOnly:(bool)interfaceOnly
{
    TGDispatchOnMainThread(^
    {
        if ([self isConversationOpened:conversation.conversationId]) {
            [TGAppDelegateInstance.rootController clearContentControllers];
        }
    });
    
    int64_t conversationId = conversation.conversationId;
    [TGTelegraphInstance.liveLocationManager stopWithPeerId:conversationId];
    
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        bool found = false;
        for (int i = 0; i < (int)self.conversationList.count; i++)
        {
            TGConversation *conversation = [self.conversationList objectAtIndex:i];
            if (TGPeerIdIsAd(conversation.conversationId)) {
                continue;
            }
            if (conversation.conversationId == conversationId)
            {
                found = true;
                [self.conversationList removeObjectAtIndex:i];
                
                NSNumber *removedIndex = [[NSNumber alloc] initWithInt:i];
                
                if (!interfaceOnly)
                {
                    if ([conversation isKindOfClass:[TGConversation class]])
                    {
                        [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/conversation/(%lld)/delete", conversationId] options:@{@"conversationId": @(conversationId), @"block": @true} watcher:self];
                    }
                    else
                    {
                        TGFeed *feed = (TGFeed *)conversation;
                        [[TGFeedManagementSignals updateFeedChannels:feed.fid peerIds:[NSSet set] alsoNewlyJoined:false] startWithNext:nil];
                    }
                }
                
                dispatch_async(dispatch_get_main_queue(), ^
                {
                    if (!animated)
                        [UIView setAnimationsEnabled:false];
                    TGDialogListController *dialogListController = self.dialogListController;
                    [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:nil updatedItems:nil removedIndices:[NSArray arrayWithObject:removedIndex]];
                    if (!animated)
                        [UIView setAnimationsEnabled:true];
                });
                
                break;
            }
        }
        
        if (!found && !interfaceOnly)
        {
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/conversation/(%lld)/delete", conversationId] options:[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:conversationId] forKey:@"conversationId"] watcher:self];
        }
    }];
}

- (void)clearItem:(TGConversation *)conversation animated:(bool)animated
{
    int64_t conversationId = conversation.conversationId;
 
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        for (int i = 0; i < (int)self.conversationList.count; i++)
        {
            TGConversation *conversation = [self.conversationList objectAtIndex:i];
            if (conversation.conversationId == conversationId && !TGPeerIdIsAd(conversation.conversationId))
            {
                [self.conversationList removeObjectAtIndex:i];
                
                TGUser *user = conversation.conversationId > 0 ? [TGDatabaseInstance() loadUser:(int)conversation.conversationId] : nil;
                if (user != nil && (user.kind == TGUserKindBot || user.kind == TGUserKindSmartBot))
                {
                    NSNumber *removedIndex = [[NSNumber alloc] initWithInt:i];
                    
                    [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/conversation/(%lld)/delete", conversationId] options:@{@"conversationId": @(conversationId), @"block": @false} watcher:self];
                    
                    dispatch_async(dispatch_get_main_queue(), ^
                    {
                        if (!animated)
                            [UIView setAnimationsEnabled:false];
                        TGDialogListController *dialogListController = self.dialogListController;
                        [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:nil updatedItems:nil removedIndices:[NSArray arrayWithObject:removedIndex]];
                        if (!animated)
                            [UIView setAnimationsEnabled:true];
                    });
                }
                else
                {
                    int actionId = 0;
                    [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/conversation/(%lld)/clearHistory/(dialogList%d)", conversationId, actionId++] options:[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:conversationId] forKey:@"conversationId"] watcher:self];
                    
                    conversation = [conversation copy];

                    conversation.outgoing = false;
                    conversation.text = nil;
                    conversation.media = nil;
                    conversation.unread = false;
                    conversation.unreadCount = 0;
                    conversation.fromUid = 0;
                    conversation.deliveryError = false;
                    conversation.deliveryState = TGMessageDeliveryStateDelivered;
                    
                    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:conversation.dialogListData];
                    dict[@"authorName"] = @"";
                    
                    dispatch_async(dispatch_get_main_queue(), ^
                    {
                        if (!animated)
                            [UIView setAnimationsEnabled:false];
                        TGDialogListController *dialogListController = self.dialogListController;
                        [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:@[@(i)] updatedItems:@[conversation] removedIndices:nil];
                        if (!animated)
                            [UIView setAnimationsEnabled:true];
                    });
                }
                
                break;
            }
        }
    }];
}

- (void)maybeLoadAd:(SAtomic *)syncResult {
    if (!_loadedAd && TGTelegraphInstance.clientUserId != 0) {
        _loadedAd = true;
        __weak TGTelegraphDialogListCompanion *weakSelf = self;
        [_adItemDisposable setDisposable:[[TGAdSignals adChatListConversation] startWithNext:^(TGConversation *conversation) {
            conversation = [conversation copy];
            conversation.conversationId = TGPeerIdFromAdId(TGChannelIdFromPeerId(conversation.conversationId));
            [ActionStageInstance() dispatchOnStageQueue:^{
                __strong TGTelegraphDialogListCompanion *strongSelf = weakSelf;
                if (strongSelf == nil) {
                    return;
                }
                
                if (_adConversation != nil) {
                    for (NSUInteger i = 0; i < _conversationList.count; i++) {
                        if (((TGConversation *)_conversationList[i]).conversationId == _adConversation.conversationId) {
                            [_conversationList removeObjectAtIndex:i];
                            break;
                        }
                    }
                }
                [self initializeDialogListData:conversation customUser:nil selfUser:nil];
                _adConversation = conversation;
                if (_adConversation != nil) {
                    [_conversationList insertObject:conversation atIndex:0];
                }
                NSNumber *isSync = [syncResult swap:@false];
                if (isSync == nil || ![isSync boolValue]) {
                    NSArray *items = [NSArray arrayWithArray:_conversationList];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        TGDialogListController *controller = self.dialogListController;
                        if (controller != nil) {
                            [controller dialogListFullyReloaded:items];
                        }
                    });
                }
            }];
        }]];
    }
}

- (void)loadMoreItems
{
    [self loadMoreItems:0];
}

- (void)loadMoreItems:(int)limit
{
    if (limit == 0)
        limit = 40;
    
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        NSMutableArray *currentConversationIds = [[NSMutableArray alloc] initWithCapacity:_conversationList.count];
        
        [self maybeLoadAd:nil];
        
        int minDate = INT_MAX;
        for (TGConversation *conversation in _conversationList)
        {
            if (TGPeerIdIsAd(conversation.conversationId)) {
                continue;
            }
            if (![conversation isKindOfClass:[TGConversation class]])
                continue;
            
            if (conversation.date < minDate && !conversation.isBroadcast)
                minDate = conversation.date;
            
            [currentConversationIds addObject:[[NSNumber alloc] initWithLongLong:conversation.conversationId]];
        }
        
        if (minDate != INT_MAX)
        {
            [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/dialoglist/(%d)", minDate] options:[NSDictionary dictionaryWithObjectsAndKeys:@(limit), @"limit", [NSNumber numberWithInt:minDate], @"date", currentConversationIds, @"excludeConversationIds", nil] watcher:self];
        }
        else
        {
            _canLoadMore = false;
            
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                
                dialogListController.canLoadMore = false;
                [dialogListController dialogListFullyReloaded:[NSArray array]];
            });
        }
    }];
}

- (void)beginSearch:(NSString *)queryString inMessages:(bool)inMessages
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        [self resetWatchedNodePaths];

        self.searchString = [[queryString stringByReplacingOccurrencesOfString:@" +" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, queryString.length)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (self.searchString.length == 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                [dialogListController searchResultsReloaded:nil searchString:nil];
            });
        } 
        else
        {
            if (inMessages)
            {
                [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/search/messages/(%lu)", (unsigned long)[self.searchString hash]] options:[NSDictionary dictionaryWithObject:self.searchString forKey:@"query"] watcher:self];
            }
            else
            {
                [ActionStageInstance() requestActor:[NSString stringWithFormat:@"/tg/search/dialogs/(%lu)", (unsigned long)[self.searchString hash]] options:[NSDictionary dictionaryWithObject:self.searchString forKey:@"query"] watcher:self];
            }
        }
    }];
}

- (void)searchResultSelectedUser:(TGUser *)user
{
    if (self.forwardMode || self.privacyMode || self.showPrivateOnly || self.showGroupsAndChannelsOnly)
    {
        [_conversatioSelectedWatcher requestAction:@"userSelected" options:[[NSDictionary alloc] initWithObjectsAndKeys:user, @"user", nil]];
    }
    else
    {
        int64_t conversationId = user.uid;
        [[TGInterfaceManager instance] navigateToConversationWithId:conversationId conversation:nil];
    }
}

- (NSString *)stringForMemberCount:(int)memberCount
{
    return [effectiveLocalization() getPluralized:@"Conversation.StatusRecipients" count:(int32_t)memberCount];
}

- (void)initializeDialogListData:(TGConversation *)conversation customUser:(TGUser *)customUser selfUser:(TGUser *)selfUser
{
    if (![conversation isKindOfClass:[TGConversation class]])
        return;
    
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    
    int64_t mutePeerId = conversation.conversationId;
    
    dict[@"authorIsSelf"] = @(conversation.fromUid == TGTelegraphInstance.clientUserId);
    dict[@"isSavedMessages"] = conversation.conversationId == TGTelegraphInstance.clientUserId ? (self.forwardMode ? @2 : @1) : @0;
    
    if (conversation.isChannel) {
        dict[@"isChannel"] = @true;
        dict[@"isChannelGroup"] = @(conversation.isChannelGroup);
        
        [dict setObject:(conversation.chatTitle == nil ? @"" : conversation.chatTitle) forKey:@"title"];
        
        if (conversation.chatPhotoSmall.length != 0)
            [dict setObject:conversation.chatPhotoFullSmall forKey:@"avatarUrl"];
        
        [dict setObject:[NSNumber numberWithBool:true] forKey:@"isChat"];
        [dict setObject:[NSNumber numberWithBool:conversation.isVerified] forKey:@"isVerified"];
        
        NSString *authorName = nil;
        NSString *authorAvatarUrl = nil;
        if (conversation.fromUid == selfUser.uid)
        {
            authorAvatarUrl = selfUser.photoUrlSmall;
            
            static NSString *youString = nil;
            if (youString == nil)
                youString = authorNameYou;
            
            if (conversation.text.length != 0 || conversation.media.count != 0)
                authorName = youString;
        }
        else
        {
            if (conversation.fromUid != 0)
            {
                TGUser *authorUser = [[TGDatabase instance] loadUser:conversation.fromUid];
                if (authorUser != nil)
                {
                    authorAvatarUrl = authorUser.photoUrlSmall;
                    authorName = authorUser.displayName;
                }
            }
        }
        
        if (authorAvatarUrl != nil)
            [dict setObject:authorAvatarUrl forKey:@"authorAvatarUrl"];
        if (authorName != nil)
            [dict setObject:authorName forKey:@"authorName"];
    }
    else if (!conversation.isChat || conversation.isEncrypted)
    {
        int32_t userId = 0;
        if (conversation.isEncrypted)
        {
            if (conversation.chatParticipants.chatParticipantUids.count != 0)
                userId = [conversation.chatParticipants.chatParticipantUids[0] intValue];
        }
        else
            userId = (int)conversation.conversationId;
        mutePeerId = userId;
        
        TGUser *user = nil;
        if (customUser != nil && customUser.uid == userId)
            user = customUser;
        else
            user = [[TGDatabase instance] loadUser:(int)userId];
        
        dict[@"isVerified"] = @(user.isVerified);
        
        NSString *title = nil;
        NSArray *titleLetters = nil;
        
        if (user.uid == [TGTelegraphInstance serviceUserUid] || user.uid == [TGTelegraphInstance voipSupportUserUid])
            title = [user displayName];
        else if ((user.phoneNumber.length != 0 && ![TGDatabaseInstance() uidIsRemoteContact:user.uid]))
            title = user.formattedPhoneNumber;
        else
            title = [user displayName];
        
        if (user.kind == TGUserKindBot || user.kind == TGUserKindSmartBot) {
            dict[@"isBot"] = @true;
        }
        
        if (user.firstName.length != 0 && user.lastName.length != 0)
            titleLetters = [[NSArray alloc] initWithObjects:user.firstName, user.lastName, nil];
        else if (user.firstName.length != 0)
            titleLetters = [[NSArray alloc] initWithObjects:user.firstName, nil];
        else if (user.lastName.length != 0)
            titleLetters = [[NSArray alloc] initWithObjects:user.lastName, nil];
        
        if (title != nil)
            [dict setObject:title forKey:@"title"];
        
        if (titleLetters != nil)
            dict[@"titleLetters"] = titleLetters;
        
        dict[@"isEncrypted"] = [[NSNumber alloc] initWithBool:conversation.isEncrypted];
        if (conversation.isEncrypted)
        {
            dict[@"encryptionStatus"] = [[NSNumber alloc] initWithInt:conversation.encryptedData.handshakeState];
            dict[@"encryptionOutgoing"] = [[NSNumber alloc] initWithBool:conversation.chatParticipants.chatAdminId == TGTelegraphInstance.clientUserId];
            NSString *firstName = user.displayFirstName;
            dict[@"encryptionFirstName"] = firstName != nil ? firstName : @"";

            if (user.firstName != nil)
                dict[@"firstName"] = user.firstName;
            if (user.lastName != nil)
                dict[@"lastName"] = user.lastName;
        }
        dict[@"encryptedUserId"] = [[NSNumber alloc] initWithInt:userId];
        
        if (user.photoUrlSmall != nil)
            [dict setObject:user.photoFullUrlSmall forKey:@"avatarUrl"];
        [dict setObject:[NSNumber numberWithBool:false] forKey:@"isChat"];
        
        NSString *authorAvatarUrl = nil;
        if (selfUser != nil)
            authorAvatarUrl = selfUser.photoUrlSmall;
        
        if (authorAvatarUrl != nil)
            [dict setObject:authorAvatarUrl forKey:@"authorAvatarUrl"];
        
        if (conversation.media.count != 0)
        {
            NSString *authorName = nil;
            if (conversation.fromUid == selfUser.uid)
            {
                static NSString *youString = nil;
                if (youString == nil)
                    youString = authorNameYou;
                
                authorName = youString;
            }
            else
            {
                if (conversation.fromUid != 0)
                {
                    TGUser *authorUser = [[TGDatabase instance] loadUser:conversation.fromUid];
                    if (authorUser != nil)
                    {
                        authorName = authorUser.displayName;
                    }
                }
            }
            
            if (authorName != nil)
                [dict setObject:authorName forKey:@"authorName"];
        }
    }
    else
    {
        dict[@"isBroadcast"] = @(conversation.isBroadcast);
        
        if (conversation.isBroadcast && conversation.chatTitle.length == 0)
            dict[@"title"] = [self stringForMemberCount:conversation.chatParticipantCount];
        else
            [dict setObject:(conversation.chatTitle == nil ? @"" : conversation.chatTitle) forKey:@"title"];
        
        if (conversation.chatPhotoSmall.length != 0)
            [dict setObject:conversation.chatPhotoFullSmall forKey:@"avatarUrl"];
        
        [dict setObject:[NSNumber numberWithBool:true] forKey:@"isChat"];
        
        NSString *authorName = nil;
        NSString *authorAvatarUrl = nil;
        if (conversation.fromUid == selfUser.uid)
        {
            authorAvatarUrl = selfUser.photoUrlSmall;
            
            static NSString *youString = nil;
            if (youString == nil)
                youString = authorNameYou;
            
            if (conversation.text.length != 0 || conversation.media.count != 0)
                authorName = youString;
        }
        else
        {
            if (conversation.fromUid != 0)
            {
                TGUser *authorUser = [[TGDatabase instance] loadUser:conversation.fromUid];
                if (authorUser != nil)
                {
                    authorAvatarUrl = authorUser.photoUrlSmall;
                    authorName = authorUser.displayName;
                }
            }
        }
        
        if (authorAvatarUrl != nil)
            [dict setObject:authorAvatarUrl forKey:@"authorAvatarUrl"];
        if (authorName != nil)
            [dict setObject:authorName forKey:@"authorName"];
    }
    
    if (conversation.draft != nil) {
        dict[@"draft"] = conversation.draft;
    }
    
    NSMutableDictionary *messageUsers = [[NSMutableDictionary alloc] init];
    for (TGMediaAttachment *attachment in conversation.media)
    {
        if (attachment.type == TGActionMediaAttachmentType)
        {
            TGActionMediaAttachment *actionAttachment = (TGActionMediaAttachment *)attachment;
            if (actionAttachment.actionType == TGMessageActionChatAddMember || actionAttachment.actionType == TGMessageActionChatDeleteMember || actionAttachment.actionType == TGMessageActionChannelInviter)
            {
                NSArray *uids = actionAttachment.actionData[@"uids"];
                if (uids != nil) {
                    for (NSNumber *nUid in uids) {
                        TGUser *user = [TGDatabaseInstance() loadUser:[nUid intValue]];
                        if (user != nil)
                            [messageUsers setObject:user forKey:nUid];
                    }
                } else {
                    NSNumber *nUid = [actionAttachment.actionData objectForKey:@"uid"];
                    if (nUid != nil)
                    {
                        TGUser *user = [TGDatabaseInstance() loadUser:[nUid intValue]];
                        if (user != nil)
                            [messageUsers setObject:user forKey:nUid];
                    }
                }
            }
            if (actionAttachment.actionType == TGMessageActionSecureValuesSent)
            {
                TGUser *user = [TGDatabaseInstance() loadUser:(int32_t)conversation.conversationId];
                if (user != nil)
                    [messageUsers setObject:user forKey:@((int32_t)conversation.conversationId)];
            }
            TGUser *user = conversation.fromUid == selfUser.uid ? selfUser : [TGDatabaseInstance() loadUser:(int)conversation.fromUid];
            if (user != nil)
            {
                [messageUsers setObject:user forKey:[[NSNumber alloc] initWithInt:user.uid]];
                [messageUsers setObject:user forKey:@"author"];
            }
        }
    }
    
    
    [dict setObject:[[NSNumber alloc] initWithBool:[TGDatabaseInstance() isPeerMuted:mutePeerId]] forKey:@"mute"];
    
    [dict setObject:messageUsers forKey:@"users"];
    
    conversation.dialogListData = dict;
}

- (void)presentLiveLocationsMenu:(NSArray *)liveLocations
{
    if (liveLocations.count == 1)
    {
        [self openLiveLocation:liveLocations.firstObject];
        return;
    }
    
    TGMenuSheetController *controller = [[TGMenuSheetController alloc] initWithContext:[TGLegacyComponentsContext shared] dark:false];
    controller.dismissesByOutsideTap = true;
    controller.narrowInLandscape = true;
    controller.hasSwipeGesture = true;
    
    __weak TGTelegraphDialogListCompanion *weakSelf = self;
    __weak TGMenuSheetController *weakController = controller;
    NSMutableArray *items = [[NSMutableArray alloc] init];
    
    NSString *formatPrefix = [TGStringUtils integerValueFormat:@"LiveLocation.MenuChatsCount_" value:liveLocations.count];
    NSString *title = [[NSString alloc] initWithFormat:TGLocalized(formatPrefix), [[NSString alloc] initWithFormat:@"%ld", liveLocations.count]];
    [items addObject:[[TGMenuSheetTitleItemView alloc] initWithTitle:nil subtitle:title]];
    for (TGLiveLocation *liveLocation in liveLocations)
    {
        [items addObject:[[TGLocationLiveSessionItemView alloc] initWithMessage:liveLocation.message peer:liveLocation.peer remaining:[TGLiveLocationSignals remainingTimeForMessage:liveLocation.message] action:^
        {
            __strong TGMenuSheetController *strongController = weakController;
            if (strongController == nil)
                return;
            
            [strongController dismissAnimated:true];
            
            __strong TGTelegraphDialogListCompanion *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            [strongSelf openLiveLocation:liveLocation];
        }]];
    }
    [items addObject:[[TGMenuSheetButtonItemView alloc] initWithTitle:TGLocalized(@"LiveLocation.MenuStopAll") type:TGMenuSheetButtonTypeDestructive action:^
    {
        __strong TGMenuSheetController *strongController = weakController;
        if (strongController == nil)
            return;
        
        [strongController dismissAnimated:true];
        
        for (TGLiveLocation *liveLocation in liveLocations)
        {
            [TGTelegraphInstance.liveLocationManager stopWithPeerId:[liveLocation peerId]];
        }
    }]];
    
    [items addObject:[[TGMenuSheetButtonItemView alloc] initWithTitle:TGLocalized(@"Common.Cancel") type:TGMenuSheetButtonTypeCancel action:^
    {
        __strong TGMenuSheetController *strongController = weakController;
        if (strongController != nil)
            [strongController dismissAnimated:true];
    }]];

    
    [controller setItemViews:items];
    controller.sourceRect = ^
    {
        __strong TGTelegraphDialogListCompanion *strongSelf = weakSelf;
        if (strongSelf == nil)
            return CGRectZero;
        
        return [strongSelf->_liveLocationPanel convertRect:strongSelf->_liveLocationPanel.bounds toView:strongSelf.dialogListController.view];
    };
    controller.permittedArrowDirections = UIPopoverArrowDirectionUp;
    [controller presentInViewController:self.dialogListController sourceView:self.dialogListController.view animated:true];
}

- (void)openLiveLocation:(TGLiveLocation *)liveLocationToOpen
{
    liveLocationToOpen = [[TGLiveLocation alloc] initWithMessage:[TGDatabaseInstance() loadMessageWithMid:liveLocationToOpen.message.mid peerId:liveLocationToOpen.message.cid] peer:[TGDatabaseInstance() loadUser:TGTelegraphInstance.clientUserId] hasOwnSession:true isOwnLocation:true isExpired:false];
    
    TGConversation *chat = [TGDatabaseInstance() loadConversationWithId:liveLocationToOpen.message.cid];
    bool isChannel = chat.isChannel && !chat.isChannelGroup;
    
    TGLocationViewController *controller = [[TGLocationViewController alloc] initWithContext:[TGLegacyComponentsContext shared] liveLocation:liveLocationToOpen];
    controller.pallete = self.dialogListController.presentation.locationPallete;
    [controller setFrequentUpdatesHandle:[TGTelegraphInstance.liveLocationManager subscribeForFrequentLocationUpdatesWithPeerId:liveLocationToOpen.message.cid]];
    controller.modalMode = true;
    controller.allowLiveLocationSharing = true;
    controller.zoomToFitAllLocationsOnScreen = true;
    __weak TGLocationViewController *weakLocationController = controller;
    controller.liveLocationStopped = ^
    {
        __strong TGLocationViewController *strongLocationController = weakLocationController;
        if (strongLocationController != nil)
            [strongLocationController.presentingViewController dismissViewControllerAnimated:true completion:nil];
        [TGTelegraphInstance.liveLocationManager stopWithPeerId:liveLocationToOpen.message.cid];
    };
    controller.remainingTimeForMessage = ^SSignal *(TGMessage *message)
    {
        return [TGLiveLocationSignals remainingTimeForMessage:message];
    };
    [controller setLiveLocationsSignal:[[TGLiveLocationSignals liveLocationsForPeerId:liveLocationToOpen.message.cid includeExpired:true onlyLocal:isChannel] map:^id(NSArray *messages)
    {
        int32_t currentTime = (int32_t)[[TGTelegramNetworking instance] globalTime];
        
        NSMutableArray *liveLocations = [[NSMutableArray alloc] init];
        for (TGMessage *message in messages)
        {
            int32_t expires = (int32_t)message.date;
            for (TGMediaAttachment *attachment in message.mediaAttachments)
            {
                if (attachment.type == TGLocationMediaAttachmentType)
                {
                    expires += ((TGLocationMediaAttachment *)attachment).period;
                    break;
                }
            }
            
            id peer = nil;
            int64_t peerId = message.fromUid;
            if (TGPeerIdIsChannel(peerId))
                peer = [TGDatabaseInstance() loadChannels:@[@(peerId)]][@(peerId)];
            else
                peer = [TGDatabaseInstance() loadUser:(int32_t)peerId];
            
            TGLiveLocation *liveLocation = [[TGLiveLocation alloc] initWithMessage:message peer:peer hasOwnSession:liveLocationToOpen.message.mid == message.mid isOwnLocation:[liveLocationToOpen peerId] == message.fromUid isExpired:currentTime > expires];
            [liveLocations addObject:liveLocation];
        }
        return liveLocations;
    }]];
    controller.receivingPeer = TGPeerIdIsUser(liveLocationToOpen.message.cid) ? [TGDatabaseInstance() loadUser:(int32_t)liveLocationToOpen.message.cid] : [TGDatabaseInstance() loadConversationWithId:liveLocationToOpen.message.cid];
    
    __weak TGTelegraphDialogListCompanion *weakSelf = self;
    controller.openLocation = ^(TGMessage *message)
    {
        __strong TGTelegraphDialogListCompanion *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf.dialogListController dismissViewControllerAnimated:true completion:^
        {
            TGLiveLocation *liveLocation = [[TGLiveLocation alloc] initWithMessage:message peer:[TGDatabaseInstance() loadUser:TGTelegraphInstance.clientUserId] hasOwnSession:true isOwnLocation:true isExpired:false];
            [strongSelf openLiveLocation:liveLocation];
        }];
    };

    TGNavigationController *navigationController = [TGNavigationController navigationControllerWithControllers:@[controller]];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        navigationController.presentationStyle = TGNavigationControllerPresentationStyleInFormSheet;
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [self.dialogListController presentViewController:navigationController animated:true completion:nil];
}

- (void)actorMessageReceived:(NSString *)path messageType:(NSString *)messageType message:(id)message
{
    if ([path isEqualToString:[NSString stringWithFormat:@"/tg/search/messages/(%lu)", (unsigned long)[_searchString hash]]])
    {
        if ([messageType isEqualToString:@"searchResultsUpdated"])
        {
            NSArray *conversations = [((SGraphObjectNode *)message[@"dialogs"]).object sortedArrayUsingComparator:^NSComparisonResult(TGConversation *conversation1, TGConversation *conversation2)
            {
                return conversation1.date > conversation2.date ? NSOrderedAscending : NSOrderedDescending;
            }];
            
            NSMutableArray *result = [[NSMutableArray alloc] init];
            
            TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
            
            CFAbsoluteTime dialogListDataStartTime = CFAbsoluteTimeGetCurrent();
            
            for (TGConversation *conversation in conversations)
            {
                [self initializeDialogListData:conversation customUser:nil selfUser:selfUser];
                [result addObject:conversation];
            }
            
            NSString *searchString = _searchString;
            
            TGLog(@"Dialog list data parsing time: %f s", CFAbsoluteTimeGetCurrent() - dialogListDataStartTime);
            
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                [dialogListController searchResultsReloaded:@{@"dialogs": result} searchString:searchString];
            });
        }
    }
}

- (id)processSearchResultItem:(id)item
{
    bool forwardMode = self.forwardMode;
    bool privacyMode = self.privacyMode;
    bool showGroupsOnly = self.showGroupsOnly;
    bool showSecretInForwardMode = self.showSecretInForwardMode;
    
    if ([item isKindOfClass:[TGConversation class]])
    {
        TGConversation *conversation = (TGConversation *)item;
        if (((forwardMode || privacyMode) && conversation.conversationId <= INT_MIN) && !showSecretInForwardMode)
            return nil;
        
        if ((forwardMode || privacyMode) && conversation.isBroadcast)
            return nil;
        
        if (showGroupsOnly && conversation.isChannel && conversation.isChannelGroup) {
            [self initializeDialogListData:conversation customUser:nil selfUser:[TGDatabaseInstance() loadUser:TGTelegraphInstance.clientUserId]];
            return conversation;
        }
        
        if (showGroupsOnly && (conversation.conversationId > 0 || conversation.conversationId <= INT_MIN))
            return nil;
        
        [self initializeDialogListData:conversation customUser:nil selfUser:[TGDatabaseInstance() loadUser:TGTelegraphInstance.clientUserId]];
        return conversation;
    }
    else if ([item isKindOfClass:[TGUser class]])
    {
        if (showGroupsOnly)
            return nil;
        
        return item;
    }
    
    return nil;
}

- (TGConversation *)selfPeer
{
    TGConversation *selfPeer = [TGDatabaseInstance() loadConversationWithId:TGTelegraphInstance.clientUserId];
    if (selfPeer == nil)
        selfPeer = [[TGConversation alloc] initWithConversationId:TGTelegraphInstance.clientUserId unreadCount:0 serviceUnreadCount:0];
    
    return selfPeer;
}

- (void)actorCompleted:(int)resultCode path:(NSString *)path result:(id)result
{
    bool hideSelf = self.forwardMode || self.showPrivateOnly || self.showGroupsAndChannelsOnly;
    
    if ([path isEqualToString:[NSString stringWithFormat:@"/tg/search/dialogs/(%lu)", (unsigned long)[_searchString hash]]])
    {
        NSDictionary *dict = ((SGraphObjectNode *)result).object;
        
        NSArray *users = [dict objectForKey:@"users"];
        NSArray *chats = [dict objectForKey:@"chats"];
        
        NSMutableArray *result = [[NSMutableArray alloc] init];
        if (chats != nil)
        {
            bool forwardMode = self.forwardMode;
            bool privacyMode = self.privacyMode;
            bool showGroupsOnly = self.showGroupsOnly;
            bool showSecretInForwardMode = self.showSecretInForwardMode;
            
            TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
            
            for (id object in chats)
            {
                if ([object isKindOfClass:[TGConversation class]])
                {
                    TGConversation *conversation = (TGConversation *)object;
                    if (((forwardMode || privacyMode) && conversation.conversationId <= INT_MIN) && !showSecretInForwardMode)
                        continue;
                    
                    if (conversation.conversationId == selfUser.uid && hideSelf)
                        continue;
                    
                    if (conversation.isDeactivated || conversation.isDeleted) {
                        continue;
                    }
                    
                    if ((forwardMode || privacyMode) && conversation.isBroadcast)
                        continue;
                    
                    if (showGroupsOnly && (conversation.conversationId <= INT_MIN || conversation.conversationId > 0))
                        continue;
                    
                    [self initializeDialogListData:conversation customUser:nil selfUser:selfUser];
                    [result addObject:conversation];
                }
                else
                {
                    [result addObject:object];
                }
            }
        }
        if (users != nil)
            [result addObjectsFromArray:users];
        
        NSString *searchString = _searchString;

        dispatch_async(dispatch_get_main_queue(), ^
        {
            TGDialogListController *dialogListController = self.dialogListController;
            [dialogListController searchResultsReloaded:@{@"dialogs": result} searchString:searchString];
        });
    }
    else if ([path isEqualToString:[NSString stringWithFormat:@"/tg/search/messages/(%lu)", (unsigned long)[_searchString hash]]])
    {
        [self actorMessageReceived:path messageType:@"searchResultsUpdated" message:result];
    }
    else if ([path hasPrefix:@"/tg/dialoglist"])
    {
        if (resultCode == 0)
        {
            SAtomic *syncResult = [[SAtomic alloc] initWithValue:@true];
            [self maybeLoadAd:syncResult];
            [syncResult swap:@false];
            
            NSMutableArray *conversationIds = [[NSMutableArray alloc] init];
            for (id<TGDialogListItem> conversation in _conversationList) {
                [conversationIds addObject:@(conversation.conversationId)];
            }
            
            SGraphListNode *listNode = (SGraphListNode *)result;
            NSMutableArray<id<TGDialogListItem>> *loadedItems = [[listNode items] mutableCopy];
            bool canLoadMore = false;
            bool forwardMode = self.forwardMode;
            bool privacyMode = self.privacyMode;
            bool showGroupsOnly = self.showGroupsOnly;
            bool showPrivateOnly = self.showPrivateOnly;
            bool showGroupsAndChannelsOnly = self.showGroupsAndChannelsOnly;
            bool showSecretInForwardMode = self.showSecretInForwardMode;
            
            TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
            
            if ((forwardMode || privacyMode) && !showSecretInForwardMode)
            {
                for (int i = 0; i < (int)loadedItems.count; i++)
                {
                    id<TGDialogListItem> conversation = loadedItems[i];
                    if (conversation.isChannel && conversation.isChannelGroup && (!self.botStartMode || conversation.channelRole == TGChannelRoleCreator || conversation.channelRole == TGChannelRoleModerator || conversation.channelRole == TGChannelRolePublisher)) {
                        
                    } else if (conversation.conversationId <= INT_MIN)
                    {
                        [loadedItems removeObjectAtIndex:i];
                        i--;
                    }
                }
            }
            
            if (forwardMode || privacyMode)
            {
                for (int i = 0; i < (int)loadedItems.count; i++)
                {
                    if (loadedItems[i].isBroadcast)
                    {
                        [loadedItems removeObjectAtIndex:i];
                        i--;
                    }
                }
            }
            
            for (int i = 0; i < (int)loadedItems.count; i++)
            {
                if (loadedItems[i].isDeactivated)
                {
                    [loadedItems removeObjectAtIndex:i];
                    i--;
                }
            }
            
            for (int i = 0; i < (int)loadedItems.count; i++)
            {
                if (loadedItems[i].feedId.intValue != 0)
                {
                    [loadedItems removeObjectAtIndex:i];
                    i--;
                }
            }
            
            if (showGroupsOnly)
            {
                for (int i = 0; i < (int)loadedItems.count; i++)
                {
                    id<TGDialogListItem> conversation = loadedItems[i];
                    if (conversation.isChannel && conversation.isChannelGroup && (!self.botStartMode || conversation.channelRole == TGChannelRoleCreator || conversation.channelRole == TGChannelRoleModerator || conversation.channelRole == TGChannelRolePublisher)) {
                    } else if (conversation.conversationId <= INT_MIN || conversation.conversationId > 0) {
                        [loadedItems removeObjectAtIndex:i];
                        i--;
                    }
                }
            }
            
            if (showPrivateOnly)
            {
                for (int i = 0; i < (int)loadedItems.count; i++)
                {
                    id<TGDialogListItem> conversation = loadedItems[i];
                    if (!TGPeerIdIsUser(conversation.conversationId) || [self.excludedIds containsObject:@(conversation.conversationId)]) {
                        [loadedItems removeObjectAtIndex:i];
                        i--;
                    }
                }
            } else if (showGroupsAndChannelsOnly)
            {
                for (int i = 0; i < (int)loadedItems.count; i++)
                {
                    id<TGDialogListItem> conversation = loadedItems[i];
                    bool skip = false;
                    if ([conversation isKindOfClass:[TGConversation class]])
                    {
                        skip = ((TGConversation *)conversation).isDeleted || ((TGConversation *)conversation).isDeactivated || ((TGConversation *)conversation).leftChat || ((TGConversation *)conversation).kickedFromChat;
                    }
                    if ((!TGPeerIdIsGroup(conversation.conversationId) && !TGPeerIdIsChannel(conversation.conversationId)) || skip || [self.excludedIds containsObject:@(conversation.conversationId)]) {
                        [loadedItems removeObjectAtIndex:i];
                        i--;
                    }
                }
            }
            
            for (id<TGDialogListItem> conversation in loadedItems)
            {
                [self initializeDialogListData:(TGConversation *)conversation customUser:nil selfUser:selfUser];
            }
            
            //[loadedItems addObjectsFromArray:[TGDatabaseInstance() feeds]];
            
            if (_conversationList.count == 0)
            {
                canLoadMore = loadedItems.count != 0;
                if (_adConversation != nil) {
                    [loadedItems addObject:_adConversation];
                }
                [_conversationList addObjectsFromArray:loadedItems];
            }
            else
            {
                std::set<int64_t> existingConversations;
                std::set<int32_t> existingFeeds;
                for (id<TGDialogListItem> conversation in _conversationList)
                {
                    existingConversations.insert(conversation.conversationId);
                }
                
                for (int i = 0; i < (int)loadedItems.count; i++)
                {
                    id<TGDialogListItem> conversation = [loadedItems objectAtIndex:i];
                    if (existingConversations.find(conversation.conversationId) != existingConversations.end())
                    {
                        [loadedItems removeObjectAtIndex:i];
                        i--;
                    }
                }
                
                canLoadMore = loadedItems.count != 0;
                
                [_conversationList addObjectsFromArray:loadedItems];
            }
            
            [_conversationList sortUsingComparator:^NSComparisonResult(id<TGDialogListItem> conversation1, id<TGDialogListItem> conversation2)
            {
                if (TGPeerIdIsAd(conversation1.conversationId)) {
                    return NSOrderedAscending;
                } else if (TGPeerIdIsAd(conversation2.conversationId)) {
                    return NSOrderedDescending;
                }
                
                int date1 = conversation1.date;
                int date2 = conversation2.date;
                
                if (date1 > date2)
                    return NSOrderedAscending;
                else if (date1 < date2)
                    return NSOrderedDescending;
                else
                    return NSOrderedSame;
            }];
            
            for (int i = 0; i < (int)_conversationList.count; i++)
            {
                if ([_conversationList[i] isKindOfClass:[TGConversation class]] && ((TGConversation *)_conversationList[i]).conversationId == selfUser.uid && hideSelf)
                {
                    [_conversationList removeObjectAtIndex:i];
                    i--;
                }
            }
        
            if (forwardMode && !showGroupsOnly && !showPrivateOnly && !showGroupsAndChannelsOnly)
            {
                TGConversation *selfConversation = [self selfPeer];
                [_conversationList insertObject:selfConversation atIndex:0];
                [self initializeDialogListData:selfConversation customUser:nil selfUser:selfUser];
            }
            
            NSArray *items = [NSArray arrayWithArray:_conversationList];
            
            _canLoadMore = canLoadMore;
            
            NSMutableArray *currentConversationIds = [[NSMutableArray alloc] init];
            for (id<TGDialogListItem> conversation in _conversationList) {
                [currentConversationIds addObject:@(conversation.conversationId)];
            }
            
            if ([currentConversationIds isEqualToArray:conversationIds]) {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                for (id<TGDialogListItem> conversation in _conversationList) {
                    dict[@(conversation.conversationId)] = conversation;
                }
                TGDispatchOnMainThread(^{
                    TGDialogListController *controller = self.dialogListController;
                    if (currentConversationIds.count == 0) {
                        [controller dialogListFullyReloaded:items];
                    } else {
                        [controller updateConversations:dict];
                    }
                });
            } else {
                if (self.dialogListController.debugReady != nil)
                    self.dialogListController.debugReady();
                dispatch_async(dispatch_get_main_queue(), ^
                {
                    TGDialogListController *controller = self.dialogListController;
                    if (controller != nil)
                    {
                        controller.canLoadMore = canLoadMore;
                        if (self.dialogListController.debugReady != nil)
                            self.dialogListController.debugReady();
                        [controller dialogListFullyReloaded:items];
                    }
                });
            }
            
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^
            {
                TGDispatchAfter(0.4, dispatch_get_main_queue(), ^
                {
                    [self dialogListReady];
                });
            });
        }
    }
    else if ([path isEqualToString:@"/tg/service/synchronizationstate"])
    {
        int state = [((SGraphObjectNode *)result).object intValue];
        
        TGDialogListState newState;
        
        if (state & 2)
        {
            if (state & 4)
                newState = TGDialogListStateWaitingForNetwork;
            else {
                if (state & 16) {
                    newState = TGDialogListStateHasProxyIssues;
                }
                else if (state & 8) {
                    newState = TGDialogListStateConnectingToProxy;
                } else {
                    newState = TGDialogListStateConnecting;
                }
            }
        }
        else if (state & 1)
            newState = TGDialogListStateUpdating;
        else
            newState = TGDialogListStateNormal;

        TGDispatchOnMainThread(^
        {
            if (newState != _state)
            {
                _state = newState;
                
                __weak TGTelegraphDialogListCompanion *weakSelf = self;
                [_stateDisposable setDisposable:[[[[SSignal complete] delay:0.3 onQueue:[SQueue mainQueue]] then:[SSignal single:@(newState)]] startWithNext:^(__unused id next)
                {
                    __strong TGTelegraphDialogListCompanion *strongSelf = weakSelf;
                    if (strongSelf == nil)
                        return;
                    
                    NSString *title = nil;
                    if (newState == TGDialogListStateConnecting)
                    {
                        title = TGLocalized(@"State.Connecting");
                    }
                    else if (newState == TGDialogListStateConnectingToProxy || newState == TGDialogListStateHasProxyIssues)
                    {
                        if ((int)TGScreenSize().width == 320 || TGIsPad())
                            title = TGLocalized(@"State.Connecting");
                        else
                            title = TGLocalized(@"State.ConnectingToProxy");
                    }
                    else if (newState == TGDialogListStateUpdating)
                        title = TGLocalized(@"State.Updating");
                    else if (newState == TGDialogListStateWaitingForNetwork)
                        title = TGLocalized(@"State.WaitingForNetwork");
                    
                    TGDialogListController *dialogListController = strongSelf.dialogListController;
                    [dialogListController titleStateUpdated:title state:newState];
                }]];
            }
        });
    }
    else if ([path hasPrefix:@"/tg/loadConversationAndMessageForSearch/"])
    {
        TGDispatchOnMainThread(^
        {
            [_progressWindow dismiss:true];
            _progressWindow = nil;
            
            if (resultCode == ASStatusSuccess)
            {
                int64_t conversationId = [result[@"peerId"] longLongValue];
                TGConversation *conversation = result[@"conversation"];
                int32_t messageId = [result[@"messageId"] intValue];
                
                [[TGInterfaceManager instance] navigateToConversationWithId:conversationId conversation:conversation performActions:nil atMessage:@{@"mid": @(messageId)} clearStack:true openKeyboard:false canOpenKeyboardWhileInTransition:false animated:true];
            }
        });
    }
}

- (void)actionStageResourceDispatched:(NSString *)path resource:(id)resource arguments:(id)arguments
{
    bool hideSelf = self.forwardMode || self.showPrivateOnly || self.showGroupsAndChannelsOnly;
    
    if ([path hasPrefix:@"/tg/dialoglist"])
    {
        [self actorCompleted:ASStatusSuccess path:path result:resource];
    }
    else if ([path hasPrefix:@"/tg/conversationsGrouped"])
    {
        NSMutableArray *conversations = ((SGraphObjectNode *)resource).object;
        bool animated = [path rangeOfString:@"(animated)"].location != NSNotFound;
        for (TGConversation *conversation in conversations)
        {
            [self deleteItem:conversation animated:animated interfaceOnly:true];
        }
    }
    else if ([path isEqualToString:@"/tg/conversations"] || [path isEqualToString:@"/tg/broadcastConversations"])
    {
        NSMutableArray *conversationIds = [[NSMutableArray alloc] init];
        for (TGConversation *conversation in _conversationList) {
            [conversationIds addObject:@(conversation.conversationId)];
        }
        
        TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
        
        NSMutableArray *conversations = [((SGraphObjectNode *)resource).object mutableCopy];
        
        if (_adConversation != nil) {
            NSMutableArray *additional = [[NSMutableArray alloc] init];
            for (TGConversation *conversation in conversations) {
                if (TGPeerIdIsChannel(conversation.conversationId) && TGAdIdFromPeerId(_adConversation.conversationId) == TGChannelIdFromPeerId(conversation.conversationId)) {
                    TGConversation *adConversation = [conversation copy];
                    adConversation.conversationId = TGPeerIdFromAdId(TGChannelIdFromPeerId(conversation.conversationId));
                    [additional addObject:adConversation];
                }
            }
            [conversations addObjectsFromArray:additional];
        }
        
        for (NSInteger i = 0; i < (NSInteger)conversations.count; i++) {
            TGConversation *conversation = conversations[i];
            
            bool isTemporaryChannel = conversation.isChannel && conversation.kind != TGConversationKindPersistentChannel;
            bool isSavedMessages = conversation.conversationId == selfUser.uid && hideSelf;
            
            bool isAd = TGPeerIdIsAd(conversation.conversationId);
            
            if ((isTemporaryChannel || isSavedMessages) && !isAd) {
                [conversations removeObjectAtIndex:i];
                i--;
            }
        }
        
        TGDialogListController *controller = self.dialogListController;
        if (controller.isDisplayingSearch)
        {
            NSMutableArray *searchConversations = [[NSMutableArray alloc] init];
            for (TGConversation *conversation in ((SGraphObjectNode *)resource).object)
            {
                TGConversation *copyConversation = [conversation copy];
                [self initializeDialogListData:copyConversation customUser:nil selfUser:selfUser];
                [searchConversations addObject:copyConversation];
            }
            TGDispatchOnMainThread(^
            {
                [controller updateSearchConversations:searchConversations];
            });
        }
        
        if ((self.forwardMode || self.privacyMode) && !self.showSecretInForwardMode)
        {
            for (int i = 0; i < (int)conversations.count; i++)
            {
                TGConversation *conversation = (TGConversation *)conversations[i];
                if (conversation.isChannel && conversation.isChannelGroup && (!self.botStartMode || conversation.channelRole == TGChannelRoleCreator || conversation.channelRole == TGChannelRoleModerator || conversation.channelRole == TGChannelRolePublisher)) {
                    
                } else {
                    if (conversation.conversationId <= INT_MIN)
                    {
                        [conversations removeObjectAtIndex:i];
                        i--;
                    }
                }
            }
        }
        
        if (self.forwardMode || self.privacyMode)
        {
            for (int i = 0; i < (int)conversations.count; i++)
            {
                if (((TGConversation *)conversations[i]).isBroadcast)
                {
                    [conversations removeObjectAtIndex:i];
                    i--;
                }
            }
        }
        
        if (self.showGroupsOnly)
        {
            for (int i = 0; i < (int)conversations.count; i++)
            {
                TGConversation *conversation = conversations[i];
                if (conversation.isChannel && conversation.isChannelGroup && (!self.botStartMode || conversation.channelRole == TGChannelRoleCreator || conversation.channelRole == TGChannelRoleModerator || conversation.channelRole == TGChannelRolePublisher)) {
                    
                } else if (conversation.conversationId <= INT_MIN || conversation.conversationId > 0) {
                    [conversations removeObjectAtIndex:i];
                    i--;
                }
            }
        }
        
        if (conversations.count == 0)
            return;
        
        [conversations sortUsingComparator:^NSComparisonResult(id<TGDialogListItem> obj1, id<TGDialogListItem> obj2)
         {
             if (TGPeerIdIsAd(obj1.conversationId)) {
                 return NSOrderedAscending;
             } else if (TGPeerIdIsAd(obj2.conversationId)) {
                 return NSOrderedDescending;
             }
             
             int date1 = (int)((TGConversation *)obj1).date;
             int date2 = (int)((TGConversation *)obj2).date;
             
             if (date1 < date2)
                 return NSOrderedAscending;
             else if (date1 > date2)
                 return NSOrderedDescending;
             else
                 return NSOrderedSame;
         }];
        
        if (conversations.count == 1 && _conversationList.count != 0)
        {
            TGConversation *singleConversation = [conversations objectAtIndex:0];
            TGConversation *topConversation = ((TGConversation *)[_conversationList objectAtIndex:0]);
            if (!singleConversation.isDeleted && !singleConversation.isDeactivated && _conversationList.count > 0 && topConversation.conversationId == singleConversation.conversationId && (topConversation.date <= singleConversation.date || topConversation.unreadCount != singleConversation.unreadCount || (singleConversation.serviceUnreadCount != -1 && topConversation.serviceUnreadCount != singleConversation.serviceUnreadCount)))
            {
                [self initializeDialogListData:singleConversation customUser:nil selfUser:selfUser];
                [_conversationList replaceObjectAtIndex:0 withObject:singleConversation];
                
                dispatch_async(dispatch_get_main_queue(), ^
                {
                    TGDialogListController *dialogListController = self.dialogListController;
                    
                    [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:[NSArray arrayWithObject:[[NSNumber alloc] initWithInt:0]] updatedItems:[NSArray arrayWithObject:singleConversation] removedIndices:nil];
                });
                
                return;
            }
        }
        
        std::map<int64_t, int> conversationIdToIndex;
        int index = -1;
        for (TGConversation *conversation in _conversationList)
        {
            index++;
            int64_t conversationId = conversation.conversationId;
            conversationIdToIndex.insert(std::pair<int64_t, int>(conversationId, index));
        }
        
        NSMutableSet *addedPeerIds = [[NSMutableSet alloc] init];
        for (TGConversation *conversation in conversations) {
            if (conversationIdToIndex.find(conversation.conversationId) == conversationIdToIndex.end()) {
                [addedPeerIds addObject:@(conversation.conversationId)];
            }
        }
        
        NSMutableSet *candidatesForCutoff = [[NSMutableSet alloc] init];
        
        for (int i = 0; i < (int)conversations.count; i++)
        {
            TGConversation *conversation = [conversations objectAtIndex:i];
            int64_t conversationId = conversation.conversationId;
            std::map<int64_t, int>::iterator it = conversationIdToIndex.find(conversationId);
            if (it != conversationIdToIndex.end())
            {
                TGConversation *newConversation = [conversation copy];
                if (!newConversation.isDeleted && !newConversation.isDeactivated)
                    [self initializeDialogListData:newConversation customUser:nil selfUser:selfUser];
                
                TGConversation *previousConversation = _conversationList[(it->second)];
                
                if (newConversation.date < previousConversation.date) {
                    [candidatesForCutoff addObject:@(newConversation.conversationId)];
                }
                
                [_conversationList replaceObjectAtIndex:(it->second) withObject:newConversation];
                [conversations removeObjectAtIndex:i];
                i--;
            }
        }
        
        for (int i = 0; i < (int)_conversationList.count; i++)
        {
            TGConversation *conversation = [_conversationList objectAtIndex:i];
            if (TGPeerIdIsAd(conversation.conversationId)) {
                continue;
            }
            if (conversation.isDeleted || conversation.isDeactivated || conversation.feedId.intValue != 0)
            {
                [_conversationList removeObjectAtIndex:i];
                i--;
            }
        }
        
        for (TGConversation *conversation in conversations)
        {
            TGConversation *newConversation = [conversation copy];
            if (!newConversation.isDeleted && !newConversation.isDeactivated && newConversation.feedId.intValue == 0)
            {
                [self initializeDialogListData:newConversation customUser:nil selfUser:selfUser];
                
                [_conversationList addObject:newConversation];
            }
        }
        
        if (self.forwardMode)
        {
            TGConversation *conversation = [_conversationList firstObject];
            if (conversation.conversationId == selfUser.uid)
                [_conversationList removeObjectAtIndex:0];
        }
        
        [_conversationList sortUsingComparator:^NSComparisonResult(id<TGDialogListItem> obj1, id<TGDialogListItem> obj2)
         {
             if (TGPeerIdIsAd(obj1.conversationId)) {
                 return NSOrderedAscending;
             } else if (TGPeerIdIsAd(obj2.conversationId)) {
                 return NSOrderedDescending;
             }
             
             int date1 = (int)((TGConversation *)obj1).date;
             int date2 = (int)((TGConversation *)obj2).date;
             
             if (date1 < date2)
                 return NSOrderedDescending;
             else if (date1 > date2)
                 return NSOrderedAscending;
             else
                 return NSOrderedSame;
         }];
        
        if ([arguments[@"filterEarliest"] boolValue] && _canLoadMore) {
            while (_conversationList.count != 0) {
                TGConversation *conversation = [_conversationList lastObject];
                if (conversation.isChannel) {
                    [_conversationList removeLastObject];
                } else {
                    break;
                }
            }
        }
        
        if (candidatesForCutoff.count != 0 && _canLoadMore) {
            for (NSInteger i = _conversationList.count - 1; i >= 0; i--) {
                TGConversation *conversation = _conversationList[i];
                if ([candidatesForCutoff containsObject:@(conversation.conversationId)]) {
                    [_conversationList removeObjectAtIndex:i];
                } else {
                    break;
                }
            }
        }
        
        if (_canLoadMore) {
            for (NSInteger i = _conversationList.count - 1; i >= 0; i--) {
                TGConversation *conversation = _conversationList[i];
                if ([addedPeerIds containsObject:@(conversation.conversationId)]) {
                    [_conversationList removeObjectAtIndex:i];
                } else {
                    break;
                }
            }
        }
        
        if (self.forwardMode && !self.showGroupsOnly && !self.showPrivateOnly && !self.showGroupsAndChannelsOnly)
        {
            TGConversation *selfConversation = [self selfPeer];
            [_conversationList insertObject:selfConversation atIndex:0];
            [self initializeDialogListData:selfConversation customUser:nil selfUser:selfUser];
        }
        
        NSMutableArray *currentConversationIds = [[NSMutableArray alloc] init];
        for (TGConversation *conversation in _conversationList) {
            [currentConversationIds addObject:@(conversation.conversationId)];
        }
        
        /*if (currentConversationIds.count >= 6 && conversationIds.count >= 6) {
            TGLog(@"update %@ %@ %@", [conversationIds subarrayWithRange:NSMakeRange(0, 6)], [conversationIds isEqualToArray:currentConversationIds] ? @"==" : @"!=", [currentConversationIds subarrayWithRange:NSMakeRange(0, 6)]);
        }*/
        
        if ([currentConversationIds isEqualToArray:conversationIds]) {
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            for (TGConversation *conversation in _conversationList) {
                dict[@(conversation.conversationId)] = conversation;
            }
            TGDispatchOnMainThread(^{
                TGDialogListController *controller = self.dialogListController;
                [controller updateConversations:dict];
            });
        } else {
            NSArray *items = [NSArray arrayWithArray:_conversationList];
            
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *controller = self.dialogListController;
                if (controller != nil)
                {
                    [controller dialogListFullyReloaded:items];
                    if (!self.forwardMode && !self.privacyMode) {
                        [controller selectConversationWithId:[self openedConversationId]];
                    }
                }
            });
        }
    }
    else if ([path isEqualToString:@"/tg/userdatachanges"])
    {
        std::map<int, int> userIdToIndex;
        int index = -1;
        NSArray *users = (((SGraphObjectNode *)resource).object);
        for (TGUser *user in users)
        {
            index++;
            userIdToIndex.insert(std::pair<int, int>(user.uid, index));
        }
        
        TGUser *selfUser = [[TGDatabase instance] loadUser:TGTelegraphInstance.clientUserId];
        
        NSMutableArray *updatedIndices = [[NSMutableArray alloc] init];
        NSMutableArray *updatedItems = [[NSMutableArray alloc] init];
        
        bool updateAllOutgoing = userIdToIndex.find(TGTelegraphInstance.clientUserId) != userIdToIndex.end();
        
        for (index = 0; index < (int)_conversationList.count; index++)
        {
            TGConversation *conversation = [_conversationList objectAtIndex:index];
            if (![conversation isKindOfClass:[TGConversation class]])
                continue;
            
            int userId = 0;
            if (conversation.isEncrypted)
            {
                if (conversation.chatParticipants.chatParticipantUids.count != 0)
                    userId = [conversation.chatParticipants.chatParticipantUids[0] intValue];
            }
            else if (conversation.isChat)
                userId = conversation.outgoing ? TGTelegraphInstance.clientUserId : conversation.fromUid;
            else
                userId = (int)conversation.conversationId;

            std::map<int, int>::iterator it = userIdToIndex.find(userId);
            if (it != userIdToIndex.end() || (updateAllOutgoing && conversation.outgoing))
            {
                TGConversation *newConversation = [conversation copy];
                [self initializeDialogListData:newConversation customUser:(it != userIdToIndex.end() ? [users objectAtIndex:it->second] : nil) selfUser:selfUser];
                [_conversationList replaceObjectAtIndex:index withObject:newConversation];
                [updatedIndices addObject:[NSNumber numberWithInt:index]];
                [updatedItems addObject:newConversation];
            }
        }
        
        if (updatedIndices.count != 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *controller = self.dialogListController;
                if (controller != nil)
                    [controller dialogListItemsChanged:nil insertedItems:nil updatedIndices:updatedIndices updatedItems:updatedItems removedIndices:nil];
            });
        }
    }
    else if ([path isEqualToString:@"/tg/conversation/*/typing"])
    {
        NSDictionary *dict = ((SGraphObjectNode *)resource).object;
        int64_t conversationId = [[dict objectForKey:@"conversationId"] longLongValue];
        if (conversationId != 0)
        {
            NSDictionary *userActivities = [dict objectForKey:@"typingUsers"];
            NSString *typingString = nil;
            NSArray *typingUsers = userActivities.allKeys;
            if (((conversationId < 0 && conversationId > INT_MIN) || TGPeerIdIsChannel(conversationId)) && typingUsers.count != 0)
            {
                NSMutableString *userNames = [[NSMutableString alloc] init];
                NSMutableArray *userNamesArray = [[NSMutableArray alloc] init];
                for (NSNumber *nUid in typingUsers)
                {
                    TGUser *user = [TGDatabaseInstance() loadUser:[nUid intValue]];
                    if (userNames.length != 0)
                        [userNames appendString:@", "];
                    [userNames appendString:user.displayFirstName == nil ? @"" : user.displayFirstName];
                    if (user.displayFirstName != nil)
                        [userNamesArray addObject:user.displayFirstName];
                }
                
                if (userNamesArray.count == 1)
                {
                    typingString = [[NSString alloc] initWithFormat:[self formatForGroupActivity:userActivities[typingUsers[0]]], userNames];
                }
                else if (userNamesArray.count != 0)
                {
                    NSString *format = [TGStringUtils integerValueFormat:@"ForwardedAuthorsOthers_" value:userNamesArray.count - 1];
                    typingString = [[NSString alloc] initWithFormat:TGLocalized(format), userNamesArray[0], [[NSString alloc] initWithFormat:@"%d", (int)userNamesArray.count - 1]];
                }
            }
            else if (typingUsers.count != 0)
            {
                NSMutableString *userNames = [[NSMutableString alloc] init];
                for (NSNumber *nUid in typingUsers)
                {
                    TGUser *user = [TGDatabaseInstance() loadUser:[nUid intValue]];
                    if (userNames.length != 0)
                        [userNames appendString:@", "];
                    [userNames appendString:user.displayFirstName];
                }
                
                if (typingUsers.count == 1)
                {
                    typingString = [[NSString alloc] initWithFormat:[self formatForUserActivity:userActivities[typingUsers[0]]], userNames];
                }
                else
                    typingString = userNames;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                
                [dialogListController userTypingInConversationUpdated:conversationId typingString:typingString];
            });
        }
    }
    else if ([path isEqualToString:@"/tg/service/synchronizationstate"])
    {
        [self actorCompleted:ASStatusSuccess path:path result:resource];
    }
    else if ([path isEqualToString:@"/tg/unreadCount"])
    {
        dispatch_async(dispatch_get_main_queue(), ^ // request to controller
        {
            [TGDatabaseInstance() dispatchOnDatabaseThread:^ // request to database
            {
                int unreadCount = [TGDatabaseInstance() databaseState].unreadCount;
                TGDispatchOnMainThread(^
                {
                    if (![arguments[@"previous"] boolValue]) {
                        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:unreadCount];
                    }
                    if (unreadCount == 0)
                        [[UIApplication sharedApplication] cancelAllLocalNotifications];
                    
                    self.unreadCount = unreadCount;
                    [TGAppDelegateInstance.rootController.mainTabsController setUnreadCount:unreadCount];
                    
                    TGDialogListController *dialogListController = self.dialogListController;
                    dialogListController.tabBarItem.badgeValue = unreadCount == 0 ? nil : [[NSString alloc] initWithFormat:@"%d", unreadCount];
                });
            } synchronous:false];
        });
    }
//    else if ([path isEqualToString:@"/tg/unreadChatsCount"])
//    {
//        dispatch_async(dispatch_get_main_queue(), ^ // request to controller
//        {
//            [TGDatabaseInstance() dispatchOnDatabaseThread:^ // request to database
//            {
//                int unreadChatsCount = [TGDatabaseInstance() unreadChatsCount];
//                int unreadChannelsCount = [TGDatabaseInstance() unreadChannelsCount];
//                TGDispatchOnMainThread(^
//                {
//                    //if (![arguments[@"previous"] boolValue]) {
//                    //    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:unreadCount];
//                    //}
//                    //if (unreadCount == 0)
//                    //    [[UIApplication sharedApplication] cancelAllLocalNotifications];
//                    
//                    //self.unreadCount = unreadCount;
//                    [TGAppDelegateInstance.rootController.mainTabsController setUnreadCount:unreadChatsCount + unreadChannelsCount];
//                });
//            } synchronous:false];
//        });
//    }
    else if ([path hasPrefix:@"/tg/peerSettings/"])
    {
        NSMutableArray *updatedIndices = [[NSMutableArray alloc] init];
        NSMutableArray *updatedItems = [[NSMutableArray alloc] init];
        
        int64_t peerId = [[path substringWithRange:NSMakeRange(18, path.length - 1 - 18)] longLongValue];
        bool isPrivateDefault = peerId == INT_MAX - 1;
        bool isGroupDefault = peerId == INT_MAX - 2;
        
        int count = (int)_conversationList.count;
        for (int i = 0; i < count; i++)
        {
            TGConversation *conversation = [_conversationList objectAtIndex:i];
            if (![conversation isKindOfClass:[TGConversation class]])
                continue;
            
            int64_t mutePeerId = conversation.conversationId;
            if (conversation.isEncrypted)
            {
                if (conversation.chatParticipants.chatParticipantUids.count != 0)
                    mutePeerId = [conversation.chatParticipants.chatParticipantUids[0] intValue];
            }
            
            if (mutePeerId == peerId || (TGPeerIdIsUser(mutePeerId) && isPrivateDefault) || (!TGPeerIdIsUser(mutePeerId) && isGroupDefault))
            {
                TGConversation *newConversation = [conversation copy];
                NSMutableDictionary *newData = [conversation.dialogListData mutableCopy];
                [newData setObject:[[NSNumber alloc] initWithBool:[TGDatabaseInstance() isPeerMuted:mutePeerId forceUpdate:true]] forKey:@"mute"];
                newConversation.dialogListData = newData;
                
                [_conversationList replaceObjectAtIndex:i withObject:newConversation];
                
                [updatedIndices addObject:[[NSNumber alloc] initWithInt:i]];
                [updatedItems addObject:newConversation];
                
                if (mutePeerId == peerId)
                    break;
            }
        }
        
        if (updatedItems.count != 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:updatedIndices updatedItems:updatedItems removedIndices:nil];
            });
        }
    }
    else if ([path isEqualToString:@"/tg/contactlist"])
    {
        NSMutableArray *updatedIndices = [[NSMutableArray alloc] init];
        NSMutableArray *updatedItems = [[NSMutableArray alloc] init];
        
        int index = -1;
        int count = (int)_conversationList.count;
        for (int i = 0; i < count; i++)
        {
            index++;
            
            TGConversation *conversation = [_conversationList objectAtIndex:i];
            if (![conversation isKindOfClass:[TGConversation class]])
                continue;
            
            if (!conversation.isChat)
            {
                TGUser *user = [TGDatabaseInstance() loadUser:(int)conversation.conversationId];
                if (user == nil)
                    continue;
                
                NSString *title = nil;
                
                if (user.uid == [TGTelegraphInstance serviceUserUid] || user.uid == [TGTelegraphInstance voipSupportUserUid])
                    title = [user displayName];
                else if (user.phoneNumber.length != 0 && ![TGDatabaseInstance() uidIsRemoteContact:user.uid])
                    title = user.formattedPhoneNumber;
                else
                    title = [user displayName];
                
                if (title != nil && ![title isEqualToString:[conversation.dialogListData objectForKey:@"title"]])
                {
                    TGConversation *newConversation = [conversation copy];
                    NSMutableDictionary *newData = [conversation.dialogListData mutableCopy];
                    [newData setObject:title forKey:@"title"];
                    newConversation.dialogListData = newData;
                    
                    [_conversationList replaceObjectAtIndex:i withObject:newConversation];
                    
                    [updatedIndices addObject:[[NSNumber alloc] initWithInt:index]];
                    [updatedItems addObject:newConversation];
                }
            }
        }
        
        if (updatedItems.count != 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                TGDialogListController *dialogListController = self.dialogListController;
                [dialogListController dialogListItemsChanged:nil insertedItems:nil updatedIndices:updatedIndices updatedItems:updatedItems removedIndices:nil];
            });
        }
    }
    else if ([path isEqualToString:@"/databasePasswordChanged"])
    {
        TGDispatchOnMainThread(^
        {
            TGDialogListController *controller = self.dialogListController;
            [controller updateDatabasePassword];
        });
    }
}

- (NSString *)formatForGroupActivity:(NSString *)activity
{
    if ([activity isEqualToString:@"recordingAudio"])
        return TGLocalized(@"DialogList.SingleRecordingAudioSuffix");
    else if ([activity isEqualToString:@"recordingVideoMessage"])
        return TGLocalized(@"DialogList.SingleRecordingVideoMessageSuffix");
    else if ([activity isEqualToString:@"uploadingPhoto"])
        return TGLocalized(@"DialogList.SingleUploadingPhotoSuffix");
    else if ([activity isEqualToString:@"uploadingVideo"])
        return TGLocalized(@"DialogList.SingleUploadingVideoSuffix");
    else if ([activity isEqualToString:@"uploadingDocument"])
        return TGLocalized(@"DialogList.SingleUploadingFileSuffix");
    else if ([activity isEqualToString:@"playingGame"])
        return TGLocalized(@"DialogList.SinglePlayingGameSuffix");
    
    return TGLocalized(@"DialogList.SingleTypingSuffix");
}

- (NSString *)formatForUserActivity:(NSString *)activity
{
    if ([activity isEqualToString:@"recordingAudio"])
        return TGLocalized(@"Activity.RecordingAudio");
    else if ([activity isEqualToString:@"recordingVideoMessage"])
        return TGLocalized(@"Activity.RecordingVideoMessage");
    else if ([activity isEqualToString:@"uploadingPhoto"])
        return TGLocalized(@"Activity.UploadingPhoto");
    else if ([activity isEqualToString:@"uploadingVideo"])
        return TGLocalized(@"Activity.UploadingVideo");
    else if ([activity isEqualToString:@"uploadingDocument"])
        return TGLocalized(@"Activity.UploadingDocument");
    else if ([activity isEqualToString:@"playingGame"])
        return TGLocalized(@"Activity.PlayingGame");
    
    return TGLocalized(@"DialogList.Typing");
}

@end
