//
//  CBTerminalGeometryTests.m
//  cbonsai saver
//

#import <Foundation/Foundation.h>
#import <math.h>

#import "CBTerminalGeometry.h"

static void CBAssert(BOOL condition, NSString *message)
{
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

static void CBAssertNearlyEqual(CGFloat actual, CGFloat expected, NSString *message)
{
    CBAssert(fabs(actual - expected) < 0.001, [NSString stringWithFormat:@"%@: got %.3f, expected %.3f", message, actual, expected]);
}

int main(void)
{
    @autoreleasepool {
        CGSize onePointCellSize = CGSizeMake(0.6, 1.2);

        CBAssertNearlyEqual(CBAutomaticTerminalFontSizeForBounds(CGSizeMake(1320.0, 816.0), onePointCellSize, NO),
                            20.0,
                            @"Automatic font size should target the configured terminal grid");
        CBAssertNearlyEqual(CBAutomaticTerminalFontSizeForBounds(CGSizeMake(10000.0, 10000.0), onePointCellSize, NO),
                            30.0,
                            @"Automatic font size should clamp large displays");
        CBAssertNearlyEqual(CBAutomaticTerminalFontSizeForBounds(CGSizeMake(300.0, 200.0), onePointCellSize, YES),
                            6.0,
                            @"Preview font size should use the preview minimum");
        CBAssertNearlyEqual(CBAutomaticTerminalFontSizeForBounds(CGSizeMake(0.0, 0.0), onePointCellSize, NO),
                            10.0,
                            @"Invalid bounds should fall back to the minimum");
    }

    return 0;
}
