import Orion
import KillControlC

struct localSettings {
    static var isEnabled: Bool!
    //Killing apps after lock + grace period
    static var killAfterLock: Bool!
    static var hasGracePeriod: Bool!
    static var killLockGracePeriodTimeMeasurement: Int! //1: Sec, 2: Min, 3: Hour
    static var killLockGracePeriod: Double!
    static var onlyKillChosenWhenLocked: Bool!
    static var onlyKillTheseWhenLocked: [String]!
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

struct tweak: HookGroup {}
struct killAfterLock: HookGroup {}
struct excludeMediaApps: HookGroup {}

//MARK: - Swipe down to kill, white-list shortcut.
class SBReusableSnapshotItemContainer_Hook: ClassHook<SBReusableSnapshotItemContainer> {
    typealias Group = tweak
        
    func initWithFrame(_ frame: CGRect, appLayout layout: SBAppLayout, delegate arg3: AnyObject, active arg4: Bool) -> Target {
        
        /* Add long hold gesture to each switcher app card, which will be used as a shortcut to whitelist / un-whitelist apps. (Temporary, does not persist over respring and is designed to be like that). */
        
        if localSettings.excludeMediaApps {
            NotificationCenter.default.addObserver(target,
                                                   selector: #selector(refreshLockedStatus),
                                                   name: NSNotification.Name("KillControl.refreshLock"),
                                                   object: nil)
        }
        
        let longHold = UILongPressGestureRecognizer(target: target, action: #selector(killControlToggleItemWhiteListedWithRecogniser(_:)))
        longHold.minimumPressDuration = 1.0
        target.addGestureRecognizer(longHold)
        
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
            SBMainSwitcherViewController.sharedInstanceIfExists().killControlKillApps(nil)
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
        
        guard filterType != .media else {
            return
        }
        
        if filterType == .whiteListed {
            //Remove from whitelisted app list if exists.
            localSettings.whitelistApps.remove(identifier)
            filterType = .noFilter
        } else {
            //Add to whitelisted app list if doesn't exist.
            localSettings.whitelistApps.insert(identifier)
            filterType = .whiteListed
        }

        killControlUpdateHeaderItems(withFilter: filterType)
        
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

class SBMainSwitcherViewController_Hook: ClassHook<SBMainSwitcherViewController> {
    typealias Group = tweak

    //orion: new
    @objc func killControlKillApps(_ apps: [String]?) {
        //Check if this method was called from a timer. If it was, only continue if the device is locked.
        if localSettings.hasGracePeriod && localSettings.comingFromTimer {
            localSettings.comingFromTimer = false
            
            guard localSettings.deviceLocked else {
                return
            }
        }
        
        //Get a filtered app layout list that respects the user's blacklisting settings and open/kill rules.
        let layoutList = killControlFilteredLayouts(withFilter: apps)
        
        //Skip the confirmation prompt if the user doesn't want it.
        guard localSettings.askBeforeKilling && !localSettings.deviceLocked else {
            killControlKillInLayoutList(layoutList)
            return
        }
        
        //Present confirmation alert
        let alert = UIAlertController(title: "KillControl", message: "Are you sure you want to kill all apps?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Kill", style: .destructive, handler: { action in
            self.killControlKillInLayoutList(layoutList)
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        target.present(alert, animated: true)
    }
    
    //orion: new
    func killControlKillInLayoutList(_ list: [SBAppLayout]) {
        //Play haptic feedback when all apps are killed (Only when the device is unlocked).
        if !localSettings.deviceLocked {
            let thud = UIImpactFeedbackGenerator(style: .medium)
            thud.prepare()
            thud.impactOccurred()
        }
        
        //Kill all apps.
        for layout in list {
            target._remove(layout, forReason: 0)
        }
    }
    
    //orion: new
    func killControlFilteredLayouts(withFilter bundleIDS: [String]?) -> [SBAppLayout] {
        //Returns a list of apps to be killed
        
        /* Create two sets, one that contains all app layouts that are currently in the app switcher,
        and another empty which we will add excluded apps to. */
        var appLayouts: Set<SBAppLayout> = Set(target.appLayouts(forSwitcherContentController: target))
        var layoutsToExclude = Set<SBAppLayout>()

        //Adding exlcuded apps to our layoutsToExclude set.
        for app in appLayouts {
            //Get the bundleIdentifier from each app's layout.
            guard let identifier = KCAppResults().identfierForItem(withLayout: app) else {
                continue
            }
            
            //Skip the media app if it's playing, device is locked and is in the onlyKillTheseWhenLocked array.
            if localSettings.deviceLocked && localSettings.onlyKillChosenWhenLocked && localSettings.onlyKillTheseWhenLocked.contains(identifier) {
                guard KCAppResults().filterTypeForItem(withIdentifier: identifier) != .media else {
                    layoutsToExclude.insert(app)
                    continue
                }
            }

            //Exclude if now playing.
            if localSettings.excludeMediaApps {
                guard KCAppResults().filterTypeForItem(withIdentifier: identifier) != .media else {
                    layoutsToExclude.insert(app)
                    continue
                }
            }
            
            if !(localSettings.onlyKillChosenWhenLocked && localSettings.deviceLocked) {
                //Exclude if black listed
                guard !localSettings.whitelistApps.contains(identifier) else {
                    layoutsToExclude.insert(app)
                    continue
                }
            }
            
            //Exclude if not found in the bundleIDS argument (If that exists).
            if bundleIDS != nil {
                guard bundleIDS!.contains(identifier) else {
                    layoutsToExclude.insert(app)
                    continue
                }
            }
        }
        
        //Subtract the excluded app set from the set that contains all app layouts, then return it as an array.
        appLayouts = appLayouts.subtracting(layoutsToExclude)
        return Array(appLayouts)
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
                            
                            SBMainSwitcherViewController.sharedInstanceIfExists().addAppLayout(forDisplayItem: displayItem,
                                                                                               completion: nil)
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
                        SBMainSwitcherViewController.sharedInstanceIfExists().killControlKillApps(localSettings.killTheseAppsOne)
                    }
                }
            }
        }

        return proccess
    }

}

class SBLockStateAggregator_Hook: ClassHook<SBLockStateAggregator> {
    typealias Group = killAfterLock
    
