//
//  cbonsai_saverView.m
//  cbonsai saver
//
//  Created by Leonard Wang on 2025/6/11.
//

#import "cbonsai_saverView.h"
#import "CBCommandLine.h"
#import "CBTerminalGeometry.h"

#import <dispatch/dispatch.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <sys/ioctl.h>
#import <sys/wait.h>
#import <unistd.h>
#import <util.h>

static NSString * const CBSettingsModuleName = @"wang.leonard.cbonsai-saver";
static NSString * const CBLegacyScreensaverKey = @"cbonsaiScreensaver";
static NSString * const CBModeDefaultsMigrationKey = @"modeDefaultsMigrated";
static const NSInteger CBDefaultForegroundColor = 7;
static const NSInteger CBDefaultBackgroundColor = -1;
enum {
    CBMinimumTerminalColumns = 40,
    CBMinimumTerminalRows = 12,
    CBMaximumTerminalColumns = 220,
    CBMaximumTerminalRows = 80,
    CBMaximumCSIParameterLength = 64,
    CBMaximumCSIParameterCount = 16,
};
static const NSTimeInterval CBIdleAnimationTimeInterval = 1.0;
static const NSTimeInterval CBTerminalDataFlushInterval = 1.0 / 30.0;
static const CGFloat CBConfigurationSheetWidth = 720.0;
static const CGFloat CBConfigurationSheetHeight = 620.0;
static NSString * const CBManualResourceName = @"cbonsai-manual";
static const CGFloat CBHelpButtonSize = 20.0;
static const CGFloat CBHelpButtonGap = 8.0;
static const NSInteger CBDefaultBaseStyle = 1;
static const NSInteger CBDefaultDarkLeafColor = 2;
static const NSInteger CBDefaultDarkWoodColor = 3;
static const NSInteger CBDefaultLightLeafColor = 10;
static const NSInteger CBDefaultLightWoodColor = 11;

typedef struct {
    unichar character;
    NSInteger foregroundColor;
    NSInteger backgroundColor;
    BOOL bold;
} CBTerminalCell;

typedef struct {
    CGRect contentBounds;
    CGRect bottomContentBounds;
} CBTerminalContentMetrics;

static CBTerminalCell CBTerminalDefaultCell(void)
{
    CBTerminalCell cell;
    cell.character = ' ';
    cell.foregroundColor = CBDefaultForegroundColor;
    cell.backgroundColor = CBDefaultBackgroundColor;
    cell.bold = NO;
    return cell;
}

static NSColor *CBColorForANSIIndex(NSInteger index)
{
    static NSArray<NSColor *> *baseColors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        baseColors = @[
            [NSColor colorWithCalibratedRed:0.00 green:0.00 blue:0.00 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.80 green:0.00 blue:0.00 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.00 green:0.55 blue:0.00 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.80 green:0.55 blue:0.00 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.00 green:0.00 blue:0.80 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.80 green:0.00 blue:0.80 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.00 green:0.55 blue:0.80 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.35 green:0.35 blue:0.35 alpha:1.0],
            [NSColor colorWithCalibratedRed:1.00 green:0.20 blue:0.20 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.20 green:1.00 blue:0.20 alpha:1.0],
            [NSColor colorWithCalibratedRed:1.00 green:1.00 blue:0.20 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.20 green:0.20 blue:1.00 alpha:1.0],
            [NSColor colorWithCalibratedRed:1.00 green:0.20 blue:1.00 alpha:1.0],
            [NSColor colorWithCalibratedRed:0.20 green:1.00 blue:1.00 alpha:1.0],
            [NSColor colorWithCalibratedRed:1.00 green:1.00 blue:1.00 alpha:1.0],
        ];
    });

    if (index < 0) {
        return [NSColor blackColor];
    }

    if (index < (NSInteger)baseColors.count) {
        return baseColors[(NSUInteger)index];
    }

    if (index >= 16 && index <= 231) {
        NSInteger cubeIndex = index - 16;
        NSInteger redIndex = cubeIndex / 36;
        NSInteger greenIndex = (cubeIndex / 6) % 6;
        NSInteger blueIndex = cubeIndex % 6;
        CGFloat red = (redIndex == 0) ? 0.0 : (CGFloat)(55 + redIndex * 40) / 255.0;
        CGFloat green = (greenIndex == 0) ? 0.0 : (CGFloat)(55 + greenIndex * 40) / 255.0;
        CGFloat blue = (blueIndex == 0) ? 0.0 : (CGFloat)(55 + blueIndex * 40) / 255.0;
        return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0];
    }

    if (index >= 232 && index <= 255) {
        CGFloat value = (CGFloat)(8 + (index - 232) * 10) / 255.0;
        return [NSColor colorWithCalibratedWhite:value alpha:1.0];
    }

    return [NSColor whiteColor];
}

static NSArray<NSNumber *> *CBNamedANSIColorIndexes(void)
{
    static NSArray<NSNumber *> *indexes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        indexes = @[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11, @12, @13, @14, @15];
    });
    return indexes;
}

static NSArray<NSNumber *> *CBDefaultTreeColorIndexes(void)
{
    return @[
        @(CBDefaultDarkLeafColor),
        @(CBDefaultDarkWoodColor),
        @(CBDefaultLightLeafColor),
        @(CBDefaultLightWoodColor),
    ];
}

static NSString *CBANSIColorNameForIndex(NSInteger index)
{
    switch (index) {
        case 0:
            return @"Black";
        case 1:
            return @"Red";
        case 2:
            return @"Green";
        case 3:
            return @"Yellow";
        case 4:
            return @"Blue";
        case 5:
            return @"Magenta";
        case 6:
            return @"Cyan";
        case 7:
            return @"White";
        case 8:
            return @"Bright black";
        case 9:
            return @"Bright red";
        case 10:
            return @"Bright green";
        case 11:
            return @"Bright yellow";
        case 12:
            return @"Bright blue";
        case 13:
            return @"Bright magenta";
        case 14:
            return @"Bright cyan";
        case 15:
            return @"Bright white";
        default:
            return [NSString stringWithFormat:@"ANSI %ld", (long)index];
    }
}

static NSArray<NSNumber *> *CBTreeColorIndexesFromString(NSString *string)
{
    if (![string isKindOfClass:NSString.class]) {
        return CBDefaultTreeColorIndexes();
    }

    NSArray<NSString *> *components = [string componentsSeparatedByString:@","];
    if (components.count != 4) {
        return CBDefaultTreeColorIndexes();
    }

    NSMutableArray<NSNumber *> *indexes = [NSMutableArray arrayWithCapacity:4];
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSString *component in components) {
        NSString *trimmedComponent = [component stringByTrimmingCharactersInSet:whitespace];
        NSScanner *scanner = [NSScanner scannerWithString:trimmedComponent];
        scanner.charactersToBeSkipped = nil;

        NSInteger index = 0;
        if (trimmedComponent.length == 0 || ![scanner scanInteger:&index] || !scanner.isAtEnd || index < 0 || index > 255) {
            return CBDefaultTreeColorIndexes();
        }

        [indexes addObject:@(index)];
    }

    return indexes;
}

static NSUInteger CBParameterAt(NSArray<NSNumber *> *parameters, NSUInteger index, NSUInteger defaultValue)
{
    if (index >= parameters.count) {
        return defaultValue;
    }
    return parameters[index].unsignedIntegerValue;
}

static unsigned short CBClampedUnsignedShortFromCGFloat(CGFloat value)
{
    if (value <= 0.0) {
        return 0;
    }
    return (unsigned short)MIN(value, (CGFloat)USHRT_MAX);
}

static char **CBCStringArrayFromStrings(NSArray<NSString *> *strings)
{
    char **result = calloc(strings.count + 1, sizeof(char *));
    if (result == NULL) {
        return NULL;
    }

    for (NSUInteger index = 0; index < strings.count; index++) {
        result[index] = strdup(strings[index].UTF8String);
        if (result[index] == NULL) {
            for (NSUInteger cleanupIndex = 0; cleanupIndex < index; cleanupIndex++) {
                free(result[cleanupIndex]);
            }
            free(result);
            return NULL;
        }
    }

    result[strings.count] = NULL;
    return result;
}

static void CBFreeCStringArray(char **strings)
{
    if (strings == NULL) {
        return;
    }

    for (NSUInteger index = 0; strings[index] != NULL; index++) {
        free(strings[index]);
    }
    free(strings);
}

