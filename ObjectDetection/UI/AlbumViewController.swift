//
//  ViewController.swift
//  HumanDetector
//
//  Created by CHENCHIAN on 2021/5/22.
//

import MobileCoreServices
import PhotosUI
import Vision

class AlbumViewController: UIViewController, UINavigationControllerDelegate {
    
    static let kAutoStopInterval = 5.0
    
    // MARK: - Core ML Model
    
    let coreMLModel = try! MobileNetV2_SSDLite(contentsOf: MobileNetV2_SSDLite.urlOfModelInThisBundle)
    
    // MARK: - Vision Properties
    
    lazy var visionModel: VNCoreMLModel = {
        do {
            return try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Failed to create VNCoreMLModel: \(error)")
        }
    }()
    
    // MARK: - AV Properties
    
    let player: AVPlayer = AVPlayer()
    var recordService: RecordService?
    var stopRecordTimer: Timer?
    lazy var videoOutput: AVPlayerItemVideoOutput = {
        let pixelBufferAttrs = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA)]
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttrs)
        videoOutput.setDelegate(self, queue: nil)
        return videoOutput
    }()
    
    lazy var displayLink: CADisplayLink = {
        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback(_:)))
        displayLink.add(to: RunLoop.current, forMode: .default)
        displayLink.isPaused = true
        return displayLink
    }()
    
    // MARK: - UI Properties
    
    lazy var importButton: UIButton = {
        let button = UIButton()
        button.setTitle("choose a video", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 20)
        button.layer.borderColor = UIColor.white.cgColor
        button.layer.borderWidth = 5.0
        button.layer.cornerRadius = 15.0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(selectVideo), for: .touchUpInside)
        return button
    }()
    
    lazy var detectButton: UIButton = {
        let button = UIButton()
        button.setTitle("analyze", for: .normal)
        button.setTitleColor(.darkGray, for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 20)
        button.layer.borderColor = UIColor.darkGray.cgColor
        button.layer.borderWidth = 5.0
        button.layer.cornerRadius = 15.0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(analyzeVideo), for: .touchUpInside)
        button.isEnabled = false
        return button
    }()
    
    lazy var videoThumbnail: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    lazy var videoPreview: AlbumVideoPreview = {
        let videoPreview = AlbumVideoPreview(frame: view.bounds)
        videoPreview.setupPreview(with: player)
        return videoPreview
    }()

    var videoUrl: URL? {
        willSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let _ = newValue {
                    self.detectButton.isEnabled = true
                    self.detectButton.setTitleColor(.white, for: .normal)
                    self.detectButton.layer.borderColor = UIColor.white.cgColor
                } else {
                    self.detectButton.isEnabled = false
                    self.detectButton.setTitleColor(.darkGray, for: .normal)
                    self.detectButton.layer.borderColor = UIColor.darkGray.cgColor
                }
            }
        }
    }
    
    // Synchronize prediction requests
    let semaphore = DispatchSemaphore(value: 1)

    // MARK: - UI Methods

    deinit {
        displayLink.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        layoutUI()
        
        // Register a notification when the item plays to its end time
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToEndTime),
                                               name: Notification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: nil)
    }
    
    func layoutUI() {
        view.backgroundColor = .black
        view.addSubview(importButton)
        view.addSubview(detectButton)
        view.addSubview(videoThumbnail)
        NSLayoutConstraint.activate([
            importButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200.0),
            importButton.heightAnchor.constraint(equalToConstant: 70.0),
            importButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 100.0),
            importButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            detectButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200.0),
            detectButton.heightAnchor.constraint(equalToConstant: 70.0),
            detectButton.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 50.0),
            detectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            videoThumbnail.widthAnchor.constraint(equalToConstant: 150.0),
            videoThumbnail.heightAnchor.constraint(equalToConstant: 150.0),
            videoThumbnail.topAnchor.constraint(equalTo: detectButton.bottomAnchor, constant: 100.0),
            videoThumbnail.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    @objc func selectVideo(){        
        requestPermission {
            /// Comment off since  using PHPickerViewController on iOS 14 gets following error after a file is selected:
            /// [default] [ERROR] Could not create a bookmark: NSError: Cocoa 257 "The file couldn’t be opened because you don’t have permission to view it." }
            /// (staying tuned) https://developer.apple.com/forums/thread/654021
//            if #available(iOS 14.0, *) {
//                var configuration = PHPickerConfiguration()
//                configuration.filter = .videos
//                let picker = PHPickerViewController(configuration: configuration)
//                picker.delegate = self
//                self.present(picker, animated: true)
//            } else {
                let picker = UIImagePickerController()
                picker.delegate = self
                picker.sourceType = .savedPhotosAlbum
                picker.mediaTypes = [kUTTypeMovie as String]
                self.present(picker, animated: true)
//            }
        }
    }
    
    func requestPermission(completion: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized:
            completion()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization() { [weak self] (status) in
                DispatchQueue.main.async {
                    if status == .authorized {
                        completion()
                    } else {
                        self?.openSettings()
                    }
                }
            }
        case .denied, .restricted, .limited:
            fallthrough
        @unknown default:
            openSettings()
        }
    }
    
    func openSettings() {
        let alertMessage = "Please allow ”All Photos” access in Settings."
        let alert = UIAlertController(title: "Allow all photos access", message: alertMessage, preferredStyle: .alert)
        let goAction = UIAlertAction(title: "OK", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString),
                  UIApplication.shared.canOpenURL(url) else {
                assertionFailure("Not able to open App privacy settings")
                return
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        alert.addAction(goAction)
        present(alert, animated: true)
    }
    
    func showVideoPreview(_ show: Bool) {
        UIView.transition(with: view, duration: 0.25, options: .transitionFlipFromLeft) { [weak self] in
            guard let self = self else { return }
            if show {
                self.view.addSubview(self.videoPreview)
            } else {
                self.videoPreview.removeFromSuperview()
            }
        }
    }

    // MARK: - CADisplayLink Callback
    
    @objc func displayLinkCallback(_ sender: CADisplayLink) {
        /*
         The callback gets called once every Vsync.
         Using the display link's timestamp and duration we can compute the next time the screen will be refreshed, and copy the pixel buffer for that time
         This pixel buffer can then be processed and later rendered on screen.
         */
        var outputItemTime = CMTime.invalid
        
        // Calculate the nextVsync time which is when the screen will be refreshed next.
        let nextVSync = (sender.timestamp + sender.duration)
        
        outputItemTime = videoOutput.itemTime(forHostTime: nextVSync)
        if videoOutput.hasNewPixelBuffer(forItemTime: outputItemTime) {
            guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: outputItemTime, itemTimeForDisplay: nil) else { return }
            
            // Detect the pixel buffer
            predict(pixelBuffer: pixelBuffer, withPresentationTime: outputItemTime)
        }
    }
    
    // MARK: - Detection Methods
    
    @objc func analyzeVideo() {
        guard let url = videoUrl else { return }
        
        let item = AVPlayerItem(url: url)
        item.add(videoOutput)
        
        videoOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03) // 30ms is about 33fps
        
        player.actionAtItemEnd = .none
        player.replaceCurrentItem(with: item)
        
        DispatchQueue.main.async {
            self.showVideoPreview(true)
            self.player.play()
        }
    }
    
    func predict(pixelBuffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) {
        semaphore.wait()

        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            self?.postPredict(with: pixelBuffer, and: presentationTime, for: request, error: error)
        }
        // NOTE: If you use another crop/scale option, you must also change
        // how the BoundingBoxView objects get scaled when they are drawn.
        // Currently they assume the full input image is used.
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform Vision request: \(error)")
        }
    }

    func postPredict(with pixelBuffer: CVPixelBuffer, and presentationTime: CMTime, for request: VNRequest, error: Error?) {
        if let results = request.results as? [VNRecognizedObjectObservation] {
            let personPredictions = results.filter { $0.labels[0].identifier == "person" }

            // Calculate bounding box position
            var boxes = [CGRect]()
            for prediction in personPredictions {
                let width = view.bounds.width
                let height = width * 16 / 9
                let offsetY = (view.bounds.height - height) / 2
                let scale = CGAffineTransform.identity.scaledBy(x: width, y: height)
                let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height - offsetY)
                let boxRect = prediction.boundingBox.applying(scale).applying(transform)
                boxes.append(boxRect)
            }
            
            // Draw boxes
            videoPreview.draw(withBoundingBoxes: boxes)

            // Start recording if first person is found
            if boxes.count > 0 && recordService == nil {
                recordService = RecordService(withURL: RecordService.urlForNewVideo(),
                                              videoOrientation: player.currentItem?.asset.videoOrientation() ?? .up)
            }
            
            // Record the pixel buffer
            recordService?.write(boxes: boxes, onPixelBuffer: pixelBuffer, withPresentationTime: presentationTime)
            
            // Check the stop timer
            if recordService != nil {
                if stopRecordTimer == nil && boxes.isEmpty {
                    stopRecordTimer = Timer.scheduledTimer(withTimeInterval: AlbumViewController.kAutoStopInterval, repeats: false) { [weak self] (timer) in
                        self?.stopRecording()
                    }
                } else if stopRecordTimer != nil && !boxes.isEmpty {
                    stopRecordTimer?.invalidate()
                    stopRecordTimer = nil
                }
            }
        }
        semaphore.signal()
    }
    
    // MARK: - Notification Callback
    
    @objc func playerItemDidPlayToEndTime() {
        DispatchQueue.main.async {
            self.showVideoPreview(false)
        }
        displayLink.isPaused = true
        stopRecording()
    }
    
    func stopRecording() {
        recordService?.stopWriting()
        recordService = nil
        stopRecordTimer?.invalidate()
        stopRecordTimer = nil
    }
}

// MARK: - PHPickerViewControllerDelegate

@available(iOS 14.0, *)
extension AlbumViewController: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        
//        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] (url, error) in
//            self?.videoUrl = url // url from this api receives signalled err=2 (errno) (open failed)
//        }
        provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] (url, inPlace, error) in
            self?.videoUrl = url
            let generator = AVAssetImageGenerator(asset: AVAsset(url: url!))
            generator.appliesPreferredTrackTransform = true
            if let imageRef = try? generator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil) {
                self?.videoThumbnail.image = UIImage(cgImage: imageRef)
            }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension AlbumViewController: UIImagePickerControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        picker.delegate = nil

        videoUrl = info[.referenceURL] as! URL
        
        let generator = AVAssetImageGenerator(asset: AVAsset(url: videoUrl!))
        generator.appliesPreferredTrackTransform = true
        if let imageRef = try? generator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil) {
            videoThumbnail.image = UIImage(cgImage: imageRef)
        }
    }
}

// MARK: - AVPlayerItemOutputPullDelegate

extension AlbumViewController: AVPlayerItemOutputPullDelegate {
    
    func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        // Restart display link
        displayLink.isPaused = false
    }
}
