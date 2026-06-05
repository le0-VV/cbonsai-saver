//
//  CBCommandLine.m
//  cbonsai saver
//

#import "CBCommandLine.h"

#import <math.h>

NSString * const CBCbonsaiTimeKey = @"cbonsaiTime";
NSString * const CBCbonsaiWaitKey = @"cbonsaiWait";
NSString * const CBCbonsaiMessageKey = @"cbonsaiMessage";
NSString * const CBCbonsaiBaseEnabledKey = @"cbonsaiBaseEnabled";
NSString * const CBCbonsaiBaseKey = @"cbonsaiBase";
NSString * const CBCbonsaiLeafKey = @"cbonsaiLeaf";
NSString * const CBCbonsaiColorKey = @"cbonsaiColor";
NSString * const CBCbonsaiMultiplierKey = @"cbonsaiMultiplier";
NSString * const CBCbonsaiLifeKey = @"cbonsaiLife";
NSString * const CBCbonsaiSeedEnabledKey = @"cbonsaiSeedEnabled";
NSString * const CBCbonsaiSeedKey = @"cbonsaiSeed";
NSString * const CBCbonsaiVerboseKey = @"cbonsaiVerbose";

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

static double CBClampedDoubleOption(NSDictionary<NSString *, id> *options, NSString *key, double fallbackValue, double minimumValue, double maximumValue)
{
    double value = CBDoubleOption(options, key);
    if (!isfinite(value)) {
        value = fallbackValue;
    }
    return fmin(fmax(value, minimumValue), maximumValue);
}

static NSInteger CBClampedIntegerOption(NSDictionary<NSString *, id> *options, NSString *key, NSInteger fallbackValue, NSInteger minimumValue, NSInteger maximumValue)
{
    id rawValue = options[key];
    NSInteger value = [rawValue respondsToSelector:@selector(integerValue)] ? [rawValue integerValue] : fallbackValue;
    return MIN(MAX(value, minimumValue), maximumValue);
}

static NSString *CBSanitizedTextOption(NSString *value, NSUInteger maximumLength)
{
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *controlCharacters = NSCharacterSet.controlCharacterSet;
    for (NSUInteger index = 0; index < value.length && result.length < maximumLength; index++) {
        unichar character = [value characterAtIndex:index];
        if ([controlCharacters characterIsMember:character]) {
            continue;
        }
        [result appendFormat:@"%C", character];
    }
    return result;
}

static NSString *CBSanitizedLeafOption(NSString *value)
{
    NSArray<NSString *> *components = [value componentsSeparatedByString:@","];
    NSMutableArray<NSString *> *leaves = [NSMutableArray array];
    for (NSString *component in components) {
        NSString *leaf = CBSanitizedTextOption([component stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet], 16);
        if (leaf.length == 0) {
            continue;
        }
        [leaves addObject:leaf];
        if (leaves.count >= 16) {
            break;
        }
    }
    return leaves.count > 0 ? [leaves componentsJoinedByString:@","] : @"&";
}

