#import "HFImageEditorViewController.h"

static const CGFloat kMaxUIImageSize = 1024;
static const CGFloat kPreviewImageSize = 120;
static const CGFloat kDefaultCropWidth = 320;
static const CGFloat kDefaultCropHeight = 320;
static const CGFloat kBoundingBoxInset = 15;
static const NSTimeInterval kAnimationIntervalReset = 0.37;
static const NSTimeInterval kAnimationIntervalTransform = 0.2;

@interface HFImageEditorViewController ()
@property (nonatomic,retain) UIImageView *imageView;
@property (nonatomic,assign) CGRect cropRect;
@property (retain, nonatomic) IBOutlet UIPanGestureRecognizer *panRecognizer;
@property (retain, nonatomic) IBOutlet UIRotationGestureRecognizer *rotationRecognizer;
@property (retain, nonatomic) IBOutlet UIPinchGestureRecognizer *pinchRecognizer;
@property (retain, nonatomic) IBOutlet UITapGestureRecognizer *tapRecognizer;
@property (nonatomic,retain) IBOutlet UIView<HFImageEditorFrame> *frameView;


@property(nonatomic,assign) NSUInteger gestureCount;
@property(nonatomic,assign) CGPoint touchCenter;
@property(nonatomic,assign) CGPoint rotationCenter;
@property(nonatomic,assign) CGPoint scaleCenter;
@property(nonatomic,assign) CGFloat scale;

@end



@implementation HFImageEditorViewController

@synthesize doneCallback = _doneCallback;
@synthesize sourceImage = _sourceImage;
@synthesize previewImage = _previewImage;
@synthesize cropSize = _cropSize;
@synthesize outputWidth = _outputWidth;
@synthesize frameView = _frameView;
@synthesize imageView = _imageView;
@synthesize panRecognizer = _panRecognizer;
@synthesize rotationRecognizer = _rotationRecognizer;
@synthesize tapRecognizer = _tapRecognizer;
@synthesize pinchRecognizer = _pinchRecognizer;
@synthesize touchCenter = _touchCenter;
@synthesize rotationCenter = _rotationCenter;
@synthesize scaleCenter = _scaleCenter;
@synthesize scale = _scale;
@synthesize minimumScale = _minimumScale;
@synthesize maximumScale = _maximumScale;
@synthesize gestureCount = _gestureCount;

@dynamic panEnabled;
@dynamic rotateEnabled;
@dynamic scaleEnabled;
@dynamic tapToResetEnabled;
@dynamic cropBoundsInSourceImage;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if(self) {
        _panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _rotationRecognizer = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotation:)];
        _pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
        _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        _snapToBoundsEnabled = NO;
    }
    return self;
}

- (void) dealloc
{
    [_imageView release];
    [_frameView release];
    [_doneCallback release];
    [_sourceImage release];
    [_previewImage release];
    [_panRecognizer release];
    [_rotationRecognizer release];
    [_pinchRecognizer release];
    [_tapRecognizer release];
    [super dealloc];
}

#pragma mark Properties

- (void)setCropSize:(CGSize)cropSize
{
    _cropSize = cropSize;
    [self updateCropRect];
}

- (CGSize)cropSize
{
    if(_cropSize.width == 0 || _cropSize.height == 0) {
        _cropSize = CGSizeMake(kDefaultCropWidth, kDefaultCropHeight);
    }
    return _cropSize;
}

- (UIImage *)previewImage
{
    if(_previewImage == nil && _sourceImage != nil) {
        if(self.sourceImage.size.height > kMaxUIImageSize || self.sourceImage.size.width > kMaxUIImageSize) {
            CGFloat aspect = self.sourceImage.size.height/self.sourceImage.size.width;
            CGSize size;
            if(aspect >= 1.0) { //square or portrait
                size = CGSizeMake(kPreviewImageSize,kPreviewImageSize*aspect);
            } else { // landscape
                size = CGSizeMake(kPreviewImageSize,kPreviewImageSize*aspect);
            }
            _previewImage = [[self scaledImage:self.sourceImage  toSize:size withQuality:kCGInterpolationLow] retain];
        } else {
            _previewImage = [_sourceImage retain];
        }
    }
    return  _previewImage;
}

- (void)setSourceImage:(UIImage *)sourceImage
{
    if(sourceImage != _sourceImage) {
        [_sourceImage release];
        _sourceImage = [sourceImage retain];
        self.previewImage = nil;
    }
}


