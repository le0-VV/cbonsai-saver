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

int main(void)
{
    @autoreleasepool {
        CBAssert([CBDefaultExecutablePath() isEqualToString:@"cbonsai"], @"Default executable should use PATH lookup for original cbonsai.");
        CBAssert([CBDefaultEnvironmentPath() containsString:@"/opt/homebrew/bin"], @"Default PATH should include Homebrew on Apple Silicon.");

        CBAssertArguments(@{}, (@[
            @"--screensaver",
            @"--time=0.03",
            @"--wait=4",
            @"--leaf=&",
            @"--color=2,3,10,11",
            @"--multiplier=5",
            @"--life=32",
        ]));

        CBAssertArguments(@{
            CBCbonsaiScreensaverKey: @NO,
            CBCbonsaiLiveKey: @YES,
            CBCbonsaiInfiniteKey: @YES,
            CBCbonsaiTimeKey: @0.12,
            CBCbonsaiWaitKey: @8.5,
            CBCbonsaiMessageKey: @" quiet bonsai ",
            CBCbonsaiBaseEnabledKey: @YES,
            CBCbonsaiBaseKey: @0,
            CBCbonsaiLeafKey: @"&,o,@",
            CBCbonsaiColorKey: @"22,94,40,82",
            CBCbonsaiMultiplierKey: @13,
            CBCbonsaiLifeKey: @144,
            CBCbonsaiPrintKey: @YES,
            CBCbonsaiSeedEnabledKey: @YES,
            CBCbonsaiSeedKey: @12345,
            CBCbonsaiSaveEnabledKey: @YES,
            CBCbonsaiSavePathKey: @" /tmp/cbonsai-save ",
            CBCbonsaiLoadEnabledKey: @YES,
            CBCbonsaiLoadPathKey: @" /tmp/cbonsai-load ",
            CBCbonsaiVerboseKey: @YES,
            CBCbonsaiHelpKey: @YES,
        }, (@[
            @"--live",
            @"--infinite",
            @"--time=0.12",
            @"--wait=8.5",
            @"--message=quiet bonsai",
            @"--base=0",
            @"--leaf=&,o,@",
            @"--color=22,94,40,82",
            @"--multiplier=13",
            @"--life=144",
            @"--print",
            @"--seed=12345",
            @"--save=/tmp/cbonsai-save",
            @"--load=/tmp/cbonsai-load",
            @"--verbose",
            @"--help",
        ]));
    }

    return 0;
}
