//
//  CBCommandLine.h
//  cbonsai saver
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const CBCommandLineErrorDomain;

NSArray<NSString *> *CBParseArgumentString(NSString *argumentString, NSError **error);
NSString *CBDefaultExecutablePath(void);
NSString *CBDefaultArgumentString(void);
NSString *CBDefaultEnvironmentPath(void);

NS_ASSUME_NONNULL_END
