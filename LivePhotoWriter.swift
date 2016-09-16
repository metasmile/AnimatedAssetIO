//
// Created by BLACKGENE on 9/16/16.
// Copyright (c) 2016 stells. All rights reserved.
//

import Foundation
import AVFoundation
import Photos

public typealias LivePhotoWriterResultHandler = ((success:Bool, imageURL:NSURL?, pairedVideoURL:NSURL?, error:NSError?) -> ())?
public typealias LivePhotoWriterAssetSavedHandler = ((success:Bool, localIdentifier:NSString?, error:NSError?) -> ())?
public typealias LivePhotoWriterAssetSavedAndFetchedHandler = ((success:Bool, livePhoto:PHLivePhoto?, asset:PHAsset?, error:NSError?) -> ())?

public class LivePhotoWriter {

    // MARK: Create PHLivePhoto
    public func createLivePhotoFromImages(paths: [String]
            , indexOfTitle: Int
            , progress: ((przogress:Double) -> Void)?
            , fps: Int32
            , created: ((livePhoto:PHLivePhoto?) -> Void)?
    ) {
        self.writeLivePhotoFromImages(paths, indexOfTitle: indexOfTitle, progress: progress, fps: fps) {
            success, imageURL, pairedVideoURL, _ in

            if success{
                self.createLivePhoto(imageURL!, withPairedVideo: pairedVideoURL!, completion: created)
            }else{
                created?(livePhoto:nil)
            }
        }
    }

    public func createLivePhotoFromVideo(videoPath: String
            , timeLocationOfTitle: Double
            , created: ((livePhoto:PHLivePhoto?) -> Void)?
    ) {
        self.writeLivePhotoFromVideo(videoPath, timeLocationOfTitle: timeLocationOfTitle, completion:{
            success, imageURL, pairedVideoURL, error in

            if success{
                self.createLivePhoto(imageURL!, withPairedVideo: pairedVideoURL!, completion: created)
            }else{
                created?(livePhoto:nil)
            }
        })
    }

    // MARK: Save LivePhoto to Library
    public func saveLivePhotoFromImages(paths: [String]
            , indexOfTitle: Int
            , progress: ((progress:Double) -> Void)?
            , fps: Int32
            , saved: LivePhotoWriterAssetSavedHandler
            , andFetched: LivePhotoWriterAssetSavedAndFetchedHandler
    ) {
        self.writeLivePhotoFromImages(paths, indexOfTitle: indexOfTitle, progress: progress, fps: fps) {
            success, imageURL, pairedVideoURL, _ in

            self.saveLivePhoto(imageURL!, withPairedVideo: pairedVideoURL!, completion: saved, fetchCompletion:andFetched)
        }

    }

    public func saveLivePhotoFromVideo(videoPath: String
            , timeLocationOfTitle : Double
            , saved: LivePhotoWriterAssetSavedHandler
            , andFetched: LivePhotoWriterAssetSavedAndFetchedHandler
    ) {
        self.writeLivePhotoFromVideo(videoPath, timeLocationOfTitle: timeLocationOfTitle, completion:{
            success, imageURL, pairedVideoURL, error in

            self.saveLivePhoto(imageURL!, withPairedVideo: pairedVideoURL!, completion: saved, fetchCompletion:andFetched)
        })
    }

    // MARK: PhotoKit Procedures
    func saveLivePhoto(imageURL: NSURL
            , withPairedVideo pairedVideoURL: NSURL
            , completion: LivePhotoWriterAssetSavedHandler
            , fetchCompletion: LivePhotoWriterAssetSavedAndFetchedHandler
    ) {

        var createdAssetsLocalIdentifier: String?

        PHPhotoLibrary.sharedPhotoLibrary().performChanges({
            let request = PHAssetCreationRequest.creationRequestForAsset()

            let options = PHAssetResourceCreationOptions()
            request.addResourceWithType(.PairedVideo, fileURL: pairedVideoURL, options: options)
            request.addResourceWithType(.Photo, fileURL: imageURL, options: options)

            createdAssetsLocalIdentifier = request.placeholderForCreatedAsset?.localIdentifier

        }, completionHandler: { success, error in
            completion?(success: success, localIdentifier: createdAssetsLocalIdentifier, error: error)

            if fetchCompletion != nil {
                if let createdAsset = PHAsset.fetchAssetsWithLocalIdentifiers([createdAssetsLocalIdentifier!], options: nil).firstObject as? PHAsset where success{
                    let livePhotoOptions = PHLivePhotoRequestOptions()
                    livePhotoOptions.deliveryMode = .HighQualityFormat

                    PHImageManager.defaultManager().requestLivePhotoForAsset(createdAsset
                            , targetSize: CGSizeZero
                            , contentMode: .Default
                            , options: livePhotoOptions
                            , resultHandler: { livePhoto, info in

                        if info?[PHImageCancelledKey]?.boolValue ?? false
                                || info?[PHImageErrorKey]?.boolValue ?? false
                                || info?[PHImageResultIsDegradedKey]?.boolValue ?? false {
                            return
                        }

                        fetchCompletion?(success: livePhoto != nil, livePhoto: livePhoto, asset: createdAsset, error: error)
                    })
                } else {
                    fetchCompletion?(success: success, livePhoto: nil, asset: nil, error: error)
                }
            }

            createdAssetsLocalIdentifier = nil
        })
    }

