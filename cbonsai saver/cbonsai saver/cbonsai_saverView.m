//
//  cbonsai_saverView.m
//  cbonsai saver
//
//  Created by Leonard Wang on 2025/6/11.
//

#import "cbonsai_saverView.h"
#import "CBCommandLine.h"

#import <dispatch/dispatch.h>
#import <errno.h>
#import <fcntl.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <sys/ioctl.h>
#import <sys/wait.h>
#import <unistd.h>
#import <util.h>

static NSString * const CBSettingsModuleName = @"wang.leonard.cbonsai-saver";
static NSString * const CBExecutablePathKey = @"executablePath";
static NSString * const CBFontSizeKey = @"fontSize";
static const CGFloat CBDefaultFontSize = 14.0;
static const NSInteger CBDefaultForegroundColor = 7;
static const NSInteger CBDefaultBackgroundColor = -1;
static const CGFloat CBConfigurationSheetWidth = 720.0;
static const CGFloat CBConfigurationSheetHeight = 620.0;
static NSString * const CBManualResourceName = @"cbonsai-manual";
static const CGFloat CBHelpButtonSize = 20.0;
static const CGFloat CBHelpButtonGap = 8.0;

typedef struct {
    unichar character;
    NSInteger foregroundColor;
    NSInteger backgroundColor;
    BOOL bold;
} CBTerminalCell;

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

