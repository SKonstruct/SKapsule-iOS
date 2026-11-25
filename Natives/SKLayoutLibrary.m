#import "SKLayoutLibrary.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SKLayoutShare.h"
#import "SKTouchControlOverlay.h"

@interface SKLayoutLibrary ()
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) SKTouchControlOverlay *overlay;
@property (nonatomic, strong) SKLayoutPresets *presets;
/// The temporary file an export hands to the picker; removed when the picker is done with it.
@property (nonatomic, strong) NSURL *exportURL;
@property (nonatomic, assign) BOOL pickingImport;
@end

@implementation SKLayoutLibrary

- (instancetype)initWithPresenter:(UIViewController *)presenter overlay:(SKTouchControlOverlay *)overlay {
    self = [super init];
    if (self) {
        _presenter = presenter;
        _overlay = overlay;
        _presets = [[SKLayoutPresets alloc] initWithDefaults:NSUserDefaults.standardUserDefaults
                                                    knownIds:[SKTouchLayout knownNodeIds]];
    }
    return self;
}

#pragma mark - List

- (void)show {
    UIViewController *presenter = self.presenter;
    if (!presenter) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Layouts", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    NSString *active = self.presets.active;
    [sheet addAction:[UIAlertAction actionWithTitle:[self mark:NSLocalizedString(@"Default (built-in)", nil)
                                                        active:[active isEqualToString:SKLayoutBuiltInName]]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                              [weakSelf confirmApplyName:SKLayoutBuiltInName preset:nil intro:nil];
                                            }]];
    for (SKSharedLayout *preset in [self.presets all]) {
        [sheet addAction:[UIAlertAction actionWithTitle:[self mark:preset.name active:[active isEqualToString:preset.name]]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
                                                  [weakSelf confirmApplyName:preset.name preset:preset intro:nil];
                                                }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"＋ Save current layout as preset…", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [weakSelf promptSave]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Export current layout to file…", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [weakSelf startExport]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Import layout from file…", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [weakSelf startImport]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    popover.sourceView = presenter.view;
    popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    popover.permittedArrowDirections = 0;
    [presenter presentViewController:sheet animated:YES completion:nil];
}

- (NSString *)mark:(NSString *)label active:(BOOL)active {
    return active ? [@"✓ " stringByAppendingString:label] : label;
}

#pragma mark - Apply and delete

/// `preset` nil means the built-in default. `intro` leads the message after an import.
- (void)confirmApplyName:(NSString *)name preset:(SKSharedLayout *)preset intro:(NSString *)intro {
    NSString *message = NSLocalizedString(@"This replaces your current arrangement. Save it as a preset first to keep it.", nil);
    if (intro) message = [NSString stringWithFormat:@"%@\n\n%@", intro, message];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Apply \"%@\"?", nil), name]
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Apply", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                              [weakSelf.overlay applySharedLayout:preset];
                                              weakSelf.presets.active = name;
                                              [weakSelf toast:[NSString stringWithFormat:NSLocalizedString(@"Applied \"%@\"", nil), name]];
                                            }]];
    // The built-in default can't be deleted.
    if (preset) {
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete", nil)
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *a) { [weakSelf confirmDelete:name]; }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self.presenter presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDelete:(NSString *)name {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Delete \"%@\"?", nil), name]
                                            message:NSLocalizedString(@"The preset is removed. The layout on screen is not changed.", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete", nil)
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
                                              [weakSelf.presets deleteNamed:name];
                                              [weakSelf toast:[NSString stringWithFormat:NSLocalizedString(@"Deleted \"%@\"", nil), name]];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self.presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Save

- (void)promptSave {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Save current layout", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = NSLocalizedString(@"Preset name", nil);
    }];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Save", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                              typeof(self) strongSelf = weakSelf;
                                              if (!strongSelf) return;
                                              NSString *typed = weakAlert.textFields.firstObject.text;
                                              SKSharedLayout *shared = [strongSelf.overlay.layout sharedLayoutNamed:typed];
                                              NSString *name = [strongSelf.presets addLayout:shared];
                                              if (!name) {
                                                  [strongSelf toastPresetListFull];
                                                  return;
                                              }
                                              strongSelf.presets.active = name;
                                              [strongSelf toast:[NSString stringWithFormat:NSLocalizedString(@"Saved as \"%@\"", nil), name]];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self.presenter presentViewController:alert animated:YES completion:nil];
}