static NSArray<NSNumber *> *CBParametersFromCSIString(NSString *string, BOOL *isPrivate)
{
    NSString *parameters = string;
    if ([parameters hasPrefix:@"?"]) {
        if (isPrivate != NULL) {
            *isPrivate = YES;
        }
        parameters = [parameters substringFromIndex:1];
    } else if (isPrivate != NULL) {
        *isPrivate = NO;
    }

    if (parameters.length == 0) {
        return @[];
    }

    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    for (NSString *component in [parameters componentsSeparatedByString:@";"]) {
        if (result.count >= CBMaximumCSIParameterCount) {
            break;
        }

        if (component.length == 0) {
            [result addObject:@0];
        } else {
            NSScanner *scanner = [NSScanner scannerWithString:component];
            scanner.charactersToBeSkipped = nil;
            NSInteger value = 0;
            if (![scanner scanInteger:&value] || !scanner.isAtEnd || value < 0) {
                value = 0;
            }
            [result addObject:@(MIN(value, 10000))];
        }
    }
    return result;
}

typedef NS_ENUM(NSUInteger, CBParserState) {
    CBParserStateGround,
    CBParserStateEscape,
    CBParserStateCSI,
    CBParserStateCharset,
};

@interface CBFlippedView : NSView
@end

@implementation CBFlippedView

- (BOOL)isFlipped
{
    return YES;
}

@end

@interface CBTerminalBuffer : NSObject

@property (nonatomic, readonly) NSUInteger columns;
@property (nonatomic, readonly) NSUInteger rows;

- (instancetype)initWithColumns:(NSUInteger)columns rows:(NSUInteger)rows;
- (void)resizeToColumns:(NSUInteger)columns rows:(NSUInteger)rows;
- (void)appendData:(NSData *)data;
- (CBTerminalCell)cellAtColumn:(NSUInteger)column row:(NSUInteger)row;
- (const CBTerminalCell *)cellsForRow:(NSUInteger)row;
- (CBTerminalContentMetrics)contentMetrics;
- (void)showStatusMessage:(NSString *)message;

@end

@implementation CBTerminalBuffer {
    CBTerminalCell *_cells;
    NSUInteger _columns;
    NSUInteger _rows;
    NSUInteger _cursorColumn;
    NSUInteger _cursorRow;
    NSUInteger _savedCursorColumn;
    NSUInteger _savedCursorRow;
    NSInteger _foregroundColor;
    NSInteger _backgroundColor;
    BOOL _bold;
    CBParserState _parserState;
    NSMutableString *_csiString;
    NSMutableData *_utf8Bytes;
    NSUInteger _expectedUTF8Length;
}

@synthesize columns = _columns;
@synthesize rows = _rows;

- (instancetype)initWithColumns:(NSUInteger)columns rows:(NSUInteger)rows
{
    self = [super init];
    if (self) {
        _columns = MAX((NSUInteger)1, columns);
        _rows = MAX((NSUInteger)1, rows);
        _cells = calloc(_columns * _rows, sizeof(CBTerminalCell));
        if (_cells == NULL) {
            return nil;
        }
        _foregroundColor = CBDefaultForegroundColor;
        _backgroundColor = CBDefaultBackgroundColor;
        _csiString = [NSMutableString string];
        _utf8Bytes = [NSMutableData data];
        [self fillCellsFromIndex:0 count:_columns * _rows];
    }
    return self;
}

- (void)dealloc
{
    free(_cells);
}

- (void)resizeToColumns:(NSUInteger)columns rows:(NSUInteger)rows
{
    columns = MAX((NSUInteger)1, columns);
    rows = MAX((NSUInteger)1, rows);

    if (columns == _columns && rows == _rows) {
        return;
    }

    CBTerminalCell *newCells = calloc(columns * rows, sizeof(CBTerminalCell));
    if (newCells == NULL) {
        return;
    }

    for (NSUInteger index = 0; index < columns * rows; index++) {
        newCells[index] = CBTerminalDefaultCell();
    }

    NSUInteger copyRows = MIN(_rows, rows);
    NSUInteger copyColumns = MIN(_columns, columns);
    for (NSUInteger row = 0; row < copyRows; row++) {
        memcpy(newCells + row * columns, _cells + row * _columns, copyColumns * sizeof(CBTerminalCell));
    }

    free(_cells);
    _cells = newCells;
    _columns = columns;
    _rows = rows;
    _cursorColumn = MIN(_cursorColumn, _columns - 1);
    _cursorRow = MIN(_cursorRow, _rows - 1);
    _savedCursorColumn = MIN(_savedCursorColumn, _columns - 1);
    _savedCursorRow = MIN(_savedCursorRow, _rows - 1);
}

- (void)appendData:(NSData *)data
{
    const unsigned char *bytes = data.bytes;
    for (NSUInteger index = 0; index < data.length; index++) {
        [self consumeByte:bytes[index]];
    }
}

- (CBTerminalCell)cellAtColumn:(NSUInteger)column row:(NSUInteger)row
{
    if (column >= _columns || row >= _rows) {
        return CBTerminalDefaultCell();
    }
    return _cells[row * _columns + column];
}

- (const CBTerminalCell *)cellsForRow:(NSUInteger)row
{
    if (row >= _rows) {
        return NULL;
    }
    return _cells + row * _columns;
}

- (CBTerminalContentMetrics)contentMetrics
{
    CBTerminalContentMetrics metrics;
    metrics.contentBounds = CGRectMake(0.0, 0.0, 0.0, 0.0);
    metrics.bottomContentBounds = CGRectMake(0.0, 0.0, 0.0, 0.0);

    BOOL foundContent = NO;
    NSUInteger minimumColumn = _columns;
    NSUInteger maximumColumn = 0;
    NSUInteger minimumRow = _rows;
    NSUInteger maximumRow = 0;
    NSUInteger bottomRow = 0;
    NSUInteger bottomMinimumColumn = _columns;
    NSUInteger bottomMaximumColumn = 0;

    for (NSUInteger row = 0; row < _rows; row++) {
        for (NSUInteger column = 0; column < _columns; column++) {
            CBTerminalCell cell = _cells[row * _columns + column];
            if (cell.character == ' ') {
                continue;
            }

            BOOL isFirstContent = !foundContent;
            foundContent = YES;
            minimumColumn = MIN(minimumColumn, column);
            maximumColumn = MAX(maximumColumn, column);
            minimumRow = MIN(minimumRow, row);
            maximumRow = MAX(maximumRow, row);

            if (isFirstContent || row > bottomRow) {
                bottomRow = row;
                bottomMinimumColumn = column;
                bottomMaximumColumn = column;
            } else if (row == bottomRow) {
                bottomMinimumColumn = MIN(bottomMinimumColumn, column);
                bottomMaximumColumn = MAX(bottomMaximumColumn, column);
            }
        }
    }

    if (foundContent) {
        metrics.contentBounds = CGRectMake((CGFloat)minimumColumn,
                                           (CGFloat)minimumRow,
                                           (CGFloat)(maximumColumn - minimumColumn + 1),
                                           (CGFloat)(maximumRow - minimumRow + 1));
        metrics.bottomContentBounds = CGRectMake((CGFloat)bottomMinimumColumn,
                                                 (CGFloat)bottomRow,
                                                 (CGFloat)(bottomMaximumColumn - bottomMinimumColumn + 1),
                                                 1.0);
    }

    return metrics;
}

- (void)showStatusMessage:(NSString *)message
{
    [self clearAllCellsAndResetCursor:YES];
    NSUInteger maxLength = MIN(message.length, _columns);
    for (NSUInteger index = 0; index < maxLength; index++) {
        CBTerminalCell cell = CBTerminalDefaultCell();
        cell.character = [message characterAtIndex:index];
        cell.foregroundColor = 9;
        _cells[index] = cell;
    }
}

- (void)consumeByte:(unsigned char)byte
{
    switch (_parserState) {
        case CBParserStateGround:
            [self consumeGroundByte:byte];
            break;
        case CBParserStateEscape:
            [self consumeEscapeByte:byte];
            break;
        case CBParserStateCSI:
            [self consumeCSIByte:byte];
            break;
        case CBParserStateCharset:
            _parserState = CBParserStateGround;
            break;
    }
}

- (void)consumeGroundByte:(unsigned char)byte
{
    if (_expectedUTF8Length > 0) {
        [self consumeUTF8ContinuationByte:byte];
        return;
    }

    if (byte == 0x1B) {
        _parserState = CBParserStateEscape;
    } else if (byte == '\r') {
        _cursorColumn = 0;
    } else if (byte == '\n') {
        [self moveCursorDownOneLine];
    } else if (byte == '\b') {
        if (_cursorColumn > 0) {
            _cursorColumn--;
        }
    } else if (byte == '\t') {
        NSUInteger targetColumn = MIN(_columns - 1, ((_cursorColumn / 8) + 1) * 8);
        while (_cursorColumn < targetColumn) {
            [self putCharacter:' '];
        }
    } else if (byte >= 0x20 && byte < 0x7F) {
        [self putCharacter:(unichar)byte];
    } else if (byte >= 0xC2 && byte <= 0xF4) {
        [self startUTF8SequenceWithByte:byte];
    }
}

