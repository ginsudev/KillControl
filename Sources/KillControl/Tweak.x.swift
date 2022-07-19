import Orion
import KillControlC

//MARK: - Preferences storage
struct localSettings {
    static var isEnabled: Bool!
    //Killing apps after lock + grace period
    static var killAfterLock: Bool!
    static var hasGracePeriod: Bool!
    static var killLockGracePeriodTimeMeasurement: Int! //1: Sec, 2: Min, 3: Hour
    static var killLockGracePeriod: Double!
    static var onlyKillChosenWhenLocked: Bool!
    static var onlyKillTheseWhenLocked: [String]!
    static var killAfterForcedlLock: Bool!
    //Kill/Open rule
    static var killOnAppLaunch: Bool!
    static var openOnAppLaunch: Bool!
    static var killTheseAppsOne: [String]!
    static var whenThisAppOpensOne: String!
    static var openTheseAppsTwo: [String]!
    static var whenThisAppOpensTwo: String!
    //Blacklisting
    static var whitelistApps: Set<String>!
    static var excludeMediaApps: Bool!
    static var useWhiteListGesture: Bool!
    static var whiteListShortcut: Int! //1 = One finger hold, 2 = Two finger hold
    //Misc
    static var swipeDownToKillAll: Bool!
    static var preventSwipe: Bool!
    static var askBeforeKilling: Bool!
    //Timer settings
    static var comingFromTimer = false
    static var deviceLocked: Bool {
        return SBLockStateAggregator.sharedInstance().lockState() == 2 || SBLockStateAggregator.sharedInstance().lockState() == 3
    }
    static var time: Double {
        switch localSettings.killLockGracePeriodTimeMeasurement {
        case 1:
            return localSettings.killLockGracePeriod //Seconds
        case 2:
            return localSettings.killLockGracePeriod * 60 //Minutes
        case 3:
            return localSettings.killLockGracePeriod * 60 * 60 //Hours
        default:
            return localSettings.killLockGracePeriod //Seconds
        }
    }
}

//MARK: - Hook groups
struct tweak: HookGroup {}
struct killAfterLock: HookGroup {}
struct excludeMediaApps: HookGroup {}
struct killAfterForcedlLock: HookGroup {}

//MARK: - Swipe down to kill, white-list shortcut.
class SBReusableSnapshotItemContainer_Hook: ClassHook<SBReusableSnapshotItemContainer> {
    typealias Group = tweak
            
