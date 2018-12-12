#import "TGShareTargetCell.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TGDatabase.h"
#import "TGTelegraph.h"
#import "TGChannelManagementSignals.h"

#import <LegacyComponents/TGCheckButtonView.h>
#import <LegacyComponents/TGLetteredAvatarView.h>

#import "TGPresentation.h"

@interface TGShareTargetCell ()
{
    TGCheckButtonView *_checkButton;
    TGLetteredAvatarView *_avatarView;
    UILabel *_nameLabel;
    UILabel *_subLabel;
    
    CALayer *_separatorLayer;
    
    bool _feed;
    int64_t _peerId;
    bool _isLastCell;
    
    SMetaDisposable *_channelDisposable;
}
@end

@implementation TGShareTargetCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self != nil)
    {
        if (iosMajorVersion() >= 7)
            self.contentView.superview.clipsToBounds = false;
        
        self.selectedBackgroundView = [[UIView alloc] init];
        
        if (iosMajorVersion() <= 6) {
            _separatorLayer = [[CALayer alloc] init];
            _separatorLayer.backgroundColor = TGSeparatorColor().CGColor;
            [self.layer addSublayer:_separatorLayer];
        }
        
        _avatarView = [[TGLetteredAvatarView alloc] initWithFrame:CGRectMake(14.0f, 4.0f, 40, 40)];
        [_avatarView setSingleFontSize:18.0f doubleFontSize:18.0f useBoldFont:false];
        _avatarView.fadeTransition = cpuCoreCount() > 1;
        [self addSubview:_avatarView];
        
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = TGMediumSystemFontOfSize(17.0f);
        _nameLabel.textColor = UIColorRGB(0x000000);
        [self addSubview:_nameLabel];
        
        CGFloat subtitleFontSize = TGIsPad() ? 14.0f : 13.0f;
        
        _subLabel = [[UILabel alloc] init];
        _subLabel.font = TGSystemFontOfSize(subtitleFontSize);
        _subLabel.textColor = UIColorRGB(0x8e8e93);
        [self addSubview:_subLabel];
        
        _checkButton = [[TGCheckButtonView alloc] initWithStyle:TGCheckButtonStyleDefault];
        _checkButton.userInteractionEnabled = false;
        [_checkButton addTarget:self action:@selector(checkButtonPressed) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_checkButton];
        
        _channelDisposable = [[SMetaDisposable alloc] init];
    }
    return self;
}

- (void)setPresentation:(TGPresentation *)presentation
{
    _presentation = presentation;
    
    self.selectedBackgroundView.backgroundColor = presentation.pallete.selectionColor;
    _nameLabel.textColor = presentation.pallete.textColor;
    _separatorLayer.backgroundColor = presentation.pallete.separatorColor.CGColor;
}

- (void)dealloc
{
    [_channelDisposable dispose];
}

- (void)checkButtonPressed
{
    [self setChecked:!_checkButton.selected animated:true];
}

- (void)setChecked:(bool)checked animated:(bool)animated
{
    [_checkButton setSelected:checked animated:animated bump:true];
}

- (void)setHighlighted:(BOOL)highlighted
{
    highlighted = false;
    [super setHighlighted:highlighted];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    highlighted = false;
    animated = false;
    [super setHighlighted:highlighted animated:animated];
}

- (void)setSelected:(BOOL)__unused selected animated:(BOOL)__unused animated
{
}

- (void)setIsLastCell:(bool)lastCell
{
    _isLastCell = lastCell;
    [self setNeedsLayout];
}

