/*****************************************************************************
* Safari XPath                                                               *
* Copyright (c) 2009 Vladimir "Farcaller" Pouzanov <farcaller@gmail.com>     *
*                                                                            *
* Permission is hereby granted, free of charge, to any person obtaining a    *
* copy of this software and associated documentation files (the "Software"), *
* to deal in the Software without restriction, including without limitation  *
* the rights to use, copy, modify, merge, publish, distribute, sublicense,   *
* and/or sell copies of the Software, and to permit persons to whom the      *
* Software is furnished to do so, subject to the following conditions:       *
*                                                                            *
* The above copyright notice and this permission notice shall be included in *
* all copies or substantial portions of the Software.                        *
*                                                                            *
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS    *
* OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF                 *
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.     *
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY       *
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,       *
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE          *
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                     *
*****************************************************************************/

#import "SXPPlugin.h"
#import <Foundation/NSObjCRuntime.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import <WebKit/WebScriptObject.h>

#pragma mark ** C API **
static SXPPlugin *Plugin = nil;

struct objc_method_ {
    SEL method_name;
    char *method_types;
    IMP method_imp;
};

typedef struct objc_method_ *Method_;

#pragma mark -
#pragma mark ** Private Methods **
@interface SXPPlugin (SXPPluginPrivate)

- (void)swizzle;

- (NSString *)xpathForNode:(id)node;
- (NSDictionary *)dictForNode:(DOMNode *)node;
- (NSDictionary *)dictForNSXMLNode:(NSXMLNode *)node;

- (NSArray *)nodesFromDOMForXPath:(NSString *)xpath;
- (NSArray *)nodesFromDocForXPath:(NSString *)xpath;

- (NSArray *)_sxp_orig_webView:(id)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems;

@end

#pragma mark -
#pragma mark ** More C Stuff **
BOOL DTRenameSelector(Class _class, SEL _oldSelector, SEL _newSelector)
{
	Method_ method = nil;

	// First, look for the methods
	method = (Method_)class_getInstanceMethod(_class, _oldSelector);
	if (method == nil)
		return NO;

	method->method_name = _newSelector;
	return YES;
}

static NSArray *webView_contextMenuItemsForElement_defaultMenuItems_(SXPPlugin *self, SEL _cmd, id sender, NSDictionary *element, NSArray *defaultMenuItems)
{
	[SXPPlugin sharedInstance].ctx = element;
	NSArray *itms = [self _sxp_orig_webView:sender contextMenuItemsForElement:element defaultMenuItems:defaultMenuItems];
	NSMutableArray *itms2 = [NSMutableArray arrayWithArray:itms];
	[itms2 addObject:[NSMenuItem separatorItem]];
	[itms2 addObject:[[SXPPlugin sharedInstance] myMenuItem]];
	return itms2;
}