    func initWithFrame(_ frame: CGRect, appLayout layout: SBAppLayout, delegate arg3: AnyObject, active arg4: Bool) -> Target {
                
        /* Add long hold gesture to each switcher app card, which will be used as a shortcut to whitelist / un-whitelist apps. */
        
        if localSettings.excludeMediaApps {
            NotificationCenter.default.addObserver(target,
                                                   selector: #selector(refreshLockedStatus),
                                                   name: NSNotification.Name("KillControl.refreshLock"),
                                                   object: nil)
        }
        
        if localSettings.useWhiteListGesture {
            let longHold = UILongPressGestureRecognizer(target: target, action: #selector(killControlToggleItemWhiteListedWithRecogniser(_:)))
            longHold.minimumPressDuration = 1.0
            longHold.numberOfTouchesRequired = localSettings.whiteListShortcut == 1 ? 1 : 2
            target.addGestureRecognizer(longHold)
        }
        
        return orig.initWithFrame(frame, appLayout: layout, delegate: arg3, active: arg4)
    }
    
    func _updateTransformForCurrentHighlight() {
        orig._updateTransformForCurrentHighlight()
        
        //Swipe down to kill all gesture.
        guard localSettings.swipeDownToKillAll else {
            return
        }
        
        //Kills all apps when the kill progress is <= -0.2.
        if target.killingProgress <= -0.2 {
            guard let switcher = SBMainSwitcherViewController.sharedInstanceIfExists() else {
                return
            }
            
            KCHelper.sharedInstance.killApps(nil, controller: switcher)
        }
    }
    
    func _scrollViewShouldPanGestureTryToBegin(_ arg1: AnyObject) -> Bool {
        /* Prevent swiping gestures on white-listed apps if the user has
           that option enabled. */
        
        guard localSettings.preventSwipe else {
            return orig._scrollViewShouldPanGestureTryToBegin(arg1)
        }
        
        //Prevent swipe gesture if app id is white-listed / now playing.
        if let identifier = KCAppResults().identfierForItem(withLayout: Ivars<SBAppLayout?>(target)._appLayout) {
            let filter = KCAppResults().filterTypeForItem(withIdentifier: identifier)
            guard filter == .noFilter else {
                return false
            }
        }
        
        return orig._scrollViewShouldPanGestureTryToBegin(arg1)
    }
    
    func _updateHeaderAnimated(_ animated: Bool) {
        orig._updateHeaderAnimated(animated)

        //Refresh locked status when presenting the app switcher.
        DispatchQueue.main.async {
            self.refreshLockedStatus()
        }
    }
    
    func setTitleOpacity(_ opacity: CGFloat) {
        orig.setTitleOpacity(opacity)
        
        /* Apply header view's title opacity to our lock icon if the app is white listed.
           Exit if app is not white listed. */
        
        if let identifier = KCAppResults().identfierForItem(withLayout: Ivars<SBAppLayout?>(target)._appLayout) {
            let filter = KCAppResults().filterTypeForItem(withIdentifier: identifier)
            guard filter != .noFilter else {
                return
            }
        }
        
        guard let headerView = Ivars<SBFluidSwitcherItemContainerHeaderView?>(target)._iconAndLabelHeader else {
            return
        }
        
        if let lockView = headerView.subviews.first(where: { $0 is UIImageView }) {
            lockView.alpha = opacity
        }
    }
    
    //orion: new
    @objc func refreshLockedStatus() {
        //Refreshes locked status. This method is called when the app switcher gets presented.
        if let identifier = KCAppResults().identfierForItem(withLayout: Ivars<SBAppLayout?>(target)._appLayout) {
            let filter = KCAppResults().filterTypeForItem(withIdentifier: identifier)
            killControlUpdateHeaderItems(withFilter: filter)
        }
    }
    
    //orion: new
    @objc func killControlToggleItemWhiteListedWithRecogniser(_ recogniser: UILongPressGestureRecognizer) {
        //Request toggling white-listed for an app by holding your finger for n seconds on an app.
        if recogniser.state == .began {
            if let identifier = KCAppResults().identfierForItem(withLayout: Ivars<SBAppLayout?>(target)._appLayout) {
                killControlToggleItemWhiteListed(withIdentifer: identifier)
            }
        }
    }

    //orion: new
    func killControlToggleItemWhiteListed(withIdentifer identifier: String) {
        //Toggle white-listed for an app.
        
        var filterType = KCAppResults().filterTypeForItem(withIdentifier: identifier)
        
        switch filterType {
        case .noFilter:
            //Add to whitelisted app list if doesn't exist.
            localSettings.whitelistApps.insert(identifier)
            filterType = .whiteListed
            break
        case .whiteListed:
            //Remove from whitelisted app list if exists.
            localSettings.whitelistApps.remove(identifier)
            filterType = .noFilter
            break
        case .media:
            //Don't continue if app is a media app.
            return
        }

        killControlUpdateHeaderItems(withFilter: filterType)
        pushChangesToWhiteList()
        
        //Haptics
        let thud = UIImpactFeedbackGenerator(style: .medium)
        thud.prepare()
        thud.impactOccurred()
    }
    
    //orion: new
    func killControlUpdateHeaderItems(withFilter filter: KCFilterType) {
        //This method is used to add/remove the lock to the header view of an app card.
                
        guard let headerView = Ivars<SBFluidSwitcherItemContainerHeaderView?>(target)._iconAndLabelHeader else {
            return
        }
        
        //Remove lock if not white-listed.
        if filter == .noFilter {
            if let lockView = headerView.subviews.first(where: { $0 is UIImageView }) {
                lockView.removeFromSuperview()
            }
            return
        }
        
        //Don't add lock if it already exists.
        guard !headerView.subviews.contains(where: { $0 is UIImageView }) else {
            return
        }
        
        //Proceed to add lock if white-listed.
        let appLabel = Ivars<UILabel>(headerView)._firstTitleLabel
        let spacing = Ivars<CGFloat>(headerView)._spacingBetweenSnapshotAndIcon
        
        let image = UIImage(systemName: filter == .media ? "music.note" : "lock.fill")
        
        let lockImageView = UIImageView(image: image)
        lockImageView.translatesAutoresizingMaskIntoConstraints = false
        lockImageView.tintColor = .white
        lockImageView.contentMode = .scaleAspectFit
        headerView.addSubview(lockImageView)
        //Constraints
        lockImageView.leftAnchor.constraint(equalTo: appLabel.rightAnchor, constant: spacing).isActive = true
        lockImageView.centerYAnchor.constraint(equalTo: appLabel.centerYAnchor).isActive = true
        lockImageView.heightAnchor.constraint(equalTo: appLabel.heightAnchor).isActive = true
        lockImageView.widthAnchor.constraint(equalTo: appLabel.heightAnchor).isActive = true
    }
}

class FBProcessManagerHook: ClassHook<FBProcessManager> {
    typealias Group = tweak

