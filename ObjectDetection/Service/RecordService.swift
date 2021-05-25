//
//  RecordService.swift
//  HumanDetector
//
//  Created by CHENCHIAN on 2021/5/24.
//

import AVKit
import Photos

struct RecordService {
    
    // MARK: - Properties
    
    private var avAssetWriter: AVAssetWriter?
    private var avAssetWriterInput: AVAssetWriterInput
    private var aVAssetWriterInputAdaptor: AVAssetWriterInputPixelBufferAdaptor // for bounding box drawing
    private var fileURL: URL
    
    // MARK: - Initializer
    
    init(withURL url: URL, videoOrientation: AVAsset.VideoOrientation) {
        avAssetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [AVVideoCodecKey:AVVideoCodecType.h264, AVVideoHeightKey:720, AVVideoWidthKey:1280])
        avAssetWriterInput.transform = RecordService.transformForNewVideo(from: videoOrientation)
        avAssetWriterInput.expectsMediaDataInRealTime = true
        
        aVAssetWriterInputAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: avAssetWriterInput, sourcePixelBufferAttributes: [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA)])        
        
        avAssetWriter = try? AVAssetWriter(url: RecordService.urlForNewVideo(), fileType: AVFileType.mp4)
        avAssetWriter?.add(avAssetWriterInput)
        avAssetWriter?.movieFragmentInterval = .invalid
        fileURL = url
    }

    // MARK: - Helper Methods

    static func transformForNewVideo(from videoOrientation: AVAsset.VideoOrientation) -> CGAffineTransform {
        switch videoOrientation {
        case .up:
            return CGAffineTransform(rotationAngle: .pi / 2)
        case .down:
            return CGAffineTransform(rotationAngle: -.pi / 2)
        case .right:
            return .identity
        case .left:
            return CGAffineTransform(rotationAngle: .pi)
        }
    }

    static func urlForNewVideo() -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = dateFormatter.string(from: Date()), ext = "mp4" // "2021-05-24-122426.mp4"
        let documentsFolder = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let dirURL = URL(fileURLWithPath: documentsFolder).appendingPathComponent("RecordedFiles", isDirectory: true)
        let fileURL = dirURL.appendingPathComponent(name).appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try! FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try! FileManager.default.removeItem(at: fileURL)
        }
        return fileURL
    }
    
    // MARK: - Writing Methods
    
    func write(sampleBuffer buffer: CMSampleBuffer) {
        guard let avAssetWriter = avAssetWriter else { return }

        if avAssetWriter.status == .unknown {
            avAssetWriter.startWriting()
            avAssetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
        }

        if avAssetWriterInput.isReadyForMoreMediaData {
            avAssetWriterInput.append(buffer)
        }
    }

    func write(pixelBuffer buffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) {
        guard let _ = avAssetWriter else { return }

        if aVAssetWriterInputAdaptor.assetWriterInput.isReadyForMoreMediaData {
            aVAssetWriterInputAdaptor.append(buffer, withPresentationTime: presentationTime)
        }
    }
    
    func write(boxes: [CGRect], onPixelBuffer buffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) {
        guard let avAssetWriter = avAssetWriter else { return }
        
        if avAssetWriter.status == .unknown {
            avAssetWriter.startWriting()
            avAssetWriter.startSession(atSourceTime: presentationTime)
        }
                
        guard !boxes.isEmpty else {
            // If no box, just append the original pixel buffer
            if aVAssetWriterInputAdaptor.assetWriterInput.isReadyForMoreMediaData {
                aVAssetWriterInputAdaptor.append(buffer, withPresentationTime: presentationTime)
            }
            return
        }
        
        // Make sure `CVPixelBuffer` will release after used
        autoreleasepool {
            // Lock `pixelBuffer` before working on it
            CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))

            // Deep copy buffer pixel to avoid memory leak
            var renderedOutputPixelBuffer: CVPixelBuffer? = nil
            let options = [
                String(kCVPixelBufferCGImageCompatibilityKey): true,
                String(kCVPixelBufferCGBitmapContextCompatibilityKey): true
            ] as CFDictionary
            let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                             CVPixelBufferGetWidth(buffer),
                                             CVPixelBufferGetHeight(buffer),
                                             kCVPixelFormatType_32BGRA,
                                             options,
                                             &renderedOutputPixelBuffer)
            guard status == kCVReturnSuccess else { return }

            CVPixelBufferLockBaseAddress(renderedOutputPixelBuffer!,
                                         CVPixelBufferLockFlags(rawValue: 0))

            let renderedOutputPixelBufferBaseAddress = CVPixelBufferGetBaseAddress(renderedOutputPixelBuffer!)

            memcpy(renderedOutputPixelBufferBaseAddress,
                   CVPixelBufferGetBaseAddress(buffer),
                   CVPixelBufferGetHeight(buffer) * CVPixelBufferGetBytesPerRow(buffer))

            // Lock the copy of pixel buffer when working on ti
            CVPixelBufferLockBaseAddress(renderedOutputPixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

            let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))
            let context = CGContext(data: renderedOutputPixelBufferBaseAddress,
                                    width: CVPixelBufferGetWidth(renderedOutputPixelBuffer!),
                                    height: CVPixelBufferGetHeight(renderedOutputPixelBuffer!),
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(renderedOutputPixelBuffer!),
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: bitmapInfo.rawValue)
            context?.setStrokeColor(UIColor.blue.cgColor)
            context?.setLineWidth(4.0)
            context?.addRects(boxes)
            context?.drawPath(using: .stroke)

            // Make sure adaptor and writer able to write
            if aVAssetWriterInputAdaptor.assetWriterInput.isReadyForMoreMediaData {
                aVAssetWriterInputAdaptor.append(renderedOutputPixelBuffer!, withPresentationTime: presentationTime)
            }

            // Unlock buffers after processed on them
            CVPixelBufferUnlockBaseAddress(renderedOutputPixelBuffer!,
                                           CVPixelBufferLockFlags(rawValue: 0))
            CVPixelBufferUnlockBaseAddress(buffer,
                                           CVPixelBufferLockFlags(rawValue: 0))
        }
    }
    
    func stopWriting() {
        guard let avAssetWriter = avAssetWriter else { return }

        avAssetWriter.finishWriting {
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
        }
    }
}