- (void)updateCropRect
{
    self.cropRect = CGRectMake((self.frameView.bounds.size.width-self.cropSize.width)/2,
                               (self.frameView.bounds.size.height-self.cropSize.height)/2,
                               self.cropSize.width, self.cropSize.height);
    
    self.frameView.cropRect = self.cropRect;
}


- (void)setPanEnabled:(BOOL)panEnabled
{
    self.panRecognizer.enabled = panEnabled;
}

- (BOOL)panEnabled
{
    return self.panRecognizer.enabled;
}

- (void)setScaleEnabled:(BOOL)scaleEnabled
{
    self.pinchRecognizer.enabled = scaleEnabled;
}

- (BOOL)scaleEnabled
{
    return self.pinchRecognizer.enabled;
}


- (void)setRotateEnabled:(BOOL)rotateEnabled
{
    self.rotationRecognizer.enabled = rotateEnabled;
}

- (BOOL)rotateEnabled
{
    return self.rotationRecognizer.enabled;
}

- (void)setTapToResetEnabled:(BOOL)tapToResetEnabled
{
    self.tapRecognizer.enabled = tapToResetEnabled;
}

- (BOOL)tapToResetEnabled
{
    return self.tapToResetEnabled;
}

#pragma mark - Private Methods
- (void)doCenter:(BOOL)animated
{
    void (^doCenter)(void) = ^{
        CGAffineTransform transform =  CGAffineTransformMakeTranslation(0, 0);
        transform = CGAffineTransformScale(transform, self.imageView.transform.a, self.imageView.transform.d);
        self.imageView.transform = transform;
    };
    if(animated) {
        self.view.userInteractionEnabled = NO;
        // animation 속도 조절
        [UIView animateWithDuration:kAnimationIntervalReset delay:0 options:UIViewAnimationOptionCurveEaseOut animations:doCenter completion:^(BOOL finished) {
            self.view.userInteractionEnabled = YES;
        }];
    } else {
        doCenter();
    }
}

// 경계로 붙이기
-(void)snapToBounds:(BOOL)animated
{
    CGFloat deltaX = 0.0f;
    CGFloat deltaY = 0.0f;

    NSLog(@"가로, 정방 이미지");
    // 이미지가 왼쪽인지 오른쪽인지 판단
    if (CGRectGetMinX(self.imageView.frame) < CGRectGetMinX(self.cropRect) && CGRectGetMaxX(self.imageView.frame) > CGRectGetMaxX(self.cropRect)) {
        NSLog(@"이미지가 크롭박스 넓이를 넘어선다");
        deltaX = 0;
        if (CGRectGetHeight(self.imageView.frame) < CGRectGetHeight(self.cropRect)) {
            NSLog(@"이미지의 세로사이즈가 크롭보다 작다, 가운데로 정렬해준다.");
            deltaY = CGRectGetMidY(self.cropRect) - CGRectGetMidY(self.imageView.frame);
        }
        else {
            if (CGRectGetMinY(self.imageView.frame) < CGRectGetMinY(self.cropRect)) {
                NSLog(@"아래라인으로 정렬해준다.");
                deltaY = CGRectGetMaxY(self.cropRect) - CGRectGetMaxY(self.imageView.frame);
            }
            else {
                NSLog(@"윗라인으로 정렬해준다.");
                // 아래쪽
                deltaY = CGRectGetMinY(self.cropRect) - CGRectGetMinY(self.imageView.frame);
            }
        }
    }
    else {
        if (CGRectGetMinX(self.imageView.frame) < 0) {
            NSLog(@"이미지가 왼쪽으로 쏠려있다.");
            deltaX = CGRectGetMaxX(self.cropRect) - CGRectGetMaxX(self.imageView.frame);
        }
        else {
            NSLog(@"이미지가 오른쪽으로 쏠려있다.");
            deltaX = CGRectGetMinX(self.cropRect) - CGRectGetMinX(self.imageView.frame);
        }
        if (CGRectGetHeight(self.imageView.frame) < CGRectGetHeight(self.cropRect)) {
            NSLog(@"이미지의 세로사이즈가 크롭보다 작다, 가운데로 정렬해준다.");
            deltaY = -self.imageView.transform.ty;
        }
        else {
            if (CGRectGetMaxY(self.imageView.frame) < CGRectGetMaxY(self.cropRect)) {
                NSLog(@"아래라인으로 정렬해준다.");
                deltaY = CGRectGetMaxY(self.cropRect) - CGRectGetMaxY(self.imageView.frame);
            }
            else if (CGRectGetMinY(self.imageView.frame) > CGRectGetMinY(self.cropRect)){
                NSLog(@"윗라인으로 정렬해준다.");
                // 아래쪽
                deltaY = CGRectGetMinY(self.cropRect) - CGRectGetMinY(self.imageView.frame);
            }
            else
                deltaY = 0;
        }
    }

    [UIView animateWithDuration:kAnimationIntervalReset delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        CGAffineTransform transform =  CGAffineTransformTranslate(self.imageView.transform, deltaX/self.scale, deltaY/self.scale);
        self.imageView.transform = transform;
    } completion:^(BOOL finished) {
        self.view.userInteractionEnabled = YES;
    }];
}

