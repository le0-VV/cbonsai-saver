//
//  CBCommandLine.m
//  cbonsai saver
//

#import "CBCommandLine.h"

NSString * const CBCommandLineErrorDomain = @"wang.leonard.cbonsai-saver.command-line";

typedef NS_ENUM(NSInteger, CBCommandLineErrorCode) {
    CBCommandLineErrorTrailingEscape = 1,
    CBCommandLineErrorUnterminatedQuote = 2,
};

static NSError *CBCommandLineError(CBCommandLineErrorCode code, NSString *description)
{
    return [NSError errorWithDomain:CBCommandLineErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

NSArray<NSString *> *CBParseArgumentString(NSString *argumentString, NSError **error)
{
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL hasCurrentArgument = NO;
    BOOL escaping = NO;
    unichar quote = 0;

    for (NSUInteger index = 0; index < argumentString.length; index++) {
        unichar character = [argumentString characterAtIndex:index];

        if (escaping) {
            [current appendFormat:@"%C", character];
            hasCurrentArgument = YES;
            escaping = NO;
            continue;
        }

        if (quote != 0) {
            if (character == quote) {
                quote = 0;
            } else if (quote == '"' && character == '\\') {
                escaping = YES;
            } else {
                [current appendFormat:@"%C", character];
                hasCurrentArgument = YES;
            }
            continue;
        }

        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:character]) {
            if (hasCurrentArgument) {
                [arguments addObject:[current copy]];
                [current setString:@""];
                hasCurrentArgument = NO;
            }
        } else if (character == '\'' || character == '"') {
            quote = character;
            hasCurrentArgument = YES;
        } else if (character == '\\') {
            escaping = YES;
            hasCurrentArgument = YES;
        } else {
            [current appendFormat:@"%C", character];
            hasCurrentArgument = YES;
        }
    }

    if (escaping) {
        if (error != NULL) {
            *error = CBCommandLineError(CBCommandLineErrorTrailingEscape, @"Arguments end with an unfinished backslash escape.");
        }
        return nil;
    }

    if (quote != 0) {
        if (error != NULL) {
            *error = CBCommandLineError(CBCommandLineErrorUnterminatedQuote, @"Arguments contain an unterminated quote.");
        }
        return nil;
    }

    if (hasCurrentArgument) {
        [arguments addObject:[current copy]];
    }

    return arguments;
}

NSString *CBDefaultExecutablePath(void)
{
    return @"cbonsai";
}

NSString *CBDefaultArgumentString(void)
{
    return @"--screensaver";
}

NSString *CBDefaultEnvironmentPath(void)
{
    return @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
}
