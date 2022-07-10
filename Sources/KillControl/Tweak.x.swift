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
    static var whitelistApps: [String]!
    static var excludeMediaApps: Bool!
    //Misc
    static var swipeDownToKillAll: Bool!
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
struct swipeDownToKillAll: HookGroup {}

//MARK: - Swipe down to kill
class SBReusableSnapshotItemContainer_Hook: ClassHook<SBReusableSnapshotItemContainer> {
    typealias Group = swipeDownToKillAll
    
    func _updateTransformForCurrentHighlight() {
        orig._updateTransformForCurrentHighlight()
        
        //Kills all apps when the kill progress is <= -0.2.
        if target.killingProgress <= -0.2 {
            SBMainSwitcherViewController.sharedInstanceIfExists().killControlKillApps(nil)
        }
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
        
        //Get the now playing app if it exists.
        var nowPlayingApp: SBApplication?
        if localSettings.excludeMediaApps {
            nowPlayingApp = SBMediaController.sharedInstance().nowPlayingApplication() ?? nil
        }
        
        //Adding exlcuded apps to our layoutsToExclude set.
        for app in appLayouts {
            //Get the bundleIdentifier from each app's layout.
            let displayItem = Ivars<SBPBDisplayItem>(app.protobufRepresentation())._primaryDisplayItem
            let identifier: String = Ivars<NSString>(displayItem)._bundleIdentifier as String
            
            if !(localSettings.onlyKillChosenWhenLocked && localSettings.deviceLocked) {
                //Exclude if now playing
                if localSettings.excludeMediaApps {
                    if nowPlayingApp?.bundleIdentifier == identifier {
                        layoutsToExclude.insert(app)
                        continue
                    }
                }
                
                //Exclude if black listed
                if localSettings.whitelistApps.contains(identifier) {
                    layoutsToExclude.insert(app)
                    continue
                }
            }
            
            //Exclude if not found in the bundleIDS argument (If that exists).
            if bundleIDS != nil {
                if !bundleIDS!.contains(identifier) {
                    layoutsToExclude.insert(app)
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
                            let displayItem = SBDisplayItem(type: 0, bundleIdentifier: identifier, uniqueIdentifier: "sceneID:\(identifier)-default")
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
        }
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
    localSettings.whitelistApps = dict.value(forKey: "whitelistApps") as? [String] ?? [""]
    localSettings.excludeMediaApps = dict.value(forKey: "excludeMediaApps") as? Bool ?? true
    //Misc
    localSettings.swipeDownToKillAll = dict.value(forKey: "swipeDownToKillAll") as? Bool ?? true
    localSettings.askBeforeKilling = dict.value(forKey: "askBeforeKilling") as? Bool ?? false
}

struct KillControl: Tweak {
    init() {
        readPrefs()
        if (localSettings.isEnabled) {
            tweak().activate()
            
            if localSettings.killAfterLock {
                killAfterLock().activate()
            }
            
            if localSettings.swipeDownToKillAll {
                swipeDownToKillAll().activate()
            }
        }
    }
}
