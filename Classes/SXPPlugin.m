//
//  SXPPlugin.m
//  SafariXPath
//
//  Created by Farcaller on 25.07.09.
//  Copyright 2009 Hack&Dev FSO. All rights reserved.
//

#import "SXPPlugin.h"
#import <Foundation/NSObjCRuntime.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import <WebKit/WebScriptObject.h>

static SXPPlugin *Plugin = nil;

BOOL DTRenameSelector(Class _class, SEL _oldSelector, SEL _newSelector)
{
	Method method = nil;

	// First, look for the methods
	method = class_getInstanceMethod(_class, _oldSelector);
	if (method == nil)
		return NO;

	method->method_name = _newSelector;
	return YES;
}

static NSArray *webView_contextMenuItemsForElement_defaultMenuItems_(id self, SEL _cmd, id *sender, NSDictionary *element, NSArray *defaultMenuItems)
{
	[SXPPlugin sharedInstance].ctx = element;
	NSArray *itms = [self _sxp_orig_webView:sender contextMenuItemsForElement:element defaultMenuItems:defaultMenuItems];
	NSMutableArray *itms2 = [NSMutableArray arrayWithArray:itms];
	[itms2 addObject:[NSMenuItem separatorItem]];
	[itms2 addObject:[[SXPPlugin sharedInstance] myMenuItem]];
	return itms2;
}

@implementation SXPPlugin

@synthesize ctx = _ctx, myMenuItem = _myMenuItem;

+ (SXPPlugin *)sharedInstance
{
	@synchronized(self) {
		if(!Plugin)
			Plugin = [[SXPPlugin alloc] init];
	}
	return Plugin;
}

- (id)init
{
	if( (self = [super init]) ) {
		// init menu
		NSMenu *m = [[NSMenu alloc] initWithTitle:@"XPath"];
		NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"XPath for node" action:@selector(onMenu:) keyEquivalent:@""];
		[mi setTarget:self];
		[m addItem:mi];
		[mi release];
		mi = [[NSMenuItem alloc] initWithTitle:@"Show browser" action:@selector(onMenuBrowser:) keyEquivalent:@""];
		[mi setTarget:self];
		[m addItem:mi];
		[mi release];
		
		_myMenuItem = [[NSMenuItem alloc] initWithTitle:@"XPath" action:nil keyEquivalent:@""];
		[_myMenuItem setSubmenu:m];
		[_myMenuItem setEnabled:YES];
		
		// init ui
		[NSBundle loadNibNamed:@"XPathBrowser" owner:self];
	}
	return self;
}

#pragma mark
#pragma mark Actions
- (void)onMenu:(id)sender
{
	[window makeKeyAndOrderFront:self];
	NSString *xp = [self xpathForNode:[_ctx objectForKey:@"WebElementDOMNode"]];
	[xpathField setStringValue:xp];
	[self onEvaluate:self];
}

- (void)onMenuBrowser:(id)sender
{
	[window makeKeyAndOrderFront:self];
}

- (void)onEvaluate:(id)sender
{
	NSString *xp = [xpathField stringValue];
	WebFrame *frame = [_ctx objectForKey:@"WebElementFrame"];
	WebView *view = [frame webView];
	NSString *js = [NSString stringWithFormat:@"document.evaluate(\"%@\", document, null, XPathResult.ANY_TYPE,null)", xp];
	
	id o = [[view windowScriptObject] evaluateWebScript:js];
	[_nodes release];
	_nodes = nil;
	if(![[o class] isEqual:[WebUndefined class]]) {
		NSMutableArray *nodes = [NSMutableArray array];
		id n = [o iterateNext];
		while(n) {
			[nodes addObject:[self dictForNode:n]];
			n = [o iterateNext];
		}
		_nodes = [nodes retain];
	};
	[outlineView reloadData];
}

