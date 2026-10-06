#import "NSHostsImportController.h"
#import "NSHostsDownload.h"
#import "../Shared/NSLocalization.h"
#import "../Shared/NSHostsImport.h"
#import "../Shared/NSStore.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSError *NSHostsUIError(NSString *message) {
    return [NSError errorWithDomain:@"NetShield2.HostsImport"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

// Read at most the input limit plus one byte, even if a file grows while reading.
static NSData *NSReadHostsFile(NSURL *url, NSError **error) {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    __block NSData *data = nil;
    __block NSError *readError = nil;
    NSError *coordinationError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator
        coordinateReadingItemAtURL:url
                           options:0
                             error:&coordinationError
                        byAccessor:^(NSURL *readURL) {
                            NSNumber *regular = nil;
                            if (![readURL getResourceValue:&regular
                                                    forKey:NSURLIsRegularFileKey
                                                     error:&readError]) {
                                return;
                            }
                            if (!regular.boolValue) {
                                readError =
                                    NSHostsUIError(NSL(@"Choose a regular Hosts text file, not a folder."));
                                return;
                            }
                            NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:readURL
                                                                                       error:&readError];
                            if (!handle) {
                                return;
                            }
                            NSMutableData *buffer = [NSMutableData new];
                            while (buffer.length <= NSHostsMaximumBytes) {
                                NSUInteger remaining = NSHostsMaximumBytes + 1 - buffer.length;
                                NSData *chunk = [handle readDataUpToLength:MIN(65536u, remaining)
                                                                     error:&readError];
                                if (!chunk || !chunk.length) {
                                    break;
                                }
                                [buffer appendData:chunk];
                            }
                            [handle closeAndReturnError:NULL];
                            if (!readError) {
                                data = buffer;
                            }
                        }];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }
    if (error) {
        *error = coordinationError ?: readError;
    }
    return coordinationError || readError ? nil : data;
}

@interface NSHostsImportController () <UIDocumentPickerDelegate>
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, strong) UILabel *instructions;
@property(nonatomic, strong) UIButton *fileButton;
@property(nonatomic, strong) UITextField *urlField;
@property(nonatomic, strong) UIButton *downloadButton;
@property(nonatomic, strong) UIStackView *urlRow;
@property(nonatomic, strong) NSHostsDownload *downloader;
@property(nonatomic, strong) NSHostsImportPlan *preview;
@property(nonatomic, copy) NSString *sourceText;
@property(nonatomic) BOOL working;
@property(nonatomic) BOOL cancelled;
@end

