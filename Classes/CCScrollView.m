//
//  SWScrollView.m
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
//  Created by Sangwoo Im on 6/3/10.
//  Copyright 2010 Sangwoo Im. All rights reserved.
//

#import "CCScrollView.h"

#import "CCNode+Autolayout.h"

#define SCROLL_DEACCEL_RATE  0.95f
#define SCROLL_DEACCEL_DIST  1.0f
#define BOUNCE_DURATION      0.35f
#define INSET_RATIO          0.3f

@interface CCScrollView()
/**
 * initial touch point
 */
@property (nonatomic, assign) CGPoint touchPoint;
/**
 * determines whether touch is moved after begin phase
 */
@property (nonatomic, assign) BOOL touchMoved;
@end

@interface CCScrollView (Private)

/**
 * Init this object with a given size to clip its content.
 *
 * @param size view size
 * @return initialized scroll view object
 */
-(id)initWithViewSize:(CGSize)size;
/**
 * Relocates the container at the proper offset, in bounds of max/min offsets.
 *
 * @param animated If YES, relocation is animated
 */
-(void)relocateContainer:(BOOL)animated;
/**
 * implements auto-scrolling behavior. change SCROLL_DEACCEL_RATE as needed to choose
 * deacceleration speed. it must be less than 1.0f.
 *
 * @param dt delta
 */
-(void)deaccelerateScrolling:(ccTime)dt;
/**
 * This method makes sure auto scrolling causes delegate to invoke its method
 */
-(void)performedAnimatedScroll:(ccTime)dt;
/**
 * Expire animated scroll delegate calls
 */
-(void)stoppedAnimatedScroll:(CCNode *)node;
/**
 * clip this view so that outside of the visible bounds can be hidden.
 */
-(void)beforeDraw;
/**
 * retract what's done in beforeDraw so that there's no side effect to
 * other nodes.
 */
-(void)afterDraw;
/**
 * Zoom handling
 */
-(void)handleZoom;
/**
 * Computes inset for bouncing
 */
-(void)computeInsets;
@end


@implementation CCScrollView
@synthesize maxZoomScale = maxScale_;
@synthesize minZoomScale = minScale_;

#pragma mark -
#pragma mark init

+(id)viewWithViewSize:(CGSize)size {
    return [[self alloc] initWithViewSize:size];
}

+(id)viewWithViewSize:(CGSize)size container:(CCNode *)container {
    return [[self alloc] initWithViewSize:size container:container];
}

-(id)initWithViewSize:(CGSize)size {
    return [self initWithViewSize:size container:nil];
}

-(id)initWithViewSize:(CGSize)size container:(CCNode *)container {
    if ((self = [super init])) {
        self.container = container;
        self.viewSize   = size;

        if (!self.container) {
            self.container = [CCLayer node];
        }
        self.touchEnabled = YES;
        _touches = [NSMutableArray array];
        _delegate = nil;
        _bounces = YES;
        clipsToBounds_ = YES;
        _container.contentSize = CGSizeZero;
        _direction = CCScrollViewDirectionBoth;
        _container.position = ccp(0.0f, 0.0f);
        touchLength_ = 0.0f;

        [self addChild:_container];
        minScale_ = maxScale_ = 1.0f;
    }
    return self;
}

-(id)init {
    NSAssert(NO, @"SWScrollView: DO NOT initialize SWScrollview directly.");
    return nil;
}

-(void)registerWithTouchDispatcher {
	CCTouchDispatcher *dispatcher = [[CCDirector sharedDirector] touchDispatcher];
    [dispatcher addTargetedDelegate:self priority:0 swallowsTouches:YES];
}

-(BOOL)isNodeVisible:(CCNode *)node {
    const CGPoint offset = self.contentOffset;
    const CGSize size = _viewSize;
    const float scale = self.zoomScale;

    CGRect viewRect;

    viewRect = CGRectMake(-offset.x/scale, -offset.y/scale, size.width/scale, size.height/scale);

    return CGRectIntersectsRect(viewRect, node.boundingBox);
}
-(void)pause:(id)sender {
    id child;
    [_container pauseSchedulerAndActions];
    CCARRAY_FOREACH(_container.children, child) {
        if ([child respondsToSelector:@selector(pause:)]) {
            [child performSelector:@selector(pause:) withObject:sender];
        }
    }
}
-(void)resume:(id)sender {
    id child;
    CCARRAY_FOREACH(_container.children, child) {
        if ([child respondsToSelector:@selector(resume:)]) {
            [child performSelector:@selector(resume:) withObject:sender];
        }
    }
    [_container resumeSchedulerAndActions];
}