- (void)consumeEscapeByte:(unsigned char)byte
{
    if (byte == '[') {
        [_csiString setString:@""];
        _parserState = CBParserStateCSI;
    } else if (byte == '7') {
        _savedCursorColumn = _cursorColumn;
        _savedCursorRow = _cursorRow;
        _parserState = CBParserStateGround;
    } else if (byte == '8') {
        _cursorColumn = MIN(_savedCursorColumn, _columns - 1);
        _cursorRow = MIN(_savedCursorRow, _rows - 1);
        _parserState = CBParserStateGround;
    } else if (byte == 'c') {
        [self clearAllCellsAndResetCursor:YES];
        _parserState = CBParserStateGround;
    } else if (byte == '(' || byte == ')') {
        _parserState = CBParserStateCharset;
    } else {
        _parserState = CBParserStateGround;
    }
}

- (void)consumeCSIByte:(unsigned char)byte
{
    if (byte >= 0x40 && byte <= 0x7E) {
        [self handleCSIWithFinalByte:byte];
        [_csiString setString:@""];
        _parserState = CBParserStateGround;
    } else if ((byte >= '0' && byte <= '9') || byte == ';' || byte == '?') {
        if (_csiString.length >= CBMaximumCSIParameterLength) {
            [_csiString setString:@""];
            _parserState = CBParserStateGround;
            return;
        }
        [_csiString appendFormat:@"%c", byte];
    } else {
        [_csiString setString:@""];
        _parserState = CBParserStateGround;
    }
}

- (void)handleCSIWithFinalByte:(unsigned char)byte
{
    BOOL privateSequence = NO;
    NSArray<NSNumber *> *parameters = CBParametersFromCSIString(_csiString, &privateSequence);

    switch (byte) {
        case 'H':
        case 'f':
            [self moveCursorToRow:CBParameterAt(parameters, 0, 1) column:CBParameterAt(parameters, 1, 1)];
            break;
        case 'A':
            _cursorRow -= MIN(_cursorRow, CBParameterAt(parameters, 0, 1));
            break;
        case 'B':
            _cursorRow = MIN(_rows - 1, _cursorRow + CBParameterAt(parameters, 0, 1));
            break;
        case 'C':
            _cursorColumn = MIN(_columns - 1, _cursorColumn + CBParameterAt(parameters, 0, 1));
            break;
        case 'D':
            _cursorColumn -= MIN(_cursorColumn, CBParameterAt(parameters, 0, 1));
            break;
        case 'G':
            [self moveCursorToColumn:CBParameterAt(parameters, 0, 1)];
            break;
        case 'd':
            [self moveCursorToRow:CBParameterAt(parameters, 0, 1) column:_cursorColumn + 1];
            break;
        case 'J':
            [self clearScreenWithMode:CBParameterAt(parameters, 0, 0)];
            break;
        case 'K':
            [self clearLineWithMode:CBParameterAt(parameters, 0, 0)];
            break;
        case 'm':
            [self applySGRParameters:parameters];
            break;
        case 's':
            _savedCursorColumn = _cursorColumn;
            _savedCursorRow = _cursorRow;
            break;
        case 'u':
            _cursorColumn = MIN(_savedCursorColumn, _columns - 1);
            _cursorRow = MIN(_savedCursorRow, _rows - 1);
            break;
        case 'h':
        case 'l':
            if (privateSequence && ([parameters containsObject:@1049] || [parameters containsObject:@47])) {
                [self clearAllCellsAndResetCursor:YES];
            }
            break;
        default:
            break;
    }
}

- (void)startUTF8SequenceWithByte:(unsigned char)byte
{
    [_utf8Bytes setLength:0];
    [_utf8Bytes appendBytes:&byte length:1];

    if ((byte & 0xE0) == 0xC0) {
        _expectedUTF8Length = 2;
    } else if ((byte & 0xF0) == 0xE0) {
        _expectedUTF8Length = 3;
    } else {
        _expectedUTF8Length = 4;
    }
}

- (void)consumeUTF8ContinuationByte:(unsigned char)byte
{
    if ((byte & 0xC0) != 0x80) {
        [_utf8Bytes setLength:0];
        _expectedUTF8Length = 0;
        [self putCharacter:'?'];
        [self consumeGroundByte:byte];
        return;
    }

    [_utf8Bytes appendBytes:&byte length:1];
    if (_utf8Bytes.length < _expectedUTF8Length) {
        return;
    }

    NSString *character = [[NSString alloc] initWithData:_utf8Bytes encoding:NSUTF8StringEncoding];
    [self putCharacter:(character.length > 0) ? [character characterAtIndex:0] : '?'];
    [_utf8Bytes setLength:0];
    _expectedUTF8Length = 0;
}

- (void)putCharacter:(unichar)character
{
    if (_cursorColumn >= _columns) {
        _cursorColumn = 0;
        [self moveCursorDownOneLine];
    }

    CBTerminalCell cell;
    cell.character = character;
    cell.foregroundColor = _foregroundColor;
    cell.backgroundColor = _backgroundColor;
    cell.bold = _bold;
    _cells[_cursorRow * _columns + _cursorColumn] = cell;

    _cursorColumn++;
    if (_cursorColumn >= _columns) {
        _cursorColumn = 0;
        [self moveCursorDownOneLine];
    }
}

- (void)moveCursorDownOneLine
{
    if (_cursorRow + 1 < _rows) {
        _cursorRow++;
    } else {
        [self scrollUpOneLine];
    }
}

- (void)moveCursorToRow:(NSUInteger)row column:(NSUInteger)column
{
    _cursorRow = MIN((row > 0) ? row - 1 : 0, _rows - 1);
    _cursorColumn = MIN((column > 0) ? column - 1 : 0, _columns - 1);
}

- (void)moveCursorToColumn:(NSUInteger)column
{
    _cursorColumn = MIN((column > 0) ? column - 1 : 0, _columns - 1);
}

- (void)scrollUpOneLine
{
    if (_rows <= 1) {
        [self fillCellsFromIndex:0 count:_columns];
        return;
    }

    memmove(_cells, _cells + _columns, (_rows - 1) * _columns * sizeof(CBTerminalCell));
    [self fillCellsFromIndex:(_rows - 1) * _columns count:_columns];
}

- (void)clearAllCellsAndResetCursor:(BOOL)resetCursor
{
    [self fillCellsFromIndex:0 count:_columns * _rows];
    if (resetCursor) {
        _cursorColumn = 0;
        _cursorRow = 0;
        _foregroundColor = CBDefaultForegroundColor;
        _backgroundColor = CBDefaultBackgroundColor;
        _bold = NO;
    }
}

- (void)clearScreenWithMode:(NSUInteger)mode
{
    if (mode == 2 || mode == 3) {
        [self clearAllCellsAndResetCursor:NO];
        return;
    }

    if (mode == 1) {
        for (NSUInteger row = 0; row <= _cursorRow; row++) {
            NSUInteger startColumn = 0;
            NSUInteger endColumn = (row == _cursorRow) ? _cursorColumn : _columns - 1;
            [self clearRow:row startColumn:startColumn endColumn:endColumn];
        }
        return;
    }

    for (NSUInteger row = _cursorRow; row < _rows; row++) {
        NSUInteger startColumn = (row == _cursorRow) ? _cursorColumn : 0;
        [self clearRow:row startColumn:startColumn endColumn:_columns - 1];
    }
}

- (void)clearLineWithMode:(NSUInteger)mode
{
    if (mode == 2) {
        [self clearRow:_cursorRow startColumn:0 endColumn:_columns - 1];
    } else if (mode == 1) {
        [self clearRow:_cursorRow startColumn:0 endColumn:_cursorColumn];
    } else {
        [self clearRow:_cursorRow startColumn:_cursorColumn endColumn:_columns - 1];
    }
}

- (void)clearRow:(NSUInteger)row startColumn:(NSUInteger)startColumn endColumn:(NSUInteger)endColumn
{
    if (row >= _rows || startColumn >= _columns || endColumn >= _columns || startColumn > endColumn) {
        return;
    }
    [self fillCellsFromIndex:row * _columns + startColumn count:endColumn - startColumn + 1];
}

- (void)fillCellsFromIndex:(NSUInteger)startIndex count:(NSUInteger)count
{
    CBTerminalCell defaultCell = CBTerminalDefaultCell();
    for (NSUInteger index = startIndex; index < startIndex + count; index++) {
        _cells[index] = defaultCell;
    }
}

