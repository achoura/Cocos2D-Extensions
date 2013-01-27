//
//  SWTableView.m
//  SWGameLib
//
//  Copyright (c) 2010 Sangwoo Im
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
//
//  Created by Sangwoo Im on 6/3/10.
//  Copyright 2010 Sangwoo Im. All rights reserved.
//

#import "CCTableView.h"
#import "CCTableViewCell.h"

#import "CCSorting.h"
#import "CCLayer.h"

@implementation CCTableView

@synthesize delegate = _tDelegate;


+(id)viewWithDataSource:(id<CCTableViewDataSource>)dataSource size:(CGSize)size {
    return [self viewWithDataSource:dataSource size:size container:nil];
}

+(id)viewWithDataSource:(id <CCTableViewDataSource>)dataSource size:(CGSize)size container:(CCNode *)container {
    CCTableView *table;
    table = [[self alloc] initWithViewSize:size container:container];
    table.dataSource = dataSource;
    [table _updateContentSize];
    return table;
}

-(id)initWithViewSize:(CGSize)size container:(CCNode *)container {
    if ((self = [super initWithViewSize:size container:container])) {
        cellsUsed_ = [NSMutableArray array];
        cellsFreed_ = [NSMutableArray array];
        indices_ = [NSMutableIndexSet indexSet];
        self.delegate = nil;
        _verticalFillOrder = CCTableViewFillBottomUp;
        self.direction  = CCScrollViewDirectionVertical;
        [super setDelegate:self];
    }
    return self;
}

#pragma mark -
#pragma mark property

-(void)setVerticalFillOrder:(CCTableViewVerticalFillOrder)fillOrder {
    if (_verticalFillOrder != fillOrder) {
        _verticalFillOrder = fillOrder;
        if (cellsUsed_.count > 0) {
            [self reloadData];
        }
    }
}

#pragma mark -
#pragma mark public

-(void)reloadData {
    @autoreleasepool {
        for (CCTableViewCell *cell in cellsUsed_) {
            [cellsFreed_ addObject:cell];
            [cell reset];
            if (cell.parent == self.container) {
                [self.container removeChild:cell cleanup:YES];
            }
        }
        [indices_ removeAllIndexes];
        cellsUsed_ = [NSMutableArray array];
        
        [self _updateContentSize];
        if ([_dataSource numberOfCellsInTableView:self] > 0) {
            [self scrollViewDidScroll:self];
        }
    }
}

-(CCTableViewCell *)cellAtIndex:(NSUInteger)idx {
    return [self _cellWithIndex:idx];
}

-(void)updateCellAtIndex:(NSUInteger)idx {
    if (idx == NSNotFound || idx > [_dataSource numberOfCellsInTableView:self]-1) {
        return;
    }
    
    CCTableViewCell *cell;
    cell = [self _cellWithIndex:idx];
    if (cell) {
        [self _moveCellOutOfSight:cell];
    }
    cell = [_dataSource table:self cellAtIndex:idx];
    [self _setIndex:idx forCell:cell];
    [self _addCellIfNecessary:cell];
}

-(void)insertCellAtIndex:(NSUInteger)idx {
    if (idx == NSNotFound || idx > [_dataSource numberOfCellsInTableView:self]-1) {
        return;
    }
    CCTableViewCell *cell;
    NSInteger newIdx;
    
    cell = (CCTableViewCell *)[cellsUsed_ objectWithObjectID:idx];
    if (cell) {
        newIdx = [cellsUsed_ indexOfSortedObject:cell];
        for (int i = newIdx; i < cellsUsed_.count; i++) {
            cell = cellsUsed_[i];
            [self _setIndex:cell.idx+1 forCell:cell];
        }
    }
    
    [indices_ shiftIndexesStartingAtIndex:idx by:1];
    
    //insert a new cell
    cell = [_dataSource table:self cellAtIndex:idx];
    [self _setIndex:idx forCell:cell];
    [self _addCellIfNecessary:cell];
    
    [self _updateContentSize];
}