#pragma mark Public methods
-(void)reset:(BOOL)animated
{
    NSLog(@"do Reset");
    CGFloat aspect = self.sourceImage.size.height/self.sourceImage.size.width;
    CGFloat w = CGRectGetWidth(self.cropRect);
    CGFloat h = aspect * w;
    self.scale = 1;
    
    void (^doReset)(void) = ^{
        self.imageView.transform = CGAffineTransformIdentity;
        self.imageView.frame = CGRectMake(CGRectGetMidX(self.cropRect) - w/2, CGRectGetMidY(self.cropRect) - h/2,w,h);
    };
    if(animated) {
        self.view.userInteractionEnabled = NO;
        // animation 속도 조절
        [UIView animateWithDuration:kAnimationIntervalReset delay:0 options:UIViewAnimationOptionCurveEaseOut animations:doReset completion:^(BOOL finished) {
            self.view.userInteractionEnabled = YES;
            NSLog(@"after imgageView frame:%@", NSStringFromCGRect(self.imageView.frame));
            NSLog(@"리셋한 이미지뷰 중심:%f, %f", CGRectGetMidX(self.imageView.frame), CGRectGetMidY(self.imageView.frame));
        }];
    } else {
        doReset();
    }
}

#pragma mark View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UIImageView *imageView = [[UIImageView alloc] init];
    [self.view insertSubview:imageView belowSubview:self.frameView];
    self.imageView = imageView;
    [imageView release];
    
    [self.view setMultipleTouchEnabled:YES];

    self.panRecognizer.cancelsTouchesInView = NO;
    self.panRecognizer.delegate = self;
    [self.frameView addGestureRecognizer:self.panRecognizer];
    self.rotationRecognizer.cancelsTouchesInView = NO;
    self.rotationRecognizer.delegate = self;
    [self.frameView addGestureRecognizer:self.rotationRecognizer];
    self.pinchRecognizer.cancelsTouchesInView = NO;
    self.pinchRecognizer.delegate = self;
    [self.frameView addGestureRecognizer:self.pinchRecognizer];
    self.tapRecognizer.numberOfTapsRequired = 2;
    [self.frameView addGestureRecognizer:self.tapRecognizer];
}


- (void)viewDidUnload
{
    [super viewDidUnload];
    
    [self setFrameView:nil];
    [self setImageView:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackTranslucent animated:YES];
    [self updateCropRect];
    [self reset:NO];
    self.imageView.image = self.previewImage;
    
    if(self.previewImage != self.sourceImage) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            CGImageRef hiresCGImage = NULL;
            CGFloat aspect = self.sourceImage.size.height/self.sourceImage.size.width;
            CGSize size;
            if(aspect >= 1.0) { //square or portrait
                size = CGSizeMake(kMaxUIImageSize*aspect,kMaxUIImageSize);
            } else { // landscape
                size = CGSizeMake(kMaxUIImageSize,kMaxUIImageSize*aspect);
            }
            hiresCGImage = [self newScaledImage:self.sourceImage.CGImage withOrientation:self.sourceImage.imageOrientation toSize:size withQuality:kCGInterpolationDefault];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.imageView.image = [UIImage imageWithCGImage:hiresCGImage scale:1.0 orientation:UIImageOrientationUp];
                CGImageRelease(hiresCGImage);
            });
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
}

#pragma mark Actions

- (IBAction)resetAction:(id)sender
{
    [self reset:NO];
}

- (IBAction)resetAnimatedAction:(id)sender
{
    [self reset:YES];
}