- (void)applySGRParameters:(NSArray<NSNumber *> *)parameters
{
    if (parameters.count == 0) {
        [self resetAttributes];
        return;
    }

    for (NSUInteger index = 0; index < parameters.count; index++) {
        NSInteger value = parameters[index].integerValue;

        if (value == 0) {
            [self resetAttributes];
        } else if (value == 1) {
            _bold = YES;
        } else if (value == 22) {
            _bold = NO;
        } else if (value >= 30 && value <= 37) {
            _foregroundColor = value - 30;
        } else if (value == 39) {
            _foregroundColor = CBDefaultForegroundColor;
        } else if (value >= 40 && value <= 47) {
            _backgroundColor = value - 40;
        } else if (value == 49) {
            _backgroundColor = CBDefaultBackgroundColor;
        } else if (value >= 90 && value <= 97) {
            _foregroundColor = value - 90 + 8;
        } else if (value >= 100 && value <= 107) {
            _backgroundColor = value - 100 + 8;
        } else if ((value == 38 || value == 48) && index + 2 < parameters.count && parameters[index + 1].integerValue == 5) {
            NSInteger color = parameters[index + 2].integerValue;
            if (color >= 0 && color <= 255) {
                if (value == 38) {
                    _foregroundColor = color;
                } else {
                    _backgroundColor = color;
                }
            }
            index += 2;
        } else if ((value == 38 || value == 48) && index + 4 < parameters.count && parameters[index + 1].integerValue == 2) {
            index += 4;
        }
    }
}

- (void)resetAttributes
{
    _foregroundColor = CBDefaultForegroundColor;
    _backgroundColor = CBDefaultBackgroundColor;
    _bold = NO;
}

@end

@interface cbonsai_saverView ()

@property (nonatomic, strong) CBTerminalBuffer *terminalBuffer;
@property (nonatomic, strong) NSFont *terminalFont;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *terminalTextAttributesCache;
@property (nonatomic, strong) NSMutableData *pendingTerminalData;
@property (nonatomic, strong) dispatch_queue_t readQueue;
@property (nonatomic, strong) dispatch_source_t readSource;
@property (nonatomic) CGFloat cellWidth;
@property (nonatomic) CGFloat cellHeight;
@property (nonatomic) int masterFileDescriptor;
@property (nonatomic) pid_t childProcessIdentifier;
@property (nonatomic) BOOL stoppingChildProcess;
@property (nonatomic) BOOL terminalDataFlushScheduled;
@property (nonatomic, strong) NSWindow *configurationSheet;
@property (nonatomic, strong) NSTextField *timeField;
@property (nonatomic, strong) NSStepper *timeStepper;
@property (nonatomic, strong) NSTextField *waitField;
@property (nonatomic, strong) NSStepper *waitStepper;
@property (nonatomic, strong) NSTextField *messageField;
@property (nonatomic, strong) NSPopUpButton *basePopUpButton;
@property (nonatomic, strong) NSTextField *leafField;
@property (nonatomic, strong) NSPopUpButton *darkLeafColorPopUpButton;
@property (nonatomic, strong) NSPopUpButton *darkWoodColorPopUpButton;
@property (nonatomic, strong) NSPopUpButton *lightLeafColorPopUpButton;
@property (nonatomic, strong) NSPopUpButton *lightWoodColorPopUpButton;
@property (nonatomic, strong) NSTextField *multiplierField;
@property (nonatomic, strong) NSStepper *multiplierStepper;
@property (nonatomic, strong) NSTextField *lifeField;
@property (nonatomic, strong) NSStepper *lifeStepper;
@property (nonatomic, strong) NSButton *seedEnabledButton;
@property (nonatomic, strong) NSTextField *seedField;
@property (nonatomic, strong) NSButton *verboseButton;

@end

@implementation cbonsai_saverView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        _masterFileDescriptor = -1;
        _childProcessIdentifier = -1;
        _pendingTerminalData = [NSMutableData data];
        _readQueue = dispatch_queue_create("wang.leonard.cbonsai-saver.pty", DISPATCH_QUEUE_SERIAL);
        [self setAnimationTimeInterval:CBIdleAnimationTimeInterval];
        [self registerDefaultSettings];
        [self updateTerminalGeometry];
    }
    return self;
}

- (void)dealloc
{
    [self stopCbonsaiProcess];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self updateTerminalGeometry];
}

- (void)startAnimation
{
    [super startAnimation];
    [self updateTerminalGeometry];
    [self startCbonsaiProcess];
}

- (void)stopAnimation
{
    [self stopCbonsaiProcess];
    [super stopAnimation];
}

- (void)drawRect:(NSRect)rect
{
    [[NSColor blackColor] setFill];
    NSRectFill(rect);

    if (self.terminalBuffer == nil || self.cellWidth <= 0.0 || self.cellHeight <= 0.0) {
        return;
    }

    CBTerminalContentMetrics metrics = [self.terminalBuffer contentMetrics];
    CGPoint origin = CBTerminalContentOriginForBounds(self.bounds.size,
                                                      CGSizeMake((CGFloat)self.terminalBuffer.columns, (CGFloat)self.terminalBuffer.rows),
                                                      CGSizeMake(self.cellWidth, self.cellHeight),
                                                      metrics.contentBounds,
                                                      metrics.bottomContentBounds);

    for (NSUInteger row = 0; row < self.terminalBuffer.rows; row++) {
        [self drawBackgroundsForRow:row originX:origin.x originY:origin.y];
        [self drawTextForRow:row originX:origin.x originY:origin.y];
    }
}

- (void)animateOneFrame
{
}

- (BOOL)hasConfigureSheet
{
    return YES;
}

- (NSWindow *)configureSheet
{
    if (self.configurationSheet == nil) {
        self.configurationSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, CBConfigurationSheetWidth, CBConfigurationSheetHeight)
                                                              styleMask:NSWindowStyleMaskTitled
                                                                backing:NSBackingStoreBuffered
                                                                  defer:NO];
        self.configurationSheet.title = @"cbonsai screen saver";
        [self buildConfigurationContent];
    }

    [self loadConfigurationFields];
    return self.configurationSheet;
}

- (ScreenSaverDefaults *)screenSaverDefaults
{
    ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:CBSettingsModuleName];
    NSMutableDictionary<NSString *, id> *registeredDefaults = [NSMutableDictionary dictionary];
    [registeredDefaults addEntriesFromDictionary:CBDefaultCbonsaiOptions()];
    [defaults registerDefaults:registeredDefaults];
    [self migrateModeDefaultsIfNeeded:defaults];
    return defaults;
}

- (void)registerDefaultSettings
{
    (void)[self screenSaverDefaults];
}

- (void)migrateModeDefaultsIfNeeded:(ScreenSaverDefaults *)defaults
{
    if ([defaults boolForKey:CBModeDefaultsMigrationKey]) {
        return;
    }

    id legacyScreensaverValue = [defaults objectForKey:CBLegacyScreensaverKey];
    if ([legacyScreensaverValue respondsToSelector:@selector(boolValue)] && [legacyScreensaverValue boolValue]) {
        if (fabs([defaults doubleForKey:CBCbonsaiWaitKey] - 4.0) < 0.0001) {
            [defaults setDouble:3.0 forKey:CBCbonsaiWaitKey];
        }
    }

    [defaults setBool:YES forKey:CBModeDefaultsMigrationKey];
    [defaults synchronize];
}

- (NSDictionary<NSString *, id> *)configuredCbonsaiOptions
{
    ScreenSaverDefaults *defaults = [self screenSaverDefaults];
    NSMutableDictionary<NSString *, id> *options = [CBDefaultCbonsaiOptions() mutableCopy];
    for (NSString *key in CBDefaultCbonsaiOptions()) {
        id value = [defaults objectForKey:key];
        if (value != nil) {
            options[key] = value;
        }
    }
    return options;
}

- (CGFloat)automaticFontSize
{
    NSFont *onePointFont = [self terminalFontWithSize:1.0];
    return CBAutomaticTerminalFontSizeForBounds(self.bounds.size, [self cellSizeForFont:onePointFont], self.isPreview);
}

