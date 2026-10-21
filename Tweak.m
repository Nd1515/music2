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

#pragma mark - Settings cache size

@interface SettingsVC : UITableViewController
@end

@interface SettingsVC (MusicBackgroundCache)
- (UITableViewCell *)mb_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
@end

@implementation SettingsVC (MusicBackgroundCache)

- (UITableViewCell *)mb_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self mb_tableView:tableView cellForRowAtIndexPath:indexPath];
    NSString *text = cell.textLabel.text;
    if ([text rangeOfString:@"清除缓存"].location != NSNotFound) {
        cell.textLabel.text = [NSString stringWithFormat:@"清除缓存（%@）", MBFormatBytes(MBCacheSize())];
    } else if ([text rangeOfString:@"清除下载"].location != NSNotFound) {
        cell.textLabel.text = [NSString stringWithFormat:@"清除下载（%@）", MBFormatBytes(MBDownloadSize())];
    }
    return cell;
}

@end

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

    Class settingsClass = objc_getClass("SettingsVC");
    if (settingsClass) {
        MBSwizzle(settingsClass, @selector(tableView:cellForRowAtIndexPath:), @selector(mb_tableView:cellForRowAtIndexPath:));
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[Player sh] performSelector:@selector(mb_updateNowPlaying) withObject:nil];
    });
}
