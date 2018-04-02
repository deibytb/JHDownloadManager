//
//  JHDownloadTask.swift
//  JHDownloadManager
//
//  Created by James Huynh on 20/2/16.
//  Copyright © 2016 jameshuynh. All rights reserved.
//

import UIKit
import FileMD5Hash

public class JHDownloadTask: NSObject {
    
    public var completed: Bool = false
    public var cachedProgress: Float = 0
    internal var totalBytesWritten: Int64 = 0
    internal var totalBytesExpectedToWrite: Int64 = 0
   
    internal var isDownloading = false
    public var url: NSURL?
    public var urlString: String?
    public var destination: String?
    public var fileName: String?
    public var checksum: String?
    public var downloadError: NSError?
    public var lastErrorMessage: String?
    
    public var identifier: String?
    public var position: Int = -1
    
    private var fileHashAlgorithm: FileHashAlgorithm?
    
    init(urlString: String, destination:String, totalBytesExpectedToWrite:Int64, checksum:String?, fileHashAltgorithm:FileHashAlgorithm) {
        super.init()
        self.url = NSURL(string: urlString)
        self.commonInit(urlString: urlString, destination: destination, totalBytesExpectedToWriteInput: totalBytesExpectedToWrite, checksum: checksum, fileHashAlgorithm: fileHashAltgorithm)
    }
    
    init(url: NSURL, destination:String, totalBytesExpectedToWrite:Int64, checksum:String?, fileHashAltgorithm:FileHashAlgorithm) {
        super.init()
        self.url = url
        self.commonInit(urlString: url.absoluteString!, destination: destination, totalBytesExpectedToWriteInput: totalBytesExpectedToWrite, checksum: checksum, fileHashAlgorithm: fileHashAltgorithm)
    }
    
    func getURL() -> NSURL {
        return self.url!
    }
    
    func commonInit(urlString: String, destination:String, totalBytesExpectedToWriteInput:Int64, checksum:String?, fileHashAlgorithm:FileHashAlgorithm) {
        self.urlString = urlString
        self.completed = false
        self.totalBytesWritten = 0
        self.totalBytesExpectedToWrite = totalBytesExpectedToWriteInput
        self.checksum = checksum
        self.fileHashAlgorithm = fileHashAlgorithm
        
        self.destination = destination
        self.fileName = (destination as NSString).lastPathComponent
        self.prepareFolderForDestination()
    }
    
    func downloadingProgress() -> Float {
        if self.completed {
            return 1
        }//end if
        
        if self.totalBytesExpectedToWrite > 0 {
            return Float(self.totalBytesWritten) / Float(self.totalBytesExpectedToWrite)
        } else {
            return 0
        }
    }
    
    func verifyDownload() -> Bool {
        let fileManager = FileManager.default
        let absoluteDestinationPath = self.absoluteDestinationPath()
        if fileManager.fileExists(atPath: absoluteDestinationPath) == false {
            return false
        }
        
        var isVerified = false
        if let unwrappedChecksum = self.checksum {
            let calculatedChecksum = self.retrieveChecksumDownnloadedFile()
            isVerified = calculatedChecksum == unwrappedChecksum
        } else {
            do {
                let fileAttributes = try fileManager.attributesOfItem(atPath: absoluteDestinationPath)
                let fileSize = (fileAttributes[FileAttributeKey.size] as! NSNumber).int64Value
                isVerified = fileSize == self.totalBytesExpectedToWrite
            } catch let error as NSError {
                print("Error Received \(error.localizedDescription)")
            } catch {
                print("Error Received")
            }
        }//end else
        
        if isVerified {
            self.completed = true
            self.cachedProgress = 1
        } else {
            self.totalBytesWritten = self.totalBytesExpectedToWrite
        }//end else
        
        return isVerified
    }
    
    func retrieveChecksumDownnloadedFile() -> String {
        let absolutePath = self.absoluteDestinationPath()
        if fileHashAlgorithm == FileHashAlgorithm.MD5 {
            return FileHash.md5HashOfFile(atPath: absolutePath)
        } else if fileHashAlgorithm == FileHashAlgorithm.SHA1 {
            return FileHash.sha1HashOfFile(atPath: absolutePath)
        } else if fileHashAlgorithm == FileHashAlgorithm.SHA512 {
            return FileHash.sha512HashOfFile(atPath: absolutePath)
        }//end else
        
        return "-1"
    }
    
    func prepareFolderForDestination() {
        let absoluteDestinationPath = self.absoluteDestinationPath()
        let containerFolderPath = (absoluteDestinationPath as NSString).deletingLastPathComponent
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: containerFolderPath) == false {
            do {
                try fileManager.createDirectory(atPath: containerFolderPath, withIntermediateDirectories: true, attributes: nil)
            } catch let error as NSError {
                print("Create Directory Error: \(error.localizedDescription)")
            } catch {
                print("Create Directory Error - Something went wrong")
            }
        }
        
        if fileManager.fileExists(atPath: absoluteDestinationPath) {
            if self.verifyDownload() {
                self.cachedProgress = 1
                // retain file - this task has been completed
            } else {
                self.cleanUp()
            }
        } else {
            self.cleanUp()
        }
    }
    
    func cleanUp() {
        self.completed = false
        self.downloadError = nil
        self.totalBytesWritten = 0
        self.cachedProgress = 0
        self.deleteDestinationFile()
    }
    
    func cleanUpWithResumableData(data: NSData) {
        self.completed = false
        self.totalBytesWritten = Int64(data.length)
        self.deleteDestinationFile()
        self.downloadError = nil
    }
    
    func deleteDestinationFile() {
        let fileManager = FileManager.default
        let absoluteDestinationPath = self.absoluteDestinationPath()
        if fileManager.fileExists(atPath: absoluteDestinationPath) {
            do {
                try fileManager.removeItem(atPath: absoluteDestinationPath)
            } catch let error as NSError {
                print("Removing Existing File Error: \(error.localizedDescription)")
            }
        }
    }
    
    func absoluteDestinationPath() -> String {
        let documentDictionary = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
        return "\(documentDictionary!)/\(self.destination!)"
    }
    
    func isHittingErrorBecauseOffline() -> Bool {
        if let _ = self.downloadError, let unwrappedLastErrorMessage = self.lastErrorMessage {
            
            return unwrappedLastErrorMessage.contains("(Code \(NSURLErrorNotConnectedToInternet))") || unwrappedLastErrorMessage.contains("(Code \(NSURLErrorNetworkConnectionLost))")
        } else {
            return false
        }
    }
    
    func isHittingErrorConnectingToServer() -> Bool {
        if let unwrappedLastErrorMessage = self.lastErrorMessage {
            return unwrappedLastErrorMessage.contains("(Code \(NSURLErrorRedirectToNonExistentLocation))") || unwrappedLastErrorMessage.contains("(Code \(NSURLErrorBadServerResponse))") ||
                unwrappedLastErrorMessage.contains("(Code \(NSURLErrorZeroByteResource))") || unwrappedLastErrorMessage.contains("(Code \(NSURLErrorTimedOut))")
        } else {
            return false
        }
    }
    
    func captureReceivedError(error:NSError) {
        self.downloadError = error
    }
    
    func fullErrorDescription() -> String {
        if let unwrappedError = self.downloadError {
            let errorCode = unwrappedError.code
            return "Downloading URL %@ failed because of error: \(String(describing: self.urlString)) (Code \(errorCode))"
        } else {
            return "No Error"
        }
    }
}