- (void)setupWithPeer:(id)peer feed:(bool)feed
{
    _feed = feed;
    
    CGFloat diameter = TGIsPad() ? 45.0f : 40.0f;
    
    UIImage *placeholder = [self.presentation.images avatarPlaceholderWithDiameter:diameter];
    UIColor *subLabelColor = self.presentation.pallete.secondaryTextColor;
    UIColor *backgroundColor = self.presentation.pallete.backgroundColor;
    
    _nameLabel.textColor = self.presentation.pallete.textColor;
    
    NSString *title = nil;
    NSString *subtitle = TGLocalized(@"Channel.NotificationLoading");
    if ([peer isKindOfClass:[TGConversation class]])
    {
        TGConversation *conversation = (TGConversation *)peer;
        _peerId = conversation.conversationId;
        
        if (conversation.pinnedToTop)
            backgroundColor = self.presentation.pallete.dialogPinnedBackgroundColor;
        
        if (conversation.additionalProperties[@"user"] != nil)
        {
            TGUser *user = conversation.additionalProperties[@"user"];
            
            if (user.photoUrlSmall.length != 0)
            {
                _avatarView.fadeTransitionDuration = 0.3;
                if (![user.photoFullUrlSmall isEqualToString:_avatarView.currentUrl])
                {
                    [_avatarView loadImage:user.photoFullUrlSmall filter:TGIsPad() ? @"circle:45x45" : @"circle:40x40" placeholder:placeholder];
                }
            }
            else
            {
                [_avatarView loadUserPlaceholderWithSize:CGSizeMake(diameter, diameter) uid:user.uid firstName:user.firstName lastName:user.lastName placeholder:placeholder];
            }
            
            title = user.displayName;
            
            NSString *presenceString = TGLocalized(@"Presence.offline");
            if (user.kind != TGUserKindGeneric)
            {
                presenceString = TGLocalized(@"Bot.GenericBotStatus");
            }
            else
            {
                if (user.presence.online)
                {
                    presenceString = TGLocalized(@"Presence.online");
                    subLabelColor = self.presentation.pallete.accentColor;
                }
                else if (user.presence.lastSeen != 0)
                {
                    presenceString = [TGDateUtils stringForRelativeLastSeen:user.presence.lastSeen];
                }
            }
            
            subtitle = presenceString;
        }
        else
        {
            if (conversation.conversationId == TGTelegraphInstance.clientUserId)
            {
                backgroundColor = self.presentation.pallete.dialogPinnedBackgroundColor;
                title = TGLocalized(@"DialogList.SavedMessages");
                subtitle = @"";
                [_avatarView loadSavedMessagesWithSize:CGSizeMake(diameter, diameter) placeholder:placeholder];
            }
            else
            {
                title = conversation.chatTitle;
                if (!conversation.isChannel)
                {
                    subtitle = [effectiveLocalization() getPluralized:@"Conversation.StatusMembers" count:(int32_t)conversation.chatParticipantCount];;
                }
                else
                {
                    SSignal *signal = [[[TGDatabaseInstance() channelCachedData:conversation.conversationId] take:1] mapToSignal:^SSignal *(TGCachedConversationData *data) {
                        if (data.memberCount != 0)
                        {
                            return [SSignal single:@(data.memberCount)];
                        }
                        else
                        {
                            return [[TGChannelManagementSignals updateChannelExtendedInfo:conversation.conversationId accessHash:conversation.accessHash updateUnread:false] then:[[[TGDatabaseInstance() channelCachedData:conversation.conversationId] take:1] map:^id(TGCachedConversationData *data)
                            {
                                return @(data.memberCount);
                            }]];
                        }
                    }];
                    
                    if (!_feed)
                    {
                        __weak TGShareTargetCell *weakSelf = self;
                        [_channelDisposable setDisposable:[[signal deliverOn:[SQueue mainQueue]] startWithNext:^(NSNumber *memberCount)
                        {
                            __strong TGShareTargetCell *strongSelf = weakSelf;
                            if (strongSelf != nil) {
                                strongSelf->_subLabel.text = [effectiveLocalization() getPluralized:@"Conversation.StatusMembers" count:memberCount.int32Value];
                                strongSelf->_subLabel.textColor = subLabelColor;
                                [strongSelf->_subLabel sizeToFit];
                                
                                [strongSelf setNeedsLayout];
                            }
                        }]];
                    }
                }
                
                if (conversation.chatPhotoFullSmall.length != 0)
                {
                    _avatarView.fadeTransitionDuration = 0.3;
                    if (![conversation.chatPhotoFullSmall isEqualToString:_avatarView.currentUrl])
                    {
                        [_avatarView loadImage:conversation.chatPhotoFullSmall filter:TGIsPad() ? @"circle:45x45" : @"circle:40x40" placeholder:placeholder];
                    }
                }
                else
                {
                    [_avatarView loadGroupPlaceholderWithSize:CGSizeMake(diameter, diameter) conversationId:conversation.conversationId title:conversation.chatTitle placeholder:placeholder];
                }
            }
        }
    }
    else if ([peer isKindOfClass:[TGUser class]])
    {
        TGUser *user = (TGUser *)peer;
        _peerId = user.uid;
        
        if (user.photoUrlSmall.length != 0)
        {
            _avatarView.fadeTransitionDuration = 0.3;
            if (![user.photoFullUrlSmall isEqualToString:_avatarView.currentUrl])
            {
                [_avatarView loadImage:user.photoFullUrlSmall filter:TGIsPad() ? @"circle:45x45" : @"circle:40x40" placeholder:placeholder];
            }
        }
        else
        {
            [_avatarView loadUserPlaceholderWithSize:CGSizeMake(diameter, diameter) uid:user.uid firstName:user.firstName lastName:user.lastName placeholder:placeholder];
        }
        
        title = user.displayName;
        
        NSString *presenceString = TGLocalized(@"Presence.offline");
        if (user.kind != TGUserKindGeneric)
        {
            presenceString = TGLocalized(@"Bot.GenericBotStatus");
        }
        else
        {
            if (user.presence.online)
            {
                presenceString = TGLocalized(@"Presence.online");
                subLabelColor = self.presentation.pallete.accentColor;
            }
            else if (user.presence.lastSeen != 0)
            {
                presenceString = [TGDateUtils stringForRelativeLastSeen:user.presence.lastSeen];
            }
        }
        
        subtitle = presenceString;
    }
    
    if (_feed)
        subtitle = nil;
    
    self.backgroundColor = backgroundColor;
    
    _nameLabel.text = title;
    [_nameLabel sizeToFit];
    
    _subLabel.text = subtitle;
    _subLabel.textColor = subLabelColor;
    [_subLabel sizeToFit];
    
    [self setNeedsLayout];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_channelDisposable setDisposable:nil];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    CGFloat separatorHeight = TGSeparatorHeight();
    CGFloat separatorInset = _isLastCell ? 0.0f : _feed ? 99.0f : 65.0f;
    _separatorLayer.frame = CGRectMake(separatorInset, self.frame.size.height - separatorHeight, self.frame.size.width - separatorInset, separatorHeight);
    
    CGRect frame = self.selectedBackgroundView.frame;
    frame.origin.y = -1;
    frame.size.height = self.frame.size.height + 1;
    self.selectedBackgroundView.frame = frame;
    
    if (_feed)
        _avatarView.frame = CGRectMake(48.0f, _avatarView.frame.origin.y, _avatarView.frame.size.width, _avatarView.frame.size.height);
    
    CGFloat leftPadding = CGRectGetMaxX(_avatarView.frame) + 12.0f;
    CGFloat nameOrigin = 5.0f;
    if (_subLabel.text.length == 0)
        nameOrigin = round((self.frame.size.height - _nameLabel.frame.size.height) / 2.0f);
        
    _nameLabel.frame = CGRectMake(leftPadding, nameOrigin, MIN(_nameLabel.frame.size.width, self.frame.size.width - leftPadding - _checkButton.frame.size.width - 30.0f), _nameLabel.frame.size.height);
    _subLabel.frame = CGRectMake(leftPadding, 26.0f, MIN(_subLabel.frame.size.width, self.frame.size.width - leftPadding - _checkButton.frame.size.width - 30.0f), _subLabel.frame.size.height);
    
    CGRect checkFrame = CGRectMake(_feed ? 7.0f : self.frame.size.width - _checkButton.frame.size.width - 10.0f, (CGFloat)ceil((self.frame.size.height - _checkButton.frame.size.height) / 2.0f), _checkButton.frame.size.width, _checkButton.frame.size.height);
    _checkButton.frame = checkFrame;
}

@end