- (IBAction)doneAction:(id)sender
{
    self.view.userInteractionEnabled = NO;
    [self startTransformHook];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CGImageRef resultRef = [self newTransformedImage:self.imageView.transform
                                        sourceImage:self.sourceImage.CGImage
                                         sourceSize:self.sourceImage.size
                                  sourceOrientation:self.sourceImage.imageOrientation
                                        outputWidth:self.outputWidth ? self.outputWidth : self.sourceImage.size.width
                                            cropSize:self.cropSize
                                    imageViewSize:self.imageView.bounds.size];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImage *transform =  [UIImage imageWithCGImage:resultRef scale:1.0 orientation:UIImageOrientationUp];
            CGImageRelease(resultRef);
            self.view.userInteractionEnabled = YES;
            if(self.doneCallback) {
                self.doneCallback(transform, NO);
            }
            [self endTransformHook];
        });
    });

}


- (IBAction)cancelAction:(id)sender
{
    if(self.doneCallback) {
        self.doneCallback(nil, YES);
    }
}

#pragma mark Touches

- (void)handleTouches:(NSSet*)touches
{
    self.touchCenter = CGPointZero;
    if(touches.count < 2) return;
    
    [touches enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
        UITouch *touch = (UITouch*)obj;
        CGPoint touchLocation = [touch locationInView:self.imageView];
        self.touchCenter = CGPointMake(self.touchCenter.x + touchLocation.x, self.touchCenter.y +touchLocation.y);
    }];
    self.touchCenter = CGPointMake(self.touchCenter.x/touches.count, self.touchCenter.y/touches.count);
}

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self handleTouches:[event allTouches]];
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
//    NSLog(@"핸들터치 tx, ty : %f, %f", self.imageView.transform.tx, self.imageView.transform.ty);
    [self handleTouches:[event allTouches]];
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
   [self handleTouches:[event allTouches]];
}

-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
   [self handleTouches:[event allTouches]];
}

#pragma mark Gestures

- (BOOL)handleGestureState:(UIGestureRecognizerState)state
{
    BOOL handle = YES;
    switch (state) {
        case UIGestureRecognizerStateBegan:
            self.gestureCount++;
            break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded: {
            self.gestureCount--;
            handle = NO;
            if(self.gestureCount == 0) {
                CGFloat scale = self.scale;
                if(self.minimumScale != 0 && self.scale < self.minimumScale) {
                    scale = self.minimumScale;
                } else
                if(self.maximumScale != 0 && self.scale > self.maximumScale) {
                    scale = self.maximumScale;
                }
                if(scale != self.scale) {
                    NSLog(@"스케일이 제한에 따른 처리, 비교스케일:%f, 현재스케일:%f", scale, self.scale);
                    CGFloat deltaX = self.scaleCenter.x-self.imageView.bounds.size.width/2.0;
                    CGFloat deltaY = self.scaleCenter.y-self.imageView.bounds.size.height/2.0;

                    CGAffineTransform transform;
                    if (self.scale < scale) {
                        transform =  CGAffineTransformMakeTranslation(0, 0);
                    }
                    else {
                        transform =  CGAffineTransformTranslate(self.imageView.transform, deltaX, deltaY);
                        transform = CGAffineTransformScale(transform, scale/self.scale , scale/self.scale);
                        transform = CGAffineTransformTranslate(transform, -deltaX, -deltaY);
                    }

                    self.view.userInteractionEnabled = NO;
                    [UIView animateWithDuration:kAnimationIntervalTransform delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                        self.imageView.transform = transform;
                    } completion:^(BOOL finished) {
                        self.view.userInteractionEnabled = YES;
                        self.scale = scale;
                    }];
                    break;
                }

                if (self.snapToBoundsEnabled) {
                    // 이미지가 프레임을 벗어났을때
                    if (CGRectContainsRect(self.imageView.frame, self.cropRect)) {
                        NSLog(@"이미지가 크롭뷰를 덮으면 아무것도 하지 않음");
                    }
                    else {
                        NSLog(@"이미지뷰가 크롭뷰를 덥고 있지 않음");
                        if (CGRectContainsRect(self.cropRect, self.imageView.frame)) {
                            NSLog(@"이미지가 크롭뷰안에 있음 (내부에 있고, 이미지뷰가 충분히 작음)");
                            NSLog(@"이 경우 이미지를 가운데로 리셋 시켜버림");
                            [self reset:YES];
                        }
                        else {
                            NSLog(@"이미지가 크롭뷰를 벗어남");
                            [self snapToBounds:YES];
                        }
                    }
                }
            }
        } break;
        default:
            break;
    }
    return handle;
}