-(void)removeCellAtIndex:(NSUInteger)idx {
    if (idx == NSNotFound || idx > [_dataSource numberOfCellsInTableView:self]-1) {
        return;
    }
    
    CCTableViewCell *cell;
    NSInteger newIdx;
    
    cell = [self _cellWithIndex:idx];
    if (!cell) {
        return;
    }
    
    newIdx = [cellsUsed_ indexOfSortedObject:cell];
    
    //remove first
    [self _moveCellOutOfSight:cell];
    
    [indices_ shiftIndexesStartingAtIndex:idx+1 by:-1];
    for (int i = cellsUsed_.count - 1; i > newIdx; i--) {
        cell = cellsUsed_[i];
        [self _setIndex:cell.idx-1 forCell:cell];
    }
}

-(CCTableViewCell *)dequeueCell {
    CCTableViewCell *cell;
    
    if ([cellsFreed_ count] == 0) {
        cell = nil;
    } else {
        cell = [cellsFreed_ objectAtIndex:0];
        [cellsFreed_ removeObjectAtIndex:0];
    }
    return cell;
}

#pragma mark -
#pragma mark private

- (void)_addCellIfNecessary:(CCTableViewCell *)cell {
    if (cell.parent != self.container) {
        [self.container addChild:cell];
    }
    [cellsUsed_ insertSortedObject:cell];
    [indices_ addIndex:cell.idx];
}

- (void)_updateContentSize {
    CGSize size, cellSize;
    NSUInteger cellCount;
    
    cellSize = [_dataSource cellSizeForTable:self];
    cellCount = [_dataSource numberOfCellsInTableView:self];

    switch (self.direction) {
        case CCScrollViewDirectionHorizontal:
            size = CGSizeMake(cellCount * cellSize.width, cellSize.height);
            size.width  = MAX(size.width,  _viewSize.width);
            break;
        default:
            size = CGSizeMake(cellSize.width, cellCount * cellSize.height);
            size.height = MAX(size.height, _viewSize.height);
            break;
    }
    [self setContentSize:size];
}
- (CGPoint)_offsetFromIndex:(NSUInteger)index {
    CGPoint offset = [self __offsetFromIndex:index];
    
    const CGSize cellSize = [_dataSource cellSizeForTable:self];
    if (_verticalFillOrder == CCTableViewFillTopDown) {
        offset.y = self.container.contentSize.height - offset.y - cellSize.height;
    }
    return offset;
}

- (CGPoint)__offsetFromIndex:(NSInteger)index {
    CGPoint offset;
    CGSize  cellSize;
    
    cellSize = [_dataSource cellSizeForTable:self];
    switch (self.direction) {
        case CCScrollViewDirectionHorizontal:
            offset = ccp(cellSize.width * index, 0.0f);
            break;
        default:
            offset = ccp(0.0f, cellSize.height * index);
            break;
    }
    
    return offset;
}
- (NSUInteger)_indexFromOffset:(CGPoint)offset {
    NSInteger index;
    const NSInteger maxIdx = [_dataSource numberOfCellsInTableView:self]-1;
    
    const CGSize cellSize = [_dataSource cellSizeForTable:self];
    if (_verticalFillOrder == CCTableViewFillTopDown) {
        offset.y = self.container.contentSize.height - offset.y - cellSize.height;
    }
    index = MAX(0, [self __indexFromOffset:offset]);
    index = MIN(index, maxIdx);
    return index;
}

- (NSInteger)__indexFromOffset:(CGPoint)offset {
    NSInteger index;
    CGSize cellSize;
    
    cellSize = [_dataSource cellSizeForTable:self];
    
    switch (self.direction) {
        case CCScrollViewDirectionHorizontal:
            index = offset.x/cellSize.width;
            break;
        default:
            index = offset.y/cellSize.height;
            break;
    }
    
    return index;
}

