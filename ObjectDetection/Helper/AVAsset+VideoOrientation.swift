//
//  AVAsset+VideoOrientation.swift
//  HumanDetector
//
//  Created by CHENCHIAN on 2021/5/25.
//

import AVKit

extension AVAsset {
    
    enum VideoOrientation {
        case right, up, left, down
        
        static func fromVideoAngle(degree: CGFloat) -> VideoOrientation? {
            switch Int(degree) {
            case 0: return .right
            case 90: return .up
            case 180: return .left
            case -90: return .down
            default: return nil
            }
        }
    }
    
    func videoOrientation() -> VideoOrientation? {
        guard let firstVideoTrack = tracks(withMediaType: .video).first else { return nil }
        
        let transform = firstVideoTrack.preferredTransform
        let radians = atan2f(Float(transform.b), Float(transform.a))
        return VideoOrientation.fromVideoAngle(degree: CGFloat(radians * 180.0 / .pi))
    }
}