#pragma mark -
#pragma mark ** Main Class **
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
		NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"Show XPath for Selected Node" action:@selector(onMenu:) keyEquivalent:@""];
		[mi setTarget:self];
		[m addItem:mi];
		[mi release];
		mi = [[NSMenuItem alloc] initWithTitle:@"Show Browser" action:@selector(onMenuBrowser:) keyEquivalent:@""];
		[mi setTarget:self];
		[m addItem:mi];
		[mi release];
		
		_myMenuItem = [[NSMenuItem alloc] initWithTitle:@"XPath" action:nil keyEquivalent:@""];
		[_myMenuItem setSubmenu:m];
		[m release];
		[_myMenuItem setEnabled:YES];
		
		// init ui
		[NSBundle loadNibNamed:@"XPathBrowser" owner:self];
		[aboutField setStringValue:[NSString
									stringWithFormat:[aboutField stringValue],
									[[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleVersion"]]];
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
	NSString *xpath = [xpathField stringValue];
	
	[_nodes release];
	_nodes = nil;
	
	if([modeMatrix selectedColumn] == 0)
		_nodes = [[self nodesFromDOMForXPath:xpath] retain];
	else
		_nodes = [[self nodesFromDocForXPath:xpath] retain];
	
	[outlineView reloadData];
}

#pragma mark
#pragma mark XPath evaluators
- (NSArray *)nodesFromDOMForXPath:(NSString *)xpath
{
	WebFrame *frame = [_ctx objectForKey:@"WebElementFrame"];
	WebView *view = [frame webView];
	NSString *js = [NSString stringWithFormat:@"document.evaluate(\"%@\", document, null, XPathResult.ANY_TYPE,null)", xpath];
	NSMutableArray *nodes = nil;
	
	id o = [[view windowScriptObject] evaluateWebScript:js];
	if(![[o class] isEqual:[WebUndefined class]]) {
		int rt = [((DOMXPathResult *)o) resultType];
		nodes = [NSMutableArray array];
		id n;
		switch(rt) {
			case 1:
				[nodes addObject:[NSDictionary dictionaryWithObjectsAndKeys:
								  @"NUMBER", @"name",
								  [NSNumber numberWithFloat:[o numberValue]], @"stringValue",
								  nil]];
				break;
			case 2:
				[nodes addObject:[NSDictionary dictionaryWithObjectsAndKeys:
								  @"STRING", @"name",
								  [o stringValue], @"stringValue",
								  nil]];
				break;
			case 3:
				[nodes addObject:[NSDictionary dictionaryWithObjectsAndKeys:
								  @"BOOLEAN", @"name",
								  [NSNumber numberWithBool:[o booleanValue]], @"stringValue",
								  nil]];
				break;
			default:
				n = [o iterateNext];
				while(n) {
					[nodes addObject:[self dictForNode:n]];
					n = [o iterateNext];
				}
				break;
		}
	};
	return nodes;
}

- (NSArray *)nodesFromDocForXPath:(NSString *)xpath
{
	WebFrame *frame = [_ctx objectForKey:@"WebElementFrame"];
	NSData *doc = [[frame dataSource] data];
	NSError *err = nil;

	NSString *encName = [[[frame dataSource] response] textEncodingName];
	NSStringEncoding responseEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding((CFStringRef)encName));
	NSString *responseString = [[[NSString alloc] initWithData:doc encoding:responseEncoding] autorelease];	
	
	NSXMLDocument *xmldoc = [[[NSXMLDocument alloc] initWithXMLString:responseString options:NSXMLDocumentTidyHTML error:&err] autorelease];
	if(!xmldoc)
		return nil; // XXX: err may be flooded with Tidy warnings
	err = nil;
	NSXMLElement *root = [xmldoc rootElement];
	
	NSArray *nl = [root nodesForXPath:xpath error:&err];
	if(err) {
		NSLog(@"xpath error: %@", err);
		return nil;
	}
	NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:[nl count]];
	for(NSXMLNode *n in nl) {
		[nodes addObject:[self dictForNSXMLNode:n]];
	}
	return nodes;
}

- (NSDictionary *)dictForNSXMLNode:(NSXMLNode *)n
{
	NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObjectsAndKeys:
							  [[n name] lowercaseString], @"name",
							  [n stringValue], @"stringValue",
							  nil];
	if([n childCount] > 0) {
		NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:[n childCount]];
		for(NSXMLNode *nn in [n children]) {
			if([nn kind] == NSXMLElementKind)
				[nodes addObject:[self dictForNSXMLNode:nn]];
		}
		if([nodes count])
			[d setObject:nodes forKey:@"children"];
	}
	int ac = [[(NSXMLElement *)n attributes] count];
	if(ac > 0) {
		NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithCapacity:ac];
		NSMutableArray *ja = [NSMutableArray arrayWithCapacity:ac];
		for(NSXMLNode *nn in [(NSXMLElement *)n attributes]) {
			NSString *k = [nn name];
			NSString *v = [nn stringValue];
			
			[attrs setObject:v forKey:k];
			if([v rangeOfString:@" "].location == NSNotFound) 
				[ja addObject:[NSString stringWithFormat:@"%@=%@", k, v]];
			else
				[ja addObject:[NSString stringWithFormat:@"%@=\"%@\"", k, v]];
		}
		[d setObject:attrs forKey:@"attributes"];
		[d setObject:[ja componentsJoinedByString:@" "] forKey:@"attributes_string"];
	}
	return d;
}

- (NSDictionary *)dictForNode:(DOMNode *)n
{
	NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObjectsAndKeys:
							  [[n nodeName] lowercaseString], @"name",
							  [n textContent], @"stringValue",
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
			[d setObject:nodes forKey:@"children"];
	}
	if([n hasAttributes]) {
		DOMNamedNodeMap *nl = [n attributes];
		int len = [nl length];
		NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithCapacity:len];
		for(int i=0; i<len; ++i) {
			DOMNode *nn = [nl item:i];
			[attrs setObject:[nn value] forKey:(id)[nn name]];
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
		return [[item objectForKey:@"children"] objectAtIndex:index];
	} else {
		return [_nodes objectAtIndex:index];
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(NSDictionary *)item
{
	return [item objectForKey:@"children"] != nil;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(NSDictionary *)item
{
	if(item) {
		return [[item objectForKey:@"children"] count];
	} else {
		return [_nodes count];
	}
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if([[tableColumn identifier] isEqualToString:@"name"]) {
		return [item objectForKey:@"name"];
	} else if([[tableColumn identifier] isEqualToString:@"value"]) {
		return [item objectForKey:@"stringValue"];
	} else {
		return [item objectForKey:@"attributes_string"];
	}
}

#pragma mark
#pragma mark Reverse XPath evaluator
- (NSString *)xpathForNode:(DOMNode *)n
{
	DOMNode *parent = [n parentNode];
	NSString *nm = @"";
	
	if((int)[n nodeType] == 1) {
		NSString *nid = [n valueForKey:@"id"];
		if([nid length] > 0) {
			nm = [NSString stringWithFormat:@"/%@[@id='%@']", [[n nodeName] lowercaseString], nid];
		} else {
			NSString *n_name = [n nodeName];
			nm = [NSString stringWithFormat:@"/%@", [n_name lowercaseString]];
			if(parent) {
				DOMNodeList *cn = [parent childNodes];
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
