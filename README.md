# ObjectDetection Ex

This is a extension of project [ObjectDetection](https://github.com/hollance/coreml-survival-guide/tree/master/MobileNetV2%2BSSDLite/ObjectDetection).

The original project only detects objects from camera. This project has extended to load a video from photo library with person detection. And it also records new video files into photo library once there's any person detected. 

The optional functions are also implemented: 

1. Draw bounding boxes at recorded video frame (*boxes are drawn but positions need to be tuned*)

2. Stop video recording automatically if no more person detected after the time of last detected
video frame over than 5 seconds (*another file will be created if a new person appears after stopped*)

## Process Explanation

After user selects a video, I'll create `AVPlayerItem` with the selected URL and create `AVPlayerItemVideoOutput` 
to bind with it via `add(_ output: AVPlayerItemOutput)`. Then, I create `CADisplayLink` and in the callback, `CVPixelBuffer` of  the next VSync will be copied  and sent to `VNImageRequestHandler` which is used to perform the detection request `VNCoreMLRequest`.  

According to detection results, I use a `CALayer` array in 1 `AlbumVideoPreview` to draw bounding boxes dynamically since the original project creates 10 `BoundingBoxView` and updates them on every run.

To record when a person is detected, I use `AVAssetWriter` and `AVAssetWriterInput` to write the video file. I also need to create `AVAssetWriterInputAdaptor` since I need to draw bounding boxes on the output images(video). Then I pass the detected pixel buffer `CVPixelBuffer`, corresponding time `CMTime` and boxes `CGRect` and use api `append(_ pixelBuffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) -> Bool` to write the file. 

After recording is finished, I use PhotoKit's `PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL) -> Self?` to move output file from application directory to the Photos library.

## Simplified Flowchart

<img src="https://user-images.githubusercontent.com/2072087/119514033-4d5c1300-bda7-11eb-93e5-3780121496ac.png" width="1024">
