#import "TGFlatActionCell.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TGInterfaceAssets.h"

#import "TGPresentation.h"

@interface TGFlatActionCell ()
{
    CALayer *_separatorLayer;
    NSString *_phoneNumber;
}

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *iconView;

@end

@implementation TGFlatActionCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self)
    {
        UIView *selectedView = [[UIView alloc] init];
        selectedView.backgroundColor = TGSelectionColor();
        self.selectedBackgroundView = selectedView;
        
        CGFloat originX = TGIsPad() ? 74.0f : 66.0f;
        
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(originX, 14 - TGRetinaPixel + (TGIsPad() ? 4.0f : 0.0f), self.contentView.frame.size.width - originX - 6, 20)];
        _titleLabel.contentMode = UIViewContentModeLeft;
        _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _titleLabel.font = TGSystemFontOfSize(17);
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.textColor = TGAccentColor();
        [self.contentView addSubview:_titleLabel];
        
        _iconView = [[UIImageView alloc] init];
        [self.contentView addSubview:_iconView];
        
        _separatorLayer = [[CALayer alloc] init];
        _separatorLayer.backgroundColor = TGSeparatorColor().CGColor;
        [self.contentView.layer addSublayer:_separatorLayer];
    }
    return self;
}

- (void)setPresentation:(TGPresentation *)presentation
{
    _presentation = presentation;
    
    self.backgroundColor = presentation.pallete.backgroundColor;

    _titleLabel.textColor = _presentation.pallete.accentColor;
    
    _separatorLayer.backgroundColor = presentation.pallete.separatorColor.CGColor;
    self.selectedBackgroundView.backgroundColor = presentation.pallete.selectionColor;
}

- (void)setMode:(TGFlatActionCellMode)mode
{
    _mode = mode;
    
    if (mode == TGFlatActionCellModeInvite)
        _titleLabel.text = TGLocalized(@"Contacts.InviteFriends");
    else if (mode == TGFlatActionCellModeCreateGroup || mode == TGFlatActionCellModeCreateGroupContacts)
        _titleLabel.text = TGLocalized(@"Compose.NewGroup");
    else if (mode == TGFlatActionCellModeCreateEncrypted)
        _titleLabel.text = TGLocalized(@"Compose.NewEncryptedChat");
    else if (mode == TGFlatActionCellModeCreateChannel)
        _titleLabel.text = TGLocalized(@"Compose.NewChannel");
    else if (mode == TGFlatActionCellModeCreateChannelGroup)
        _titleLabel.text = TGLocalized(@"Compose.NewChannelGroupButton");
    else if (mode == TGFlatActionCellModeAddPhoneNumber)
        _titleLabel.text = [NSString stringWithFormat:TGLocalized(@"Contacts.AddPhoneNumber"), _phoneNumber];
    else if (mode == TGFlatActionCellModeShareApp)
        _titleLabel.text = TGLocalized(@"Contacts.ShareTelegram");

    CGFloat verticalOffset = TGIsPad() ? 4.0f : 0.0f;
    CGFloat horizontalOffset = TGIsPad() ? 8.0f : 0.0f;
    
    if (mode == TGFlatActionCellModeInvite)
    {
        _iconView.image = self.presentation.images.contactsInviteIcon;
        [_iconView sizeToFit];
        
        CGRect iconFrame = _iconView.frame;
        iconFrame.origin = CGPointMake(14.0f + horizontalOffset, 5.0f + verticalOffset);
        _iconView.frame = iconFrame;
    }
    else if (mode == TGFlatActionCellModeCreateGroup || mode == TGFlatActionCellModeCreateGroupContacts || mode == TGFlatActionCellModeCreateChannelGroup)
    {
        _iconView.image = self.presentation.images.contactsNewGroupIcon;
        [_iconView sizeToFit];
        
        CGRect iconFrame = _iconView.frame;
        iconFrame.origin = CGPointMake(14 + horizontalOffset, 5 + verticalOffset);
        _iconView.frame = iconFrame;
    }
    else if (mode == TGFlatActionCellModeCreateEncrypted)
    {
        _iconView.image = self.presentation.images.contactsNewEncryptedIcon;
        [_iconView sizeToFit];
        
        CGRect iconFrame = _iconView.frame;
        iconFrame.origin = CGPointMake(14 + horizontalOffset - 1, 4 + verticalOffset);
        _iconView.frame = iconFrame;
    }
    else if (mode == TGFlatActionCellModeChannels || mode == TGFlatActionCellModeCreateChannel)
    {
        _iconView.image = self.presentation.images.contactsNewChannelIcon;
        [_iconView sizeToFit];
        
        CGRect iconFrame = _iconView.frame;
        iconFrame.origin = CGPointMake(14 + horizontalOffset, 1 + verticalOffset + 3);
        _iconView.frame = iconFrame;
    }
    else if (mode == TGFlatActionCellModeAddPhoneNumber)
    {
        _iconView.image = self.presentation.images.contactsInviteIcon;
        [_iconView sizeToFit];
        
        CGRect iconFrame = _iconView.frame;
        iconFrame.origin = CGPointMake(14.0f + horizontalOffset, 5.0f + verticalOffset);
        _iconView.frame = iconFrame;
    }
    else if (mode == TGFlatActionCellModeShareApp)
    {
        _iconView.image = self.presentation.images.contactsShareIcon;
        [_iconView sizeToFit];
        
        CGRect iconFrame = _iconView.frame;
        iconFrame.origin = CGPointMake(14.0f + horizontalOffset, 5.0f + verticalOffset);
        _iconView.frame = iconFrame;
    }
}

