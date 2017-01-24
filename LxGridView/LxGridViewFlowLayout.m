//
//  LxGridViewFlowLayout.m
//  LxGridView
//

#import "LxGridView.h"


static CGFloat const PRESS_TO_MOVE_MIN_DURATION = 0.1;
static CGFloat const MIN_PRESS_TO_BEGIN_EDITING_DURATION = 0.6;

CG_INLINE CGPoint CGPointOffset(CGPoint point, CGFloat dx, CGFloat dy)
{
    return CGPointMake(point.x + dx, point.y + dy);
}

@interface LxGridViewFlowLayout () <UIGestureRecognizerDelegate>

/// getter overrided
@property (nonatomic,readonly) id<LxGridViewDataSource> dataSource;
@property (nonatomic,readonly) id<LxGridViewDelegateFlowLayout> delegate;

/// getter setter overrided
@property (nonatomic,assign) BOOL editing;

@end

@implementation LxGridViewFlowLayout
{
    // ges
    UILongPressGestureRecognizer * _longPressGestureRecognizer;
    UIPanGestureRecognizer * _panGestureRecognizer;
    
    // 当前正在移动的项
    NSIndexPath * _movingItemIndexPath;
    UIView * _beingMovedPromptView;
    
    // 正在拖拽的cell的中心
    CGPoint _sourceItemCollectionViewCellCenter;
    
    CADisplayLink * _displayLink;
    CFTimeInterval _remainSecondsToBeginEditing;
}

#pragma mark - setup

/// 移除手势 通知
- (void)dealloc
{
    [_displayLink invalidate];
    
    [self removeGestureRecognizers];
    [self removeObserver:self forKeyPath:@stringify(collectionView)];
}

- (instancetype)init
{
    if (self = [super init]) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        [self setup];
    }
    return self;
}

/// 监听collectionView属性
- (void)setup
{
    [self addObserver:self forKeyPath:@stringify(collectionView) options:NSKeyValueObservingOptionNew context:nil];
}

/// longPressGestureRecognizerTriggerd _panGestureRecognizer UIApplicationWillResignActiveNotification
- (void)addGestureRecognizers
{
    self.collectionView.userInteractionEnabled = YES;
    
    _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(longPressGestureRecognizerTriggerd:)];
    _longPressGestureRecognizer.cancelsTouchesInView = NO;
    // 0.1秒就触发
    _longPressGestureRecognizer.minimumPressDuration = PRESS_TO_MOVE_MIN_DURATION;
    _longPressGestureRecognizer.delegate = self;
    
    for (UIGestureRecognizer * gestureRecognizer in self.collectionView.gestureRecognizers) {
        if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
            [gestureRecognizer requireGestureRecognizerToFail:_longPressGestureRecognizer];
        }
    }
    
    [self.collectionView addGestureRecognizer:_longPressGestureRecognizer];
    
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panGestureRecognizerTriggerd:)];
    _panGestureRecognizer.delegate = self;
    [self.collectionView addGestureRecognizer:_panGestureRecognizer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
}

/// 移除手势 通知
- (void)removeGestureRecognizers
{
    if (_longPressGestureRecognizer) {
        if (_longPressGestureRecognizer.view) {
            [_longPressGestureRecognizer.view removeGestureRecognizer:_longPressGestureRecognizer];
        }
        _longPressGestureRecognizer = nil;
    }
    
    if (_panGestureRecognizer) {
        if (_panGestureRecognizer.view) {
            [_panGestureRecognizer.view removeGestureRecognizer:_panGestureRecognizer];
        }
        _panGestureRecognizer = nil;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
}

#pragma mark - getter and setter implementation

- (id<LxGridViewDataSource>)dataSource
{
    return (id<LxGridViewDataSource>)self.collectionView.dataSource;
}

- (id<LxGridViewDelegateFlowLayout>)delegate
{
    return (id<LxGridViewDelegateFlowLayout>)self.collectionView.delegate;
}

- (void)setEditing:(BOOL)editing
{
    NSCAssert([self.collectionView isKindOfClass:[LxGridView class]] || self.collectionView == nil, @"LxGridViewFlowLayout: Must use LxGridView as your collectionView class!");
    LxGridView * gridView = (LxGridView *)self.collectionView;
    gridView.editing = editing;
}

- (BOOL)editing
{
    NSCAssert([self.collectionView isKindOfClass:[LxGridView class]] || self.collectionView == nil, @"LxGridViewFlowLayout: Must use LxGridView as your collectionView class!");
    LxGridView * gridView = (LxGridView *)self.collectionView;
    return gridView.editing;
}

#pragma mark - override UICollectionViewLayout methods

/// 当前正在移动的是隐藏状态

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSArray * layoutAttributesForElementsInRect = [super layoutAttributesForElementsInRect:rect];
    
    for (UICollectionViewLayoutAttributes * layoutAttributes in layoutAttributesForElementsInRect) {
        
        if (layoutAttributes.representedElementCategory == UICollectionElementCategoryCell) {
            layoutAttributes.hidden = [layoutAttributes.indexPath isEqual:_movingItemIndexPath];
        }
    }
    return layoutAttributesForElementsInRect;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewLayoutAttributes * layoutAttributes = [super layoutAttributesForItemAtIndexPath:indexPath];
    if (layoutAttributes.representedElementCategory == UICollectionElementCategoryCell) {
        layoutAttributes.hidden = [layoutAttributes.indexPath isEqual:_movingItemIndexPath];
    }
    return layoutAttributes;
}

