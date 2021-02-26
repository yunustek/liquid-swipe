//
//  LiquidSwipeContainerManager.swift
//  liquid-swipe
//
//  Created by Yunus Tek on 26.02.2021.
//

import UIKit
import pop

public protocol LiquidSwipeDataSource {
    func numberOfControllersInLiquidSwipeContainer(_ liquidSwipeContainer: UIViewController) -> Int
    func liquidSwipeContainer(_ liquidSwipeContainer: UIViewController, viewControllerAtIndex index: Int) -> UIView
}

public protocol LiquidSwipeDelegate {
    func liquidSwipeContainer(_ liquidSwipeContainer: UIViewController, willTransitionTo: UIView)
    func liquidSwipeContainer(_ liquidSwipeContainer: UIViewController, didFinishTransitionTo: UIView, transitionCompleted: Bool)
}

public struct LiquidSwipeOptions {

    public static var shared = LiquidSwipeOptions()

    /// Current page index number. Default is 0
    public var currentPageIndex: Int = 0

    /// Initial horizontal radius. Default is 48.0
    public var initialHorRadius: CGFloat = 48.0

    /// Maximum horizontal radius percentage. Default is 0.8
    public var maxHorRadiusPerc: CGFloat = 0.8

    /// Initial vertical radius. Default is 82.0
    public var initialVertRadius: CGFloat = 82.0

    /// Initial side width. Default is 15.0
    public var initialSideWidthValue: CGFloat = 15.0

    /// Initial wave center percentage. Default is 0.7
    public var initialWaveCenterPerc: CGFloat = 0.7

    /// Maximum radius change percentage. Default is 0.45
    public var maxRadiusChangePerc: CGFloat = 0.45

    /// Should finish for right gesture after progress. Default is 0.15
    public var shouldFinishRightProgress: CGFloat = 0.15

    /// Should finish for left gesture after progress. Default is 0.40
    public var shouldFinishLeftProgress: CGFloat = 0.40

    /// Pan gesture will be active and swipe left/right will disable when is setting true. Default is false
    public var enablePanGesture: Bool = false

    /// Next button image
    public var btnNextImage: UIImage? = UIImage(named: "btnNext.png", in: Bundle.resourseBundle, compatibleWith: nil)
}

// MARK: - Manager

open class LiquidSwipeContainerManager: NSObject {

    public var datasource: LiquidSwipeDataSource?
    public var delegate: LiquidSwipeDelegate?
    
    private var containerViewController: UIViewController
    private var options: LiquidSwipeOptions!
    private var view: UIView {
        return containerViewController.view
    }
    private var currentView: UIView?
    private var nextView: UIView?
    private var previousView: UIView?
    private var maxHorRadius: CGFloat {
        return view.bounds.width * options.maxHorRadiusPerc
    }

