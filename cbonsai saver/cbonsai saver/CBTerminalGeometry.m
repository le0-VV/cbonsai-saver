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

CGPoint CBTerminalContentOriginForBounds(CGSize boundsSize, CGSize terminalSizeInCells, CGSize cellSize, CGRect contentBoundsInCells, CGRect horizontalAnchorBoundsInCells)
{
    CGFloat terminalWidth = terminalSizeInCells.width * cellSize.width;
    CGFloat terminalHeight = terminalSizeInCells.height * cellSize.height;
    if (boundsSize.width <= 0.0 || boundsSize.height <= 0.0 || cellSize.width <= 0.0 || cellSize.height <= 0.0) {
        return CGPointMake(0.0, 0.0);
    }

    if (contentBoundsInCells.size.width <= 0.0 || contentBoundsInCells.size.height <= 0.0) {
        return CGPointMake(floor((boundsSize.width - terminalWidth) / 2.0),
                           floor((boundsSize.height - terminalHeight) / 2.0));
    }

    CGRect anchorBounds = (horizontalAnchorBoundsInCells.size.width > 0.0 && horizontalAnchorBoundsInCells.size.height > 0.0) ? horizontalAnchorBoundsInCells : contentBoundsInCells;
    CGFloat contentCenterColumn = anchorBounds.origin.x + (anchorBounds.size.width / 2.0);
    CGFloat contentBottomRow = contentBoundsInCells.origin.y + contentBoundsInCells.size.height;
    CGFloat bottomMargin = fmax(cellSize.height * 2.0, boundsSize.height * 0.08);
    return CGPointMake(floor((boundsSize.width / 2.0) - (contentCenterColumn * cellSize.width)),
                       floor(boundsSize.height - bottomMargin - (contentBottomRow * cellSize.height)));
}