#pragma mark - gesture

- (void)setPanGestureRecognizerEnable:(BOOL)panGestureRecognizerEnable
{
    _panGestureRecognizer.enabled = panGestureRecognizerEnable;
}

- (BOOL)panGestureRecognizerEnable
{
    return _panGestureRecognizer.enabled;
}

- (void)longPressGestureRecognizerTriggerd:(UILongPressGestureRecognizer *)longPress
{
    switch (longPress.state) {
        case UIGestureRecognizerStatePossible:
            break;
        case UIGestureRecognizerStateBegan:
        {
            // 开启定时器
            if (_displayLink == nil) {
                _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkTriggered:)];
                _displayLink.frameInterval = 6;
                [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

                _remainSecondsToBeginEditing = MIN_PRESS_TO_BEGIN_EDITING_DURATION;
            }
            
            // 第一次触发 到这里就结束 然后 定时器的回调会将editing设为YES
            if (self.editing == NO) {
                return;
            }
            
            _movingItemIndexPath = [self.collectionView indexPathForItemAtPoint:[longPress locationInView:self.collectionView]];
            
            // 不能移动
            if ([self.dataSource respondsToSelector:@selector(collectionView:canMoveItemAtIndexPath:)] && [self.dataSource collectionView:self.collectionView canMoveItemAtIndexPath:_movingItemIndexPath] == NO) {
                _movingItemIndexPath = nil;
                return;
            }
            
            // 即将开始拖动
            if ([self.delegate respondsToSelector:@selector(collectionView:layout:willBeginDraggingItemAtIndexPath:)]) {
                [self.delegate collectionView:self.collectionView layout:self willBeginDraggingItemAtIndexPath:_movingItemIndexPath];
            }
            
            // 取出目标cell+类型检查
            UICollectionViewCell * sourceCollectionViewCell = [self.collectionView cellForItemAtIndexPath:_movingItemIndexPath];
            NSCAssert([sourceCollectionViewCell isKindOfClass:[LxGridViewCell class]] || sourceCollectionViewCell == nil, @"LxGridViewFlowLayout: Must use LxGridViewCell as your collectionViewCell class!");
            LxGridViewCell * sourceGridViewCell = (LxGridViewCell *)sourceCollectionViewCell;
            
            // 创建快照视图
            _beingMovedPromptView = [[UIView alloc]initWithFrame:CGRectOffset(sourceCollectionViewCell.frame, -LxGridView_DELETE_RADIUS, -LxGridView_DELETE_RADIUS)];
            
            sourceCollectionViewCell.highlighted = YES;
            UIView * highlightedSnapshotView = [sourceGridViewCell snapshotView];
            highlightedSnapshotView.frame = sourceGridViewCell.bounds;
            highlightedSnapshotView.alpha = 1;

            sourceCollectionViewCell.highlighted = NO;
            UIView * snapshotView = [sourceGridViewCell snapshotView];
            snapshotView.frame = sourceGridViewCell.bounds;
            snapshotView.alpha = 0;
            
            [_beingMovedPromptView addSubview:snapshotView];
            [_beingMovedPromptView addSubview:highlightedSnapshotView];
            [self.collectionView addSubview:_beingMovedPromptView];
            
            // 快照视图添加震动动画
            static NSString * const kVibrateAnimation = @stringify(kVibrateAnimation);
            static CGFloat const VIBRATE_DURATION = 0.1;
            static CGFloat const VIBRATE_RADIAN = M_PI / 96;
            
            CABasicAnimation * vibrateAnimation = [CABasicAnimation animationWithKeyPath:@stringify(transform.rotation.z)];
            vibrateAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            vibrateAnimation.fromValue = @(- VIBRATE_RADIAN);
            vibrateAnimation.toValue = @(VIBRATE_RADIAN);
            vibrateAnimation.autoreverses = YES;
            vibrateAnimation.duration = VIBRATE_DURATION;
            vibrateAnimation.repeatCount = CGFLOAT_MAX;
            [_beingMovedPromptView.layer addAnimation:vibrateAnimation forKey:kVibrateAnimation];
            
            // 移动的cell的center
            _sourceItemCollectionViewCellCenter = sourceCollectionViewCell.center;
            
            // 动画0？。。。 通知代理开始拖拽
            typeof(self) __weak weakSelf = self;
            [UIView animateWithDuration:0
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState
                             animations:^{

                                 typeof(self) __strong strongSelf = weakSelf;
                                 if (strongSelf) {
                                     highlightedSnapshotView.alpha = 0;
                                     snapshotView.alpha = 1;
                                 }
                             }
                             completion:^(BOOL finished) {
                                 
                                 typeof(self) __strong strongSelf = weakSelf;
                                 if (strongSelf) {
                                     [highlightedSnapshotView removeFromSuperview];
                                     
                                     if ([strongSelf.delegate respondsToSelector:@selector(collectionView:layout:didBeginDraggingItemAtIndexPath:)]) {
                                         [strongSelf.delegate collectionView:strongSelf.collectionView layout:strongSelf didBeginDraggingItemAtIndexPath:_movingItemIndexPath];
                                     }
                                 }
                             }];
            
            // 重新布局 这样会使目标cell隐藏
            [self invalidateLayout];
        }
            break;
        case UIGestureRecognizerStateChanged:
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        {
            // 取消定时器
            [_displayLink invalidate];
            _displayLink = nil;
            
            NSIndexPath * movingItemIndexPath = _movingItemIndexPath;
            
            if (movingItemIndexPath) {
                /// 即将停止拖拽
                if ([self.delegate respondsToSelector:@selector(collectionView:layout:willEndDraggingItemAtIndexPath:)]) {
                    [self.delegate collectionView:self.collectionView layout:self willEndDraggingItemAtIndexPath:movingItemIndexPath];
                }
                
                _movingItemIndexPath = nil;
                _sourceItemCollectionViewCellCenter = CGPointZero;
                
                UICollectionViewLayoutAttributes * movingItemCollectionViewLayoutAttributes = [self layoutAttributesForItemAtIndexPath:movingItemIndexPath];
                
                // 动画的时候不触发长按手势
                _longPressGestureRecognizer.enabled = NO;
                
                // 还原 然后移除cell的快照 invalidateLayout重新布局 调用代理方法
                typeof(self) __weak weakSelf = self;
                [UIView animateWithDuration:0
                                      delay:0
                                    options:UIViewAnimationOptionBeginFromCurrentState
                                 animations:^{
                                     typeof(self) __strong strongSelf = weakSelf;
                                     if (strongSelf) {
                                         _beingMovedPromptView.center = movingItemCollectionViewLayoutAttributes.center;
                                     }
                                 }
                                 completion:^(BOOL finished) {

                                     _longPressGestureRecognizer.enabled = YES;
                                     
                                     typeof(self) __strong strongSelf = weakSelf;
                                     if (strongSelf) {
                                         [_beingMovedPromptView removeFromSuperview];
                                         _beingMovedPromptView = nil;
                                         [strongSelf invalidateLayout];
                                         
                                         if ([strongSelf.delegate respondsToSelector:@selector(collectionView:layout:didEndDraggingItemAtIndexPath:)]) {
                                             [strongSelf.delegate collectionView:strongSelf.collectionView layout:strongSelf didEndDraggingItemAtIndexPath:movingItemIndexPath];
                                         }
                                     }
                                 }];
            }
        }
            break;
        case UIGestureRecognizerStateFailed:
            break;
        default:
            break;
    }
}