@implementation NSHostsImportController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSL(@"Import Hosts");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSL(@"Preview")
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(next)];
    self.instructions = [UILabel new];
    self.instructions.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.instructions.adjustsFontForContentSizeCategory = YES;
    self.instructions.numberOfLines = 0;
    self.instructions.text = NSL(
        @"Paste Hosts text below, choose a file, or download from an HTTPS URL. UTF-8, up to 2 MiB. "
        @"Only 0.0.0.0, 127.0.0.1, :: and ::1 mappings become blocking rules. "
        @"Other IP mappings are skipped. Downloading does not import rules; confirm the preview to save.");
    self.fileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.fileButton setTitle:NSL(@"Choose Hosts File…") forState:UIControlStateNormal];
    [self.fileButton addTarget:self
                        action:@selector(chooseFileOrEdit)
              forControlEvents:UIControlEventTouchUpInside];
    self.urlField = [UITextField new];
    self.urlField.borderStyle = UITextBorderStyleRoundedRect;
    self.urlField.placeholder = @"https://example.com/hosts";
    self.urlField.accessibilityLabel = NSL(@"Hosts download URL");
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.urlField.smartQuotesType = UITextSmartQuotesTypeNo;
    self.urlField.smartDashesType = UITextSmartDashesTypeNo;
    self.urlField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.downloadButton setTitle:NSL(@"Download & Preview") forState:UIControlStateNormal];
    [self.downloadButton addTarget:self
                            action:@selector(downloadURL)
                  forControlEvents:UIControlEventTouchUpInside];
    self.urlRow = [[UIStackView alloc] initWithArrangedSubviews:@[ self.urlField, self.downloadButton ]];
    self.urlRow.axis = UILayoutConstraintAxisVertical;
    self.urlRow.spacing = 4;
    self.textView = [UITextView new];
    self.textView.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    self.textView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.textView.layer.cornerRadius = 8;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.textView.smartDashesType = UITextSmartDashesTypeNo;
    self.textView.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    self.textView.accessibilityLabel = NSL(@"Hosts text");
    UIStackView *stack = [[UIStackView alloc]
        initWithArrangedSubviews:@[ self.instructions, self.urlRow, self.fileButton, self.textView ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor
                                             constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12]
    ]];
    // Do not permit a swipe-dismiss during the final atomic save.
    self.navigationController.modalInPresentation = YES;
}
- (void)cancel {
    self.cancelled = YES;
    [self.downloader cancel];
    self.downloader = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)setWorkingState:(BOOL)working {
    self.working = working;
    self.fileButton.enabled = !working;
    self.downloadButton.enabled = !working;
    self.urlField.enabled = !working;
    self.urlRow.hidden = self.preview != nil;
    self.textView.editable = !working && !self.preview;
    self.navigationItem.rightBarButtonItem.enabled =
        !working && (!self.preview || self.preview.addedKeys.count > 0);
    self.navigationItem.rightBarButtonItem.title = working        ? NSL(@"Working…")
                                                   : self.preview ? NSL(@"Import")
                                                                  : NSL(@"Preview");
}
- (void)showImportError:(NSError *)error {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSL(@"Hosts not imported")
                         message:error.localizedDescription
                                     ?: NSL(@"Could not read or save the Hosts rules. No import was saved.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)chooseFileOrEdit {
    if (self.working) {
        return;
    }
    if (self.preview) {
        self.preview = nil;
        self.textView.text = self.sourceText;
        self.textView.accessibilityLabel = NSL(@"Hosts text");
        self.instructions.text =
            NSL(@"Edit the Hosts text and preview again. No rules are changed until Import.");
        [self.fileButton setTitle:NSL(@"Choose Hosts File…") forState:UIControlStateNormal];
        [self setWorkingState:NO];
        return;
    }
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeData ] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count != 1 || self.working || self.cancelled) {
        return;
    }
    void (^start)(void) = ^{
        if (!self.working && !self.cancelled) {
            [self beginPreviewWithFile:urls.firstObject text:nil];
        }
    };
    if (self.presentedViewController == controller) {
        [controller dismissViewControllerAnimated:YES completion:start];
    } else {
        start();
    }
}
- (void)next {
    if (self.working) {
        return;
    }
    [self.view endEditing:YES];
    if (self.preview) {
        [self savePreview];
    } else {
        [self beginPreviewWithFile:nil text:self.textView.text];
    }
}
- (void)downloadURL {
    if (self.working || self.cancelled || self.preview) {
        return;
    }
    [self.view endEditing:YES];
    NSHostsDownload *download = [NSHostsDownload new];
    self.downloader = download;
    [self setWorkingState:YES];
    __weak typeof(self) weakSelf = self;
    __weak NSHostsDownload *weakDownload = download;
    [download startURLString:self.urlField.text
                  completion:^(NSData *data, NSError *error) {
                      NSHostsImportController *owner = weakSelf;
                      if (!owner || owner.cancelled || owner.downloader != weakDownload) {
                          return;
                      }
                      owner.downloader = nil;
                      if (!data) {
                          [owner setWorkingState:NO];
                          [owner showImportError:error];
                          return;
                      }
                      [owner beginPreviewWithFile:nil text:nil data:data];
                  }];
}
- (void)beginPreviewWithFile:(NSURL *)url text:(NSString *)text {
    [self beginPreviewWithFile:url text:text data:nil];
}
- (void)beginPreviewWithFile:(NSURL *)url text:(NSString *)text data:(NSData *)downloadedData {
    if (!url && text.length > NSHostsMaximumBytes) {
        [self showImportError:NSHostsUIError(
                                  NSL(@"Hosts input exceeds the 2 MiB limit. Nothing was imported."))];
        return;
    }
    [self.view endEditing:YES];
    [self setWorkingState:YES];
    NSString *snapshot = [text copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            NSData *data = downloadedData
                               ?: (url ? NSReadHostsFile(url, &error)
                                       : [snapshot dataUsingEncoding:NSUTF8StringEncoding]);
            NSHostsImportResult *result = data ? NSParseHostsData(data, &error) : nil;
            NSPolicy *current = result ? NSReadPolicy(&error) : nil;
            NSHostsImportPlan *plan =
                current ? NSPlanHostsImport(result.domainKeys, current.document, &error) : nil;
            NSString *source =
                plan ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.cancelled) {
                    return;
                }
                if (!plan) {
                    [self setWorkingState:NO];
                    [self showImportError:error];
                    return;
                }
                self.sourceText = source;
                self.preview = plan;
                self.instructions.text =
                    NSL(@"Preview only. Review the counts, warnings and added domains below. "
                        @"Import appends blocking rules; existing rules are kept.");
                [self.fileButton setTitle:NSL(@"Back to Input") forState:UIControlStateNormal];
                NSHostsParseStats stats = result.stats;
                NSMutableString *previewText = [NSMutableString
                    stringWithFormat:
                        NSL(@"Will add: %lu\nAlready covered: %lu\nConflicting rules kept: %lu\n"
                            @"Duplicate entries: %lu\nRedirect lines skipped: %zu\n"
                            @"Local names skipped: %zu\nInvalid lines / names: %zu / %zu\n"
                            @"Blank / comment lines: %zu\nTotal global rules after import: %lu / %d\n\n"
                            @"IMPORTANT\n"
                            @"• This converts a blocklist, not system Hosts or DNS redirection.\n"
                            @"• Existing domain/www rules are never overwritten. The current engine matches "
                            @"www aliases and may block shared IPs from DNS results.\n"
                            @"• Global rules override app rules and the iOS system-process allowance. "
                            @"Other existing IP/domain rules may take precedence.\n"
                            @"• Domain rules trigger DNS lookups. Large lists can take a long time to "
                            @"resolve "
                            @"and increase background work. IP-only connections rely on short-lived DNS "
                            @"caches; "
                            @"coverage can be delayed or incomplete. Saving rules does not verify "
                            @"filtering.\n"
                            @"• Only new connections are affected. Firewall must already be enabled. "
                            @"This import does not change Firewall, Default Rule or notification settings.\n"
                            @"• Export your existing rules first if you need a record; "
                            @"this version has no one-tap batch undo.\n\nADDED DOMAINS\n"),
                        (unsigned long)plan.addedKeys.count, (unsigned long)plan.existingCount,
                        (unsigned long)plan.conflictCount, (unsigned long)result.duplicateCount,
                        stats.redirectLines, stats.localNames, stats.invalidLines, stats.invalidNames,
                        stats.ignoredLines, (unsigned long)plan.globalRules.count, NSMaximumRules];
                for (NSString *key in plan.addedKeys) {
                    [previewText appendFormat:@"%@\n", [key substringFromIndex:7]];
                }
                if (!result.domainKeys.count && stats.invalidLines > 0) {
                    [previewText
                        appendString:
                            NSL(@"No Hosts blocking entries were recognized. Surge "
                                @"DOMAIN/SUFFIX/KEYWORD rules and plain domain lists are not Hosts files; "
                                @"they are not converted automatically.\n")];
                }
                if (!plan.addedKeys.count) {
                    [previewText appendString:NSL(@"No new rules to import. Nothing has been saved.\n")];
                }
                self.textView.text = previewText;
                self.textView.accessibilityLabel = NSL(@"Hosts import preview");
                [self.textView setContentOffset:CGPointZero animated:NO];
                [self setWorkingState:NO];
            });
        }
    });
}
- (void)savePreview {
    NSArray<NSString *> *approved = self.preview.addedKeys;
    if (!approved.count) {
        return;
    }
    [self setWorkingState:YES];
    self.navigationItem.leftBarButtonItem.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            __block NSUInteger imported = 0;
            NSError *error = nil;
            BOOL saved = NSUpdatePolicy(
                ^BOOL(NSMutableDictionary *document, NSError **mutationError) {
                    // Never add a key excluded from the preview, even if its conflict disappeared.
                    NSHostsImportPlan *latest = NSPlanHostsImport(approved, document, mutationError);
                    if (!latest) {
                        return NO;
                    }
                    if (!latest.addedKeys.count) {
                        if (mutationError) {
                            *mutationError = NSHostsUIError(
                                NSL(@"Rules changed after preview; no new rules remain. "
                                    @"Return to input and preview again. Nothing was imported."));
                        }
                        return NO;
                    }
                    imported = latest.addedKeys.count;
                    NSApplyHostsImportPlan(latest, document);
                    return YES;
                },
                &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.navigationItem.leftBarButtonItem.enabled = YES;
                [self setWorkingState:NO];
                if (!saved) {
                    [self showImportError:error];
                    return;
                }
                if (self.didImport) {
                    self.didImport(imported);
                }
                [self dismissViewControllerAnimated:YES completion:nil];
            });
        }
    });
}
@end
