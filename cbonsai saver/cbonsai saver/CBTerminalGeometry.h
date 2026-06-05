//
//  CBTerminalGeometry.h
//  cbonsai saver
//

#import <CoreGraphics/CoreGraphics.h>

CGFloat CBAutomaticTerminalFontSizeForBounds(CGSize boundsSize, CGSize onePointCellSize, BOOL isPreview);
CGPoint CBTerminalContentOriginForBounds(CGSize boundsSize, CGSize terminalSizeInCells, CGSize cellSize, CGRect contentBoundsInCells);
