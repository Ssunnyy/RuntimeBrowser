/*
 
 AllClasses.m created by eepstein on Sat 16-Mar-2002 

 Author: Ezra Epstein (eepstein@prajna.com)

 Copyright (c) 2002 by Prajna IT Consulting.
                       http://www.prajna.com

 ========================================================================

 THIS PROGRAM AND THIS CODE COME WITH ABSOLUTELY NO WARRANTY.
 THIS CODE HAS BEEN PROVIDED "AS IS" AND THE RESPONSIBILITY
 FOR ITS OPERATIONS IS 100% YOURS.

 ========================================================================
 This file is part of RuntimeBrowser.

 RuntimeBrowser is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.

 RuntimeBrowser is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with RuntimeBrowser (in a file called "COPYING.txt"); if not,
 write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
 Boston, MA  02111-1307  USA

*/

#import "AllClasses.h"
#import "ClassStub.h"
#import "ProtocolStub.h"
#import "RTBRuntimeHeader.h"

#if (! TARGET_OS_IPHONE)
#import <objc/objc-runtime.h>
#else
#import <objc/runtime.h>
#import <objc/message.h>
#endif

#import <stdio.h>

static AllClasses *sharedInstance;

@implementation AllClasses

+ (AllClasses *)sharedInstance {
	if(sharedInstance == nil) {
		sharedInstance = [[AllClasses alloc] init];
		sharedInstance.rootClasses = [NSMutableArray array];
		sharedInstance.allClassStubsByName = [NSMutableDictionary dictionary];
		sharedInstance.allClassStubsByImagePath = [NSMutableDictionary dictionary];
        sharedInstance.allProtocols = [NSMutableDictionary dictionary];
	}
	
	return sharedInstance;
}

+ (void)thisClassIsPartOfTheRuntimeBrowser {}

- (ClassStub *)classStubForClassName:(NSString *)classname {
    return [_allClassStubsByName valueForKey:classname];
}

- (ClassStub *)getOrCreateClassStubsRecursivelyForClass:(Class)klass {
	
    //self.allProtocols = [NSMutableDictionary dictionary];
    
	//Lookup the ClassStub for klass or create one if none exists and add it to +allClassStuds.
    NSString *klassName = NSStringFromClass(klass);
	
    // First check if we've already got a ClassStub for klass. If yes, we'll return it.
    ClassStub *cs = [self classStubForClassName:klassName];
	if(cs) return cs;
	
    // klass doesn't yet have a ClassStub...
	cs = [ClassStub classStubWithClass:klass]; // Create a ClassStub for klass
	
	if(cs == nil) {
		NSLog(@"-- cannot create classStub for %@, ignore it", klassName);
		return nil;
	}
	
	_allClassStubsByName[klassName] = cs; // Add it to our uniquing dictionary.
	
	/* fill stubsForImage */
	NSString *path = [cs imagePath];
    
#if TARGET_IPHONE_SIMULATOR
    // remove path prefix, eg.
    //   /Applications/Xcode5-DP.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator7.0.sdk/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI
    // will become
    //   /System/Library/PrivateFrameworks/CoreUI.framework/CoreUI

    if([path hasPrefix:@"/Applications/"]) {
        NSUInteger i = [path rangeOfString:@".sdk"].location;
        if(i != NSNotFound) {
            NSUInteger start = i + 4;
            path = [path substringFromIndex:start];
        }
    }
#endif
    
	if(path) {
		NSMutableArray *stubsForImage = [_allClassStubsByImagePath valueForKey:path];
		if(stubsForImage == nil) {
            _allClassStubsByImagePath[path] = [NSMutableArray array];
			stubsForImage = [_allClassStubsByImagePath valueForKey:path];
		}
		if([stubsForImage containsObject:cs] == NO) [stubsForImage addObject:cs]; // TODO: use a set?
	}
	
	Class parent = class_getSuperclass(klass);   // Get klass's superclass 
	if (parent != nil) {               // and recursively create (or get) its stub.
		ClassStub *parentCs = [self getOrCreateClassStubsRecursivelyForClass:parent];
		[parentCs addSubclassStub:cs];  // we are a subclass of our parent.
	} else  // If there is no superclass, then klass is a root class.
		[[self rootClasses] addObject:cs];
	
    /**/
    
    NSArray *protocolNames = [RTBRuntimeHeader sortedProtocolsForClass:klass];
    for(NSString *protocolName in protocolNames) {
        ProtocolStub *ps = _allProtocols[protocolName];
        if(ps == nil) {
            _allProtocols[protocolName] = [ProtocolStub protocolStubWithProtocolName:protocolName];
        }
        [ps.conformingClassesStubsSet addObject:cs];
    }
    
    return cs;
}

- (NSArray *)sortedClassStubs {
	if([_allClassStubsByName count] == 0) [self readAllRuntimeClasses];
	
	NSMutableArray *stubs = [NSMutableArray arrayWithArray:[_allClassStubsByName allValues]];
	[stubs sortUsingSelector:@selector(compare:)];
	return stubs;
}

+ (NSArray *)readAndSortAllRuntimeProtocolNames {

    NSMutableArray *ma = [NSMutableArray array];
    
    unsigned int protocolListCount = 0;
    __unsafe_unretained Protocol **protocolList = objc_copyProtocolList(&protocolListCount);
    for(NSUInteger i = 0; i < protocolListCount; i++) {
        __unsafe_unretained Protocol *p = protocolList[i];
        NSString *protocolName = NSStringFromProtocol(p);
        [ma addObject:protocolName];
    }
    free(protocolList);
    
    [ma sortUsingSelector:@selector(compare:)];
    
    return ma;
}

- (NSArray *)sortedProtocolStubs {
    
    if([_allProtocols count] == 0) {
        [self readAllRuntimeClasses];
    }
    
    return [[_allProtocols allValues] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)readAllRuntimeClasses {
	int i, numClasses = 0;
	int newNumClasses = objc_getClassList(NULL, 0);
	Class *classes = NULL;

	while (numClasses < newNumClasses) {
		numClasses = newNumClasses;
		classes = (Class *)realloc(classes, sizeof(Class) * numClasses);
		newNumClasses = objc_getClassList(classes, numClasses);
	}

	for (i=0; i<numClasses; ++i)
		[self getOrCreateClassStubsRecursivelyForClass:classes[i]];

	free(classes);
    
	[_rootClasses sortUsingSelector:@selector(compare:)];
}

- (NSMutableDictionary *)allClassStubsByImagePath {
	if([_allClassStubsByImagePath count] == 0) {
		[self readAllRuntimeClasses];
	}
	return _allClassStubsByImagePath;
}

- (NSMutableArray *)rootClasses {
    /*" Classes are wrapped by ClassStub.  This array contains wrappers for root classes (classes that have no superclass). "*/
	if ([_rootClasses count] == 0) {
		[self readAllRuntimeClasses];
	}
	return _rootClasses;
}

- (void)emptyCachesAndReadAllRuntimeClasses {
/*"
We autorelease and reset the nil the global, static containers that
 hold the parsed runtime info.  This forces the entire runtime to\
 be re-parsed.

 +reset is designed to be called after the user has loaded new
 bundles (via "File -> Open..." in the UI's menu).
"*/	
	self.rootClasses = [NSMutableArray array];
	self.allClassStubsByName = [NSMutableDictionary dictionary];
	self.allClassStubsByImagePath = [NSMutableDictionary dictionary];
    self.allProtocols = [NSMutableDictionary dictionary];
	
	[self readAllRuntimeClasses];
}

@end
