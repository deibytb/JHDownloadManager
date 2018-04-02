//
//  JHDownloadBatch.swift
//  Pods
//
//  Created by James Huynh on 21/2/16.
//
//

import UIKit

public enum FileHashAlgorithm: Int {
    case MD5 = 1
    case SHA1 = 2
    case SHA512 = 3
}

public enum JHDownloadTaskStatus: Int {
    case BinaryUnits = 1
    case OSNativeUnits = 2
    case LocalizedFormat = 4
}

public class JHDownloadBatch: NSObject {
    private var downloadInputs: [JHDownloadTask] = [JHDownloadTask]()
    private var urls:[String] = [String]()
    private var session:URLSession?
    private var fileHashAlgorithm:FileHashAlgorithm!
    private var numberOfBytesDownloadedSinceStart:Int = 0
    private var startTime: NSDate?
    internal var completed: Bool = false
    
    required public init(fileHashAlgorithm:FileHashAlgorithm) {
        super.init()
        self.fileHashAlgorithm = fileHashAlgorithm
    }
    
    func addTask(taskInfo: [String: AnyObject]) -> JHDownloadTask? {
        var urlString:String?
        
        assert(taskInfo["url"] != nil, "Task Info's URL must not be present")
        assert(taskInfo["url"] is NSURL || taskInfo["url"] is String, "Task Info's URL must be NSURL or String")
        assert(taskInfo["destination"] != nil, "Task Info's Destination must be present")
        assert(taskInfo["destination"] is String, "Task Info's Destination must be a String")
        
        if let url = taskInfo["url"] as? NSURL {
            urlString = url.absoluteString
        } else if let url = taskInfo["url"] as? String {
            urlString = url
        }//end else
        
        let destination = taskInfo["destination"] as! String
        var totalExpectedToWrite:Int64 = 0
        if let fileSize = taskInfo["fileSize"] as? Int {
            totalExpectedToWrite = Int64(fileSize)
        }//end if
        if let unwrappedURLString = urlString {
            if self.isTaskExistWithURL(urlString: unwrappedURLString) == false {
                let downloadTask = JHDownloadTask(urlString: urlString!, destination: destination, totalBytesExpectedToWrite: totalExpectedToWrite, checksum: taskInfo["checksum"] as? String, fileHashAltgorithm: self.fileHashAlgorithm)
                
                if let identifier = taskInfo["identifier"] as? String {
                    downloadTask.identifier = identifier
                }//end if
                downloadTask.position = self.downloadInputs.count
                
                urls.append(unwrappedURLString)
                downloadInputs.append(downloadTask)
                
                return downloadTask
            }
        }
        return nil
    }
    
    func isTaskExistWithURL(urlString: String) -> Bool {
        return self.urls.index(of: urlString) != nil
    }
    
    func handleDownloadFileAt(downloadFileLocation: NSURL, forDownloadURL:String) -> Bool {
        if let downloadTask = self.downloadInfoOfTaskUrl(url: forDownloadURL) {
            let absoluteDestinationPath = downloadTask.absoluteDestinationPath()
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: absoluteDestinationPath) {
                do {
                    try fileManager.removeItem(atPath: absoluteDestinationPath)
                } catch {
                    print("Something went wrong when removing the file")
                    return false
                }
            }
            do {
                try fileManager.moveItem(atPath: downloadFileLocation.path!, toPath: absoluteDestinationPath)
            } catch let error as NSError {
                puts(error.description)
                return false
            }
          
            downloadTask.isDownloading = false
            let isVerified = downloadTask.verifyDownload()
            if isVerified {
                self.updateCompleteStatus()
            }//end if
            return isVerified
        }
        