    func createLivePhoto(imageURL: NSURL
            , withPairedVideo pairedVideoURL: NSURL
            , completion: ((livePhoto:PHLivePhoto?) -> ())?
    ) {

        PHLivePhoto.requestLivePhotoWithResourceFileURLs([imageURL, pairedVideoURL], placeholderImage: nil, targetSize: CGSizeZero, contentMode: .Default, resultHandler:{
            livePhoto, info in

            if let livePhoto = livePhoto{
                if info[PHImageCancelledKey]?.boolValue ?? true
                        && info[PHLivePhotoInfoIsDegradedKey]?.boolValue ?? true {

                    completion?(livePhoto:livePhoto)
                }
            }else{
                completion?(livePhoto:nil)
            }
        })
    }

    // MARK: Core Utils
    func writeLivePhotoFromImages(photoPaths: [String]
            , indexOfTitle: Int
            , progress: ((progress:Double) -> Void)?
            , fps: Int32
            , completion: LivePhotoWriterResultHandler
    ) {

        if let titleImagePath = indexOfTitle < photoPaths.count-1 ? photoPaths[indexOfTitle] : photoPaths.first{
            let builder = TimeLapseMovieWriter(photoPaths: photoPaths)
            builder.FPS = fps
            builder.write({ prog in
                progress?(progress: prog.fractionCompleted)

            }, success: { url in
                self.writeLivePhoto(titleImagePath, withVideo: url.path!, completion: completion)

            }, failure: { error in
                completion?(success:false, imageURL:nil, pairedVideoURL:nil, error:error)
            })
        }else{
            completion?(success:false, imageURL:nil, pairedVideoURL:nil, error:nil)
        }
    }

    func writeLivePhotoFromVideo(videoPath: String
            , timeLocationOfTitle: Double
            , completion: LivePhotoWriterResultHandler
    ) {
        let asset = AVURLAsset(URL: NSURL.fileURLWithPath(videoPath), options: nil)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let tempPath = self.dynamicType.tempWritingPathByAppedingSuffix((videoPath as NSString).lastPathComponent, suffix: "", ext: nil).path!

        let destExtractedImagePath = self.dynamicType.tempWritingPathByAppedingSuffix(tempPath, suffix: "_extracted_image", ext: "jpg").path!

        let time = NSValue(CMTime: CMTimeMakeWithSeconds(CMTimeGetSeconds(asset.duration) * (timeLocationOfTitle ?? 0.5), asset.duration.timescale))

        generator.generateCGImagesAsynchronouslyForTimes([time]) {
            [weak self] _, image, _, result, error in

            if let image = image, data = UIImageJPEGRepresentation(UIImage(CGImage: image), 0.8)
            where result != .Succeeded
                    && error == nil
                    && data.writeToFile(destExtractedImagePath, atomically: true) {

                self?.writeLivePhoto(destExtractedImagePath, withVideo: videoPath, completion: completion)
            }
        }
    }

    func writeLivePhoto(photoPath: String
            , withVideo videoPath: String
            , completion: LivePhotoWriterResultHandler
    ) {

        dispatch_async(dispatch_queue_create("com.stells.livephotowriter.write", DISPATCH_QUEUE_SERIAL), {

            let destImageURL = self.dynamicType.tempWritingPathByAppedingSuffix((photoPath as NSString).lastPathComponent, suffix:"_encoded_livephoto", ext:nil)
            if NSFileManager.defaultManager().fileExistsAtPath(destImageURL.path!) {
                try! NSFileManager.defaultManager().removeItemAtPath(destImageURL.path!)
            }

            let destPairedVideoURL = self.dynamicType.tempWritingPathByAppedingSuffix((videoPath as NSString).lastPathComponent, suffix:"_encoded_livephoto", ext:nil)
            if NSFileManager.defaultManager().fileExistsAtPath(destPairedVideoURL.path!) {
                try! NSFileManager.defaultManager().removeItemAtPath(destPairedVideoURL.path!)
            }

            let uuid = NSUUID().UUIDString

            let photoWriter = LivePhotoImageResourceWriter(path:photoPath)
            photoWriter.write(destImageURL.path!, assetIdentifier: uuid)

            let pairedVideoWriter = LivePhotoImageResourceWriter(path:videoPath)
            pairedVideoWriter.write(destPairedVideoURL.path!, assetIdentifier: uuid)

            dispatch_async(dispatch_get_main_queue(),{
                completion?(success:true, imageURL:destImageURL, pairedVideoURL: destPairedVideoURL, error:nil)
            })
        })
    }

    static func tempWritingPathByAppedingSuffix(lastPathComponent:String
                                         ,suffix:String?
                                         ,ext:String?
    ) -> NSURL {
        let _lastPathComponent:NSString = lastPathComponent as NSString
        let tempPath = (_lastPathComponent .stringByDeletingLastPathComponent as NSString).stringByAppendingPathComponent(
                ((_lastPathComponent.stringByDeletingPathExtension as NSString)
                .stringByAppendingString(suffix! ?? "") as NSString)
                .stringByAppendingPathExtension(ext! ?? _lastPathComponent.pathExtension) ?? "")

        return NSURL.fileURLWithPath((NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(tempPath))
    }

}
