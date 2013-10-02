//
//  MMScrap.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/23/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import "MMScrapView.h"
#import "UIColor+ColorWithHex.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import "MMRotationManager.h"
#import "DrawKit-iOS.h"
#import "UIColor+Shadow.h"
#import "MMDebugDrawView.h"
#import "NSString+UUID.h"
#import "NSThread+BlockAdditions.h"
#import "MMScrapViewState.h"

#import <JotUI/AbstractBezierPathElement-Protected.h>

@implementation MMScrapView{
    // **
    // these properties will be saved by the page that holds us, if any
    //
    // our current scale
    CGFloat scale;
    // our current rotation around our center
    CGFloat rotation;

    
    // these properties are UI only, and
    // don't need to be persisted
    
    // boolean to say if the user is currently holding this scrap. used for blue border
    BOOL selected;
    // the layer used for our white background. won't clip sub-content
    CAShapeLayer* backgroundColorLayer;

    
    // these properties are calculated, and
    // don't need to be persisted

    // this will track whenever a property of the scrap has changed,
    // so that we can recalculate the path to use when clipping strokes
    // around/through this scrap
    BOOL needsClippingPathUpdate;

    UIBezierPath* clippingPath;
    
    NSString* uuid;
    
    MMScrapViewState* scrapState;
}

@synthesize uuid;
@synthesize scale;
@synthesize rotation;
@synthesize selected;
@synthesize clippingPath;


-(id) initWithUUID:(NSString*)_uuid{
    
    scrapState = [[MMScrapViewState alloc] initWithUUID:_uuid];
    scrapState.delegate = self;

    if(scrapState.bezierPath){
        if(self = [self initWithBezierPath:scrapState.bezierPath andUUID:_uuid]){
            // TODO: load in thumbnail image view while state loads
        }
        return self;
    }
    // can't find any information about that scrap
    return nil;
}

- (id)initWithBezierPath:(UIBezierPath *)path{
    return [self initWithBezierPath:path andUUID:[NSString createStringUUID]];
}

/**
 * this input path is in CoreGraphics coordinate space. it's been generated by all of the touch
 * points, and then fed through TouchShape to generate a SYShape, which has generated this input path
 */
- (id)initWithBezierPath:(UIBezierPath*)_path andUUID:(NSString*)_uuid
{
    UIBezierPath* originalPath = [_path copy];

    if(!scrapState){
        // one of our other [init] methods may have already created a state
        // for us, but if not, then go ahead and build one
        scrapState = [[MMScrapViewState alloc] initWithUUID:_uuid andBezierPath:originalPath];
        scrapState.delegate = self;
    }
    
    // -4 b/c twice the 2px shadow
    if ((self = [super initWithFrame:scrapState.drawableBounds])){
        self.center = _path.center;
        uuid = _uuid;
        scale = 1;
        
        //
        // this is our white background
        backgroundColorLayer = [CAShapeLayer layer];
        [backgroundColorLayer setPath:scrapState.bezierPath.CGPath];
        backgroundColorLayer.fillColor = [UIColor whiteColor].CGColor;
        backgroundColorLayer.masksToBounds = YES;
        backgroundColorLayer.frame = self.layer.bounds;
        [self.layer addSublayer:backgroundColorLayer];
        
        // now we need to show our shadow.
        // this is done just as we do with Shadowed view
        // our view clips to bounds, and our shadow is
        // displayed inside our bounds. this way we dont
        // need to do any offscreen rendering when displaying
        // this view
        self.layer.shadowPath = scrapState.bezierPath.CGPath;
        self.layer.shadowRadius = 1.5;
        self.layer.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:.5].CGColor;
        self.layer.shadowOpacity = .65;
        self.layer.shadowOffset = CGSizeMake(0, 0);
        
        // only the path contents are opaque, but outside the path needs to be transparent
        self.opaque = NO;
        // yes clip to bounds so we keep good performance
        self.clipsToBounds = YES;
        // update our shadow rotation
        [self didUpdateAccelerometerWithRawReading:[[MMRotationManager sharedInstace] currentRawRotationReading]];
        needsClippingPathUpdate = YES;
        
        //
        // TODO: add this to our subviews only when our state
        // is loaded, otherwise show an image preview instead.
        [self addSubview:scrapState.contentView];
        
        [MMDebugDrawView sharedInstace].frame = self.bounds;
        [self addSubview:[MMDebugDrawView sharedInstace]];

    }
    return self;
}

