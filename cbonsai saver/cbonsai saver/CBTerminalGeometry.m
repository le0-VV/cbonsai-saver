//
//  CBTerminalGeometry.m
//  cbonsai saver
//

#import "CBTerminalGeometry.h"

#import <math.h>

static const CGFloat CBTargetTerminalColumns = 110.0;
static const CGFloat CBTargetTerminalRows = 34.0;
static const CGFloat CBMinimumFontSize = 10.0;
static const CGFloat CBMaximumFontSize = 30.0;
static const CGFloat CBPreviewMinimumFontSize = 6.0;
static const CGFloat CBPreviewMaximumFontSize = 14.0;

static CGFloat CBClamp(CGFloat value, CGFloat minimum, CGFloat maximum)
{
    return fmin(fmax(value, minimum), maximum);
}

CGFloat CBAutomaticTerminalFontSizeForBounds(CGSize boundsSize, CGSize onePointCellSize, BOOL isPreview)
{
    CGFloat minimum = isPreview ? CBPreviewMinimumFontSize : CBMinimumFontSize;
    CGFloat maximum = isPreview ? CBPreviewMaximumFontSize : CBMaximumFontSize;
    if (boundsSize.width <= 0.0 || boundsSize.height <= 0.0 || onePointCellSize.width <= 0.0 || onePointCellSize.height <= 0.0) {
        return minimum;
    }

    CGFloat fontSizeForWidth = boundsSize.width / (CBTargetTerminalColumns * onePointCellSize.width);
    CGFloat fontSizeForHeight = boundsSize.height / (CBTargetTerminalRows * onePointCellSize.height);
    CGFloat snappedFontSize = floor(fmin(fontSizeForWidth, fontSizeForHeight) * 2.0) / 2.0;
    return CBClamp(snappedFontSize, minimum, maximum);
}