- (IBAction)handlePan:(UIPanGestureRecognizer*)recognizer
{
    if([self handleGestureState:recognizer.state]) {
        CGPoint translation = [recognizer translationInView:self.imageView];
        CGAffineTransform transform = CGAffineTransformTranslate(self.imageView.transform, translation.x, translation.y);
        self.imageView.transform = transform;
        NSLog(@"now transform:%@", NSStringFromCGAffineTransform(self.imageView.transform));
        [recognizer setTranslation:CGPointMake(0, 0) inView:self.frameView];
    }

}

- (IBAction)handleRotation:(UIRotationGestureRecognizer*)recognizer
{
    if([self handleGestureState:recognizer.state]) {
        if(recognizer.state == UIGestureRecognizerStateBegan){
            self.rotationCenter = self.touchCenter;
        } 
        CGFloat deltaX = self.rotationCenter.x-self.imageView.bounds.size.width/2;
        CGFloat deltaY = self.rotationCenter.y-self.imageView.bounds.size.height/2;

        CGAffineTransform transform =  CGAffineTransformTranslate(self.imageView.transform,deltaX,deltaY);
        transform = CGAffineTransformRotate(transform, recognizer.rotation);
        transform = CGAffineTransformTranslate(transform, -deltaX, -deltaY);
        self.imageView.transform = transform;

        recognizer.rotation = 0;
    }

}

- (IBAction)handlePinch:(UIPinchGestureRecognizer *)recognizer
{
    if([self handleGestureState:recognizer.state]) {
        if(recognizer.state == UIGestureRecognizerStateBegan){
            self.scaleCenter = self.touchCenter;
        }
        CGFloat deltaX = self.scaleCenter.x-self.imageView.bounds.size.width/2.0;
        CGFloat deltaY = self.scaleCenter.y-self.imageView.bounds.size.height/2.0;

        CGAffineTransform transform =  CGAffineTransformTranslate(self.imageView.transform,deltaX,deltaY);
        transform = CGAffineTransformScale(transform, recognizer.scale, recognizer.scale);
        transform = CGAffineTransformTranslate(transform, -deltaX, -deltaY);
        self.scale *= recognizer.scale;
        self.imageView.transform = transform;

        recognizer.scale = 1;
    }
}

- (IBAction)handleTap:(UITapGestureRecognizer *)recogniser {
    [self reset:YES];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

# pragma mark Image Transformation


- (UIImage *)scaledImage:(UIImage *)source toSize:(CGSize)size withQuality:(CGInterpolationQuality)quality
{
    CGImageRef cgImage  = [self newScaledImage:source.CGImage withOrientation:source.imageOrientation toSize:size withQuality:quality];
    UIImage * result = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return result;
}


- (CGImageRef)newScaledImage:(CGImageRef)source withOrientation:(UIImageOrientation)orientation toSize:(CGSize)size withQuality:(CGInterpolationQuality)quality
{
    CGSize srcSize = size;
    CGFloat rotation = 0.0;
    
    switch(orientation)
    {
        case UIImageOrientationUp: {
            rotation = 0;
        } break;
        case UIImageOrientationDown: {
            rotation = M_PI;
        } break;
        case UIImageOrientationLeft:{
            rotation = M_PI_2;
            srcSize = CGSizeMake(size.height, size.width);
        } break;
        case UIImageOrientationRight: {
            rotation = -M_PI_2;
            srcSize = CGSizeMake(size.height, size.width);
        } break;
        default:
            break;
    }
    
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 size.width,
                                                 size.height,
                                                 8, //CGImageGetBitsPerComponent(source),
                                                 0,
                                                 CGImageGetColorSpace(source),
                                                 kCGImageAlphaNoneSkipFirst//CGImageGetBitmapInfo(source)
                                                 );
    
    CGContextSetInterpolationQuality(context, quality);
    CGContextTranslateCTM(context,  size.width/2,  size.height/2);
    CGContextRotateCTM(context,rotation);
    
    CGContextDrawImage(context, CGRectMake(-srcSize.width/2 ,
                                           -srcSize.height/2,
                                           srcSize.width,
                                           srcSize.height),
                       source);
    
    CGImageRef resultRef = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    return resultRef;
}

