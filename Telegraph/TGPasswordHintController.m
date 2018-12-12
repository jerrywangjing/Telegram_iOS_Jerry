#import "TGPasswordHintController.h"

#import "TGPasswordSetupView.h"

#import "TGPresentation.h"

@interface TGPasswordHintController ()
{
    NSString *_password;
    TGPasswordSetupView *_view;
    UIBarButtonItem *_nextItem;
}

@end

@implementation TGPasswordHintController

- (instancetype)initWithPassword:(NSString *)password
{
    self = [super init];
    if (self != nil)
    {
        _password = password;
        
        self.title = TGLocalized(@"TwoStepAuth.SetupHintTitle");
        
        _nextItem = [[UIBarButtonItem alloc] initWithTitle:TGLocalized(@"Common.Next") style:UIBarButtonItemStyleDone target:self action:@selector(nextPressed)];
        [self setRightBarButtonItem:_nextItem];
        _nextItem.enabled = true;
        
        self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:TGLocalized(@"Common.Back") style:UIBarButtonItemStylePlain target:self action:@selector(backPressed)];
    }
    return self;
}

- (void)backPressed
{
    [self.navigationController popViewControllerAnimated:true];
}

- (void)nextPressed
{
    if (_completion)
        _completion(_view.password);
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [_view becomeFirstResponder];
}

- (void)loadView
{
    [super loadView];
    
    TGPresentation *presentation = TGPresentation.current;
    self.view.backgroundColor = presentation.pallete.collectionMenuBackgroundColor;
    
    _view = [[TGPasswordSetupView alloc] initWithFrame:self.view.bounds];
    _view.presentation = presentation;
    _view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _view.secureEntry = false;
    __weak TGPasswordHintController *weakSelf = self;
    _view.returnPressed = ^(__unused NSString *password)
    {
        __strong TGPasswordHintController *strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf nextPressed];
        }
    };
    [self.view addSubview:_view];
    
    [_view setTitle:TGLocalized(@"TwoStepAuth.SetupHint")];
    
    if (![self _updateControllerInset:false])
        [self controllerInsetUpdated:UIEdgeInsetsZero];
}

- (void)controllerInsetUpdated:(UIEdgeInsets)previousInset
{
    [super controllerInsetUpdated:previousInset];
    
    if (!self.viewControllerIsDisappearing)
        [_view setContentInsets:self.controllerInset];
}

- (bool)willCaptureInputShortly
{
    return true;
}

@end
