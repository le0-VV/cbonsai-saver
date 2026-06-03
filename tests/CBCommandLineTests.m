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

static void CBAssertArguments(NSString *input, NSArray<NSString *> *expected)
{
    NSError *error = nil;
    NSArray<NSString *> *actual = CBParseArgumentString(input, &error);
    CBAssert(actual != nil, [NSString stringWithFormat:@"Expected arguments for input '%@', got error '%@'", input, error.localizedDescription]);
    CBAssert([actual isEqualToArray:expected], [NSString stringWithFormat:@"Input '%@' parsed as %@, expected %@", input, actual, expected]);
}

int main(void)
{
    @autoreleasepool {
        CBAssertArguments(@"", @[]);
        CBAssertArguments(@"--screensaver -M 7 -L 80", (@[@"--screensaver", @"-M", @"7", @"-L", @"80"]));
        CBAssertArguments(@"--message 'quiet bonsai' --leaf='&,o'", (@[@"--message", @"quiet bonsai", @"--leaf=&,o"]));
        CBAssertArguments(@"--message=\"escaped \\\"quote\\\"\"", (@[@"--message=escaped \"quote\""]));
        CBAssertArguments(@"--message hello\\ world", (@[@"--message", @"hello world"]));

        NSError *error = nil;
        NSArray<NSString *> *unterminatedQuote = CBParseArgumentString(@"--message 'open", &error);
        CBAssert(unterminatedQuote == nil, @"Unterminated quote should fail.");
        CBAssert([error.domain isEqualToString:CBCommandLineErrorDomain], @"Unterminated quote should use the command-line error domain.");

        error = nil;
        NSArray<NSString *> *trailingEscape = CBParseArgumentString(@"--message hello\\", &error);
        CBAssert(trailingEscape == nil, @"Trailing escape should fail.");
        CBAssert([error.domain isEqualToString:CBCommandLineErrorDomain], @"Trailing escape should use the command-line error domain.");

        CBAssert([CBDefaultExecutablePath() isEqualToString:@"cbonsai"], @"Default executable should use PATH lookup for original cbonsai.");
        CBAssert([CBDefaultArgumentString() isEqualToString:@"--screensaver"], @"Default arguments should use cbonsai screensaver mode.");
        CBAssert([CBDefaultEnvironmentPath() containsString:@"/opt/homebrew/bin"], @"Default PATH should include Homebrew on Apple Silicon.");
    }

    return 0;
}