- (void)panGestureRecognizerTriggerd:(UIPanGestureRecognizer *)pan
{
    switch (pan.state) {
        case UIGestureRecognizerStatePossible:
            break;
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
        {
            // 偏移
            CGPoint panTranslation = [pan translationInView:self.collectionView];
            // 设置快照的中心
            _beingMovedPromptView.center = CGPointOffset(_sourceItemCollectionViewCellCenter, panTranslation.x, panTranslation.y);
            
            NSIndexPath * sourceIndexPath = _movingItemIndexPath;
            NSIndexPath * destinationIndexPath = [self.collectionView indexPathForItemAtPoint:_beingMovedPromptView.center];
            
            // 是否可以替换
            if ((destinationIndexPath == nil) || [destinationIndexPath isEqual:sourceIndexPath]) {
                return;
            }
            if ([self.dataSource respondsToSelector:@selector(collectionView:itemAtIndexPath:canMoveToIndexPath:)] && [self.dataSource collectionView:self.collectionView itemAtIndexPath:sourceIndexPath canMoveToIndexPath:destinationIndexPath] == NO) {
                return;
            }
            
            // 通知代理
            if ([self.dataSource respondsToSelector:@selector(collectionView:itemAtIndexPath:willMoveToIndexPath:)]) {
                [self.dataSource collectionView:self.collectionView itemAtIndexPath:sourceIndexPath willMoveToIndexPath:destinationIndexPath];
            }
            
            // 替换位置
            _movingItemIndexPath = destinationIndexPath;
            typeof(self) __weak weakSelf = self;
            [self.collectionView performBatchUpdates:^{
                typeof(self) __strong strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf.collectionView deleteItemsAtIndexPaths:@[sourceIndexPath]];
                    [strongSelf.collectionView insertItemsAtIndexPaths:@[destinationIndexPath]];
                }
            } completion:^(BOOL finished) {
                typeof(self) __strong strongSelf = weakSelf;
                if ([strongSelf.dataSource respondsToSelector:@selector(collectionView:itemAtIndexPath:didMoveToIndexPath:)]) {
                    [strongSelf.dataSource collectionView:strongSelf.collectionView itemAtIndexPath:sourceIndexPath didMoveToIndexPath:destinationIndexPath];
                }
            }];
        }
            break;
        case UIGestureRecognizerStateEnded:
            break;
        case UIGestureRecognizerStateCancelled:
            break;
        case UIGestureRecognizerStateFailed:
            break;
        default:
            break;
    }
}

