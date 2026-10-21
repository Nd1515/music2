#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
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

static unsigned long long MBCacheSize(void) {
    NSString *home = NSHomeDirectory();
    return MBDirectorySize(NSTemporaryDirectory()) +
           MBDirectorySize([home stringByAppendingPathComponent:@"Library/Caches"]);
}

static unsigned long long MBDownloadSize(void) {
    NSString *home = NSHomeDirectory();
    return MBDirectorySize([home stringByAppendingPathComponent:@"Documents"]) +
           MBDirectorySize([home stringByAppendingPathComponent:@"Library/Application Support"]);
}

static void MusicBackgroundApplySession(void) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setActive:YES error:&error];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
}

#pragma mark - App classes

@interface Song : NSObject
@property (nonatomic, copy) NSString *n;
@property (nonatomic, copy) NSString *a;
@property (nonatomic, copy) NSString *u;
@property (nonatomic, copy) NSString *p;
@end

@interface Player : NSObject
+ (instancetype)sh;
- (Song *)cur;
- (AVPlayer *)av;
- (double)knownDuration;
- (void)next;
- (void)prev;
- (void)toggle;
- (void)playURL:(id)url local:(BOOL)local;
@end

@interface Player (MusicBackgroundMedia)
- (void)mb_playURL:(id)url local:(BOOL)local;
- (void)mb_next;
- (void)mb_prev;
- (void)mb_toggle;
- (void)mb_updateNowPlaying;
@end

@implementation Player (MusicBackgroundMedia)

- (void)mb_updateNowPlaying {
    Song *song = [self cur];
    if (!song) {
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
        return;
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSString *name = [song valueForKey:@"n"];
    NSString *artist = [song valueForKey:@"a"];
    if (name.length) [info setObject:name forKey:MPMediaItemPropertyTitle];
    if (artist.length) [info setObject:artist forKey:MPMediaItemPropertyArtist];

    AVPlayer *player = [self av];
    if (player) {
        double elapsed = CMTimeGetSeconds(player.currentTime);
        if (isfinite(elapsed) && elapsed >= 0) {
            [info setObject:[NSNumber numberWithDouble:elapsed] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        }
        [info setObject:[NSNumber numberWithDouble:(player.rate > 0.01 ? 1.0 : 0.0)]
                 forKey:MPNowPlayingInfoPropertyPlaybackRate];
    }
    double duration = [self knownDuration];
    if (isfinite(duration) && duration > 0) {
        [info setObject:[NSNumber numberWithDouble:duration] forKey:MPMediaItemPropertyPlaybackDuration];
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
}

- (void)mb_playURL:(id)url local:(BOOL)local {
    [self mb_playURL:url local:local];
    [self performSelector:@selector(mb_updateNowPlaying) withObject:nil afterDelay:0.3];
}

- (void)mb_next {
    [self mb_next];
    [self performSelector:@selector(mb_updateNowPlaying) withObject:nil afterDelay:0.3];
}

- (void)mb_prev {
    [self mb_prev];
    [self performSelector:@selector(mb_updateNowPlaying) withObject:nil afterDelay:0.3];
}

- (void)mb_toggle {
    [self mb_toggle];
    [self performSelector:@selector(mb_updateNowPlaying) withObject:nil afterDelay:0.2];
}

@end

static void MBRemoteControl(id self, SEL _cmd, UIEvent *event) {
    if (event.type != UIEventTypeRemoteControl) return;
    Player *player = [Player sh];
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlPlay:
        case UIEventSubtypeRemoteControlPause:
        case UIEventSubtypeRemoteControlTogglePlayPause:
            [player toggle];
            break;
        case UIEventSubtypeRemoteControlNextTrack:
            [player next];
            break;
        case UIEventSubtypeRemoteControlPreviousTrack:
            [player prev];
            break;
        case UIEventSubtypeRemoteControlStop:
            if ([[player av] rate] > 0.01) [player toggle];
            break;
        default:
            break;
    }
}



#pragma mark - Cache page

@interface MBCacheViewController : UITableViewController <UIAlertViewDelegate>
@end

@implementation MBCacheViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"缓存管理";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                             style:UIBarButtonItemStyleBordered
                                                                            target:self
                                                                            action:@selector(closeTapped:)];
}