- (void)updateTerminalGeometry
{
    CGFloat fontSize = [self automaticFontSize];
    if (self.terminalFont == nil || fabs(self.terminalFont.pointSize - fontSize) > 0.1) {
        self.terminalFont = [self terminalFontWithSize:fontSize];
        self.terminalTextAttributesCache = nil;
        CGSize cellSize = [self cellSizeForFont:self.terminalFont];
        self.cellWidth = ceil(cellSize.width);
        self.cellHeight = ceil(cellSize.height);
    }

    if (self.cellWidth <= 0.0 || self.cellHeight <= 0.0 || NSWidth(self.bounds) <= 0.0 || NSHeight(self.bounds) <= 0.0) {
        return;
    }

    NSUInteger columns = MIN(CBMaximumTerminalColumns, MAX(CBMinimumTerminalColumns, (NSUInteger)floor(NSWidth(self.bounds) / self.cellWidth)));
    NSUInteger rows = MIN(CBMaximumTerminalRows, MAX(CBMinimumTerminalRows, (NSUInteger)floor(NSHeight(self.bounds) / self.cellHeight)));

    if (self.terminalBuffer == nil) {
        self.terminalBuffer = [[CBTerminalBuffer alloc] initWithColumns:columns rows:rows];
    } else {
        [self.terminalBuffer resizeToColumns:columns rows:rows];
    }

    [self updatePtyWindowSize];
}

- (NSFont *)terminalFontWithSize:(CGFloat)fontSize
{
    NSFont *font = [NSFont userFixedPitchFontOfSize:fontSize];
    return font ?: [NSFont monospacedSystemFontOfSize:fontSize weight:NSFontWeightRegular];
}

- (CGSize)cellSizeForFont:(NSFont *)font
{
    NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName: font};
    return CGSizeMake([@"W" sizeWithAttributes:attributes].width,
                      font.ascender - font.descender + font.leading);
}

- (void)updatePtyWindowSize
{
    if (self.masterFileDescriptor < 0 || self.terminalBuffer == nil) {
        return;
    }

    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_col = (unsigned short)self.terminalBuffer.columns;
    size.ws_row = (unsigned short)self.terminalBuffer.rows;
    size.ws_xpixel = CBClampedUnsignedShortFromCGFloat(NSWidth(self.bounds));
    size.ws_ypixel = CBClampedUnsignedShortFromCGFloat(NSHeight(self.bounds));
    ioctl(self.masterFileDescriptor, TIOCSWINSZ, &size);
}

- (void)startCbonsaiProcess
{
    if (self.childProcessIdentifier > 0 || self.terminalBuffer == nil) {
        return;
    }

    NSString *executablePath = self.bundledCbonsaiPath;
    if (executablePath.length == 0 || ![NSFileManager.defaultManager isExecutableFileAtPath:executablePath]) {
        [self.terminalBuffer showStatusMessage:@"Bundled cbonsai binary is missing."];
        [self setNeedsDisplay:YES];
        return;
    }

    NSArray<NSString *> *arguments = CBCbonsaiArgumentsFromOptions(self.configuredCbonsaiOptions);

    char **processArgv = [self createProcessArgvWithExecutablePath:executablePath arguments:arguments];
    char **processEnvironment = [self createProcessEnvironment];
    if (processArgv == NULL || processEnvironment == NULL) {
        CBFreeCStringArray(processArgv);
        CBFreeCStringArray(processEnvironment);
        [self.terminalBuffer showStatusMessage:@"Unable to allocate cbonsai launch arguments."];
        [self setNeedsDisplay:YES];
        return;
    }

    int masterFileDescriptor = -1;
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_col = (unsigned short)self.terminalBuffer.columns;
    size.ws_row = (unsigned short)self.terminalBuffer.rows;
    size.ws_xpixel = CBClampedUnsignedShortFromCGFloat(NSWidth(self.bounds));
    size.ws_ypixel = CBClampedUnsignedShortFromCGFloat(NSHeight(self.bounds));

    pid_t childPid = forkpty(&masterFileDescriptor, NULL, NULL, &size);
    if (childPid < 0) {
        CBFreeCStringArray(processArgv);
        CBFreeCStringArray(processEnvironment);
        [self.terminalBuffer showStatusMessage:[NSString stringWithFormat:@"forkpty failed: %s", strerror(errno)]];
        [self setNeedsDisplay:YES];
        return;
    }

    if (childPid == 0) {
        execve(processArgv[0], processArgv, processEnvironment);
        _exit(127);
    }

    CBFreeCStringArray(processArgv);
    CBFreeCStringArray(processEnvironment);

    fcntl(masterFileDescriptor, F_SETFL, fcntl(masterFileDescriptor, F_GETFL, 0) | O_NONBLOCK);
    self.masterFileDescriptor = masterFileDescriptor;
    self.childProcessIdentifier = childPid;
    self.stoppingChildProcess = NO;
    [self startReadingFromPty:masterFileDescriptor];
}

- (char **)createProcessArgvWithExecutablePath:(NSString *)executablePath arguments:(NSArray<NSString *> *)arguments
{
    NSMutableArray<NSString *> *processArguments = [NSMutableArray arrayWithObject:executablePath];
    [processArguments addObjectsFromArray:arguments];
    return CBCStringArrayFromStrings(processArguments);
}

- (NSString *)bundledCbonsaiPath
{
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"cbonsai" withExtension:nil];
    return url.path ?: @"";
}

- (char **)createProcessEnvironment
{
    NSMutableArray<NSString *> *environment = [NSMutableArray arrayWithObjects:
        [@"PATH=" stringByAppendingString:CBDefaultEnvironmentPath()],
        @"TERM=xterm-256color",
        @"LANG=en_US.UTF-8",
        @"LC_ALL=en_US.UTF-8",
        nil];

    return CBCStringArrayFromStrings(environment);
}

- (void)startReadingFromPty:(int)fileDescriptor
{
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fileDescriptor, 0, self.readQueue);
    self.readSource = source;

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        char buffer[4096];
        NSMutableData *availableData = nil;
        BOOL shouldHandleExit = NO;
        while (YES) {
            ssize_t byteCount = read(fileDescriptor, buffer, sizeof(buffer));
            if (byteCount > 0) {
                if (availableData == nil) {
                    availableData = [NSMutableData dataWithCapacity:(NSUInteger)byteCount];
                }
                [availableData appendBytes:buffer length:(NSUInteger)byteCount];
            } else if (byteCount == 0) {
                shouldHandleExit = YES;
                break;
            } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
                break;
            } else {
                shouldHandleExit = YES;
                break;
            }
        }

        if (availableData.length > 0) {
            NSData *data = availableData;
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf enqueueTerminalData:data];
            });
        }

        if (shouldHandleExit) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf handleChildProcessExit];
            });
        }
    });

    dispatch_source_set_cancel_handler(source, ^{
        close(fileDescriptor);
    });

    dispatch_resume(source);
}

- (void)enqueueTerminalData:(NSData *)data
{
    if (data.length == 0) {
        return;
    }

    if (self.pendingTerminalData == nil) {
        self.pendingTerminalData = [NSMutableData data];
    }
    [self.pendingTerminalData appendData:data];

    if (self.terminalDataFlushScheduled) {
        return;
    }

    self.terminalDataFlushScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CBTerminalDataFlushInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self flushPendingTerminalDataAndDisplay];
    });
}

- (void)flushPendingTerminalDataAndDisplay
{
    self.terminalDataFlushScheduled = NO;
    if (self.pendingTerminalData.length == 0 || self.terminalBuffer == nil) {
        return;
    }

    NSMutableData *data = self.pendingTerminalData;
    self.pendingTerminalData = [NSMutableData dataWithCapacity:data.length];
    [self.terminalBuffer appendData:data];
    [self setNeedsDisplay:YES];
}

- (void)handleChildProcessExit
{
    [self flushPendingTerminalDataAndDisplay];

    if (self.readSource != nil) {
        dispatch_source_cancel(self.readSource);
        self.readSource = nil;
    }
    self.masterFileDescriptor = -1;

    pid_t childPid = self.childProcessIdentifier;
    self.childProcessIdentifier = -1;
    if (childPid > 0) {
        int status = 0;
        waitpid(childPid, &status, WNOHANG);
    }

    if (!self.stoppingChildProcess) {
        [self.terminalBuffer showStatusMessage:@"cbonsai exited."];
        [self setNeedsDisplay:YES];
    }
}

- (void)stopCbonsaiProcess
{
    self.stoppingChildProcess = YES;
    self.terminalDataFlushScheduled = NO;
    [self.pendingTerminalData setLength:0];

    pid_t childPid = self.childProcessIdentifier;
    self.childProcessIdentifier = -1;
    if (childPid > 0) {
        kill(childPid, SIGTERM);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            int status = 0;
            pid_t result = waitpid(childPid, &status, WNOHANG);
            if (result == 0) {
                kill(childPid, SIGKILL);
                waitpid(childPid, &status, 0);
            }
        });
    }

    if (self.readSource != nil) {
        dispatch_source_cancel(self.readSource);
        self.readSource = nil;
    } else if (self.masterFileDescriptor >= 0) {
        close(self.masterFileDescriptor);
    }
    self.masterFileDescriptor = -1;
}

