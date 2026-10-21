#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static unsigned long long MBDirectorySize(NSString *path) {
    if (path.length == 0) return 0;
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return 0;
    }
    unsigned long long total = 0;
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtPath:path];
    for (NSString *relative in enumerator) {
        NSString *full = [path stringByAppendingPathComponent:relative];
        NSDictionary *attributes = [manager attributesOfItemAtPath:full error:NULL];
        if ([[attributes fileType] isEqualToString:NSFileTypeRegular]) {
            total += [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        }
    }
    return total;
}

static NSString *MBFormatBytes(unsigned long long bytes) {
    if (bytes >= 1024ULL * 1024ULL * 1024ULL) {
        return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    }
    if (bytes >= 1024ULL * 1024ULL) {
        return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    }
    if (bytes >= 1024ULL) {
        return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
    }
    return [NSString stringWithFormat:@"%llu B", bytes];
}

static void MusicBackgroundApplySession(void) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setActive:YES error:&error];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
}

@interface SettingsVC : UITableViewController
- (void)clearCache;
- (void)clearDownloads;
@end

@interface SettingsVC (MusicBackgroundCache)
- (void)mb_viewDidLoad;
- (void)mb_cacheTapped:(id)sender;
@end

@implementation SettingsVC (MusicBackgroundCache)

- (void)mb_viewDidLoad {
    [self mb_viewDidLoad];
    if (self.navigationController) {
        UIBarButtonItem *cacheButton = [[UIBarButtonItem alloc] initWithTitle:@"缓存"
                                                                        style:UIBarButtonItemStyleBordered
                                                                       target:self
                                                                       action:@selector(mb_cacheTapped:)];
        self.navigationItem.rightBarButtonItem = cacheButton;
    } else {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(self.view.bounds.size.width - 72.0, 6.0, 64.0, 30.0);
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        button.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.95];
        button.layer.cornerRadius = 6.0;
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.25] CGColor];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        [button setTitle:@"缓存" forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(mb_cacheTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:button];
    }
}

- (void)mb_cacheTapped:(id)sender {
    NSString *home = NSHomeDirectory();
    NSString *caches = [home stringByAppendingPathComponent:@"Library/Caches"];
    NSString *documents = [home stringByAppendingPathComponent:@"Documents"];
    NSString *support = [home stringByAppendingPathComponent:@"Library/Application Support"];
    unsigned long long cacheSize = MBDirectorySize(NSTemporaryDirectory()) + MBDirectorySize(caches);
    unsigned long long documentSize = MBDirectorySize(documents) + MBDirectorySize(support);

    NSString *message = [NSString stringWithFormat:
                         @"临时/图片缓存：%@\n下载/文档：%@\n\n可在下面“清理”里清除缓存或下载。",
                         MBFormatBytes(cacheSize), MBFormatBytes(documentSize)];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"缓存管理"
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"好"
                                          otherButtonTitles:nil];
    [alert show];
}

@end

static void MBSwizzle(Class cls, SEL original, SEL replacement) {
    if (!cls) return;
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) {
        method_exchangeImplementations(a, b);
    }
}

__attribute__((constructor))
static void MusicBackgroundInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        MusicBackgroundApplySession();
    });

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        MusicBackgroundApplySession();
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        MusicBackgroundApplySession();
    }];

    Class settingsClass = objc_getClass("SettingsVC");
    if (settingsClass) {
        MBSwizzle(settingsClass, @selector(viewDidLoad), @selector(mb_viewDidLoad));
    }
}