static NSUInteger CBParameterAt(NSArray<NSNumber *> *parameters, NSUInteger index, NSUInteger defaultValue)
{
    if (index >= parameters.count) {
        return defaultValue;
    }
    return parameters[index].unsignedIntegerValue;
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
        if (component.length == 0) {
            [result addObject:@0];
        } else {
            [result addObject:@(component.integerValue)];
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
    } else {
        [_csiString appendFormat:@"%c", byte];
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
@property (nonatomic, strong) dispatch_queue_t readQueue;
@property (nonatomic, strong) dispatch_source_t readSource;
@property (nonatomic) CGFloat cellWidth;
@property (nonatomic) CGFloat cellHeight;
@property (nonatomic) int masterFileDescriptor;
@property (nonatomic) pid_t childProcessIdentifier;
@property (nonatomic) BOOL stoppingChildProcess;
@property (nonatomic, strong) NSWindow *configurationSheet;
@property (nonatomic, strong) NSTextField *executableField;
@property (nonatomic, strong) NSTextField *fontSizeField;
@property (nonatomic, strong) NSStepper *fontSizeStepper;
@property (nonatomic, strong) NSButton *screensaverButton;
@property (nonatomic, strong) NSButton *liveButton;
@property (nonatomic, strong) NSButton *infiniteButton;
@property (nonatomic, strong) NSTextField *timeField;
@property (nonatomic, strong) NSStepper *timeStepper;
@property (nonatomic, strong) NSTextField *waitField;
@property (nonatomic, strong) NSStepper *waitStepper;
@property (nonatomic, strong) NSTextField *messageField;
@property (nonatomic, strong) NSButton *baseEnabledButton;
@property (nonatomic, strong) NSTextField *baseField;
@property (nonatomic, strong) NSTextField *leafField;
@property (nonatomic, strong) NSTextField *colorField;
@property (nonatomic, strong) NSTextField *multiplierField;
@property (nonatomic, strong) NSStepper *multiplierStepper;
@property (nonatomic, strong) NSTextField *lifeField;
@property (nonatomic, strong) NSStepper *lifeStepper;
@property (nonatomic, strong) NSButton *printButton;
@property (nonatomic, strong) NSButton *seedEnabledButton;
@property (nonatomic, strong) NSTextField *seedField;
@property (nonatomic, strong) NSButton *saveEnabledButton;
@property (nonatomic, strong) NSTextField *savePathField;
@property (nonatomic, strong) NSButton *loadEnabledButton;
@property (nonatomic, strong) NSTextField *loadPathField;
@property (nonatomic, strong) NSButton *verboseButton;
@property (nonatomic, strong) NSButton *helpButton;

@end

@implementation cbonsai_saverView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        _masterFileDescriptor = -1;
        _childProcessIdentifier = -1;
        _readQueue = dispatch_queue_create("wang.leonard.cbonsai-saver.pty", DISPATCH_QUEUE_SERIAL);
        [self setAnimationTimeInterval:1.0 / 30.0];
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

    [self updateTerminalGeometry];
    if (self.terminalBuffer == nil || self.cellWidth <= 0.0 || self.cellHeight <= 0.0) {
        return;
    }

    CGFloat terminalWidth = (CGFloat)self.terminalBuffer.columns * self.cellWidth;
    CGFloat terminalHeight = (CGFloat)self.terminalBuffer.rows * self.cellHeight;
    CGFloat originX = floor((NSWidth(self.bounds) - terminalWidth) / 2.0);
    CGFloat originY = floor((NSHeight(self.bounds) - terminalHeight) / 2.0);

    for (NSUInteger row = 0; row < self.terminalBuffer.rows; row++) {
        [self drawBackgroundsForRow:row originX:originX originY:originY];
        [self drawTextForRow:row originX:originX originY:originY];
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
    NSMutableDictionary<NSString *, id> *registeredDefaults = [@{
        CBExecutablePathKey: CBDefaultExecutablePath(),
        CBFontSizeKey: @(CBDefaultFontSize),
    } mutableCopy];
    [registeredDefaults addEntriesFromDictionary:CBDefaultCbonsaiOptions()];
    [defaults registerDefaults:registeredDefaults];
    return defaults;
}

- (void)registerDefaultSettings
{
    (void)[self screenSaverDefaults];
}

- (NSString *)configuredExecutablePath
{
    NSString *path = [[self screenSaverDefaults] stringForKey:CBExecutablePathKey];
    return (path.length > 0) ? path : CBDefaultExecutablePath();
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

- (CGFloat)configuredFontSize
{
    CGFloat fontSize = [[self screenSaverDefaults] doubleForKey:CBFontSizeKey];
    if (fontSize < 8.0 || fontSize > 48.0) {
        return CBDefaultFontSize;
    }
    return fontSize;
}

- (void)updateTerminalGeometry
{
    CGFloat fontSize = [self configuredFontSize];
    if (self.terminalFont == nil || fabs(self.terminalFont.pointSize - fontSize) > 0.1) {
        self.terminalFont = [NSFont userFixedPitchFontOfSize:fontSize];
        if (self.terminalFont == nil) {
            self.terminalFont = [NSFont monospacedSystemFontOfSize:fontSize weight:NSFontWeightRegular];
        }
        NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName: self.terminalFont};
        self.cellWidth = ceil([@"W" sizeWithAttributes:attributes].width);
        self.cellHeight = ceil(self.terminalFont.ascender - self.terminalFont.descender + self.terminalFont.leading);
    }

    if (self.cellWidth <= 0.0 || self.cellHeight <= 0.0 || NSWidth(self.bounds) <= 0.0 || NSHeight(self.bounds) <= 0.0) {
        return;
    }

    NSUInteger columns = MAX((NSUInteger)1, (NSUInteger)floor(NSWidth(self.bounds) / self.cellWidth));
    NSUInteger rows = MAX((NSUInteger)1, (NSUInteger)floor(NSHeight(self.bounds) / self.cellHeight));

    if (self.terminalBuffer == nil) {
        self.terminalBuffer = [[CBTerminalBuffer alloc] initWithColumns:columns rows:rows];
    } else {
        [self.terminalBuffer resizeToColumns:columns rows:rows];
    }

    [self updatePtyWindowSize];
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
    size.ws_xpixel = (unsigned short)NSWidth(self.bounds);
    size.ws_ypixel = (unsigned short)NSHeight(self.bounds);
    ioctl(self.masterFileDescriptor, TIOCSWINSZ, &size);
}

- (void)startCbonsaiProcess
{
    if (self.childProcessIdentifier > 0 || self.terminalBuffer == nil) {
        return;
    }

    NSString *executablePath = [self.configuredExecutablePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (executablePath.length == 0) {
        [self.terminalBuffer showStatusMessage:@"cbonsai executable path is empty."];
        [self setNeedsDisplay:YES];
        return;
    }

    NSArray<NSString *> *arguments = CBCbonsaiArgumentsFromOptions(self.configuredCbonsaiOptions);

    char **shellArgv = [self createShellArgvWithArguments:arguments];
    char **shellEnvironment = [self createShellEnvironmentWithExecutablePath:executablePath];
    if (shellArgv == NULL || shellEnvironment == NULL) {
        CBFreeCStringArray(shellArgv);
        CBFreeCStringArray(shellEnvironment);
        [self.terminalBuffer showStatusMessage:@"Unable to allocate cbonsai launch arguments."];
        [self setNeedsDisplay:YES];
        return;
    }

    int masterFileDescriptor = -1;
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_col = (unsigned short)self.terminalBuffer.columns;
    size.ws_row = (unsigned short)self.terminalBuffer.rows;
    size.ws_xpixel = (unsigned short)NSWidth(self.bounds);
    size.ws_ypixel = (unsigned short)NSHeight(self.bounds);

    pid_t childPid = forkpty(&masterFileDescriptor, NULL, NULL, &size);
    if (childPid < 0) {
        CBFreeCStringArray(shellArgv);
        CBFreeCStringArray(shellEnvironment);
        [self.terminalBuffer showStatusMessage:[NSString stringWithFormat:@"forkpty failed: %s", strerror(errno)]];
        [self setNeedsDisplay:YES];
        return;
    }

    if (childPid == 0) {
        execve("/bin/sh", shellArgv, shellEnvironment);
        _exit(127);
    }

    CBFreeCStringArray(shellArgv);
    CBFreeCStringArray(shellEnvironment);

    fcntl(masterFileDescriptor, F_SETFL, fcntl(masterFileDescriptor, F_GETFL, 0) | O_NONBLOCK);
    self.masterFileDescriptor = masterFileDescriptor;
    self.childProcessIdentifier = childPid;
    self.stoppingChildProcess = NO;
    [self startReadingFromPty:masterFileDescriptor];
}

- (char **)createShellArgvWithArguments:(NSArray<NSString *> *)arguments
{
    NSMutableArray<NSString *> *shellArguments = [NSMutableArray arrayWithObjects:
        @"sh",
        @"-c",
        @"exec \"$CBONSAI_EXECUTABLE\" \"$@\"",
        @"cbonsai-saver",
        nil];
    [shellArguments addObjectsFromArray:arguments];
    return CBCStringArrayFromStrings(shellArguments);
}

- (char **)createShellEnvironmentWithExecutablePath:(NSString *)executablePath
{
    NSDictionary<NSString *, NSString *> *processEnvironment = NSProcessInfo.processInfo.environment;
    NSMutableArray<NSString *> *environment = [NSMutableArray arrayWithObjects:
        [@"CBONSAI_EXECUTABLE=" stringByAppendingString:executablePath],
        [@"PATH=" stringByAppendingString:CBDefaultEnvironmentPath()],
        @"TERM=xterm-256color",
        nil];

    NSString *language = processEnvironment[@"LANG"];
    [environment addObject:[@"LANG=" stringByAppendingString:(language.length > 0 ? language : @"en_US.UTF-8")]];

    for (NSString *key in @[@"HOME", @"USER", @"LOGNAME", @"TMPDIR", @"XDG_CACHE_HOME"]) {
        NSString *value = processEnvironment[key];
        if (value.length > 0) {
            [environment addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
        }
    }

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
        while (YES) {
            ssize_t byteCount = read(fileDescriptor, buffer, sizeof(buffer));
            if (byteCount > 0) {
                NSData *data = [NSData dataWithBytes:buffer length:(NSUInteger)byteCount];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf.terminalBuffer appendData:data];
                    [strongSelf setNeedsDisplay:YES];
                });
            } else if (byteCount == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf handleChildProcessExit];
                });
                break;
            } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
                break;
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf handleChildProcessExit];
                });
                break;
            }
        }
    });

    dispatch_source_set_cancel_handler(source, ^{
        close(fileDescriptor);
    });

    dispatch_resume(source);
}