- (void)drawBackgroundsForRow:(NSUInteger)row originX:(CGFloat)originX originY:(CGFloat)originY
{
    const CBTerminalCell *cells = [self.terminalBuffer cellsForRow:row];
    if (cells == NULL) {
        return;
    }

    NSUInteger column = 0;
    while (column < self.terminalBuffer.columns) {
        CBTerminalCell cell = cells[column];
        NSInteger backgroundColor = cell.backgroundColor;
        NSUInteger startColumn = column;
        column++;
        while (column < self.terminalBuffer.columns) {
            CBTerminalCell nextCell = cells[column];
            if (nextCell.backgroundColor != backgroundColor) {
                break;
            }
            column++;
        }

        if (backgroundColor >= 0) {
            [CBColorForANSIIndex(backgroundColor) setFill];
            NSRectFill(NSMakeRect(originX + (CGFloat)startColumn * self.cellWidth,
                                  originY + (CGFloat)row * self.cellHeight,
                                  (CGFloat)(column - startColumn) * self.cellWidth,
                                  self.cellHeight));
        }
    }
}

- (void)drawTextForRow:(NSUInteger)row originX:(CGFloat)originX originY:(CGFloat)originY
{
    const CBTerminalCell *cells = [self.terminalBuffer cellsForRow:row];
    if (cells == NULL) {
        return;
    }

    NSUInteger column = 0;
    while (column < self.terminalBuffer.columns) {
        CBTerminalCell cell = cells[column];
        if (cell.character == ' ') {
            column++;
            continue;
        }

        NSInteger foregroundColor = cell.foregroundColor;
        BOOL bold = cell.bold;
        NSUInteger startColumn = column;
        unichar characters[CBMaximumTerminalColumns];
        NSUInteger length = 0;
        NSUInteger drawableLength = 0;

        while (column < self.terminalBuffer.columns) {
            CBTerminalCell nextCell = cells[column];
            if (nextCell.foregroundColor != foregroundColor || nextCell.bold != bold) {
                break;
            }
            characters[length] = nextCell.character;
            length++;
            if (nextCell.character != ' ') {
                drawableLength = length;
            }
            column++;
        }

        if (drawableLength == 0) {
            continue;
        }

        NSString *text = [[NSString alloc] initWithCharacters:characters length:drawableLength];
        NSDictionary<NSAttributedStringKey, id> *attributes = [self textAttributesForForegroundColor:foregroundColor bold:bold];
        [text drawAtPoint:NSMakePoint(originX + (CGFloat)startColumn * self.cellWidth,
                                      originY + (CGFloat)row * self.cellHeight)
           withAttributes:attributes];
    }
}

- (NSDictionary<NSAttributedStringKey, id> *)textAttributesForForegroundColor:(NSInteger)foregroundColor bold:(BOOL)bold
{
    NSInteger effectiveColor = (bold && foregroundColor >= 0 && foregroundColor <= 7) ? foregroundColor + 8 : foregroundColor;
    NSNumber *cacheKey = @(effectiveColor);
    NSDictionary<NSAttributedStringKey, id> *attributes = self.terminalTextAttributesCache[cacheKey];
    if (attributes != nil) {
        return attributes;
    }

    if (self.terminalTextAttributesCache == nil) {
        self.terminalTextAttributesCache = [NSMutableDictionary dictionary];
    }

    attributes = @{
        NSFontAttributeName: self.terminalFont,
        NSForegroundColorAttributeName: CBColorForANSIIndex(effectiveColor),
    };
    self.terminalTextAttributesCache[cacheKey] = attributes;
    return attributes;
}

