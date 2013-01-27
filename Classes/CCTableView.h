//
//  SWTableView.h
//  SWGameLib
//
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

#import "CCScrollView.h"

@class CCTableViewCell, CCTableView;

typedef enum {
    CCTableViewFillTopDown,
    CCTableViewFillBottomUp
} CCTableViewVerticalFillOrder;

@protocol CCTableViewDelegate<CCScrollViewDelegate>
-(void)table:(CCTableView *)table cellTouched:(CCTableViewCell *)cell;
@end

@protocol CCTableViewDataSource<NSObject>
-(CGSize)cellSizeForTable:(CCTableView *)table;
-(CCTableViewCell *)table:(CCTableView *)table cellAtIndex:(NSUInteger)idx;
-(NSUInteger)numberOfCellsInTableView:(CCTableView *)table;

@end


@interface CCTableView : CCScrollView<CCScrollViewDelegate> {
@private
    NSMutableIndexSet *indices_;
    NSMutableArray *cellsUsed_;
    NSMutableArray *cellsFreed_;
    __weak id<CCTableViewDelegate> _tDelegate;
}
@property (nonatomic, assign) id<CCTableViewDataSource> dataSource;
@property (nonatomic, weak) id<CCTableViewDelegate> delegate;
@property (nonatomic, assign) CCTableViewVerticalFillOrder verticalFillOrder;
+(id)viewWithDataSource:(id<CCTableViewDataSource>)verticalFillOrder size:(CGSize)size;
+(id)viewWithDataSource:(id <CCTableViewDataSource>)dataSource size:(CGSize)size container:(CCNode *)container;
-(void)updateCellAtIndex:(NSUInteger)idx;
-(void)insertCellAtIndex:(NSUInteger)idx;
-(void)removeCellAtIndex:(NSUInteger)idx;
-(void)reloadData;
-(CCTableViewCell *)dequeueCell;
-(CCTableViewCell *)cellAtIndex:(NSUInteger)idx;
@end