- (void)closeTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : (section == 1 ? 2 : 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"当前占用";
    if (section == 1) return @"清理";
    return @"说明";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MBCacheCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [UIColor blackColor];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"临时/图片缓存";
            cell.detailTextLabel.text = MBFormatBytes(MBCacheSize());
        } else {
            cell.textLabel.text = @"下载/文档";
            cell.detailTextLabel.text = MBFormatBytes(MBDownloadSize());
        }
    } else if (indexPath.section == 1) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"清除缓存";
        } else {
            cell.textLabel.text = @"清除下载";
            cell.textLabel.textColor = [UIColor colorWithRed:0.8 green:0.15 blue:0.1 alpha:1.0];
        }
    } else {
        cell.textLabel.text = @"清除下载会删除离线歌曲、歌词和封面";
        cell.textLabel.font = [UIFont systemFontOfSize:12.0];
        cell.textLabel.textColor = [UIColor grayColor];
        cell.textLabel.numberOfLines = 0;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    NSInteger tag = indexPath.row + 1;
    NSString *title = (tag == 1) ? @"清除缓存" : @"清除下载";
    NSString *message = (tag == 1)
        ? [NSString stringWithFormat:@"将清除临时文件和图片缓存（%@）。", MBFormatBytes(MBCacheSize())]
        : [NSString stringWithFormat:@"将删除所有下载的歌曲、歌词和封面（%@）。", MBFormatBytes(MBDownloadSize())];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"取消"
                                          otherButtonTitles:@"清除", nil];
    alert.tag = tag;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != 1) return;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *home = NSHomeDirectory();
    if (alertView.tag == 1) {
        [self clearDirectory:NSTemporaryDirectory()];
        [self clearDirectory:[home stringByAppendingPathComponent:@"Library/Caches"]];
    } else {
        [self clearDirectory:[home stringByAppendingPathComponent:@"Documents"]];
        [self clearDirectory:[home stringByAppendingPathComponent:@"Library/Application Support"]];
    }
    [manager createDirectoryAtPath:[home stringByAppendingPathComponent:@"Documents"]
       withIntermediateDirectories:YES attributes:nil error:NULL];
    [self.tableView reloadData];
}

- (void)clearDirectory:(NSString *)path {
    if (path.length == 0) return;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *items = [manager contentsOfDirectoryAtPath:path error:NULL];
    for (NSString *item in items) {
        [manager removeItemAtPath:[path stringByAppendingPathComponent:item] error:NULL];
    }
}

@end

@interface MBCacheLauncher : NSObject
- (void)open:(id)sender;
@end

@implementation MBCacheLauncher
- (void)open:(id)sender {
    UIViewController *top = [[UIApplication sharedApplication] keyWindow].rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    MBCacheViewController *controller = [[MBCacheViewController alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    [top presentViewController:navigation animated:YES completion:nil];
}
@end

static void MBInstallCacheButton(void) {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window) return;
    if ([window viewWithTag:0x4D424332]) return;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(10.0, window.bounds.size.height - 100.0, 54.0, 30.0);
    button.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.9];
    button.layer.cornerRadius = 6.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.25] CGColor];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    [button setTitle:@"缓存" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.tag = 0x4D424332;
    MBCacheLauncher *launcher = [[MBCacheLauncher alloc] init];
    objc_setAssociatedObject(button, "MBCacheLauncher", launcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [button addTarget:launcher action:@selector(open:) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button];
}

#pragma mark - Swizzling

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

    Class playerClass = objc_getClass("Player");
    if (playerClass) {
        MBSwizzle(playerClass, @selector(playURL:local:), @selector(mb_playURL:local:));
        MBSwizzle(playerClass, @selector(next), @selector(mb_next));
        MBSwizzle(playerClass, @selector(prev), @selector(mb_prev));
        MBSwizzle(playerClass, @selector(toggle), @selector(mb_toggle));
    }

    Class appDelegateClass = objc_getClass("AppDelegate");
    if (appDelegateClass) {
        SEL remoteSelector = @selector(remoteControlReceivedWithEvent:);
        if (!class_addMethod(appDelegateClass, remoteSelector, (IMP)MBRemoteControl, "v@:@")) {
            class_replaceMethod(appDelegateClass, remoteSelector, (IMP)MBRemoteControl, "v@:@");
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[Player sh] performSelector:@selector(mb_updateNowPlaying) withObject:nil];
        MBInstallCacheButton();
    });
}