-(void) setSelected:(BOOL)_selected{
    selected = _selected;
    if(selected){
        self.layer.shadowColor = [[UIColor blueShadowColor] colorWithAlphaComponent:1].CGColor;
        self.layer.shadowRadius = 2.5;
    }else{
        self.layer.shadowRadius = 1.5;
        self.layer.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:.5].CGColor;
    }
}

-(void) setBackgroundColor:(UIColor *)backgroundColor{
    backgroundColorLayer.fillColor = backgroundColor.CGColor;
}

/**
 * scraps will show the shadow move ever so slightly as the device is turned
 */
-(void) didUpdateAccelerometerWithRawReading:(CGFloat)currentRawReading{
    self.layer.shadowOffset = CGSizeMake(cosf(currentRawReading)*1, sinf(currentRawReading)*1);
}

#pragma mark - UITouch Helper methods

/**
 * these methods are used from inside of gestures to help
 * determine when touches begin/move/etc inide of a scrap
 */

-(BOOL) containsTouch:(UITouch*)touch{
    CGPoint locationOfTouch = [touch locationInView:self];
    return [scrapState.bezierPath containsPoint:locationOfTouch];
}

-(NSSet*) matchingPairTouchesFrom:(NSSet*) touches{
    NSSet* outArray = [self allMatchingTouchesFrom:touches];
    if([outArray count] >= 2){
        return outArray;
    }
    return nil;
}

-(NSSet*) allMatchingTouchesFrom:(NSSet*) touches{
    NSMutableSet* outArray = [NSMutableSet set];
    for(UITouch* touch in touches){
        if([self containsTouch:touch]){
            [outArray addObject:touch];
        }
    }
    return outArray;
}

#pragma mark - Postion, Scale, Rotation

-(void) setScale:(CGFloat)_scale andRotation:(CGFloat)_rotation{
//    if(_scale > 2) _scale = 2;
//    if(_scale * self.bounds.size.width < 100){
//        _scale = 100 / self.bounds.size.width;
//    }
//    if(_scale * self.bounds.size.height < 100){
//        _scale = 100 / self.bounds.size.height;
//    }
    scale = _scale;
    rotation = _rotation;
    needsClippingPathUpdate = YES;
    self.transform = CGAffineTransformConcat(CGAffineTransformMakeRotation(rotation),CGAffineTransformMakeScale(scale, scale));
}

-(void) setScale:(CGFloat)_scale{
    [self setScale:_scale andRotation:self.rotation];
}

-(void) setRotation:(CGFloat)_rotation{
    [self setScale:self.scale andRotation:_rotation];
}

-(void) setFrame:(CGRect)frame{
    [super setFrame:frame];
    needsClippingPathUpdate = YES;
}

-(void) setBounds:(CGRect)bounds{
    [super setBounds:bounds];
    needsClippingPathUpdate = YES;
}

-(void) setCenter:(CGPoint)center{
    [super setCenter:center];
    needsClippingPathUpdate = YES;
}


#pragma mark - Clipping Path

/**
 * we'll cache our clipping path since it
 * takes a bit of processing power to
 * calculate.
 *
 * this will always return the correct clipping
 * path, and will recalculate and update our
 * cache if need be
 */
-(UIBezierPath*) clippingPath{
    if(needsClippingPathUpdate){
        [self commitEditsAndUpdateClippingPath];
        needsClippingPathUpdate = NO;
    }
    return clippingPath;
}

/**
 * our clippingPath is in OpenGL coordinate space, just
 * as all of the CurveToPathElements that we use for
 * drawing. This will transform our CoreGraphics coordinated
 * bezierPath into OpenGL including our location, rotation,
 * and scale so that we can clip all of the CurveToPathElements
 * with this path to help determine which parts of the drawn
 * line should be added to this scrap.
 */
