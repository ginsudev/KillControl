//
//  KCAppResults.swift
//  
//
//  Created by Noah Little on 17/7/2022.
//

import Orion
import KillControlC

@objc enum KCFilterType: Int {
    case noFilter = 0
    case whiteListed = 1
    case media = 2
}

final class KCAppResults: NSObject {

    public func identfierForItem(withLayout layout: SBAppLayout?) -> String? {
        //Returns the bundle identifier of an app card.
        
        guard let layout = layout else {
            return nil
        }
        
        let displayItem = Ivars<SBPBDisplayItem>(layout.protobufRepresentation())._primaryDisplayItem
        let identifier: String = Ivars<NSString>(displayItem)._bundleIdentifier as String
        return identifier
    }
    
    public func filterTypeForItem(withIdentifier identifier: String) -> KCFilterType {
        //Returns true if app is whitelisted.
        
        //Check and return if app is media app.
        if localSettings.excludeMediaApps {
            if let nowPlayingApp = SBMediaController.sharedInstance().nowPlayingApplication() {
                if nowPlayingApp.bundleIdentifier == identifier && !SBMediaController.sharedInstance().isPaused() {
                    return .media
                }
            }
        }
        
        //Check and return if app is white listed.
        if localSettings.whitelistApps.contains(identifier) {
            return .whiteListed
        }
        
        //App has no filter, return with no filter.
        return .noFilter
    }
}