- (NSDictionary *)dictForNode:(DOMNode *)n
{
	NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObjectsAndKeys:
							  [[n nodeName] lowercaseString], @"name",
							  [n textContent], @"content",
							  nil];
	if([n hasChildNodes]) {
		DOMNodeList *nl = [n childNodes];
		int len = [nl length];
		NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:len];
		for(int i=0; i<len; ++i) {
			DOMNode *nn = [nl item:i];
			if([nn nodeType] == 1)
				[nodes addObject:[self dictForNode:nn]];
		}
		if([nodes count])
			[d setObject:nodes forKey:@"childNodes"];
	}
	if([n hasAttributes]) {
		DOMNamedNodeMap *nl = [n attributes];
		int len = [nl length];
		NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithCapacity:len];
		for(int i=0; i<len; ++i) {
			id *nn = [nl item:i];
			[attrs setObject:[nn value] forKey:[nn name]];
		}
		[d setObject:attrs forKey:@"attributes"];
		NSMutableArray *ja = [NSMutableArray arrayWithCapacity:len];
		for(NSString *k in attrs) {
			NSString *v = [attrs objectForKey:k];
			if([v rangeOfString:@" "].location == NSNotFound) 
				[ja addObject:[NSString stringWithFormat:@"%@=%@", k, v]];
			else
				[ja addObject:[NSString stringWithFormat:@"%@=\"%@\"", k, v]];
		}
		[d setObject:[ja componentsJoinedByString:@" "] forKey:@"attributes_string"];
	}
	return d;
}

#pragma mark
#pragma mark Outline View DS
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(NSDictionary *)item
{
	if(item) {
		return [[item objectForKey:@"childNodes"] objectAtIndex:index];
	} else {
		return [_nodes objectAtIndex:index];
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(NSDictionary *)item
{
	return [item objectForKey:@"childNodes"] != nil;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(NSDictionary *)item
{
	if(item) {
		return [[item objectForKey:@"childNodes"] count];
	} else {
		return [_nodes count];
	}
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if([[tableColumn identifier] isEqualToString:@"name"]) {
		return [item objectForKey:@"name"];
	} else if([[tableColumn identifier] isEqualToString:@"value"]) {
		return [item objectForKey:@"content"];
	} else {
		return [item objectForKey:@"attributes_string"];
	}
}

#pragma mark
#pragma mark XPath evaluator
- (NSString *)xpathForNode:(id)n
{
	id parent = [n parentNode];
	NSString *nm = @"";
	
	if((int)[n nodeType] == 1) {
		NSString *nid = [n valueForKey:@"id"];
		if([nid length] > 0) {
			nm = [NSString stringWithFormat:@"/%@[@id='%@']", [[n nodeName] lowercaseString], nid];
		} else {
			NSString *n_name = [n nodeName];
			nm = [NSString stringWithFormat:@"/%@", [n_name lowercaseString]];
			if(parent) {
				id cn = [parent childNodes];
				int cn_len = (int)[cn length];
				if(cn_len > 1) {
					int mi = 0;
					BOOL dupNodes = NO;
					int i = 0;
					int ri = 0;
					while(i < cn_len) {
						id sn = [cn item:i];
						NSString *sn_name = [sn nodeName];
						++i;
						if((int)[sn nodeType] != 1) {
							continue;
						} else if([sn_name isEqualToString:n_name]){
							++ri;
						}
						if(sn == n) {
							mi = ri;
						} else if([sn_name isEqualToString:n_name]) {
							dupNodes = YES;
						}
					}
					if(dupNodes)
						nm = [nm stringByAppendingFormat:@"[%d]", mi];
				}
			}
		}
	}
	if(parent)
		return [[self xpathForNode:parent] stringByAppendingString:nm];
	else
		return @"";
}

#pragma mark
#pragma mark Dark magic
- (void)swizzle
{
	Class BrowserWebView = objc_getClass("BrowserWebView");
	if(BrowserWebView) {
		class_addMethod(BrowserWebView, @selector(_sxp_fake_webView:contextMenuItemsForElement:defaultMenuItems:), (IMP)webView_contextMenuItemsForElement_defaultMenuItems_, "@@:@@@");
		
		DTRenameSelector(BrowserWebView, @selector(webView:contextMenuItemsForElement:defaultMenuItems:), @selector (_sxp_orig_webView:contextMenuItemsForElement:defaultMenuItems:));
		DTRenameSelector(BrowserWebView, @selector(_sxp_fake_webView:contextMenuItemsForElement:defaultMenuItems:), @selector(webView:contextMenuItemsForElement:defaultMenuItems:));
	} else {
		NSLog(@"Failed to get BrowserWebView class");
	}
}

+ (void)load
{
	SXPPlugin *plugin = [SXPPlugin sharedInstance];
	[plugin swizzle];
}

@end