/// 拖拽手势只有编辑时且_movingItemIndexPath不为空才触发
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if ([_panGestureRecognizer isEqual:gestureRecognizer] && self.editing) {
        return _movingItemIndexPath != nil;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    //  only _longPressGestureRecognizer and _panGestureRecognizer can recognize simultaneously
    if ([_longPressGestureRecognizer isEqual:gestureRecognizer]) {
        return [_panGestureRecognizer isEqual:otherGestureRecognizer];
    }
    if ([_panGestureRecognizer isEqual:gestureRecognizer]) {
        return [_longPressGestureRecognizer isEqual:otherGestureRecognizer];
    }
    return NO;
}

#pragma mark - displayLink

// 定时器回调 6帧一次 长按手势触发时会开启定时器
// _remainSecondsToBeginEditing - 0.1 直到小于0 editing设为YES 然后停止计时器
- (void)displayLinkTriggered:(CADisplayLink *)displayLink
{
    if (_remainSecondsToBeginEditing <= 0) {
        
        self.editing = YES;
        [_displayLink invalidate];
        _displayLink = nil;
    }
    
    _remainSecondsToBeginEditing = _remainSecondsToBeginEditing - 0.1;
}

#pragma mark - KVO and notification

/// 添加/移除 手势、通知
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@stringify(collectionView)]) {
        if (self.collectionView) {
            [self addGestureRecognizers];
        }
        else {
            [self removeGestureRecognizers];
        }
    }
}

/// 停止手势再启用？
- (void)applicationWillResignActive:(NSNotification *)notificaiton
{
    _panGestureRecognizer.enabled = NO;
    _panGestureRecognizer.enabled = YES;
}

@end