- (CGImageRef)newTransformedImage:(CGAffineTransform)transform
                     sourceImage:(CGImageRef)sourceImage
                    sourceSize:(CGSize)sourceSize
           sourceOrientation:(UIImageOrientation)sourceOrientation
                 outputWidth:(CGFloat)outputWidth
                    cropSize:(CGSize)cropSize
               imageViewSize:(CGSize)imageViewSize
{
    CGImageRef source = [self newScaledImage:sourceImage
                             withOrientation:sourceOrientation
                                      toSize:sourceSize
                                 withQuality:kCGInterpolationNone];

    NSLog(@"이미지소스 사이즈:%@", NSStringFromCGSize(sourceSize));
    NSLog(@"이미지뷰 사이즈:%@", NSStringFromCGSize(imageViewSize));
    NSLog(@"이미지뷰 스케일:%f, %f", transform.a, transform.d);
    
    CGSize scaledImageViewSize = CGSizeMake(imageViewSize.width * transform.a, imageViewSize.height * transform.d);
    NSLog(@"이미지뷰 실제 사이즈:%@", NSStringFromCGSize(scaledImageViewSize));
    NSLog(@"크롭뷰 사이즈:%@", NSStringFromCGSize(cropSize));

    CGFloat aspect = sourceSize.height/sourceSize.width;
    NSLog(@"%@", aspect>=1?@"세로이미지":@"가로이미지");

    // 크롭뷰사이즈보다 이미지뷰가 충분히 크지 않으면, 크롭뷰 사이즈를 이미지 사이즈로 재설정 해준다.
    if (scaledImageViewSize.width < cropSize.width || scaledImageViewSize.height < cropSize.width) {
        // 가로사진
        if (aspect <= 1) {
            cropSize = CGSizeMake(cropSize.width, scaledImageViewSize.height);
        }
        // 세로사진
        else {
            cropSize = CGSizeMake(scaledImageViewSize.width, cropSize.height);
        }
        NSLog(@"새로운 크롭뷰 사이즈:%@", NSStringFromCGSize(cropSize));
    }

    aspect = cropSize.height/cropSize.width;
    CGSize outputSize = CGSizeMake(outputWidth, outputWidth*aspect);
    NSLog(@"최종 outputSize:%@", NSStringFromCGSize(outputSize));

    NSLog(@"output사이지 비트맵context생성");
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 outputSize.width,
                                                 outputSize.height,
                                                 CGImageGetBitsPerComponent(source),
                                                 0,
                                                 CGImageGetColorSpace(source),
                                                 CGImageGetBitmapInfo(source));
    CGContextSetFillColorWithColor(context, [[UIColor clearColor] CGColor]);

    CGContextFillRect(context, CGRectMake(0, 0, outputSize.width, outputSize.height));

    CGAffineTransform uiCoords = CGAffineTransformMakeScale(outputSize.width/cropSize.width,
                                                            outputSize.height/cropSize.height);
    uiCoords = CGAffineTransformTranslate(uiCoords, cropSize.width/2.0, cropSize.height/2.0);
    // 좌표게변환, 뒤집어 나오느걸 방지
    uiCoords = CGAffineTransformScale(uiCoords, 1.0, -1.0);
    CGContextConcatCTM(context, uiCoords);
    
    CGContextConcatCTM(context, transform);
    CGContextScaleCTM(context, 1.0, -1.0);
    
    CGContextDrawImage(context, CGRectMake(-imageViewSize.width/2.0,
                                           -imageViewSize.height/2.0,
                                           imageViewSize.width,
                                           imageViewSize.height)
                       ,source);
    
    CGImageRef resultRef = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(source);
    return resultRef;
}

- (CGRect)cropBoundsInSourceImage
{
    CGAffineTransform uiCoords = CGAffineTransformMakeScale(self.sourceImage.size.width/self.imageView.bounds.size.width,
                                                            self.sourceImage.size.height/self.imageView.bounds.size.height);
    uiCoords = CGAffineTransformTranslate(uiCoords, self.imageView.bounds.size.width/2.0, self.imageView.bounds.size.height/2.0);
    uiCoords = CGAffineTransformScale(uiCoords, 1.0, -1.0);

    CGRect crop =  CGRectMake(-self.cropSize.width/2.0, -self.cropSize.height/2.0, self.cropSize.width, self.cropSize.height);
    return CGRectApplyAffineTransform(crop, CGAffineTransformConcat(CGAffineTransformInvert(self.imageView.transform),uiCoords));
}


#pragma mark Subclass Hooks

- (void)startTransformHook
{
}

- (void)endTransformHook
{
}



@end
