//
//  CBCommandLine.h
//  cbonsai saver
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const CBCbonsaiTimeKey;
extern NSString * const CBCbonsaiWaitKey;
extern NSString * const CBCbonsaiMessageKey;
extern NSString * const CBCbonsaiBaseEnabledKey;
extern NSString * const CBCbonsaiBaseKey;
extern NSString * const CBCbonsaiLeafKey;
extern NSString * const CBCbonsaiColorKey;
extern NSString * const CBCbonsaiMultiplierKey;
extern NSString * const CBCbonsaiLifeKey;
extern NSString * const CBCbonsaiSeedEnabledKey;
extern NSString * const CBCbonsaiSeedKey;
extern NSString * const CBCbonsaiSaveEnabledKey;
extern NSString * const CBCbonsaiSavePathKey;
extern NSString * const CBCbonsaiLoadEnabledKey;
extern NSString * const CBCbonsaiLoadPathKey;
extern NSString * const CBCbonsaiVerboseKey;

NSString *CBDefaultEnvironmentPath(void);
NSDictionary<NSString *, id> *CBDefaultCbonsaiOptions(void);
NSArray<NSString *> *CBCbonsaiArgumentsFromOptions(NSDictionary<NSString *, id> *options);

NS_ASSUME_NONNULL_END
