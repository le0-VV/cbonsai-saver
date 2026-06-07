//
//  CBCommandLineTests.m
//  cbonsai saver
//

#import <Foundation/Foundation.h>

#import "CBCommandLine.h"

static void CBAssert(BOOL condition, NSString *message)
{
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

static void CBAssertArguments(NSDictionary<NSString *, id> *options, NSArray<NSString *> *expected)
{
    NSArray<NSString *> *actual = CBCbonsaiArgumentsFromOptions(options);
    CBAssert([actual isEqualToArray:expected], [NSString stringWithFormat:@"Compiled arguments %@, expected %@", actual, expected]);
}

static void CBAssertArgumentsWithAutomaticSeed(NSDictionary<NSString *, id> *options, NSInteger automaticSeed, NSArray<NSString *> *expected)
{
    NSArray<NSString *> *actual = CBCbonsaiArgumentsFromOptionsWithAutomaticSeed(options, automaticSeed);
    CBAssert([actual isEqualToArray:expected], [NSString stringWithFormat:@"Compiled arguments %@, expected %@", actual, expected]);
}

static void CBAssertArgumentsExclude(NSDictionary<NSString *, id> *options, NSArray<NSString *> *excluded)
{
    NSArray<NSString *> *actual = CBCbonsaiArgumentsFromOptions(options);
    for (NSString *argument in excluded) {
        CBAssert(![actual containsObject:argument], [NSString stringWithFormat:@"Compiled arguments %@ should not include %@", actual, argument]);
    }
}

int main(void)
{
    @autoreleasepool {
        CBAssert([CBDefaultEnvironmentPath() isEqualToString:@"/usr/bin:/bin:/usr/sbin:/sbin"], @"Default PATH should only include system directories.");

        CBAssertArguments(@{}, (@[
            @"--live",
            @"--infinite",
            @"--time=0.03",
            @"--wait=3",
            @"--base=1",
            @"--leaf=&",
            @"--colors=2,3,10,11",
            @"--multiplier=5",
            @"--life=32",
        ]));

        CBAssertArgumentsWithAutomaticSeed(@{}, 4242, (@[
            @"--live",
            @"--infinite",
            @"--time=0.03",
            @"--wait=3",
            @"--base=1",
            @"--leaf=&",
            @"--colors=2,3,10,11",
            @"--multiplier=5",
            @"--life=32",
            @"--seed=4242",
        ]));

        CBAssertArgumentsExclude(@{
            CBCbonsaiVerboseKey: @NO,
        }, (@[
            @"--verbose",
            @"--color=2,3,10,11",
        ]));

        CBAssertArguments(@{
            CBCbonsaiTimeKey: @0.12,
            CBCbonsaiWaitKey: @8.5,
            CBCbonsaiMessageKey: @" quiet bonsai ",
            CBCbonsaiBaseEnabledKey: @YES,
            CBCbonsaiBaseKey: @0,
            CBCbonsaiLeafKey: @"&,o,@",
            CBCbonsaiColorKey: @"22,94,40,82",
            CBCbonsaiMultiplierKey: @13,
            CBCbonsaiLifeKey: @144,
            CBCbonsaiSeedEnabledKey: @YES,
            CBCbonsaiSeedKey: @12345,
            CBCbonsaiVerboseKey: @YES,
        }, (@[
            @"--live",
            @"--infinite",
            @"--time=0.12",
            @"--wait=8.5",
            @"--message=quiet bonsai",
            @"--base=0",
            @"--leaf=&,o,@",
            @"--colors=22,94,40,82",
            @"--multiplier=13",
            @"--life=144",
            @"--seed=12345",
            @"--verbose",
        ]));

        CBAssertArgumentsWithAutomaticSeed(@{
            CBCbonsaiSeedEnabledKey: @YES,
            CBCbonsaiSeedKey: @12345,
        }, 999, (@[
            @"--live",
            @"--infinite",
            @"--time=0.03",
            @"--wait=3",
            @"--base=1",
            @"--leaf=&",
            @"--colors=2,3,10,11",
            @"--multiplier=5",
            @"--life=32",
            @"--seed=12345",
        ]));

        CBAssertArguments(@{
            @"cbonsaiLive": @NO,
            @"cbonsaiInfinite": @NO,
        }, (@[
            @"--live",
            @"--infinite",
            @"--time=0.03",
            @"--wait=3",
            @"--base=1",
            @"--leaf=&",
            @"--colors=2,3,10,11",
            @"--multiplier=5",
            @"--life=32",
        ]));

        CBAssertArguments(@{
            CBCbonsaiTimeKey: @(-5.0),
            CBCbonsaiWaitKey: @0,
            CBCbonsaiMessageKey: @" hi \033[31m\nthere ",
            CBCbonsaiBaseKey: @99,
            CBCbonsaiLeafKey: @"a,\n,b,\033,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q",
            CBCbonsaiColorKey: @"1,2,invalid,4",
            CBCbonsaiMultiplierKey: @0,
            CBCbonsaiLifeKey: @0,
            CBCbonsaiSeedEnabledKey: @YES,
            CBCbonsaiSeedKey: @0,
        }, (@[
            @"--live",
            @"--infinite",
            @"--time=0.01",
            @"--wait=0.01",
            @"--message=hi [31mthere",
            @"--base=2",
            @"--leaf=a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p",
            @"--colors=2,3,10,11",
            @"--multiplier=1",
            @"--life=1",
        ]));
    }

    return 0;
}