- (void)handleChildProcessExit
{
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
        [self.terminalBuffer showStatusMessage:@"cbonsai exited. Use --screensaver or -li for continuous output."];
        [self setNeedsDisplay:YES];
    }
}

- (void)stopCbonsaiProcess
{
    self.stoppingChildProcess = YES;

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
    NSUInteger column = 0;
    while (column < self.terminalBuffer.columns) {
        CBTerminalCell cell = [self.terminalBuffer cellAtColumn:column row:row];
        NSInteger backgroundColor = cell.backgroundColor;
        NSUInteger startColumn = column;
        column++;
        while (column < self.terminalBuffer.columns) {
            CBTerminalCell nextCell = [self.terminalBuffer cellAtColumn:column row:row];
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
    NSUInteger column = 0;
    while (column < self.terminalBuffer.columns) {
        CBTerminalCell cell = [self.terminalBuffer cellAtColumn:column row:row];
        if (cell.character == ' ') {
            column++;
            continue;
        }

        NSInteger foregroundColor = cell.foregroundColor;
        BOOL bold = cell.bold;
        NSUInteger startColumn = column;
        NSMutableString *text = [NSMutableString string];

        while (column < self.terminalBuffer.columns) {
            CBTerminalCell nextCell = [self.terminalBuffer cellAtColumn:column row:row];
            if (nextCell.foregroundColor != foregroundColor || nextCell.bold != bold) {
                break;
            }
            [text appendFormat:@"%C", nextCell.character];
            column++;
        }

        NSInteger effectiveColor = (bold && foregroundColor >= 0 && foregroundColor <= 7) ? foregroundColor + 8 : foregroundColor;
        NSDictionary<NSAttributedStringKey, id> *attributes = @{
            NSFontAttributeName: self.terminalFont,
            NSForegroundColorAttributeName: CBColorForANSIIndex(effectiveColor),
        };
        [text drawAtPoint:NSMakePoint(originX + (CGFloat)startColumn * self.cellWidth,
                                      originY + (CGFloat)row * self.cellHeight)
           withAttributes:attributes];
    }
}

- (void)buildConfigurationContent
{
    NSView *contentView = self.configurationSheet.contentView;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 66, CBConfigurationSheetWidth - 40, CBConfigurationSheetHeight - 88)];
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    [contentView addSubview:scrollView];

    CGFloat documentWidth = NSWidth(scrollView.frame) - 18.0;
    CBFlippedView *documentView = [[CBFlippedView alloc] initWithFrame:NSMakeRect(0, 0, documentWidth, 790)];
    scrollView.documentView = documentView;

    CGFloat y = 18.0;
    CGFloat labelX = 20.0;
    CGFloat fieldX = 190.0;
    CGFloat helpButtonX = documentWidth - labelX - CBHelpButtonSize;
    CGFloat fieldWidth = helpButtonX - fieldX - CBHelpButtonGap;
    CGFloat compactHelpX = fieldX + 118.0;

    y = [self addSectionTitle:@"General" toView:documentView y:y];
    NSTextField *executableLabel = [self addLabel:@"Executable" toView:documentView frame:NSMakeRect(labelX, y, 150, 24)];
    self.executableField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, fieldWidth, 24)];
    [self setToolTip:@"Command used to launch cbonsai." forViews:@[executableLabel, self.executableField]];
    [self addHelpButtonForAnchor:@"executable" toView:documentView frame:NSMakeRect(helpButtonX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 38.0;

    NSTextField *fontSizeLabel = [self addLabel:@"Font size" toView:documentView frame:NSMakeRect(labelX, y, 150, 24)];
    self.fontSizeField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 72, 24)];
    self.fontSizeStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 80, y - 4, 20, 28) min:8.0 max:48.0 increment:1.0];
    [self setToolTip:@"Terminal font size." forViews:@[fontSizeLabel, self.fontSizeField, self.fontSizeStepper]];
    [self addHelpButtonForAnchor:@"font-size" toView:documentView frame:NSMakeRect(fieldX + 108.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 48.0;

    y = [self addSectionTitle:@"Mode" toView:documentView y:y];
    self.screensaverButton = [self addCheckbox:@"Screensaver (--screensaver)" toView:documentView frame:NSMakeRect(labelX, y - 2, 210, 24)];
    [self setToolTip:@"Continuously redraw trees." forViews:@[self.screensaverButton]];
    [self addHelpButtonForAnchor:@"screensaver" toView:documentView frame:NSMakeRect(labelX + 214.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    self.liveButton = [self addCheckbox:@"Live (--live)" toView:documentView frame:NSMakeRect(labelX + 260, y - 2, 116, 24)];
    [self setToolTip:@"Animate growth." forViews:@[self.liveButton]];
    [self addHelpButtonForAnchor:@"live" toView:documentView frame:NSMakeRect(labelX + 380.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    self.infiniteButton = [self addCheckbox:@"Infinite (--infinite)" toView:documentView frame:NSMakeRect(labelX + 420, y - 2, 152, 24)];
    [self setToolTip:@"Keep cbonsai running." forViews:@[self.infiniteButton]];
    [self addHelpButtonForAnchor:@"infinite" toView:documentView frame:NSMakeRect(labelX + 576.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 42.0;

    y = [self addSectionTitle:@"Timing" toView:documentView y:y];
    NSTextField *timeLabel = [self addLabel:@"Growth time (--time)" toView:documentView frame:NSMakeRect(labelX, y, 160, 24)];
    self.timeField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    self.timeStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:0.01 max:60.0 increment:0.01];
    [self setToolTip:@"Growth delay in seconds." forViews:@[timeLabel, self.timeField, self.timeStepper]];
    [self addHelpButtonForAnchor:@"time" toView:documentView frame:NSMakeRect(compactHelpX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *waitLabel = [self addLabel:@"Tree wait (--wait)" toView:documentView frame:NSMakeRect(labelX, y, 160, 24)];
    self.waitField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    self.waitStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:0.0 max:600.0 increment:0.25];
    [self setToolTip:@"Delay after each tree." forViews:@[waitLabel, self.waitField, self.waitStepper]];
    [self addHelpButtonForAnchor:@"wait" toView:documentView frame:NSMakeRect(compactHelpX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 48.0;

    y = [self addSectionTitle:@"Tree" toView:documentView y:y];
    NSTextField *messageLabel = [self addLabel:@"Message (--message)" toView:documentView frame:NSMakeRect(labelX, y, 160, 24)];
    self.messageField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, fieldWidth, 24)];
    [self setToolTip:@"Text rendered with the tree." forViews:@[messageLabel, self.messageField]];
    [self addHelpButtonForAnchor:@"message" toView:documentView frame:NSMakeRect(helpButtonX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    self.baseEnabledButton = [self addCheckbox:@"Base (--base)" toView:documentView frame:NSMakeRect(labelX, y - 2, 160, 24)];
    self.baseField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    [self setToolTip:@"Pass --base when enabled." forViews:@[self.baseEnabledButton, self.baseField]];
    [self addHelpButtonForAnchor:@"base" toView:documentView frame:NSMakeRect(fieldX + 90.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *leafLabel = [self addLabel:@"Leaves (--leaf)" toView:documentView frame:NSMakeRect(labelX, y, 160, 24)];
    self.leafField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, fieldWidth, 24)];
    [self setToolTip:@"Leaf character list." forViews:@[leafLabel, self.leafField]];
    [self addHelpButtonForAnchor:@"leaf" toView:documentView frame:NSMakeRect(helpButtonX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *colorLabel = [self addLabel:@"Colors (--color)" toView:documentView frame:NSMakeRect(labelX, y, 160, 24)];
    self.colorField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, fieldWidth, 24)];
    [self setToolTip:@"ANSI color list." forViews:@[colorLabel, self.colorField]];
    [self addHelpButtonForAnchor:@"color" toView:documentView frame:NSMakeRect(helpButtonX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *multiplierLabel = [self addLabel:@"Multiplier (--multiplier)" toView:documentView frame:NSMakeRect(labelX, y, 170, 24)];
    self.multiplierField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    self.multiplierStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:0.0 max:20.0 increment:1.0];
    [self setToolTip:@"Branch density." forViews:@[multiplierLabel, self.multiplierField, self.multiplierStepper]];
    [self addHelpButtonForAnchor:@"multiplier" toView:documentView frame:NSMakeRect(compactHelpX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    NSTextField *lifeLabel = [self addLabel:@"Life (--life)" toView:documentView frame:NSMakeRect(labelX, y, 160, 24)];
    self.lifeField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 82, 24)];
    self.lifeStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:0.0 max:200.0 increment:1.0];
    [self setToolTip:@"Branch lifetime." forViews:@[lifeLabel, self.lifeField, self.lifeStepper]];
    [self addHelpButtonForAnchor:@"life" toView:documentView frame:NSMakeRect(compactHelpX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 48.0;

    y = [self addSectionTitle:@"Output" toView:documentView y:y];
    self.printButton = [self addCheckbox:@"Print when finished (--print)" toView:documentView frame:NSMakeRect(labelX, y - 2, 222, 24)];
    [self setToolTip:@"Print final tree." forViews:@[self.printButton]];
    [self addHelpButtonForAnchor:@"print" toView:documentView frame:NSMakeRect(labelX + 226.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    self.verboseButton = [self addCheckbox:@"Verbose (--verbose)" toView:documentView frame:NSMakeRect(labelX + 280, y - 2, 146, 24)];
    [self setToolTip:@"Print extra output." forViews:@[self.verboseButton]];
    [self addHelpButtonForAnchor:@"verbose" toView:documentView frame:NSMakeRect(labelX + 430.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    self.helpButton = [self addCheckbox:@"Show help (--help)" toView:documentView frame:NSMakeRect(labelX + 470, y - 2, 130, 24)];
    [self setToolTip:@"Show cbonsai help and exit." forViews:@[self.helpButton]];
    [self addHelpButtonForAnchor:@"help" toView:documentView frame:NSMakeRect(labelX + 604.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    self.seedEnabledButton = [self addCheckbox:@"Seed (--seed)" toView:documentView frame:NSMakeRect(labelX, y - 2, 160, 24)];
    self.seedField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, 120, 24)];
    [self setToolTip:@"Fixed random seed." forViews:@[self.seedEnabledButton, self.seedField]];
    [self addHelpButtonForAnchor:@"seed" toView:documentView frame:NSMakeRect(fieldX + 128.0, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    self.saveEnabledButton = [self addCheckbox:@"Save file (--save)" toView:documentView frame:NSMakeRect(labelX, y - 2, 170, 24)];
    self.savePathField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, fieldWidth, 24)];
    [self setToolTip:@"Save tree state file." forViews:@[self.saveEnabledButton, self.savePathField]];
    [self addHelpButtonForAnchor:@"save" toView:documentView frame:NSMakeRect(helpButtonX, y, CBHelpButtonSize, CBHelpButtonSize)];
    y += 34.0;

    self.loadEnabledButton = [self addCheckbox:@"Load file (--load)" toView:documentView frame:NSMakeRect(labelX, y - 2, 170, 24)];
    self.loadPathField = [self addTextFieldToView:documentView frame:NSMakeRect(fieldX, y - 2, fieldWidth, 24)];
    [self setToolTip:@"Load tree state file." forViews:@[self.loadEnabledButton, self.loadPathField]];
    [self addHelpButtonForAnchor:@"load" toView:documentView frame:NSMakeRect(helpButtonX, y, CBHelpButtonSize, CBHelpButtonSize)];

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

- (void)loadConfigurationFields
{
    NSDictionary<NSString *, id> *options = self.configuredCbonsaiOptions;
    self.executableField.stringValue = self.configuredExecutablePath;
    self.fontSizeField.stringValue = [NSString stringWithFormat:@"%.0f", self.configuredFontSize];
    self.fontSizeStepper.doubleValue = self.configuredFontSize;

    self.screensaverButton.state = [self boolOption:options key:CBCbonsaiScreensaverKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.liveButton.state = [self boolOption:options key:CBCbonsaiLiveKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infiniteButton.state = [self boolOption:options key:CBCbonsaiInfiniteKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [self setDoubleField:self.timeField stepper:self.timeStepper value:[self doubleOption:options key:CBCbonsaiTimeKey]];
    [self setDoubleField:self.waitField stepper:self.waitStepper value:[self doubleOption:options key:CBCbonsaiWaitKey]];
    self.messageField.stringValue = [self stringOption:options key:CBCbonsaiMessageKey];
    self.baseEnabledButton.state = [self boolOption:options key:CBCbonsaiBaseEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.baseField.stringValue = [NSString stringWithFormat:@"%ld", (long)[self integerOption:options key:CBCbonsaiBaseKey]];
    self.leafField.stringValue = [self stringOption:options key:CBCbonsaiLeafKey];
    self.colorField.stringValue = [self stringOption:options key:CBCbonsaiColorKey];
    [self setIntegerField:self.multiplierField stepper:self.multiplierStepper value:[self integerOption:options key:CBCbonsaiMultiplierKey]];
    [self setIntegerField:self.lifeField stepper:self.lifeStepper value:[self integerOption:options key:CBCbonsaiLifeKey]];
    self.printButton.state = [self boolOption:options key:CBCbonsaiPrintKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.seedEnabledButton.state = [self boolOption:options key:CBCbonsaiSeedEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.seedField.stringValue = [NSString stringWithFormat:@"%ld", (long)[self integerOption:options key:CBCbonsaiSeedKey]];
    self.saveEnabledButton.state = [self boolOption:options key:CBCbonsaiSaveEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.savePathField.stringValue = [self stringOption:options key:CBCbonsaiSavePathKey];
    self.loadEnabledButton.state = [self boolOption:options key:CBCbonsaiLoadEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.loadPathField.stringValue = [self stringOption:options key:CBCbonsaiLoadPathKey];
    self.verboseButton.state = [self boolOption:options key:CBCbonsaiVerboseKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.helpButton.state = [self boolOption:options key:CBCbonsaiHelpKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateOptionalFieldStates];
}

- (void)saveConfiguration:(id)sender
{
    CGFloat fontSize = self.fontSizeField.doubleValue;
    fontSize = MIN(MAX(fontSize, 8.0), 48.0);
    double time = MAX(self.timeField.doubleValue, 0.01);
    double wait = MAX(self.waitField.doubleValue, 0.0);
    NSInteger multiplier = MIN(MAX(self.multiplierField.integerValue, 0), 20);
    NSInteger life = MIN(MAX(self.lifeField.integerValue, 0), 200);

    ScreenSaverDefaults *defaults = [self screenSaverDefaults];
    [defaults setObject:self.executableField.stringValue forKey:CBExecutablePathKey];
    [defaults setDouble:fontSize forKey:CBFontSizeKey];
    [defaults setBool:self.screensaverButton.state == NSControlStateValueOn forKey:CBCbonsaiScreensaverKey];
    [defaults setBool:self.liveButton.state == NSControlStateValueOn forKey:CBCbonsaiLiveKey];
    [defaults setBool:self.infiniteButton.state == NSControlStateValueOn forKey:CBCbonsaiInfiniteKey];
    [defaults setDouble:time forKey:CBCbonsaiTimeKey];
    [defaults setDouble:wait forKey:CBCbonsaiWaitKey];
    [defaults setObject:[self trimmedStringFromField:self.messageField] forKey:CBCbonsaiMessageKey];
    [defaults setBool:self.baseEnabledButton.state == NSControlStateValueOn forKey:CBCbonsaiBaseEnabledKey];
    [defaults setInteger:self.baseField.integerValue forKey:CBCbonsaiBaseKey];
    [defaults setObject:[self trimmedStringFromField:self.leafField] forKey:CBCbonsaiLeafKey];
    [defaults setObject:[self trimmedStringFromField:self.colorField] forKey:CBCbonsaiColorKey];
    [defaults setInteger:multiplier forKey:CBCbonsaiMultiplierKey];
    [defaults setInteger:life forKey:CBCbonsaiLifeKey];
    [defaults setBool:self.printButton.state == NSControlStateValueOn forKey:CBCbonsaiPrintKey];
    [defaults setBool:self.seedEnabledButton.state == NSControlStateValueOn forKey:CBCbonsaiSeedEnabledKey];
    [defaults setInteger:self.seedField.integerValue forKey:CBCbonsaiSeedKey];
    [defaults setBool:self.saveEnabledButton.state == NSControlStateValueOn forKey:CBCbonsaiSaveEnabledKey];
    [defaults setObject:[self trimmedStringFromField:self.savePathField] forKey:CBCbonsaiSavePathKey];
    [defaults setBool:self.loadEnabledButton.state == NSControlStateValueOn forKey:CBCbonsaiLoadEnabledKey];
    [defaults setObject:[self trimmedStringFromField:self.loadPathField] forKey:CBCbonsaiLoadPathKey];
    [defaults setBool:self.verboseButton.state == NSControlStateValueOn forKey:CBCbonsaiVerboseKey];
    [defaults setBool:self.helpButton.state == NSControlStateValueOn forKey:CBCbonsaiHelpKey];
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
    if (sender == self.fontSizeStepper) {
        self.fontSizeField.stringValue = [NSString stringWithFormat:@"%.0f", self.fontSizeStepper.doubleValue];
    } else if (sender == self.timeStepper) {
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
    self.baseField.enabled = self.baseEnabledButton.state == NSControlStateValueOn;
    self.seedField.enabled = self.seedEnabledButton.state == NSControlStateValueOn;
    self.savePathField.enabled = self.saveEnabledButton.state == NSControlStateValueOn;
    self.loadPathField.enabled = self.loadEnabledButton.state == NSControlStateValueOn;
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

- (void)cancelConfiguration:(id)sender
{
    [[NSApplication sharedApplication] endSheet:self.configurationSheet];
}

@end
