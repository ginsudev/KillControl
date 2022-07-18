//
//  KCHelper.swift
//  
//
//  Created by Noah Little on 18/7/2022.
//

import KillControlC

final class KCHelper: NSObject {
    static let sharedInstance = KCHelper()
    
    private var timer: Timer?
    
    private var switcher: SBMainSwitcherViewController!
    
    public func killUsingTimer(withInterval interval: Double, controller switcher: SBMainSwitcherViewController) {
        
        self.switcher = switcher
        
        if timer == nil {
            timer = Timer()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false, block: { action in
            localSettings.comingFromTimer = true
            
            self.killApps(localSettings.onlyKillChosenWhenLocked ? localSettings.onlyKillTheseWhenLocked : nil, controller: nil)
            
            self.timer?.invalidate()
        })
    }
    
    private func filteredLayouts(withFilter bundleIDS: [String]?) -> [SBAppLayout] {
        //Returns a list of apps to be killed
        
        /* Create two sets, one that contains all app layouts that are currently in the app switcher,
        and another empty which we will add excluded apps to. */
        var appLayouts: Set<SBAppLayout> = Set(switcher.appLayouts(forSwitcherContentController: switcher))
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
    
    public func killApps(_ apps: [String]?, controller switcher: SBMainSwitcherViewController?) {
        
        if switcher != nil {
            self.switcher = switcher
        }
        
        //Check if this method was called from a timer. If it was, only continue if the device is locked.
        if localSettings.hasGracePeriod && localSettings.comingFromTimer {
            localSettings.comingFromTimer = false
            
            guard localSettings.deviceLocked else {
                return
            }
        }
        
        //Get a filtered app layout list that respects the user's blacklisting settings and open/kill rules.
        let layoutList = filteredLayouts(withFilter: apps)
        
        //Skip the confirmation prompt if the user doesn't want it.
        guard localSettings.askBeforeKilling && !localSettings.deviceLocked else {
            killInLayoutList(layoutList)
            return
        }
        
        //Present confirmation alert
        let alert = UIAlertController(title: "KillControl", message: "Are you sure you want to kill all apps?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Kill", style: .destructive, handler: { action in
            self.killInLayoutList(layoutList)
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        self.switcher.present(alert, animated: true)
    }
    
    //orion: new
    private func killInLayoutList(_ list: [SBAppLayout]) {
        //Play haptic feedback when all apps are killed (Only when the device is unlocked).
        if !localSettings.deviceLocked {
            let thud = UIImpactFeedbackGenerator(style: .medium)
            thud.prepare()
            thud.impactOccurred()
        }
        
        //Kill all apps.
        for layout in list {
            switcher._remove(layout, forReason: 0)
        }
    }
    
    public func invalidateTimer() {
        //Invalidate the timer.
        
        if let timer = timer {
            if timer.isValid {
                timer.invalidate()
            }
        }
    }
    
    private override init() {}
}