    func _createProcessWithExecutionContext(_ executionContext: FBProcessExecutionContext) -> FBProcess? {
        let proccess = orig._createProcessWithExecutionContext(executionContext)

        //Opens user-specified apps in the background when a different app is opened.
        if localSettings.openOnAppLaunch {
            if let processIdentifier = proccess?.identity.embeddedApplicationIdentifier {
                if processIdentifier == localSettings.whenThisAppOpensTwo {
                    DispatchQueue.main.async {
                        for identifier in localSettings.openTheseAppsTwo {
                            DispatchQueue.global().async {
                                //Launch the application in the background
                                SBSLaunchApplicationWithIdentifier(identifier as CFString, true)
                            }
                            
                            //Manually add the app to switcher
                            let displayItem = SBDisplayItem(type: 0,
                                                            bundleIdentifier: identifier,
                                                            uniqueIdentifier: "sceneID:\(identifier)-default")
                            
                            SBMainSwitcherViewController.sharedInstanceIfExists().addAppLayout(forDisplayItem: displayItem, completion: nil)
                        }
                    }
                }
            }
        }
        
        //Kills user-specified apps when a different app is opened.
        if localSettings.killOnAppLaunch {
            if let processIdentifier = proccess?.identity.embeddedApplicationIdentifier {
                if processIdentifier == localSettings.whenThisAppOpensOne {
                    DispatchQueue.main.async {
                        //Kill user-specified apps
                        guard let switcher = SBMainSwitcherViewController.sharedInstanceIfExists() else {
                            return
                        }
                        
                        KCHelper.sharedInstance.killApps(localSettings.killTheseAppsOne, controller: switcher)
                    }
                }
            }
        }

        return proccess
    }

}

class SBLockStateAggregator_Hook: ClassHook<SBLockStateAggregator> {
    typealias Group = killAfterLock
        
    func _updateLockState() {
        orig._updateLockState()
        
        /* Lock states
         0 = Device unlocked and lock screen dismissed.
         1 = Device unlocked and lock screen not dismissed.
         2 = Locking... ??
         3 = Locked.
        */
        
        guard let switcher = SBMainSwitcherViewController.sharedInstanceIfExists() else {
            //Don't progress if switcher has no shared instance ready for use
            return
        }
        
        guard !switcher.appLayouts(forSwitcherContentController: switcher).isEmpty else {
            //Don't progress if app switcher empty
            return
        }
                
        guard localSettings.deviceLocked else {
            //Invalidate the timer if it is valid and the device is unlocked
            KCHelper.sharedInstance.invalidateTimer()
            //Don't progress if unlocked
            return
        }
        
        guard !localSettings.killAfterForcedlLock else {
            //Don't progress if lock button only is enabled.
            return
        }
                
        if localSettings.hasGracePeriod {
            KCHelper.sharedInstance.killUsingTimer(withInterval: localSettings.time, controller: switcher)
        } else {
            KCHelper.sharedInstance.killApps(localSettings.onlyKillChosenWhenLocked ? localSettings.onlyKillTheseWhenLocked : nil, controller: switcher)
        }
    }
}

class SBDashBoardLockScreenEnvironment_Hook: ClassHook<SBDashBoardLockScreenEnvironment> {
    typealias Group = killAfterForcedlLock
    
    @Property (.nonatomic, .retain) var lastLockPressTime: Date? = Date()
        
    func handleLockButtonPress() -> Bool {
        lastLockPressTime = Date()
        return orig.handleLockButtonPress()
    }
    
    func prepareForUILock() {
        orig.prepareForUILock()
        
        guard let lastLockPressTime = lastLockPressTime else {
            return
        }
        
        let interval = DateInterval(start: lastLockPressTime, end: Date())
        
        if interval.duration <= 2 {
            guard let switcher = SBMainSwitcherViewController.sharedInstanceIfExists() else {
                //Don't progress if switcher has no shared instance ready for use
                return
            }

            if localSettings.hasGracePeriod {
                KCHelper.sharedInstance.killUsingTimer(withInterval: localSettings.time, controller: switcher)
            } else {
                KCHelper.sharedInstance.killApps(localSettings.onlyKillChosenWhenLocked ? localSettings.onlyKillTheseWhenLocked : nil, controller: switcher)
            }
        }
    }
}

class SBMediaController_Hook: ClassHook<SBMediaController> {
    typealias Group = excludeMediaApps
    