        return false
    }
    
    func captureDownloadingInfoOfDownloadTask(downloadTask: URLSessionDownloadTask) -> JHDownloadTask? {
        if let url = downloadTask.originalRequest?.url {
            if let downloadTaskInfo = self.downloadInfoOfTaskUrl(url: url.absoluteString) {
                downloadTaskInfo.totalBytesWritten = downloadTask.countOfBytesReceived
                if downloadTaskInfo.totalBytesExpectedToWrite == 0 {
                    downloadTaskInfo.totalBytesExpectedToWrite = downloadTask.countOfBytesExpectedToReceive
                }
                return downloadTaskInfo
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    func updateProgressOfDownloadURL(url:String, progressPercentage:Float, totalBytesWritten:Int64) -> JHDownloadTask? {
        if let downloadTask = self.downloadInfoOfTaskUrl(url: url) {
            numberOfBytesDownloadedSinceStart += Int(totalBytesWritten) - Int(downloadTask.totalBytesWritten)
            downloadTask.totalBytesWritten = totalBytesWritten
            return downloadTask
        }//end if
        
        return nil
    }
    
    func downloadObjects() -> [JHDownloadTask] {
        return self.downloadInputs
    }
    
    func downloadInfoOfTaskUrl(url: String) -> JHDownloadTask? {
        if let indexOfObject = urls.index(of: url) {
            return downloadInputs[Int(indexOfObject)]
        } else {
            return nil
        }
    }
    
    func startDownloadTask(downloadTask: JHDownloadTask) {
        let request = NSMutableURLRequest(url: downloadTask.getURL() as URL)
        if downloadTask.totalBytesExpectedToWrite == 0 {
            self.requestForTotalBytesForURL(url: downloadTask.getURL(), callback: { (totalBytes) -> () in
                downloadTask.totalBytesExpectedToWrite = totalBytes
                self.downloadRequest(request: request, task: downloadTask)
            })
        } else {
            self.downloadRequest(request: request, task: downloadTask)
        }
    }
    
    func requestForTotalBytesForURL(url: NSURL, callback: @escaping (Int64) -> ()) {
        let headRequest = NSMutableURLRequest(url: url as URL)
        headRequest.setValue("", forHTTPHeaderField: "Accept-Encoding")
        headRequest.httpMethod = "HEAD"
        
        let sharedSession = URLSession.shared
        let headTask = sharedSession.dataTask(with: headRequest as URLRequest) { (data, response, error) -> Void in
            if let expectedContentLength = response?.expectedContentLength {
                callback(expectedContentLength)
            } else {
                callback(-1)
            }
        }
        headTask.resume()
    }
    
    func redownloadRequestOfTask(task:JHDownloadTask) {
        if let error = task.downloadError {
            if let resumableData = error.userInfo[NSURLSessionDownloadTaskResumeData] as? NSData {
                if let unwrappedSession = self.session {
                    let downloadTask = unwrappedSession.downloadTask(withResumeData: resumableData as Data)
                    task.cleanUpWithResumableData(data: resumableData)
                    downloadTask.resume()
                }
            }
        } else {
            let request = NSMutableURLRequest(url: task.getURL() as URL)
            request.timeoutInterval = 90
            if let unwrappedSession = self.session {
                let downloadTask = unwrappedSession.downloadTask(with: request as URLRequest)
                task.cleanUp()
                downloadTask.cancel()
                self.startDownloadTask(downloadTask: task)
            }
        }
    }
    
    func downloadRequest(request: NSMutableURLRequest, task: JHDownloadTask) {
        request.timeoutInterval = 90
        if let unwrappedSession = self.session {
            if let error = task.downloadError {
                let downloadTask = unwrappedSession.downloadTask(withResumeData: (error.userInfo[NSURLSessionDownloadTaskResumeData] as! NSData) as Data)
                task.isDownloading = true
                downloadTask.resume()
                task.downloadError = nil
            } else {
                let downloadTask = unwrappedSession.downloadTask(with: request as URLRequest)
                task.isDownloading = true
                downloadTask.resume()
            }
        }
    }
    
    func totalBytesWrittenAndReceived() -> [String: Int64] {
        var totalDownloadedBytes:Int64 = 0
        var totalBytesExpectedToReceived:Int64 = 0
        for task in downloadInputs {
            totalDownloadedBytes += task.totalBytesWritten
            totalBytesExpectedToReceived += task.totalBytesExpectedToWrite
        }//end for
        
        return ["totalDownloadedBytes": totalDownloadedBytes, "totalToBeReceivedBytes": totalBytesExpectedToReceived]
    }
    
    func updateCompleteStatus() {
        for task in downloadInputs {
            if task.completed == false {
                self.completed = false
                return
            }
        }
        
        self.completed = true
    }
    
    func setDownloadingSession(inputSession: URLSession) {
        self.startTime = NSDate()
        self.session = inputSession
    }
    
    func continuteAllInCompleteDownloadTask() {
        for task in downloadInputs {
            if task.completed == false {
                self.startDownloadTask(downloadTask: task)
            }
        }
    }
    
    func resumeAllSuspendedTasks() {
        if let unwrappedSession = session {
            unwrappedSession.getTasksWithCompletionHandler({ (dataTasks, uploadTasks, downloadTasks) -> Void in
                for downloadTask in downloadTasks {
                    if let urlString = downloadTask.originalRequest?.url?.absoluteString {
                        if let _ = self.downloadInfoOfTaskUrl(url: urlString) {
                            if downloadTask.state == URLSessionTask.State.suspended {
                                downloadTask.resume()
                            }
                        }
                    }
                }
            })
        }
    }
    
    func suspendAllOngoingDownloadTasks() {
        if let unwrappedSession = session {
            unwrappedSession.getTasksWithCompletionHandler({ (dataTasks, uploadTasks, downloadTasks) -> Void in
                for downloadTask in downloadTasks {
                    if let urlString = downloadTask.originalRequest?.url?.absoluteString {
                        if let _ = self.downloadInfoOfTaskUrl(url: urlString) {
                            if downloadTask.state == URLSessionTask.State.running {
                                downloadTask.suspend()
                            }
                        }
                    }
                }
            })
        }
    }
    
    func elapsedSeconds() -> Double {
        let now = NSDate()
        if let unwrappedStartTime = startTime {
            let distanceBetweenDates = now.timeIntervalSince(unwrappedStartTime as Date)
            return distanceBetweenDates
        } else {
            return 0
        }
    }
    
    func downloadRate() -> Int64 {
        let rate = Int64(Double(numberOfBytesDownloadedSinceStart) / self.elapsedSeconds())
        return rate
    }
    
    func isDownloading() -> Bool {
        return session != nil
    }
}