- (void)buildConfigurationContent
{
    NSView *contentView = self.configurationSheet.contentView;

    NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(20, 66, CBConfigurationSheetWidth - 40, CBConfigurationSheetHeight - 88)];
    [contentView addSubview:tabView];

    NSTabViewItem *settingsTab = [[NSTabViewItem alloc] initWithIdentifier:@"settings"];
    settingsTab.label = @"Settings";
    NSView *settingsView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(tabView.frame), NSHeight(tabView.frame))];
    settingsTab.view = settingsView;
    [tabView addTabViewItem:settingsTab];

    NSTabViewItem *advancedTab = [[NSTabViewItem alloc] initWithIdentifier:@"advanced"];
    advancedTab.label = @"Advanced";
    CBFlippedView *advancedView = [[CBFlippedView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(tabView.frame), NSHeight(tabView.frame))];
    advancedTab.view = advancedView;
    [tabView addTabViewItem:advancedTab];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:settingsView.bounds];
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [settingsView addSubview:scrollView];

    CGFloat documentWidth = NSWidth(scrollView.frame) - 18.0;
    CBFlippedView *documentView = [[CBFlippedView alloc] initWithFrame:NSMakeRect(0, 0, documentWidth, 500)];
    scrollView.documentView = documentView;

    CGFloat y = 18.0;
    CGFloat labelX = 20.0;
    CGFloat fieldX = 310.0;
    CGFloat helpButtonX = documentWidth - labelX - CBHelpButtonSize;
    CGFloat fieldWidth = helpButtonX - fieldX - CBHelpButtonGap;
    CGFloat compactHelpX = fieldX + 118.0;

    y = [self addSectionTitle:@"Timing" toView:documentView y:y];
    NSTextField *timeLabel = [self addLabel:@"Tree growth interval (seconds)" toView:documentView frame:NSMakeRect(labelX, y, 280, 24)];
    self.timeField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    self.timeStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:0.01 max:60.0 increment:0.01];
    [self setToolTip:@"Delay between growth steps." forViews:@[timeLabel, self.timeField, self.timeStepper]];
    [self addHelpButtonForAnchor:@"time" toView:documentView frame:NSMakeRect(compactHelpX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *waitLabel = [self addLabel:@"Growth restart wait time (seconds)" toView:documentView frame:NSMakeRect(labelX, y, 280, 24)];
    self.waitField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    self.waitStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:0.01 max:600.0 increment:0.25];
    [self setToolTip:@"Delay before restarting growth." forViews:@[waitLabel, self.waitField, self.waitStepper]];
    [self addHelpButtonForAnchor:@"wait" toView:documentView frame:NSMakeRect(compactHelpX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 48.0;

    y = [self addSectionTitle:@"Tree" toView:documentView y:y];
    NSTextField *messageLabel = [self addLabel:@"Message" toView:documentView frame:NSMakeRect(labelX, y, 160, 24)];
    self.messageField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, fieldWidth, 24)];
    [self setToolTip:@"Text rendered with the tree." forViews:@[messageLabel, self.messageField]];
    [self addHelpButtonForAnchor:@"message" toView:documentView frame:NSMakeRect(helpButtonX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *baseLabel = [self addLabel:@"Pot style" toView:documentView frame:NSMakeRect(labelX, y, 280, 24)];
    self.basePopUpButton = [self addPopUpButtonToView:documentView frame:NSMakeRect(fieldX, y - 3, 180, 26)];
    [self addPotStyleItemsToPopUpButton:self.basePopUpButton];
    [self setToolTip:@"Choose style 1, style 2, or no pot." forViews:@[baseLabel, self.basePopUpButton]];
    [self addHelpButtonForAnchor:@"base" toView:documentView frame:NSMakeRect(fieldX + 188.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *leafLabel = [self addLabel:@"Leaf character" toView:documentView frame:NSMakeRect(labelX, y, 280, 24)];
    self.leafField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, fieldWidth, 24)];
    [self setToolTip:@"Character used for leaves." forViews:@[leafLabel, self.leafField]];
    [self addHelpButtonForAnchor:@"leaf" toView:documentView frame:NSMakeRect(helpButtonX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *colorLabel = [self addLabel:@"Tree colour" toView:documentView frame:NSMakeRect(labelX, y + 22, 280, 24)];
    CGFloat colorGap = 12.0;
    CGFloat colorColumnWidth = floor((fieldWidth - colorGap) / 2.0);
    CGFloat colorSecondColumnX = fieldX + colorColumnWidth + colorGap;
    NSTextField *darkLeafColorLabel = [self addCaptionLabel:@"Dark leaves" toView:documentView frame:NSMakeRect(fieldX, y, colorColumnWidth, 16)];
    self.darkLeafColorPopUpButton = [self addPopUpButtonToView:documentView frame:NSMakeRect(fieldX, y + 16, colorColumnWidth, 26)];
    NSTextField *darkWoodColorLabel = [self addCaptionLabel:@"Dark wood" toView:documentView frame:NSMakeRect(colorSecondColumnX, y, colorColumnWidth, 16)];
    self.darkWoodColorPopUpButton = [self addPopUpButtonToView:documentView frame:NSMakeRect(colorSecondColumnX, y + 16, colorColumnWidth, 26)];
    NSTextField *lightLeafColorLabel = [self addCaptionLabel:@"Light leaves" toView:documentView frame:NSMakeRect(fieldX, y + 46, colorColumnWidth, 16)];
    self.lightLeafColorPopUpButton = [self addPopUpButtonToView:documentView frame:NSMakeRect(fieldX, y + 62, colorColumnWidth, 26)];
    NSTextField *lightWoodColorLabel = [self addCaptionLabel:@"Light wood" toView:documentView frame:NSMakeRect(colorSecondColumnX, y + 46, colorColumnWidth, 16)];
    self.lightWoodColorPopUpButton = [self addPopUpButtonToView:documentView frame:NSMakeRect(colorSecondColumnX, y + 62, colorColumnWidth, 26)];
    for (NSPopUpButton *button in @[self.darkLeafColorPopUpButton, self.darkWoodColorPopUpButton, self.lightLeafColorPopUpButton, self.lightWoodColorPopUpButton]) {
        [self addANSIColorItemsToPopUpButton:button];
    }
    [self setToolTip:@"Choose fixed ANSI colours." forViews:@[
        colorLabel,
        darkLeafColorLabel,
        self.darkLeafColorPopUpButton,
        darkWoodColorLabel,
        self.darkWoodColorPopUpButton,
        lightLeafColorLabel,
        self.lightLeafColorPopUpButton,
        lightWoodColorLabel,
        self.lightWoodColorPopUpButton,
    ]];
    [self addHelpButtonForAnchor:@"color" toView:documentView frame:NSMakeRect(helpButtonX, y + 34, CBHelpButtonSize, CBHelpButtonSize)];
    y += 98.0;

    NSTextField *multiplierLabel = [self addLabel:@"Tree density" toView:documentView frame:NSMakeRect(labelX, y, 280, 24)];
    self.multiplierField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    self.multiplierStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:1.0 max:20.0 increment:1.0];
    [self setToolTip:@"Branch density." forViews:@[multiplierLabel, self.multiplierField, self.multiplierStepper]];
    [self addHelpButtonForAnchor:@"multiplier" toView:documentView frame:NSMakeRect(compactHelpX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *lifeLabel = [self addLabel:@"Branch lifetime duration (steps)" toView:documentView frame:NSMakeRect(labelX, y, 280, 24)];
    self.lifeField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    self.lifeStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:1.0 max:200.0 increment:1.0];
    [self setToolTip:@"How long branches keep growing." forViews:@[lifeLabel, self.lifeField, self.lifeStepper]];
    [self addHelpButtonForAnchor:@"life" toView:documentView frame:NSMakeRect(compactHelpX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    CGFloat advancedY = 24.0;
    self.seedEnabledButton = [self addCheckbox:@"Seed" toView:advancedView frame:NSMakeRect(labelX, advancedY - 2, 160, 24)];
    self.seedField = [self addTextFieldToView:advancedView frame:NSMakeRect(fieldX, advancedY - 2, 120, 24)];
    [self setToolTip:@"Fixed random seed." forViews:@[self.seedEnabledButton, self.seedField]];
    [self addHelpButtonForAnchor:@"seed" toView:advancedView frame:NSMakeRect(fieldX + 128.0, advancedY, CBHelpButtonSize, CBHelpButtonSize)];
    advancedY += 34.0;

    self.verboseButton = [self addCheckbox:@"Verbose" toView:advancedView frame:NSMakeRect(labelX, advancedY - 2, 180, 24)];
    [self setToolTip:@"Print extra output." forViews:@[self.verboseButton]];
    [self addHelpButtonForAnchor:@"verbose" toView:advancedView frame:NSMakeRect(labelX + 184.0, advancedY, CBHelpButtonSize, CBHelpButtonSize)];

    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(CBConfigurationSheetWidth - 220, 18, 90, 30)];
    cancelButton.title = @"Cancel";
    cancelButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.target = self;
    cancelButton.action = @selector(cancelConfiguration:);
    [contentView addSubview:cancelButton];

    NSButton *okButton = [[NSButton alloc] initWithFrame:NSMakeRect(CBConfigurationSheetWidth - 120, 18, 90, 30)];
    okButton.title = @"OK";
    okButton.bezelStyle = NSBezelStyleRounded;
    okButton.keyEquivalent = @"\r";
    okButton.target = self;
    okButton.action = @selector(saveConfiguration:);
    [contentView addSubview:okButton];
}

- (CGFloat)addSectionTitle:(NSString *)title toView:(NSView *)view y:(CGFloat)y
{
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:13.0];
    label.frame = NSMakeRect(20, y, NSWidth(view.bounds) - 40, 20);
    [view addSubview:label];
    return y + 28.0;
}

- (NSTextField *)addLabel:(NSString *)title toView:(NSView *)view frame:(NSRect)frame
{
    NSTextField *label = [NSTextField labelWithString:title];
    label.frame = frame;
    [view addSubview:label];
    return label;
}

- (NSTextField *)addCaptionLabel:(NSString *)title toView:(NSView *)view frame:(NSRect)frame
{
    NSTextField *label = [self addLabel:title toView:view frame:frame];
    label.font = [NSFont systemFontOfSize:11.0];
    label.textColor = NSColor.secondaryLabelColor;
    return label;
}

- (NSTextField *)addTextFieldToView:(NSView *)view frame:(NSRect)frame
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    [view addSubview:field];
    return field;
}

- (NSButton *)addCheckbox:(NSString *)title toView:(NSView *)view frame:(NSRect)frame
{
    NSButton *button = [NSButton checkboxWithTitle:title target:self action:@selector(optionCheckboxChanged:)];
    button.frame = frame;
    [view addSubview:button];
    return button;
}

- (NSPopUpButton *)addPopUpButtonToView:(NSView *)view frame:(NSRect)frame
{
    NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
    [view addSubview:button];
    return button;
}

- (NSButton *)addHelpButtonForAnchor:(NSString *)anchor toView:(NSView *)view frame:(NSRect)frame
{
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(openManualSection:)];
    button.frame = frame;
    button.bezelStyle = NSBezelStyleHelpButton;
    button.identifier = anchor;
    button.toolTip = @"Open manual.";
    [view addSubview:button];
    return button;
}

- (void)setToolTip:(NSString *)toolTip forViews:(NSArray<NSView *> *)views
{
    for (NSView *view in views) {
        view.toolTip = toolTip;
    }
}

- (NSStepper *)addStepperToView:(NSView *)view frame:(NSRect)frame min:(double)minimum max:(double)maximum increment:(double)increment
{
    NSStepper *stepper = [[NSStepper alloc] initWithFrame:frame];
    stepper.minValue = minimum;
    stepper.maxValue = maximum;
    stepper.increment = increment;
    stepper.target = self;
    stepper.action = @selector(optionStepperChanged:);
    [view addSubview:stepper];
    return stepper;
}

- (void)addPotStyleItemsToPopUpButton:(NSPopUpButton *)button
{
    [button removeAllItems];
    [button addItemWithTitle:@"style 1"];
    button.lastItem.tag = 1;
    [button addItemWithTitle:@"style 2"];
    button.lastItem.tag = 2;
    [button addItemWithTitle:@"no pot"];
    button.lastItem.tag = 0;
}

- (void)addANSIColorItemsToPopUpButton:(NSPopUpButton *)button
{
    [button removeAllItems];
    for (NSNumber *index in CBNamedANSIColorIndexes()) {
        [self addANSIColorIndex:index.integerValue toPopUpButton:button];
    }
}

- (void)addANSIColorIndex:(NSInteger)index toPopUpButton:(NSPopUpButton *)button
{
    [button addItemWithTitle:CBANSIColorNameForIndex(index)];
    NSMenuItem *item = button.lastItem;
    item.tag = index;
    item.image = [self swatchImageForANSIColorIndex:index];
}

- (NSImage *)swatchImageForANSIColorIndex:(NSInteger)index
{
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(14.0, 14.0)];
    [image lockFocus];
    NSRect rect = NSMakeRect(1.0, 1.0, 12.0, 12.0);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2.0 yRadius:2.0];
    [CBColorForANSIIndex(index) setFill];
    [path fill];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.35] setStroke];
    path.lineWidth = 1.0;
    [path stroke];
    [image unlockFocus];
    return image;
}

