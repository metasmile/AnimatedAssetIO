//
//  LivePhotoImageResourceWriter.swift
//  Live Photos
//
//  Originally Created by genadyo (github.com/genadyo).
//  Newly Written by metasmile (github.com/metasmile) on 9/12/16.
//

import Foundation
import MobileCoreServices
import ImageIO

public class LivePhotoImageResourceWriter: NSObject {
    private let kFigAppleMakerNote_AssetIdentifier = "17"
    public var path : String

    public init(path : String) {
        self.path = path
    }

    func read() -> String? {
        guard let makerNote = metadata()?.objectForKey(kCGImagePropertyMakerAppleDictionary) as! NSDictionary? else {
            return nil
        }
        return makerNote.objectForKey(kFigAppleMakerNote_AssetIdentifier) as! String?
    }

    public func write(destPath: String, assetIdentifier : String) {
        guard let dest = CGImageDestinationCreateWithURL(NSURL(fileURLWithPath: destPath), kUTTypeJPEG, 1, nil)
            else { return }
        defer { CGImageDestinationFinalize(dest) }
        guard let imageSource = self.imageSource() else { return }
        guard let metadata = self.metadata()?.mutableCopy() as! NSMutableDictionary! else { return }

        let makerNote = NSMutableDictionary()
        makerNote.setObject(assetIdentifier, forKey: kFigAppleMakerNote_AssetIdentifier)
        metadata.setObject(makerNote, forKey: kCGImagePropertyMakerAppleDictionary as String)
        CGImageDestinationAddImageFromSource(dest, imageSource, 0, metadata)
    }

    private func metadata() -> NSDictionary? {
        return self.imageSource().flatMap {
            CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as NSDictionary?
        }
    }

    private func imageSource() ->  CGImageSourceRef? {
        return self.data().flatMap {
            CGImageSourceCreateWithData($0, nil)
        }
    }

    private func data() -> NSData? {
        return NSData(contentsOfFile: path)
    }
}