static NSString *CBSanitizedColorOption(NSString *value)
{
    NSArray<NSString *> *components = [value componentsSeparatedByString:@","];
    if (components.count != 4) {
        return @"2,3,10,11";
    }

    NSMutableArray<NSString *> *colors = [NSMutableArray arrayWithCapacity:4];
    for (NSString *component in components) {
        NSString *trimmedComponent = [component stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSScanner *scanner = [NSScanner scannerWithString:trimmedComponent];
        scanner.charactersToBeSkipped = nil;

        NSInteger color = 0;
        if (trimmedComponent.length == 0 || ![scanner scanInteger:&color] || !scanner.isAtEnd || color < 0 || color > 255) {
            return @"2,3,10,11";
        }
        [colors addObject:[NSString stringWithFormat:@"%ld", (long)color]];
    }
    return [colors componentsJoinedByString:@","];
}

static NSString *CBFormatDouble(double value)
{
    return [NSString stringWithFormat:@"%.6g", value];
}

NSString *CBDefaultEnvironmentPath(void)
{
    return @"/usr/bin:/bin:/usr/sbin:/sbin";
}

NSDictionary<NSString *, id> *CBDefaultCbonsaiOptions(void)
{
    return @{
        CBCbonsaiTimeKey: @0.03,
        CBCbonsaiWaitKey: @3.0,
        CBCbonsaiMessageKey: @"",
        CBCbonsaiBaseEnabledKey: @YES,
        CBCbonsaiBaseKey: @1,
        CBCbonsaiLeafKey: @"&",
        CBCbonsaiColorKey: @"2,3,10,11",
        CBCbonsaiMultiplierKey: @5,
        CBCbonsaiLifeKey: @32,
        CBCbonsaiSeedEnabledKey: @NO,
        CBCbonsaiSeedKey: @0,
        CBCbonsaiVerboseKey: @NO,
    };
}

NSArray<NSString *> *CBCbonsaiArgumentsFromOptions(NSDictionary<NSString *, id> *options)
{
    return CBCbonsaiArgumentsFromOptionsWithAutomaticSeed(options, 0);
}

NSArray<NSString *> *CBCbonsaiArgumentsFromOptionsWithAutomaticSeed(NSDictionary<NSString *, id> *options, NSInteger automaticSeed)
{
    NSMutableDictionary<NSString *, id> *mergedOptions = [CBDefaultCbonsaiOptions() mutableCopy];
    [mergedOptions addEntriesFromDictionary:options ?: @{}];

    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    [arguments addObject:@"--live"];
    [arguments addObject:@"--infinite"];

    [arguments addObject:[@"--time=" stringByAppendingString:CBFormatDouble(CBClampedDoubleOption(mergedOptions, CBCbonsaiTimeKey, 0.03, 0.01, 60.0))]];
    [arguments addObject:[@"--wait=" stringByAppendingString:CBFormatDouble(CBClampedDoubleOption(mergedOptions, CBCbonsaiWaitKey, 3.0, 0.01, 600.0))]];

    NSString *message = CBSanitizedTextOption(CBStringOption(mergedOptions, CBCbonsaiMessageKey), 256);
    if (message.length > 0) {
        [arguments addObject:[@"--message=" stringByAppendingString:message]];
    }

    if (CBBoolOption(mergedOptions, CBCbonsaiBaseEnabledKey)) {
        [arguments addObject:[NSString stringWithFormat:@"--base=%ld", (long)CBClampedIntegerOption(mergedOptions, CBCbonsaiBaseKey, 1, 0, 2)]];
    }

    [arguments addObject:[@"--leaf=" stringByAppendingString:CBSanitizedLeafOption(CBStringOption(mergedOptions, CBCbonsaiLeafKey))]];
    [arguments addObject:[@"--color=" stringByAppendingString:CBSanitizedColorOption(CBStringOption(mergedOptions, CBCbonsaiColorKey))]];
    [arguments addObject:[NSString stringWithFormat:@"--multiplier=%ld", (long)CBClampedIntegerOption(mergedOptions, CBCbonsaiMultiplierKey, 5, 1, 20)]];
    [arguments addObject:[NSString stringWithFormat:@"--life=%ld", (long)CBClampedIntegerOption(mergedOptions, CBCbonsaiLifeKey, 32, 1, 200)]];

    NSInteger seed = CBIntegerOption(mergedOptions, CBCbonsaiSeedKey);
    if (CBBoolOption(mergedOptions, CBCbonsaiSeedEnabledKey) && seed > 0) {
        [arguments addObject:[NSString stringWithFormat:@"--seed=%ld", (long)seed]];
    } else if (automaticSeed > 0) {
        [arguments addObject:[NSString stringWithFormat:@"--seed=%ld", (long)automaticSeed]];
    }

    if (CBBoolOption(mergedOptions, CBCbonsaiVerboseKey)) {
        [arguments addObject:@"--verbose"];
    }

    return arguments;
}
