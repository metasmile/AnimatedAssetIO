//
//  TimeLapseBuilder.swift
//  Vapor
//
//  Originally Created by Adam Jensen (github.com/acj) on 5/10/15.
//  Newly Written by metasmile (github.com/metasmile) on 9/12/16.
//
// NOTE: This implementation is written in Swift 2.0.

import AVFoundation
import UIKit

let kErrorDomain = "TimeLapseBuilder"
let kFailedToStartAssetWriterError = 0
let kFailedToAppendPixelBufferError = 1

public class TimeLapseMovieWriter: NSObject {
    public var photoPaths: [String]
    public var inputSize: CGSize = CGSizeZero
    public var outputSize: CGSize = CGSizeZero
    public var FPS:Int32 = 30
    public var destinationFilePath: String?
    public var pixelFormatType:OSType = kCVPixelFormatType_32ARGB

    var videoWriter: AVAssetWriter?

    public init(photoPaths: [String]) {
        self.photoPaths = photoPaths
    }

    func initProperties(){
        if CGSizeEqualToSize(self.inputSize, CGSizeZero){
            self.inputSize = UIImage(contentsOfFile: photoPaths.first! as String)!.size
            self.outputSize = self.inputSize
        }
    }

    public func write(progress: ((progress: NSProgress, error: NSError?) -> Void)?, success: (NSURL -> Void), failure: (NSError -> Void)) {
        
        self.initProperties()

        let inputSize = self.inputSize
        let outputSize = self.outputSize
        var error: NSError?

        let documentsPath = self.destinationFilePath ?? (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("TimeLapseVideo.mov")
        let videoOutputURL = NSURL(fileURLWithPath: documentsPath)

        do {
            try NSFileManager.defaultManager().removeItemAtURL(videoOutputURL)
        } catch {}

        do {
            try videoWriter = AVAssetWriter(URL: videoOutputURL, fileType: AVFileTypeQuickTimeMovie)
        } catch let writerError as NSError {
            error = writerError
            videoWriter = nil
        }

        if let videoWriter = videoWriter {
            let videoSettings: [String : AnyObject] = [
                    AVVideoCodecKey  : AVVideoCodecH264,
                    AVVideoWidthKey  : outputSize.width,
                    AVVideoHeightKey : outputSize.height,
//        AVVideoCompressionPropertiesKey : [
//          AVVideoAverageBitRateKey : NSInteger(1000000),
//          AVVideoMaxKeyFrameIntervalKey : NSInteger(16),
//          AVVideoProfileLevelKey : AVVideoProfileLevelH264BaselineAutoLevel
//        ]
            ]

            let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings)

            let sourceBufferAttributes = [String : AnyObject](dictionaryLiteral:
            (kCVPixelBufferPixelFormatTypeKey as String, Int(self.pixelFormatType)),
                    (kCVPixelBufferWidthKey as String, Float(inputSize.width)),
                    (kCVPixelBufferHeightKey as String, Float(inputSize.height))
                    )

            let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoWriterInput,
                    sourcePixelBufferAttributes: sourceBufferAttributes
                    )

            assert(videoWriter.canAddInput(videoWriterInput))
            videoWriter.addInput(videoWriterInput)

            if videoWriter.startWriting() {
                videoWriter.startSessionAtSourceTime(kCMTimeZero)
                assert(pixelBufferAdaptor.pixelBufferPool != nil)

                let media_queue = dispatch_queue_create("mediaInputQueue", nil)

                videoWriterInput.requestMediaDataWhenReadyOnQueue(media_queue, usingBlock: { () -> Void in
                    let fps: Int32 = self.FPS
                    let frameDuration = CMTimeMake(1, fps)
                    let currentProgress = NSProgress(totalUnitCount: Int64(self.photoPaths.count))

                    var frameCount: Int64 = 0
                    var remainingPhotoURLs = [String](self.photoPaths)

                    while !remainingPhotoURLs.isEmpty {
                        if videoWriterInput.readyForMoreMediaData{
                            let nextPhotoURL = remainingPhotoURLs.removeAtIndex(0)
                            print(remainingPhotoURLs.count)
                            let lastFrameTime = CMTimeMake(frameCount, fps)
                            let presentationTime = frameCount == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, frameDuration)


                            if !self.appendPixelBufferForImageAtURL(nextPhotoURL, pixelBufferAdaptor: pixelBufferAdaptor, presentationTime: presentationTime) {
                                error = NSError(
                                        domain: kErrorDomain,
                                        code: kFailedToAppendPixelBufferError,
                                        userInfo: [
                                                "description": "AVAssetWriterInputPixelBufferAdapter failed to append pixel buffer",
                                                "rawError": videoWriter.error ?? "(none)"
                                        ]
                                )

                                break
                            }

                            frameCount += 1

                            currentProgress.completedUnitCount = frameCount
                            progress?(progress:currentProgress, error:error)
                        }
                    }

                    videoWriterInput.markAsFinished()
                    videoWriter.finishWritingWithCompletionHandler { () -> Void in
                        if error == nil {
                            dispatch_async(dispatch_get_main_queue()) {
                                success(videoOutputURL)
                            }
                        }

                        self.videoWriter = nil
                    }
                })
            } else {
                error = NSError(
                        domain: kErrorDomain,
                        code: kFailedToStartAssetWriterError,
                        userInfo: ["description": "AVAssetWriter failed to start writing"]
                        )
            }
        }

        if let error = error {
            dispatch_async(dispatch_get_main_queue()) {
                failure(error)
            }
        }
    }

    func appendPixelBufferForImageAtURL(url: String, pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor, presentationTime: CMTime) -> Bool {
        var appendSucceeded = false

        autoreleasepool {
            let data:NSData? = NSData(data: NSFileManager.defaultManager().contentsAtPath(url)!)
            if let imageData = data,
            let image = UIImage(data: imageData),
            let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool {
                let pixelBufferPointer = UnsafeMutablePointer<CVPixelBuffer?>.alloc(1)
                let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(
                        kCFAllocatorDefault,
                        pixelBufferPool,
                        pixelBufferPointer
                        )

                if let pixelBuffer = pixelBufferPointer.memory where status == 0 {
                    fillPixelBufferFromImage(image, pixelBuffer: pixelBuffer)

                    appendSucceeded = pixelBufferAdaptor.appendPixelBuffer(
                            pixelBuffer,
                            withPresentationTime: presentationTime
                            )

                    pixelBufferPointer.destroy()
                } else {
                    NSLog("error: Failed to allocate pixel buffer from pool")
                }

                pixelBufferPointer.dealloc(1)
            }
        }

        return appendSucceeded
    }

    func fillPixelBufferFromImage(image: UIImage, pixelBuffer: CVPixelBufferRef) {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

        let context = CGBitmapContextCreate(
                pixelData,
                Int(image.size.width),
                Int(image.size.height),
                8,
                CVPixelBufferGetBytesPerRow(pixelBuffer),
                rgbColorSpace,
                CGImageAlphaInfo.PremultipliedFirst.rawValue
                )

        CGContextDrawImage(context!, CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage!)

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
    }
}