    @Property(.nonatomic, .retain) var killTimer: Timer? = Timer()
    
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
            if let killTimer = killTimer {
                if killTimer.isValid {
                    killTimer.invalidate()
                }
            }
            //Don't progress if unlocked
            return
        }
        
        if localSettings.hasGracePeriod {
            if killTimer != nil {
                killTimer = Timer()
            }
            
            killTimer = Timer.scheduledTimer(withTimeInterval: localSettings.time, repeats: false, block: { action in
                localSettings.comingFromTimer = true
                switcher.killControlKillApps(localSettings.onlyKillChosenWhenLocked ? localSettings.onlyKillTheseWhenLocked : nil)
                self.killTimer?.invalidate()
            })
        } else {
            switcher.killControlKillApps(localSettings.onlyKillChosenWhenLocked ? localSettings.onlyKillTheseWhenLocked : nil)
        }
    }
}

class SBMediaController_Hook: ClassHook<SBMediaController> {
    typealias Group = excludeMediaApps
    
    func _mediaRemoteNowPlayingApplicationIsPlayingDidChange(_ change: AnyObject) {
        orig._mediaRemoteNowPlayingApplicationIsPlayingDidChange(change)
        
        NotificationCenter.default.post(name: NSNotification.Name("KillControl.refreshLock"), object: nil, userInfo: nil)
    }
}

//MARK: - Preferences
func readPrefs() {
    
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
            
            if localSettings.killAfterLock {
                killAfterLock().activate()
            }
        }
    }
}
