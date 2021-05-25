//
//  VideoPreview.swift
//  HumanDetector
//
//  Created by CHENCHIAN on 2021/5/24.
//

import AVKit
import Vision

class AlbumVideoPreview: UIView {

    private var boxes: [CALayer] = []
    
    func setupPreview(with player: AVPlayer) {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        layer.addSublayer(playerLayer)
        backgroundColor = .black
    }
    
    func draw(withBoundingBoxes boundingBoxes: [CGRect]) {
        // clear previous boxes
        boxes.forEach { $0.removeFromSuperlayer() }
        boxes.removeAll()
        
        // draw new boxes
        for box in boundingBoxes {
            let shapeLayer = CAShapeLayer()
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.lineWidth = 4
            let path = UIBezierPath(rect: box)
            shapeLayer.path = path.cgPath
            shapeLayer.strokeColor = UIColor.red.cgColor
            shapeLayer.isHidden = false
            layer.addSublayer(shapeLayer)
            boxes.append(shapeLayer)
        }
    }
}