- (CCTableViewCell *)_cellWithIndex:(NSUInteger)cellIndex {
    CCTableViewCell *found;
    
    found = nil;
    
    if ([indices_ containsIndex:cellIndex]) {
        found = (CCTableViewCell *)[cellsUsed_ objectWithObjectID:cellIndex];
    }
    
    return found;
}
- (void)_moveCellOutOfSight:(CCTableViewCell *)cell {
    [cellsFreed_ addObject:cell];
    [cellsUsed_ removeSortedObject:cell];
    [indices_ removeIndex:cell.idx];
    [cell reset];
    if (cell.parent == self.container) {
        [self.container removeChild:cell cleanup:YES];
    }
}
- (void)_setIndex:(NSUInteger)index forCell:(CCTableViewCell *)cell {
    cell.anchorPoint = ccp(0.0f, 0.0f);
    cell.position    = [self _offsetFromIndex:index];
    cell.idx         = index;
}

#pragma mark -
#pragma mark scrollView

-(void)scrollViewDidScroll:(CCScrollView *)view {
    NSUInteger startIdx, endIdx, idx, maxIdx;
    CGPoint offset;
    
    maxIdx = [_dataSource numberOfCellsInTableView:self];
    
    if (maxIdx == 0) {
        return; // early termination
    }
    
@autoreleasepool {
    offset = ccpMult([self contentOffset], -1);
    maxIdx = MAX(maxIdx - 1, 0);
    
    const CGSize cellSize = [_dataSource cellSizeForTable:self];
    
    if (_verticalFillOrder == CCTableViewFillTopDown) {
        offset.y = offset.y + _viewSize.height/self.container.scaleY - cellSize.height;
    }
    startIdx = [self _indexFromOffset:offset];
    if (_verticalFillOrder == CCTableViewFillTopDown) {
        offset.y -= _viewSize.height/self.container.scaleY;
    } else {
        offset.y += _viewSize.height/self.container.scaleY;
    }
    offset.x += _viewSize.width/self.container.scaleX;
    
    endIdx = [self _indexFromOffset:offset];
    
    
    if (cellsUsed_.count > 0) {
        idx = [cellsUsed_[0] idx];
        while (idx < startIdx) {
            CCTableViewCell *cell = [cellsUsed_ objectAtIndex:0];
            [self _moveCellOutOfSight:cell];
            if ([cellsUsed_ count] > 0) {
                idx = [[cellsUsed_ objectAtIndex:0] idx];
            } else {
                break;
            }
        }
    }
    if ([cellsUsed_ count] > 0) {
        idx = [[cellsUsed_ lastObject] idx];
        while(idx <= maxIdx && idx > endIdx) {
            CCTableViewCell *cell = [cellsUsed_ lastObject];
            [self _moveCellOutOfSight:cell];
            if ([cellsUsed_ count] > 0) {
                idx = [[cellsUsed_ lastObject] idx];
            } else {
                break;
            }
        }
    }
    
    for (NSUInteger i=startIdx; i <= endIdx; i++) {
        if ([indices_ containsIndex:i]) {
            continue;
        }
        [self updateCellAtIndex:i];
    }
}
}

#pragma mark -
#pragma mark Touch events

-(void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!self.visible) {
        return;
    }
    if (_touches.count == 1 && !_touchMoved) {
        NSUInteger        index;
        CCTableViewCell   *cell;
        CGPoint           point;
        
        point = [self.container convertTouchToNodeSpace:touch];
        if (_verticalFillOrder == CCTableViewFillTopDown) {
            CGSize cellSize = [_dataSource cellSizeForTable:self];
            point.y -= cellSize.height;
        }
        index = [self _indexFromOffset:point];
        cell  = [self _cellWithIndex:index];
        
        if (cell) {
            [self.delegate table:self cellTouched:cell];
        }
    }
    [super ccTouchEnded:touch withEvent:event];
}

@end