- (void)toastPresetListFull {
    [self toast:[NSString stringWithFormat:NSLocalizedString(@"Preset list is full (%ld). Delete one first.", nil),
                                           (long)SKLayoutShareMaxPresets]];
}

#pragma mark - Export and import

- (NSString *)exportName {
    NSString *active = self.presets.active;
    return (active.length && ![active isEqualToString:SKLayoutBuiltInName]) ? active : NSLocalizedString(@"My layout", nil);
}

- (void)startExport {
    SKSharedLayout *shared = [self.overlay.layout sharedLayoutNamed:[self exportName]];
    NSString *slug = [[shared.name lowercaseString] stringByReplacingOccurrencesOfString:@"[^a-z0-9]+"
                                                                              withString:@"-"
                                                                                 options:NSRegularExpressionSearch
                                                                                   range:NSMakeRange(0, shared.name.length)];
    slug = [slug stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-"]];
    if (slug.length == 0) slug = @"layout";
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"skapsule-controls-%@.json", slug]];
    if (![[shared jsonData] writeToURL:url options:NSDataWritingAtomic error:nil]) {
        [self toast:NSLocalizedString(@"Could not write the file", nil)];
        return;
    }
    self.exportURL = url;
    self.pickingImport = NO;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[ url ] asCopy:YES];
    picker.delegate = self;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}

- (void)startImport {
    self.pickingImport = YES;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeJSON, UTTypeData ] asCopy:YES];
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.pickingImport) {
        if (urls.firstObject) [self readImport:urls.firstObject];
    } else {
        [self toast:NSLocalizedString(@"Layout exported", nil)];
        [self removeExportFile];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (!self.pickingImport) [self removeExportFile];
}

- (void)removeExportFile {
    if (self.exportURL) [NSFileManager.defaultManager removeItemAtURL:self.exportURL error:nil];
    self.exportURL = nil;
}

- (void)readImport:(NSURL *)url {
    BOOL scoped = [url startAccessingSecurityScopedResource];  // a no-op for a copy, harmless
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    // One byte more than the cap, so a file that is too big is refused rather than truncated.
    NSData *data = [handle readDataUpToLength:SKLayoutShareMaxBytes + 1 error:nil];
    [handle closeFile];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!data) {
        [self toast:NSLocalizedString(@"Could not read the file", nil)];
        return;
    }
    NSError *error = nil;
    SKSharedLayout *shared = [SKSharedLayout parseData:data knownIds:[SKTouchLayout knownNodeIds] error:&error];
    if (!shared) {
        switch (error.code) {
            case SKLayoutShareErrorNewer:
                [self toast:NSLocalizedString(@"That layout was made by a newer version of SKapsule.", nil)];
                break;
            case SKLayoutShareErrorTooLarge:
                [self toast:NSLocalizedString(@"That file is too large to be a layout.", nil)];
                break;
            default:
                [self toast:NSLocalizedString(@"That file isn't a valid SKapsule controls layout.", nil)];
                break;
        }
        return;
    }
    NSString *name = [self.presets addLayout:shared];
    if (!name) {
        [self toastPresetListFull];
        return;
    }
    [self confirmApplyName:name
                    preset:[self.presets presetNamed:name]
                     intro:[NSString stringWithFormat:NSLocalizedString(@"Imported as \"%@\".", nil), name]];
}

#pragma mark - Toast

/// A short message that fades on its own, like Android's Toast.
- (void)toast:(NSString *)message {
    UIView *host = self.presenter.view;
    if (!host) return;
    UILabel *label = [UILabel new];
    label.text = [NSString stringWithFormat:@"  %@  ", message];
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:14];
    label.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
    label.layer.cornerRadius = 14;
    label.clipsToBounds = YES;
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [label.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [label.heightAnchor constraintEqualToConstant:32],
    ]];
    [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{ label.alpha = 0; } completion:^(BOOL done) {
        [label removeFromSuperview];
    }];
}

@end