    private var maxVertRadius: CGFloat {
        return view.bounds.height * 0.9
    }
    private var initialSideWidth: CGFloat {
        if #available(iOS 11.0, *) {
            return options.initialSideWidthValue + view.safeAreaInsets.right
        }
        return options.initialSideWidthValue
    }
    private var initialWaveCenter: CGFloat {
        return view.bounds.height * options.initialWaveCenterPerc
    }
    private var animationStartTime: CFTimeInterval?
    private var animating: Bool = false
    private var duration: CFTimeInterval = 0.8
    private var btnNext: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        return button
    }()
    private var rightEdgeGesture = UIScreenEdgePanGestureRecognizer()
    private var leftEdgeGesture = UIScreenEdgePanGestureRecognizer()
    private var panGesture = UIPanGestureRecognizer()
    private var csBtnNextLeading: NSLayoutConstraint?
    private var csBtnNextCenterY: NSLayoutConstraint?
    private var leftEdgeGestureIsEnabled = false

    public init(container: UIViewController, options: LiquidSwipeOptions? = nil) {

        self.delegate = container as? LiquidSwipeDelegate
        self.datasource = container as? LiquidSwipeDataSource
        self.containerViewController = container
        self.options = options ?? LiquidSwipeOptions.shared

        super.init()

        configure()
    }

    private func configure() {

        configureBtnNext()
        configureGestures()
        configureInitialState()
    }

    private func configureBtnNext() {
        view.addSubview(btnNext)
        csBtnNextLeading = btnNext.leadingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(options.initialHorRadius + initialSideWidth) + 8.0)
        csBtnNextLeading?.isActive = true
        csBtnNextCenterY = btnNext.centerYAnchor.constraint(equalTo: view.topAnchor, constant: initialWaveCenter)
        csBtnNextCenterY?.isActive = true
        btnNext.addTarget(self, action: #selector(btnTapped(_:)), for: .touchUpInside)
        btnNext.setImage(options.btnNextImage, for: .normal)
    }

    private func configureGestures() {

        if options.enablePanGesture {

            panGesture.addTarget(self, action: #selector(pan))
            view.addGestureRecognizer(panGesture)
            panGesture.isEnabled = options.enablePanGesture
        } else {

            rightEdgeGesture.addTarget(self, action: #selector(rightEdgePan))
            rightEdgeGesture.edges = .right
            view.addGestureRecognizer(rightEdgeGesture)

            leftEdgeGesture.addTarget(self, action: #selector(leftEdgePan))
            leftEdgeGesture.edges = .left
            view.addGestureRecognizer(leftEdgeGesture)
            leftEdgeGesture.isEnabled = leftEdgeGestureIsEnabled
        }
    }

    private func animate(view: UIView, forProgress progress: CGFloat, waveCenterY: CGFloat? = nil) {
        guard let mask = view.layer.mask as? WaveLayer else {
            return
        }
        if let centerY = waveCenterY {
            mask.waveCenterY = centerY
            csBtnNextCenterY?.constant = centerY
        }
        btnNext.alpha = btnAlpha(forProgress: progress)
        mask.sideWidth = sideWidth(forProgress: progress)
        mask.waveHorRadius = waveHorRadius(forProgress: progress)
        mask.waveVertRadius = waveVertRadius(forProgress: progress)
        csBtnNextLeading?.constant = -(mask.waveHorRadius + mask.sideWidth - 8.0)
        mask.updatePath()

        self.btnNext.layoutIfNeeded()
    }

    private func animateBack(view: UIView, forProgress progress: CGFloat, waveCenterY: CGFloat? = nil) {
        guard let mask = view.layer.mask as? WaveLayer else {
            return
        }
        if let centerY = waveCenterY {
            mask.waveCenterY = centerY
        }
        mask.sideWidth = sideWidth(forProgress: progress)
        mask.waveHorRadius = waveHorRadiusBack(forProgress: progress)
        mask.waveVertRadius = waveVertRadius(forProgress: progress)
        mask.updatePath()
        self.btnNext.layoutIfNeeded()
    }


    private var shouldFinish: Bool = false
    private var shouldCancel: Bool = false
    private var animationProgress: CGFloat = 0.0
    @objc private func rightEdgePan(_ sender: UIPanGestureRecognizer) {
        guard !animating else {
            return
        }
        if sender.state == .began {
            shouldCancel = false
            shouldFinish = false
            animating = true
            if let viewController = nextView {
                delegate?.liquidSwipeContainer(containerViewController, willTransitionTo: viewController)
            }
            let animation = POPCustomAnimation { [weak self, weak sender] (target, animation) -> Bool in
                guard let self = self else { return false }

                guard let gesture = sender,
                      let view = target as? UIView,
                      let mask = view.layer.mask as? WaveLayer,
                      let time = animation?.elapsedTime else {
                    if let viewController = self.nextView {
                        self.delegate?.liquidSwipeContainer(self.containerViewController, didFinishTransitionTo: viewController, transitionCompleted: false)
                    }
                    return false
                }
                let speed: CGFloat = 2000
                let direction: CGFloat = (gesture.location(in: view).y - mask.waveCenterY).sign == .plus ? 1 : -1
                let distance = min(CGFloat(time) * speed, abs(mask.waveCenterY - gesture.location(in: view).y))
                let centerY = mask.waveCenterY + distance * direction
                let change = -gesture.translation(in: view).x
                let maxChange: CGFloat = self.view.bounds.width * (1.0/self.options.maxRadiusChangePerc)
                if !(self.shouldFinish || self.shouldCancel) {
                    let progress: CGFloat = min(1.0, max(0, change / maxChange))
                    self.animate(view: view, forProgress: progress, waveCenterY: centerY)
                    switch gesture.state {
                    case .began, .changed:
                        return true
                    default:
                        if progress >= self.options.shouldFinishRightProgress {
                            self.shouldFinish = true
                            self.shouldCancel = false
                            self.animationStartTime = CACurrentMediaTime() - CFTimeInterval(CGFloat(self.duration) * progress)
                        } else {
                            self.shouldFinish = false
                            self.shouldCancel = true
                            self.animationProgress = progress
                            self.animationStartTime = CACurrentMediaTime()
                        }
                    }
                }
                let cTime = (animation?.currentTime ?? CACurrentMediaTime()) - (self.animationStartTime ?? CACurrentMediaTime())
                if self.shouldFinish {
                    let progress = CGFloat(cTime/self.duration)
                    self.animate(view: view, forProgress: progress)
                    self.animating = progress <= 1.0
                    return self.animating
                } else if self.shouldCancel {
                    let progress = self.animationProgress - CGFloat(cTime/self.duration)
                    let direction: CGFloat = (self.initialWaveCenter - mask.waveCenterY).sign == .plus ? 1 : -1
                    let distance = min(CGFloat(time) * speed, abs(self.initialWaveCenter - mask.waveCenterY))
                    let centerY = mask.waveCenterY + distance * direction
                    self.animate(view: view, forProgress: progress, waveCenterY: centerY)
                    self.animating = progress >= 0.0 || abs(self.initialWaveCenter - mask.waveCenterY) > 0.01
                    return self.animating
                } else {
                    return false
                }
            }
            animation?.completionBlock = { [weak self] (animation, isFinished) in
                guard let self = self else { return }

                self.animating = false
                if self.shouldFinish {
                    self.showNextPage()
                }
                if self.shouldCancel,
                   let viewController = self.nextView {
                    self.delegate?.liquidSwipeContainer(self.containerViewController, didFinishTransitionTo: viewController, transitionCompleted: false)
                }
            }
            if let mask = nextView?.layer.mask as? WaveLayer {
                mask.frame = self.view.bounds
                mask.updatePath()
            }
            currentView?.pop_add(animation, forKey: "animation")
        }
    }

    @objc private func leftEdgePan(_ sender: UIPanGestureRecognizer) {
        guard !animating else {
            return
        }
        if sender.state == .began {
            shouldCancel = false
            shouldFinish = false
            animating = true
            previousView?.isHidden = false
            if let viewController = previousView {
                delegate?.liquidSwipeContainer(containerViewController, willTransitionTo: viewController)
            }
            let previousViewAnimation = POPCustomAnimation { [weak self, weak sender] (target, animation) -> Bool in
                guard let self = self else { return false }

                guard let gesture = sender,
                      let view = target as? UIView,
                      let mask = view.layer.mask as? WaveLayer,
                      let time = animation?.elapsedTime else {
                    if let nextViewController = self.nextView {
                        self.delegate?.liquidSwipeContainer(self.containerViewController, didFinishTransitionTo: nextViewController, transitionCompleted: false)
                    }
                    return false
                }
                let speed: CGFloat = 2000
                let direction: CGFloat = (gesture.location(in: view).y - mask.waveCenterY).sign == .plus ? 1 : -1
                let distance = min(CGFloat(time) * speed, abs(mask.waveCenterY - gesture.location(in: view).y))
                let centerY = mask.waveCenterY + distance * direction
                let change = gesture.translation(in: view).x
                let maxChange: CGFloat = self.view.bounds.width
                if !(self.shouldFinish || self.shouldCancel) {
                    let progress: CGFloat = min(1.0, max(0, 1 - change / maxChange))
                    self.animateBack(view: view, forProgress: progress, waveCenterY: centerY)
                    switch gesture.state {
                    case .began, .changed:
                        return true
                    default:
                        if progress <= (1 - self.options.shouldFinishLeftProgress) {
                            self.shouldFinish = true
                            self.shouldCancel = false
                            self.animationProgress = progress
                            self.animationStartTime = CACurrentMediaTime()
                        } else {
                            self.shouldFinish = false
                            self.shouldCancel = true
                            self.animationStartTime = CACurrentMediaTime() - CFTimeInterval(CGFloat(self.duration) * progress)
                        }
                    }
                }
                let cTime = (animation?.currentTime ?? CACurrentMediaTime()) - (self.animationStartTime ?? CACurrentMediaTime())
                if self.shouldFinish {
                    let progress = self.animationProgress - CGFloat(cTime/self.duration)
                    let direction: CGFloat = (self.initialWaveCenter - mask.waveCenterY).sign == .plus ? 1 : -1
                    let distance = min(CGFloat(time) * speed, abs(self.initialWaveCenter - mask.waveCenterY))
                    let centerY = mask.waveCenterY + distance * direction
                    self.animateBack(view: view, forProgress: progress, waveCenterY: centerY)
                    self.animating = progress >= 0 || abs(self.initialWaveCenter - mask.waveCenterY) > 0.01
                    return self.animating
                } else if self.shouldCancel {
                    let progress = CGFloat(cTime/self.duration)
                    self.animateBack(view: view, forProgress: progress)
                    self.animating = progress <= 1.0
                    return self.animating
                } else {
                    return false
                }
            }
            previousViewAnimation?.completionBlock = { (animation, isFinished) in
                self.animating = false
                if self.shouldFinish {
                    self.showPreviousPage()
                }
                if self.shouldCancel,
                   let view = self.previousView {
                    view.isHidden = true
                    self.delegate?.liquidSwipeContainer(self.containerViewController, didFinishTransitionTo: view, transitionCompleted: false)
                }
            }
            if let mask = previousView?.layer.mask as? WaveLayer {
                mask.frame = self.view.bounds
                mask.updatePath()
            }
            previousView?.pop_add(previousViewAnimation, forKey: "animation")
            guard nextView != nil else {
                return
            }
            let startTime = CACurrentMediaTime()
            var cancelTime: CFTimeInterval?
            let currentViewAnimation = POPCustomAnimation { [weak self, weak sender] (target, animation) -> Bool in
                guard let self = self else { return false }

                guard let gesture = sender,
                      let view = target as? UIView,
                      let mask = view.layer.mask as? WaveLayer,
                      let time = animation?.currentTime else {
                    return false
                }
                let duration: CGFloat = 0.3
                if !self.shouldCancel {
                    let progress: CGFloat = 1.0 - min(1.0, max(0, CGFloat(time - startTime) / duration))
                    mask.sideWidth = self.initialSideWidth * progress
                    mask.waveHorRadius = self.options.initialHorRadius * progress
                    self.csBtnNextLeading?.constant = -(mask.waveHorRadius + mask.sideWidth - 8.0)
                    self.btnNext.transform = CGAffineTransform(scaleX: progress, y: progress)
                    mask.updatePath()
                    switch gesture.state {
                    case .began, .changed:
                        return true
                    default:
                        break
                    }
                }
                if self.shouldFinish {
                    return self.animating
                } else if self.shouldCancel {
                    if cancelTime == nil {
                        cancelTime = CACurrentMediaTime()
                    }
                    let progress = min(1.0, max(0, CGFloat(time - (cancelTime ?? CACurrentMediaTime())) / duration))
                    mask.sideWidth = self.initialSideWidth * progress
                    mask.waveHorRadius = self.options.initialHorRadius * progress
                    self.csBtnNextLeading?.constant = -(mask.waveHorRadius + mask.sideWidth - 8.0)
                    self.btnNext.transform = CGAffineTransform(scaleX: progress, y: progress)
                    self.btnNext.layoutIfNeeded()
                    mask.updatePath()
                    return progress < 1.0
                } else {
                    return self.animating
                }
            }
            currentView?.pop_add(currentViewAnimation, forKey: "animation")
        }
    }

    @objc private func pan(_ sender: UIPanGestureRecognizer) {

        guard let isLeft = panIsLeft(sender, theViewYouArePassing: view) else { return }

        if isLeft {
            rightEdgePan(sender)
        } else if leftEdgeGestureIsEnabled {
            leftEdgePan(sender)
        }
    }

    private func panIsLeft(_ gesture: UIPanGestureRecognizer, theViewYouArePassing: UIView) -> Bool? {
        let velocity : CGPoint = gesture.velocity(in: theViewYouArePassing)

        if abs(velocity.x) > abs(velocity.y) && velocity.x > 0 {
            return false
        } else if abs(velocity.x) > abs(velocity.y) && velocity.x < 0 {
            return true
        }
        return nil
    }

    private func layoutPageView(_ page: UIView) {
        page.translatesAutoresizingMaskIntoConstraints = false
        page.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        page.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        page.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        page.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    private func clearSubviews() {
        if previousView?.superview == view {
            previousView?.removeFromSuperview()
        }
        previousView = nil
        if currentView?.superview == view {
            currentView?.removeFromSuperview()
        }
        currentView = nil
        if nextView?.superview == view {
            nextView?.removeFromSuperview()
        }
        nextView = nil
    }

    private func configureInitialState() {
        clearSubviews()
        guard let datasource = datasource else {
            return
        }
        let pagesCount = datasource.numberOfControllersInLiquidSwipeContainer(self.containerViewController)
        guard pagesCount > 0 else {
            return
        }
        let firstPage = datasource.liquidSwipeContainer(self.containerViewController, viewControllerAtIndex: options.currentPageIndex)
        view.addSubview(firstPage)
        layoutPageView(firstPage)

        if pagesCount > options.currentPageIndex + 1 {
            let maskLayer = WaveLayer(waveCenterY: initialWaveCenter, waveHorRadius: options.initialHorRadius, waveVertRadius: options.initialVertRadius, sideWidth: initialSideWidth)
            apply(mask: maskLayer, on: firstPage)
        }
        currentView = firstPage
        configureNextPage()
        if options.currentPageIndex > 0 {

            let preView = datasource.liquidSwipeContainer(self.containerViewController, viewControllerAtIndex: options.currentPageIndex - 1)
            let maskLayer = WaveLayer(waveCenterY: initialWaveCenter,
                                      waveHorRadius: 0,
                                      waveVertRadius: options.initialVertRadius,
                                      sideWidth: 0)
            apply(mask: maskLayer, on: preView)

            configurePreviousPage()
            leftEdgeGesture.isEnabled = true
            leftEdgeGestureIsEnabled = true
        }
        if options.btnNextImage != nil {
            view.bringSubviewToFront(btnNext)
        }
    }

    private func showNextPage() {
        previousView?.removeFromSuperview()
        currentView?.isHidden = true
        previousView = currentView
        currentView = nextView
        options.currentPageIndex += 1
        leftEdgeGesture.isEnabled = true
        leftEdgeGestureIsEnabled = true
        let maskLayer = WaveLayer(waveCenterY: initialWaveCenter,
                                  waveHorRadius: 0,
                                  waveVertRadius: options.initialVertRadius,
                                  sideWidth: 0)
        if let currentView = currentView {
            apply(mask: maskLayer, on: currentView)
        }
        configureNextPage()
        containerViewController.setNeedsStatusBarAppearanceUpdate()
        guard nextView != nil else {
            btnNext.isHidden = true
            rightEdgeGesture.isEnabled = false
            if let viewController = currentView {
                delegate?.liquidSwipeContainer(containerViewController, didFinishTransitionTo: viewController, transitionCompleted: true)
            }
            return
        }

        let startTime = CACurrentMediaTime()
        let duration: CFTimeInterval = 0.3
        csBtnNextCenterY?.constant = initialWaveCenter
        let animation = POPCustomAnimation { [weak self] (target, animation) -> Bool in
            guard let self = self else { return false }

            guard let view = target as? UIView,
                  let mask = view.layer.mask as? WaveLayer,
                  let time = animation?.currentTime else {
                return false
            }
            let cTime = time - startTime
            let progress = CGFloat(cTime/duration)
            mask.waveHorRadius = self.options.initialHorRadius * progress
            mask.waveVertRadius = self.options.initialVertRadius
            mask.sideWidth = self.initialSideWidth * progress
            mask.updatePath()
            self.btnNext.alpha = progress
            self.csBtnNextLeading?.constant = -(mask.waveHorRadius + mask.sideWidth - 8.0)
            self.btnNext.transform = CGAffineTransform(scaleX: progress, y: progress)
            self.btnNext.layoutIfNeeded()
            return progress <= 1.0
        }
        animation?.completionBlock = { (_,_) in
            if let viewController = self.currentView {
                self.delegate?.liquidSwipeContainer(self.containerViewController, didFinishTransitionTo: viewController, transitionCompleted: true)
            }
        }
        currentView?.pop_add(animation, forKey: "animation")
    }

    private func showPreviousPage() {
        nextView?.removeFromSuperview()
        nextView = currentView
        currentView = previousView
        options.currentPageIndex -= 1
        btnNext.isHidden = false
        rightEdgeGesture.isEnabled = true
        let maskLayer = WaveLayer(waveCenterY: initialWaveCenter,
                                  waveHorRadius: 0,
                                  waveVertRadius: maxVertRadius,
                                  sideWidth: view.bounds.width)
        configurePreviousPage()
        self.containerViewController.setNeedsStatusBarAppearanceUpdate()
        if let prevPage = previousView {
            apply(mask: maskLayer, on: prevPage)
        } else {
            leftEdgeGesture.isEnabled = false
            leftEdgeGestureIsEnabled = false
        }
        let startTime = CACurrentMediaTime()
        let duration: CFTimeInterval = 0.3
        csBtnNextCenterY?.constant = initialWaveCenter
        view.bringSubviewToFront(btnNext)
        let animation = POPCustomAnimation { [weak self] (target, animation) -> Bool in
            guard let self = self else { return false }

            guard let view = target as? UIView,
                  let mask = view.layer.mask as? WaveLayer,
                  let time = animation?.currentTime else {
                return false
            }
            let cTime = time - startTime
            let progress = CGFloat(cTime/duration)
            self.btnNext.alpha = progress
            self.csBtnNextLeading?.constant = -(mask.waveHorRadius + mask.sideWidth - 8.0)
            self.btnNext.transform = CGAffineTransform(scaleX: progress, y: progress)
            self.btnNext.layoutIfNeeded()
            return progress <= 1.0
        }
        animation?.completionBlock = { (_,_) in
            if let viewController = self.currentView {
                self.delegate?.liquidSwipeContainer(self.containerViewController, didFinishTransitionTo: viewController, transitionCompleted: true)
            }
        }
        currentView?.pop_add(animation, forKey: "animation")
    }

    private func configureNextPage() {
        guard let datasource = datasource else {
            return
        }
        let pagesCount = datasource.numberOfControllersInLiquidSwipeContainer(containerViewController)
        guard pagesCount > options.currentPageIndex + 1 else {
            nextView = nil
            rightEdgeGesture.isEnabled = false
            return
        }
        let nextPage = datasource.liquidSwipeContainer(containerViewController, viewControllerAtIndex: options.currentPageIndex + 1)
        nextView = nextPage
        if let mask = nextPage.layer.mask as? WaveLayer {
            mask.frame = view.bounds
            mask.updatePath()
        }
        if let currentView = currentView {
            view.insertSubview(nextPage, belowSubview: currentView)
        } else {
            view.addSubview(nextPage)
        }
        layoutPageView(nextPage)
    }

    private func configurePreviousPage() {
        guard let datasource = datasource else {
            return
        }
        let pagesCount = datasource.numberOfControllersInLiquidSwipeContainer(containerViewController)
        guard options.currentPageIndex > 0 && pagesCount > 0 else {
            previousView = nil
            leftEdgeGesture.isEnabled = false
            leftEdgeGestureIsEnabled = false
            return
        }
        let previousPage = datasource.liquidSwipeContainer(containerViewController, viewControllerAtIndex: options.currentPageIndex - 1)
        previousView = previousPage
        if let mask = previousPage.layer.mask as? WaveLayer {
            mask.frame = view.bounds
            mask.updatePath()
        } else {
            let maskLayer = WaveLayer(waveCenterY: initialWaveCenter,
                                      waveHorRadius: 0,
                                      waveVertRadius: options.initialVertRadius,
                                      sideWidth: 0)
            if let currentView = currentView {
                apply(mask: maskLayer, on: currentView)
            }
        }
        if let currentView = currentView {
            view.insertSubview(previousPage, aboveSubview: currentView)
        } else {
            view.addSubview(previousPage)
        }
        layoutPageView(previousPage)
        previousPage.isHidden = true
    }

    private func apply(mask: WaveLayer, on view: UIView) {
        mask.frame = self.view.bounds
        mask.updatePath()
        view.layer.mask = mask
    }

    @objc private func btnTapped(_ sender: AnyObject) {
        animationStartTime = CACurrentMediaTime()
        guard !animating else {
            return
        }
        animating = true
        if let viewController = nextView {
            delegate?.liquidSwipeContainer(containerViewController, willTransitionTo: viewController)
        }
        let animation = POPCustomAnimation { [weak self] (target, animation) -> Bool in
            guard let self = self else { return false }

            guard let view = target as? UIView,
                  let time = animation?.currentTime else {
                return false
            }
            let cTime = time - (self.animationStartTime ?? CACurrentMediaTime())
            let progress = CGFloat(cTime/self.duration)
            self.animate(view: view, forProgress: progress)
            self.animating = progress <= 1.0
            return progress <= 1.0
        }
        animation?.completionBlock = { (animation, isFinished) in
            self.animating = false
            self.showNextPage()
        }
        currentView?.pop_add(animation, forKey: "animation")
    }

    // FIXME: Yunus -
//    override open func viewSafeAreaInsetsDidChange() {
//        if let mask = self.currentPage?.layer.mask as? WaveLayer {
//            if mask.sideWidth > 0 {
//                mask.sideWidth = initialSideWidth
//                mask.updatePath()
//                csBtnNextLeading?.constant = -(mask.waveHorRadius + mask.sideWidth - 8.0)
//                view.layoutIfNeeded()
//            }
//        }
//
//    }

    // FIXME: Yunus -
//    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
//        let btnNextWasHidden = btnNext.isHidden
//        btnNext.isHidden = true
//        currentPage?.layer.mask = nil
//        previousViewController?.view?.layer.mask = nil
//        nextViewController?.view?.layer.mask = nil
//
//        coordinator.animate(alongsideTransition: { (_) in
//        }) { (_) in
//            if let currentPage = self.currentPage {
//                let hasNextPage = self.nextViewController != nil
//                let maskLayer = WaveLayer(waveCenterY: self.initialWaveCenter,
//                                          waveHorRadius: hasNextPage ? self.options.initialHorRadius : 0,
//                                          waveVertRadius: self.options.initialVertRadius, sideWidth: hasNextPage ?self.initialSideWidth : 0)
//                self.apply(mask: maskLayer, on: currentPage)
//            }
//            if let nextPage = self.nextViewController?.view {
//                let maskLayer = WaveLayer(waveCenterY: self.initialWaveCenter, waveHorRadius: 0, waveVertRadius: self.options.initialVertRadius, sideWidth: 0)
//                self.apply(mask: maskLayer, on: nextPage)
//            }
//            if let prevPage = self.previousViewController?.view {
//                let maskLayer = WaveLayer(waveCenterY: self.initialWaveCenter, waveHorRadius: 0, waveVertRadius: self.options.initialVertRadius, sideWidth: prevPage.bounds.height)
//                self.apply(mask: maskLayer, on: prevPage)
//            }
//            self.csBtnNextCenterY?.constant = self.initialWaveCenter
//            self.csBtnNextLeading?.constant = -(self.options.initialHorRadius + self.initialSideWidth - 8.0)
//            self.btnNext.isHidden = btnNextWasHidden
//            self.btnNext.transform = CGAffineTransform.identity
//            self.view.layoutIfNeeded()
//        }
//        super.viewWillTransition(to: size, with: coordinator)
//    }
}

//MARK: Animation helpers

private extension LiquidSwipeContainerManager {

    private func btnAlpha(forProgress progress: CGFloat) -> CGFloat {
        let p1: CGFloat = 0.1
        let p2: CGFloat = 0.3
        if progress <= p1 {
            return 1.0
        }
        if progress >= p2 {
            return 0.0
        }
        return 1.0 - (progress - p1)/(p2-p1)
    }

    private func waveHorRadius(forProgress progress: CGFloat) -> CGFloat {
        if progress <= 0 {
            return options.initialHorRadius
        }
        if progress >= 1 {
            return 0
        }
        let p1: CGFloat = 0.4
        if progress <= p1 {
            return options.initialHorRadius + progress/p1*(maxHorRadius - options.initialHorRadius)
        }
        let t: CGFloat = (progress - p1)/(1.0 - p1)
        let A: CGFloat = maxHorRadius
        let r: CGFloat = 40
        let m: CGFloat = 9.8
        let beta: CGFloat = r/(2*m)
        let k: CGFloat = 50
        let omega0: CGFloat = k/m
        let omega: CGFloat = pow(-pow(beta,2)+pow(omega0,2), 0.5)

        return A * exp(-beta * t) * cos( omega * t)
    }

    private func waveHorRadiusBack(forProgress progress: CGFloat) -> CGFloat {
        if progress <= 0 {
            return options.initialHorRadius
        }
        if progress >= 1 {
            return 0
        }
        let p1: CGFloat = 0.4
        if progress <= p1 {
            return options.initialHorRadius + progress/p1*options.initialHorRadius
        }
        let t: CGFloat = (progress - p1)/(1.0 - p1)
        let A: CGFloat = 2 * options.initialHorRadius
        let r: CGFloat = 40
        let m: CGFloat = 9.8
        let beta: CGFloat = r/(2*m)
        let k: CGFloat = 50
        let omega0: CGFloat = k/m
        let omega: CGFloat = pow(-pow(beta,2)+pow(omega0,2), 0.5)

        return A * exp(-beta * t) * cos( omega * t)
    }

    private func waveVertRadius(forProgress progress: CGFloat) -> CGFloat {
        let p1: CGFloat = 0.4
        if progress <= 0 {
            return options.initialVertRadius
        }
        if progress >= p1 {
            return maxVertRadius
        }
        return options.initialVertRadius + (maxVertRadius - options.initialVertRadius) * progress/p1
    }

    private func sideWidth(forProgress progress: CGFloat) -> CGFloat {
        let p1: CGFloat = 0.2
        let p2: CGFloat = 0.8
        if progress <= p1 {
            return initialSideWidth
        }
        if progress >= p2 {
            return view.bounds.width
        }
        return initialSideWidth + (view.bounds.width - initialSideWidth) * (progress - p1)/(p2 - p1)
    }
}