    func _mediaRemoteNowPlayingApplicationIsPlayingDidChange(_ change: AnyObject) {
        orig._mediaRemoteNowPlayingApplicationIsPlayingDidChange(change)
        
        //Update the now playing indicator when media playback changes.
        NotificationCenter.default.post(name: NSNotification.Name("KillControl.refreshLock"),
                                        object: nil,
                                        userInfo: nil)
    }
}

fileprivate func pushChangesToWhiteList() {
    let path = "/var/mobile/Library/Preferences/com.ginsu.killcontrol.plist"

    guard let dict = NSDictionary(contentsOfFile: path) else {
        return
    }
    
    let newWhitelist = Array(localSettings.whitelistApps)
    dict.setValue(newWhitelist, forKey: "whitelistApps")
    
    dict.write(toFile: path, atomically: true)
}

//MARK: - Preferences
fileprivate func readPrefs() {
    
    let path = "/var/mobile/Library/Preferences/com.ginsu.killcontrol.plist"
    
    if !FileManager().fileExists(atPath: path) {
        try? FileManager().copyItem(atPath: "Library/PreferenceBundles/killcontrol.bundle/defaults.plist", toPath: path)
    }
    
    guard let dict = NSDictionary(contentsOfFile: path) else {
        return
    }
    
    //Reading values
    localSettings.isEnabled = dict.value(forKey: "isEnabled") as? Bool ?? true
    //Kill when locked
    localSettings.killAfterLock = dict.value(forKey: "killAfterLock") as? Bool ?? false
    localSettings.killAfterForcedlLock = dict.value(forKey: "killAfterForcedlLock") as? Bool ?? false
    localSettings.hasGracePeriod = dict.value(forKey: "hasGracePeriod") as? Bool ?? false
    localSettings.killLockGracePeriodTimeMeasurement = dict.value(forKey: "killLockGracePeriodTimeMeasurement") as? Int ?? 1
    localSettings.killLockGracePeriod = dict.value(forKey: "killLockGracePeriod") as? Double ?? 10.0
    localSettings.onlyKillChosenWhenLocked = dict.value(forKey: "onlyKillChosenWhenLocked") as? Bool ?? false
    localSettings.onlyKillTheseWhenLocked = dict.value(forKey: "onlyKillTheseWhenLocked") as? [String] ?? [String]()
    //Kill/Open Rules
    localSettings.killOnAppLaunch = dict.value(forKey: "killOnAppLaunch") as? Bool ?? false
    localSettings.openOnAppLaunch = dict.value(forKey: "openOnAppLaunch") as? Bool ?? false
    localSettings.killTheseAppsOne = dict.value(forKey: "killTheseAppsOne") as? [String] ?? [""]
    localSettings.whenThisAppOpensOne = dict.value(forKey: "whenThisAppOpensOne") as? String ?? ""
    localSettings.openTheseAppsTwo = dict.value(forKey: "openTheseAppsTwo") as? [String] ?? [""]
    localSettings.whenThisAppOpensTwo = dict.value(forKey: "whenThisAppOpensTwo") as? String ?? ""
    //Blacklisting
    localSettings.whitelistApps = Set(dict.value(forKey: "whitelistApps") as? [String] ?? [""])
    localSettings.excludeMediaApps = dict.value(forKey: "excludeMediaApps") as? Bool ?? true
    localSettings.useWhiteListGesture = dict.value(forKey: "useWhiteListGesture") as? Bool ?? true
    localSettings.whiteListShortcut = dict.value(forKey: "whiteListShortcut") as? Int ?? 1
    //Misc
    localSettings.swipeDownToKillAll = dict.value(forKey: "swipeDownToKillAll") as? Bool ?? true
    localSettings.askBeforeKilling = dict.value(forKey: "askBeforeKilling") as? Bool ?? false
    localSettings.preventSwipe = dict.value(forKey: "preventSwipe") as? Bool ?? false
}

struct KillControl: Tweak {
    init() {
        readPrefs()
        if (localSettings.isEnabled) {
            tweak().activate()
            
            if localSettings.excludeMediaApps {
                excludeMediaApps().activate()
            }
            
            if localSettings.killAfterLock {
                killAfterLock().activate()

                if localSettings.killAfterForcedlLock {
                    killAfterForcedlLock().activate()
                }
            }
        }
    }
}