- (void)setPhoneNumber:(NSString *)phoneNumber
{
    _phoneNumber = [TGPhoneUtils formatPhone:phoneNumber forceInternational:true];
    [self setMode:TGFlatActionCellModeAddPhoneNumber];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    
    if (selected)
    {
        CGRect frame = self.selectedBackgroundView.frame;
        frame.origin.y = -1;
        frame.size.height = self.frame.size.height + 1;
        self.selectedBackgroundView.frame = frame;
        
        [self adjustOrdering];
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    [super setHighlighted:highlighted animated:animated];
    
    if (highlighted)
    {
        CGRect frame = self.selectedBackgroundView.frame;
        frame.origin.y = -1;
        frame.size.height = self.frame.size.height + 1;
        self.selectedBackgroundView.frame = frame;
        
        [self adjustOrdering];
    }
}

- (void)adjustOrdering
{
    if ([self.superview isKindOfClass:[UITableView class]])
    {
        Class UITableViewCellClass = [UITableViewCell class];
        Class UISearchBarClass = [UISearchBar class];
        int maxCellIndex = 0;
        int index = -1;
        int selfIndex = 0;
        for (UIView *view in self.superview.subviews)
        {
            index++;
            if ([view isKindOfClass:UITableViewCellClass] || [view isKindOfClass:UISearchBarClass])// || ((int)view.frame.size.height) == 25)
            {
                maxCellIndex = index;
                
                if (view == self)
                    selfIndex = index;
            }
        }
        
        if (selfIndex < maxCellIndex)
        {
            [self.superview insertSubview:self atIndex:maxCellIndex];
        }
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    CGFloat separatorHeight = TGScreenPixel;
    
    CGRect frame = self.selectedBackgroundView.frame;
    frame.origin.y = -1;
    frame.size.height = self.frame.size.height + 1;
    self.selectedBackgroundView.frame = frame;
    
    CGFloat separatorOrigin = (TGIsPad() ? 74.0f : 65.0f);
    _separatorLayer.frame = CGRectMake(separatorOrigin, self.frame.size.height - separatorHeight, self.frame.size.width - separatorOrigin, separatorHeight);
}

@end
