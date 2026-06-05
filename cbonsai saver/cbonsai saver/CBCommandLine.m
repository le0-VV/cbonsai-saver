//
//  CBCommandLine.m
//  cbonsai saver
//

#import "CBCommandLine.h"

NSString * const CBCbonsaiLiveKey = @"cbonsaiLive";
NSString * const CBCbonsaiInfiniteKey = @"cbonsaiInfinite";
NSString * const CBCbonsaiTimeKey = @"cbonsaiTime";
NSString * const CBCbonsaiWaitKey = @"cbonsaiWait";
NSString * const CBCbonsaiMessageKey = @"cbonsaiMessage";
NSString * const CBCbonsaiBaseEnabledKey = @"cbonsaiBaseEnabled";
NSString * const CBCbonsaiBaseKey = @"cbonsaiBase";
NSString * const CBCbonsaiLeafKey = @"cbonsaiLeaf";
NSString * const CBCbonsaiColorKey = @"cbonsaiColor";
NSString * const CBCbonsaiMultiplierKey = @"cbonsaiMultiplier";
NSString * const CBCbonsaiLifeKey = @"cbonsaiLife";
NSString * const CBCbonsaiPrintKey = @"cbonsaiPrint";
NSString * const CBCbonsaiSeedEnabledKey = @"cbonsaiSeedEnabled";
NSString * const CBCbonsaiSeedKey = @"cbonsaiSeed";
NSString * const CBCbonsaiSaveEnabledKey = @"cbonsaiSaveEnabled";
NSString * const CBCbonsaiSavePathKey = @"cbonsaiSavePath";
NSString * const CBCbonsaiLoadEnabledKey = @"cbonsaiLoadEnabled";
NSString * const CBCbonsaiLoadPathKey = @"cbonsaiLoadPath";
NSString * const CBCbonsaiVerboseKey = @"cbonsaiVerbose";
NSString * const CBCbonsaiHelpKey = @"cbonsaiHelp";

static BOOL CBBoolOption(NSDictionary<NSString *, id> *options, NSString *key)
{
    id value = options[key];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

static NSInteger CBIntegerOption(NSDictionary<NSString *, id> *options, NSString *key)
{
    id value = options[key];
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

static double CBDoubleOption(NSDictionary<NSString *, id> *options, NSString *key)
{
    id value = options[key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
}

static NSString *CBStringOption(NSDictionary<NSString *, id> *options, NSString *key)
{
    id value = options[key];
    if (![value isKindOfClass:NSString.class]) {
        return @"";
    }
    return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *CBFormatDouble(double value)
{
    return [NSString stringWithFormat:@"%.6g", value];
}

NSString *CBDefaultEnvironmentPath(void)
{
    return @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
}

NSDictionary<NSString *, id> *CBDefaultCbonsaiOptions(void)
{
    return @{
        CBCbonsaiLiveKey: @YES,
        CBCbonsaiInfiniteKey: @YES,
        CBCbonsaiTimeKey: @0.03,
        CBCbonsaiWaitKey: @3.0,
        CBCbonsaiMessageKey: @"",
        CBCbonsaiBaseEnabledKey: @NO,
        CBCbonsaiBaseKey: @1,
        CBCbonsaiLeafKey: @"&",
        CBCbonsaiColorKey: @"2,3,10,11",
        CBCbonsaiMultiplierKey: @5,
        CBCbonsaiLifeKey: @32,
        CBCbonsaiPrintKey: @NO,
        CBCbonsaiSeedEnabledKey: @NO,
        CBCbonsaiSeedKey: @0,
        CBCbonsaiSaveEnabledKey: @NO,
        CBCbonsaiSavePathKey: @"",
        CBCbonsaiLoadEnabledKey: @NO,
        CBCbonsaiLoadPathKey: @"",
        CBCbonsaiVerboseKey: @NO,
        CBCbonsaiHelpKey: @NO,
    };
}

NSArray<NSString *> *CBCbonsaiArgumentsFromOptions(NSDictionary<NSString *, id> *options)
{
    NSMutableDictionary<NSString *, id> *mergedOptions = [CBDefaultCbonsaiOptions() mutableCopy];
    [mergedOptions addEntriesFromDictionary:options ?: @{}];

    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    if (CBBoolOption(mergedOptions, CBCbonsaiLiveKey)) {
        [arguments addObject:@"--live"];
    }
    if (CBBoolOption(mergedOptions, CBCbonsaiInfiniteKey)) {
        [arguments addObject:@"--infinite"];
    }

    [arguments addObject:[@"--time=" stringByAppendingString:CBFormatDouble(CBDoubleOption(mergedOptions, CBCbonsaiTimeKey))]];
    [arguments addObject:[@"--wait=" stringByAppendingString:CBFormatDouble(CBDoubleOption(mergedOptions, CBCbonsaiWaitKey))]];

    NSString *message = CBStringOption(mergedOptions, CBCbonsaiMessageKey);
    if (message.length > 0) {
        [arguments addObject:[@"--message=" stringByAppendingString:message]];
    }

    if (CBBoolOption(mergedOptions, CBCbonsaiBaseEnabledKey)) {
        [arguments addObject:[NSString stringWithFormat:@"--base=%ld", (long)CBIntegerOption(mergedOptions, CBCbonsaiBaseKey)]];
    }

    [arguments addObject:[@"--leaf=" stringByAppendingString:CBStringOption(mergedOptions, CBCbonsaiLeafKey)]];
    [arguments addObject:[@"--color=" stringByAppendingString:CBStringOption(mergedOptions, CBCbonsaiColorKey)]];
    [arguments addObject:[NSString stringWithFormat:@"--multiplier=%ld", (long)CBIntegerOption(mergedOptions, CBCbonsaiMultiplierKey)]];
    [arguments addObject:[NSString stringWithFormat:@"--life=%ld", (long)CBIntegerOption(mergedOptions, CBCbonsaiLifeKey)]];

    if (CBBoolOption(mergedOptions, CBCbonsaiPrintKey)) {
        [arguments addObject:@"--print"];
    }
    if (CBBoolOption(mergedOptions, CBCbonsaiSeedEnabledKey)) {
        [arguments addObject:[NSString stringWithFormat:@"--seed=%ld", (long)CBIntegerOption(mergedOptions, CBCbonsaiSeedKey)]];
    }

    NSString *savePath = CBStringOption(mergedOptions, CBCbonsaiSavePathKey);
    if (CBBoolOption(mergedOptions, CBCbonsaiSaveEnabledKey) && savePath.length > 0) {
        [arguments addObject:[@"--save=" stringByAppendingString:savePath]];
    }

    NSString *loadPath = CBStringOption(mergedOptions, CBCbonsaiLoadPathKey);
    if (CBBoolOption(mergedOptions, CBCbonsaiLoadEnabledKey) && loadPath.length > 0) {
        [arguments addObject:[@"--load=" stringByAppendingString:loadPath]];
    }

    if (CBBoolOption(mergedOptions, CBCbonsaiVerboseKey)) {
        [arguments addObject:@"--verbose"];
    }
    if (CBBoolOption(mergedOptions, CBCbonsaiHelpKey)) {
        [arguments addObject:@"--help"];
    }

    return arguments;
}