- (void)loadConfigurationFields
{
    NSDictionary<NSString *, id> *options = self.configuredCbonsaiOptions;

    [self setDoubleField:self.timeField stepper:self.timeStepper value:[self doubleOption:options key:CBCbonsaiTimeKey]];
    [self setDoubleField:self.waitField stepper:self.waitStepper value:[self doubleOption:options key:CBCbonsaiWaitKey]];
    self.messageField.stringValue = [self stringOption:options key:CBCbonsaiMessageKey];
    NSInteger baseStyle = [self boolOption:options key:CBCbonsaiBaseEnabledKey] ? [self integerOption:options key:CBCbonsaiBaseKey] : CBDefaultBaseStyle;
    [self selectPopUpButton:self.basePopUpButton tag:baseStyle fallbackTag:CBDefaultBaseStyle];
    self.leafField.stringValue = [self stringOption:options key:CBCbonsaiLeafKey];
    [self selectColorPopUpButtonsWithColorString:[self stringOption:options key:CBCbonsaiColorKey]];
    [self setIntegerField:self.multiplierField stepper:self.multiplierStepper value:[self integerOption:options key:CBCbonsaiMultiplierKey]];
    [self setIntegerField:self.lifeField stepper:self.lifeStepper value:[self integerOption:options key:CBCbonsaiLifeKey]];
    self.seedEnabledButton.state = [self boolOption:options key:CBCbonsaiSeedEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.seedField.stringValue = [NSString stringWithFormat:@"%ld", (long)[self integerOption:options key:CBCbonsaiSeedKey]];
    self.verboseButton.state = [self boolOption:options key:CBCbonsaiVerboseKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateOptionalFieldStates];
}

- (void)saveConfiguration:(id)sender
{
    double time = MIN(MAX(self.timeField.doubleValue, 0.01), 60.0);
    double wait = MIN(MAX(self.waitField.doubleValue, 0.01), 600.0);
    NSInteger multiplier = MIN(MAX(self.multiplierField.integerValue, 1), 20);
    NSInteger life = MIN(MAX(self.lifeField.integerValue, 1), 200);

    ScreenSaverDefaults *defaults = [self screenSaverDefaults];
    [defaults setDouble:time forKey:CBCbonsaiTimeKey];
    [defaults setDouble:wait forKey:CBCbonsaiWaitKey];
    [defaults setObject:[self trimmedStringFromField:self.messageField] forKey:CBCbonsaiMessageKey];
    [defaults setBool:YES forKey:CBCbonsaiBaseEnabledKey];
    [defaults setInteger:[self selectedTagForPopUpButton:self.basePopUpButton fallbackTag:CBDefaultBaseStyle] forKey:CBCbonsaiBaseKey];
    [defaults setObject:[self trimmedStringFromField:self.leafField] forKey:CBCbonsaiLeafKey];
    [defaults setObject:[self colorStringFromColorPopUpButtons] forKey:CBCbonsaiColorKey];
    [defaults setInteger:multiplier forKey:CBCbonsaiMultiplierKey];
    [defaults setInteger:life forKey:CBCbonsaiLifeKey];
    [defaults setBool:self.seedEnabledButton.state == NSControlStateValueOn forKey:CBCbonsaiSeedEnabledKey];
    [defaults setInteger:self.seedField.integerValue forKey:CBCbonsaiSeedKey];
    [defaults setBool:self.verboseButton.state == NSControlStateValueOn forKey:CBCbonsaiVerboseKey];
    [defaults synchronize];

    self.terminalFont = nil;
    [self stopCbonsaiProcess];
    [self updateTerminalGeometry];
    if (self.isAnimating) {
        [self startCbonsaiProcess];
    }

    [[NSApplication sharedApplication] endSheet:self.configurationSheet];
}

- (void)optionStepperChanged:(id)sender
{
    if (sender == self.timeStepper) {
        self.timeField.stringValue = [NSString stringWithFormat:@"%.2f", self.timeStepper.doubleValue];
    } else if (sender == self.waitStepper) {
        self.waitField.stringValue = [NSString stringWithFormat:@"%.2f", self.waitStepper.doubleValue];
    } else if (sender == self.multiplierStepper) {
        self.multiplierField.stringValue = [NSString stringWithFormat:@"%.0f", self.multiplierStepper.doubleValue];
    } else if (sender == self.lifeStepper) {
        self.lifeField.stringValue = [NSString stringWithFormat:@"%.0f", self.lifeStepper.doubleValue];
    }
}

- (void)optionCheckboxChanged:(id)sender
{
    [self updateOptionalFieldStates];
}

- (void)openManualSection:(NSButton *)sender
{
    NSString *anchor = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    NSURL *manualURL = [[NSBundle bundleForClass:self.class] URLForResource:CBManualResourceName withExtension:@"html"];
    if (anchor.length == 0 || manualURL == nil) {
        NSLog(@"cbonsai saver manual resource is missing or the requested section is empty.");
        NSBeep();
        return;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:manualURL resolvingAgainstBaseURL:NO];
    components.fragment = anchor;
    NSURL *sectionURL = components.URL ?: manualURL;
    if (![[NSWorkspace sharedWorkspace] openURL:sectionURL]) {
        NSBeep();
    }
}

- (void)updateOptionalFieldStates
{
    self.seedField.enabled = self.seedEnabledButton.state == NSControlStateValueOn;
}

- (BOOL)boolOption:(NSDictionary<NSString *, id> *)options key:(NSString *)key
{
    id value = options[key];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

- (NSInteger)integerOption:(NSDictionary<NSString *, id> *)options key:(NSString *)key
{
    id value = options[key];
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

- (double)doubleOption:(NSDictionary<NSString *, id> *)options key:(NSString *)key
{
    id value = options[key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
}

- (NSString *)stringOption:(NSDictionary<NSString *, id> *)options key:(NSString *)key
{
    id value = options[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

- (void)setDoubleField:(NSTextField *)field stepper:(NSStepper *)stepper value:(double)value
{
    field.stringValue = [NSString stringWithFormat:@"%.6g", value];
    stepper.doubleValue = value;
}

- (void)setIntegerField:(NSTextField *)field stepper:(NSStepper *)stepper value:(NSInteger)value
{
    field.stringValue = [NSString stringWithFormat:@"%ld", (long)value];
    stepper.integerValue = value;
}

- (NSString *)trimmedStringFromField:(NSTextField *)field
{
    return [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)selectPopUpButton:(NSPopUpButton *)button tag:(NSInteger)tag fallbackTag:(NSInteger)fallbackTag
{
    NSMenuItem *item = [button.menu itemWithTag:tag] ?: [button.menu itemWithTag:fallbackTag];
    if (item != nil) {
        [button selectItem:item];
    }
}

- (void)selectANSIColorIndex:(NSInteger)index forPopUpButton:(NSPopUpButton *)button fallbackIndex:(NSInteger)fallbackIndex
{
    if ([button.menu itemWithTag:index] == nil && index >= 0 && index <= 255) {
        [self addANSIColorIndex:index toPopUpButton:button];
    }
    [self selectPopUpButton:button tag:index fallbackTag:fallbackIndex];
}

- (void)selectColorPopUpButtonsWithColorString:(NSString *)colorString
{
    NSArray<NSNumber *> *indexes = CBTreeColorIndexesFromString(colorString);
    [self selectANSIColorIndex:indexes[0].integerValue forPopUpButton:self.darkLeafColorPopUpButton fallbackIndex:CBDefaultDarkLeafColor];
    [self selectANSIColorIndex:indexes[1].integerValue forPopUpButton:self.darkWoodColorPopUpButton fallbackIndex:CBDefaultDarkWoodColor];
    [self selectANSIColorIndex:indexes[2].integerValue forPopUpButton:self.lightLeafColorPopUpButton fallbackIndex:CBDefaultLightLeafColor];
    [self selectANSIColorIndex:indexes[3].integerValue forPopUpButton:self.lightWoodColorPopUpButton fallbackIndex:CBDefaultLightWoodColor];
}

- (NSInteger)selectedTagForPopUpButton:(NSPopUpButton *)button fallbackTag:(NSInteger)fallbackTag
{
    NSMenuItem *item = button.selectedItem;
    return item != nil ? item.tag : fallbackTag;
}

- (NSString *)colorStringFromColorPopUpButtons
{
    NSInteger darkLeaf = [self selectedTagForPopUpButton:self.darkLeafColorPopUpButton fallbackTag:CBDefaultDarkLeafColor];
    NSInteger darkWood = [self selectedTagForPopUpButton:self.darkWoodColorPopUpButton fallbackTag:CBDefaultDarkWoodColor];
    NSInteger lightLeaf = [self selectedTagForPopUpButton:self.lightLeafColorPopUpButton fallbackTag:CBDefaultLightLeafColor];
    NSInteger lightWood = [self selectedTagForPopUpButton:self.lightWoodColorPopUpButton fallbackTag:CBDefaultLightWoodColor];
    return [NSString stringWithFormat:@"%ld,%ld,%ld,%ld", (long)darkLeaf, (long)darkWood, (long)lightLeaf, (long)lightWood];
}

- (void)cancelConfiguration:(id)sender
{
    [[NSApplication sharedApplication] endSheet:self.configurationSheet];
}

@end
