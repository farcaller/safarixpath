//
//  SXPPlugin.h
//  SafariXPath
//
//  Created by Farcaller on 25.07.09.
//  Copyright 2009 Hack&Dev FSO. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class DOMNode;

@interface SXPPlugin : NSObject {
	IBOutlet NSWindow *window;
	IBOutlet NSTextField *xpathField;
	IBOutlet NSOutlineView *outlineView;
	
	NSMenuItem *_myMenuItem;
	NSDictionary *_ctx;
	NSArray *_nodes;
}
@property (readwrite, retain) NSDictionary *ctx;
@property (readonly) NSMenuItem *myMenuItem;

+ (SXPPlugin *)sharedInstance;
- (void)swizzle;

- (NSString *)xpathForNode:(id)node;
- (NSDictionary *)dictForNode:(DOMNode *)node;

- (void)onMenu:(id)sender;
- (void)onMenuBrowser:(id)sender;
- (void)onEvaluate:(id)sender;

@end