-(void) commitEditsAndUpdateClippingPath{
    // start with our original path
    clippingPath = [scrapState.bezierPath copy];
    
    // when we pick up a scrap with a two finger gesture, we also
    // change the position and anchor (which change the center), so
    // that it rotates underneath the gesture correctly.
    //
    // we need to re-caculate the true center of the scrap as if it
    // was not being held, so that we can position our path correctly
    // over it.
    CGPoint actualScrapCenter = CGPointMake( CGRectGetMidX(self.frame), CGRectGetMidY(self.frame));
    CGPoint clippingPathCenter = clippingPath.center;
    
    // first, align the center of the scrap to the center of the path
    CGAffineTransform reCenterTransform = CGAffineTransformMakeTranslation(actualScrapCenter.x - clippingPathCenter.x, actualScrapCenter.y - clippingPathCenter.y);
    clippingPathCenter = CGPointApplyAffineTransform(clippingPathCenter, reCenterTransform);
    
    
    // now we need to rotate the path around it's new center
    CGAffineTransform moveFromCenter = CGAffineTransformMakeTranslation(-clippingPathCenter.x, -clippingPathCenter.y);
    CGAffineTransform rotateAndScale = CGAffineTransformConcat(CGAffineTransformMakeRotation(self.rotation),CGAffineTransformMakeScale(self.scale, self.scale));
    CGAffineTransform moveToCenter = CGAffineTransformMakeTranslation(clippingPathCenter.x, clippingPathCenter.y);
    
    CGAffineTransform flipTransform = CGAffineTransformMake(1, 0, 0, -1, 0, self.superview.bounds.size.height);
    
    CGAffineTransform clippingPathTransform = reCenterTransform;
    clippingPathTransform = CGAffineTransformConcat(clippingPathTransform, moveFromCenter);
    clippingPathTransform = CGAffineTransformConcat(clippingPathTransform, rotateAndScale);
    clippingPathTransform = CGAffineTransformConcat(clippingPathTransform, moveToCenter);
    clippingPathTransform = CGAffineTransformConcat(clippingPathTransform, flipTransform);
    
    [clippingPath applyTransform:clippingPathTransform];
}



#pragma mark - JotView

-(void) addElement:(AbstractBezierPathElement *)element{
    [scrapState addElement:element];
}


#pragma mark - MMScrapViewStateDelegate

-(void) didLoadScrapViewState:(MMScrapViewState*)state{
    // noop
}




#pragma mark - Ignore Touches

/**
 * these two methods make sure that the ruler view
 * can never intercept any touch input. instead it will
 * effectively pass through this view to the views behind it
 */
-(UIView*) hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    return nil;
}

-(BOOL) pointInside:(CGPoint)point withEvent:(UIEvent *)event{
    return NO;
}


#pragma mark - Saving

-(void) saveToDisk{
    [scrapState saveToDisk];
}



#pragma mark - State

-(void) loadStateAsynchronously:(BOOL)async{
    [scrapState loadStateAsynchronously:async];
}

-(void) unloadState{
    [scrapState unloadState];
}


#pragma mark - Properties

-(UIBezierPath*) bezierPath{
    return scrapState.bezierPath;
}

-(CGSize) originalSize{
    return scrapState.originalSize;
}


#pragma mark - Debug


/**
 * draws a large boxed "X" on the scrap to show it's bounds and location
 */
-(void) drawX{
    
    UIColor* color = [UIColor randomColor];
    
    CurveToPathElement* curveTo = [CurveToPathElement elementWithStart:CGPointMake(10, 10)
                                                             andLineTo:CGPointMake(self.bounds.size.width-10, 10)];
    curveTo.width = 10;
    curveTo.color = color;
    curveTo.rotation = 0;
    [scrapState addElement:curveTo];
    
    curveTo = [CurveToPathElement elementWithStart:CGPointMake(self.bounds.size.width-10, 10)
                                         andLineTo:CGPointMake(self.bounds.size.width-10, self.bounds.size.height - 10)];
    curveTo.width = 10;
    curveTo.color = color;
    curveTo.rotation = 0;
    [scrapState addElement:curveTo];
    
    curveTo = [CurveToPathElement elementWithStart:CGPointMake(self.bounds.size.width-10, self.bounds.size.height - 10)
                                         andLineTo:CGPointMake(10, self.bounds.size.height - 10)];
    curveTo.width = 10;
    curveTo.color = color;
    curveTo.rotation = 0;
    [scrapState addElement:curveTo];
    
    curveTo = [CurveToPathElement elementWithStart:CGPointMake(10, self.bounds.size.height - 10)
                                         andLineTo:CGPointMake(10, 10)];
    curveTo.width = 10;
    curveTo.color = color;
    curveTo.rotation = 0;
    [scrapState addElement:curveTo];
    
    curveTo = [CurveToPathElement elementWithStart:CGPointMake(10, 10)
                                         andLineTo:CGPointMake(self.bounds.size.width-10, self.bounds.size.height - 10)];
    curveTo.width = 10;
    curveTo.color = color;
    curveTo.rotation = 0;
    [scrapState addElement:curveTo];
    
    curveTo = [CurveToPathElement elementWithStart:CGPointMake(10, self.bounds.size.height - 10)
                                         andLineTo:CGPointMake(self.bounds.size.width - 10, 10)];
    curveTo.width = 10;
    curveTo.color = color;
    curveTo.rotation = 0;
    [scrapState addElement:curveTo];
}


@end