#pragma mark -
#pragma mark Properties

-(void)setTouchEnabled:(BOOL)e {
    [super setTouchEnabled:e];
    if (!e) {
        _isDragging = NO;
        _touchMoved = NO;
        [_touches removeAllObjects];
    }
}
-(void)setContentOffset:(CGPoint)offset {
    [self setContentOffset:offset animated:NO];
}
-(void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    if (animated) { //animate scrolling
        [self setContentOffset:offset animatedInDuration:BOUNCE_DURATION];
    } else { //set the container position directly
        if (!_bounces) {
            const CGPoint minOffset = self.minContainerOffset;
            const CGPoint maxOffset = self.maxContainerOffset;

            offset.x = MAX(minOffset.x, MIN(maxOffset.x, offset.x));
            offset.y = MAX(minOffset.y, MIN(maxOffset.y, offset.y));
        }
        _container.position = offset;
        if([_delegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
            [_delegate scrollViewDidScroll:self];
        }
    }
}

-(void)setContentOffset:(CGPoint)offset animatedInDuration:(ccTime)dt {
    CCFiniteTimeAction *scroll, *expire;

    scroll = [CCMoveTo actionWithDuration:dt position:offset];
    expire = [CCCallFunc actionWithTarget:self selector:@selector(stoppedAnimatedScroll:)];
    [_container runAction:[CCSequence actions:scroll, expire, nil]];
    [self schedule:@selector(performedAnimatedScroll:)];
}

-(CGPoint)contentOffset {
    return _container.position;
}

-(void)setZoomScale:(float)s {
    if (_container.scale != s) {
        CGPoint oldCenter, newCenter;
        CGPoint center;

        if (touchLength_ == 0.0f) {
            center = ccp(_viewSize.width*0.5f, _viewSize.height*0.5f);
            center = [self convertToWorldSpace:center];
        } else {
            center = _touchPoint;
        }

        oldCenter = [_container convertToNodeSpace:center];
        _container.scale = MAX(minScale_, MIN(maxScale_, s));
        newCenter = [_container convertToWorldSpace:oldCenter];

        const CGPoint offset = ccpSub(center, newCenter);
        if ([_delegate respondsToSelector:@selector(scrollViewDidZoom:)]) {
            [_delegate scrollViewDidZoom:self];
        }
		
		[self computeInsets];
        [self setContentOffset:ccpAdd(_container.position,offset)];
    }
}

-(CGFloat)zoomScale {
    return _container.scale;
}

-(void)setZoomScale:(float)s animated:(BOOL)animated {
    if (animated) {
        [self setZoomScale:s animatedInDuration:BOUNCE_DURATION];
    } else {
        [self setZoomScale:s];
    }
}

-(void)setZoomScale:(float)s animatedInDuration:(ccTime)dt {
    if (dt > 0) {
        if (_container.scale != s) {
            CCActionTween *scaleAction;
            scaleAction = [CCActionTween actionWithDuration:dt
                                                        key:@"zoomScale"
                                                       from:_container.scale
                                                         to:s];
            [self runAction:scaleAction];
        }
    } else {
        [self setZoomScale:s];
    }
}

-(void)setViewSize:(CGSize)size {
    if (!CGSizeEqualToSize(_viewSize, size)) {
        _viewSize = size;
		[self computeInsets];
    }
}

#pragma mark -
#pragma mark Private
-(void)computeInsets {
	maxInset_ = [self maxContainerOffset];
	maxInset_ = ccp(maxInset_.x + _viewSize.width * INSET_RATIO,
					maxInset_.y + _viewSize.height * INSET_RATIO);
	minInset_ = [self minContainerOffset];
	minInset_ = ccp(minInset_.x - _viewSize.width * INSET_RATIO,
					minInset_.y - _viewSize.height * INSET_RATIO);
}

-(void)relocateContainer:(BOOL)animated {
    CGPoint oldPoint, min, max;
    CGFloat newX, newY;

    min = [self minContainerOffset];
    max = [self maxContainerOffset];

    oldPoint = _container.position;
    newX = oldPoint.x;
    newY = oldPoint.y;
    if (_direction == CCScrollViewDirectionBoth || _direction == CCScrollViewDirectionHorizontal) {
        newX = MIN(newX, max.x);
        newX = MAX(newX, min.x);
    }
    if (_direction == CCScrollViewDirectionBoth || _direction == CCScrollViewDirectionVertical) {
        newY = MIN(newY, max.y);
        newY = MAX(newY, min.y);
    }
    if (newY != oldPoint.y || newX != oldPoint.x) {
        [self setContentOffset:ccp(newX, newY) animated:animated];
    }
}

-(CGPoint)maxContainerOffset {
    return ccp(0.0f, 0.0f);
}

-(CGPoint)minContainerOffset {
    return ccp(_viewSize.width - _container.contentSize.width*_container.scaleX,
               _viewSize.height - _container.contentSize.height*_container.scaleY);
}

-(void)deaccelerateScrolling:(ccTime)dt {
    if (_isDragging) {
        [self unschedule:@selector(deaccelerateScrolling:)];
        return;
    }

    CGFloat newX, newY;
    CGPoint maxInset, minInset;

    _container.position = ccpAdd(_container.position, scrollDistance_);

    if (_bounces) {
        maxInset = maxInset_;
        minInset = minInset_;
    } else {
        maxInset = self.maxContainerOffset;
        minInset = self.minContainerOffset;
    }

    //check to see if offset lies within the inset bounds
    newX     = MIN(_container.position.x, maxInset.x);
    newX     = MAX(newX, minInset.x);
    newY     = MIN(_container.position.y, maxInset.y);
    newY     = MAX(newY, minInset.y);

    scrollDistance_     = ccpSub(scrollDistance_, ccp(newX - _container.position.x, newY - _container.position.y));
    scrollDistance_     = ccpMult(scrollDistance_, SCROLL_DEACCEL_RATE);
    [self setContentOffset:ccp(newX,newY)];

    if (ccpLengthSQ(scrollDistance_) <= SCROLL_DEACCEL_DIST*SCROLL_DEACCEL_DIST ||
        newX == maxInset.x || newX == minInset.x ||
        newY == maxInset.y || newY == minInset.y) {
        [self unschedule:@selector(deaccelerateScrolling:)];
        [self relocateContainer:YES];
    }
}
-(void)stoppedAnimatedScroll:(CCNode *)node {
    [self unschedule:@selector(performedAnimatedScroll:)];
}
-(void)performedAnimatedScroll:(ccTime)dt {
    if (_isDragging) {
        [self unschedule:@selector(performedAnimatedScroll:)];
        return;
    }
    if ([_delegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
        [_delegate scrollViewDidScroll:self];
    }
}

#pragma mark -
#pragma mark overriden

- (void)visit
{
    [self iterate];
}

-(void)setAnchorPoint:(CGPoint)anchorPoint {
	CCLOG(@"The current implementation doesn't support anchor point change");
}

-(void)layoutChildren {
	[self relocateContainer:NO];
}

-(CGSize)contentSize {
    return CGSizeMake(_container.contentSize.width, _container.contentSize.height);
}

-(void)setContentSize:(CGSize)size {
    _container.contentSize = size;
    maxInset_ = [self maxContainerOffset];
    maxInset_ = ccp(maxInset_.x + _viewSize.width * INSET_RATIO,
                    maxInset_.y + _viewSize.height * INSET_RATIO);
    minInset_ = [self minContainerOffset];
    minInset_ = ccp(minInset_.x - _viewSize.width * INSET_RATIO,
                    minInset_.y - _viewSize.height * INSET_RATIO);
}
/**
 * make sure all children go to the container
 */
-(void)addChild:(CCNode *)node  z:(int)z tag:(int)aTag {
    node.ignoreAnchorPointForPosition = NO;
    node.anchorPoint           = ccp(0.0f, 0.0f);
    if (_container != node) {
        [_container addChild:node z:z tag:aTag];
    } else {
        [super addChild:node z:z tag:aTag];
    }
}
/**
 * clip this view so that outside of the visible bounds can be hidden.
 */
-(void)beforeDraw {
    if (clipsToBounds_) {
        glEnable(GL_SCISSOR_TEST);
        const CGFloat s = [[CCDirector sharedDirector] contentScaleFactor];
        glScissor(self.position.x*s, self.position.y*s, _viewSize.width*s, _viewSize.height*s);
    }
}
/**
 * retract what's done in beforeDraw so that there's no side effect to
 * other nodes.
 */
-(void)afterDraw {
    if (clipsToBounds_) {
        glDisable(GL_SCISSOR_TEST);
    }
}

#pragma mark -
#pragma mark touch events

-(BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!self.visible) {
        return NO;
    }
    CGRect frame;

    frame = CGRectMake(self.position.x, self.position.y, _viewSize.width, _viewSize.height);
    //dispatcher does not know about clipping. reject touches outside visible bounds.
    if ([_touches count] > 2 ||
        _touchMoved          ||
        !CGRectContainsPoint(frame, [_container convertToWorldSpace:[_container convertTouchToNodeSpace:touch]])) {
        return NO;
    }
	
    if (![_touches containsObject:touch]) {
        [_touches addObject:touch];
    }
    if ([_touches count] == 1) { // scrolling
        _touchPoint     = [self convertTouchToNodeSpace:touch];
        _touchMoved     = NO;
        _isDragging     = YES; //dragging started
        scrollDistance_ = ccp(0.0f, 0.0f);
        touchLength_    = 0.0f;
    } else if ([_touches count] == 2) {
        _touchPoint  = ccpMidpoint([self convertTouchToNodeSpace:[_touches objectAtIndex:0]],
                                   [self convertTouchToNodeSpace:[_touches objectAtIndex:1]]);
        touchLength_ = ccpDistance([_container convertTouchToNodeSpace:[_touches objectAtIndex:0]],
                                   [_container convertTouchToNodeSpace:[_touches objectAtIndex:1]]);
        _isDragging  = NO;
    }
    return YES;
}
-(void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!self.visible) {
        return;
    }
    if ([_touches containsObject:touch]) {
        if ([_touches count] == 1 && _isDragging) { // scrolling
            CGPoint moveDistance, newPoint;
            CGRect  frame;
            CGFloat newX, newY;

            _touchMoved  = YES;
            frame        = CGRectMake(self.position.x, self.position.y, _viewSize.width, _viewSize.height);
            newPoint     = [self convertTouchToNodeSpace:[_touches objectAtIndex:0]];
            moveDistance = ccpSub(newPoint, _touchPoint);
            _touchPoint  = newPoint;

            if (CGRectContainsPoint(frame, [self convertToWorldSpace:newPoint])) {
                switch (_direction) {
                    case CCScrollViewDirectionVertical:
                        moveDistance = ccp(0.0f, moveDistance.y);
                        break;
                    case CCScrollViewDirectionHorizontal:
                        moveDistance = ccp(moveDistance.x, 0.0f);
                        break;
                    default:
                        break;
                }
                _container.position = ccpAdd(_container.position, moveDistance);

                //check to see if offset lies within the inset bounds
                newX     = MIN(_container.position.x, maxInset_.x);
                newX     = MAX(newX, minInset_.x);
                newY     = MIN(_container.position.y, maxInset_.y);
                newY     = MAX(newY, minInset_.y);

                scrollDistance_     = ccpSub(moveDistance, ccp(newX - _container.position.x, newY - _container.position.y));
                [self setContentOffset:ccp(newX, newY)];
            }
        } else if ([_touches count] == 2 && !_isDragging) {
			_touchMoved = YES;
            const CGFloat len = ccpDistance([_container convertTouchToNodeSpace:[_touches objectAtIndex:0]],
                                            [_container convertTouchToNodeSpace:[_touches objectAtIndex:1]]);
            [self setZoomScale:self.zoomScale*len/touchLength_];
        }
    }
}
-(void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!self.visible) {
        return;
    }
    if ([_touches containsObject:touch]) {
        if (_touchMoved) {
            [self schedule:@selector(deaccelerateScrolling:)];
        }
        [_touches removeObject:touch];
    }
    if ([_touches count] == 0) {
        _isDragging = NO;
        _touchMoved = NO;
    }
}
-(void)ccTouchCancelled:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!self.visible) {
        return;
    }
    [_touches removeObject:touch];
    if ([_touches count] == 0) {
        _isDragging = NO;
        _touchMoved = NO;
    }
}
@end
