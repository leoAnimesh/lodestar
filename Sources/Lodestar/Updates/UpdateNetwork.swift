import Foundation
import LodestarCore

enum UpdateNetworkError: Error, CustomStringConvertible {
    case hostNotAllowed(String)
    case httpStatus(Int)
    case rateLimited
    case noRelease
    case tooLarge
    case transport(String)

    var description: String {
        switch self {
        case .hostNotAllowed(let host): return "Lodestar only downloads updates from GitHub, not from \(host)."
        case .httpStatus(let code): return "GitHub answered with HTTP \(code)."
        case .rateLimited: return "GitHub is limiting requests right now. Try again in a little while."
        case .noRelease: return "No Lodestar release has been published yet."
        case .tooLarge: return "The response from GitHub was unexpectedly large, so it was not used."
        case .transport(let reason): return reason
        }
    }
}

/// The updater's only network access: an ephemeral URLSession (no cookies,
/// no cache, no credentials) that checks every URL and redirect against
/// `UpdateHostPolicy` and reports download progress.
final class UpdateNetwork: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate {
    struct Response {
        let status: Int
        let data: Data
        let etag: String?
    }

    let policy: UpdateHostPolicy
    private let userAgent: String
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 15 * 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var downloads: [Int: (progress: (Int64, Int64?) -> Void, continuation: CheckedContinuation<URL, Error>, destination: URL, limit: Int64)] = [:]

    init(policy: UpdateHostPolicy, appVersion: String) {
        self.policy = policy
        self.userAgent = "Lodestar/\(appVersion) (+https://github.com/\(UpdateFeed.repository))"
    }

    func invalidate() { session.invalidateAndCancel() }

    private func request(_ url: URL, accept: String) throws -> URLRequest {
        guard policy.allows(url) else { throw UpdateNetworkError.hostNotAllowed(url.host ?? url.absoluteString) }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    /// GET with an optional `If-None-Match`. 304 comes back as status 304 with empty data.
    func fetch(_ url: URL, etag: String? = nil, accept: String = "application/vnd.github+json", limit: Int = 5 << 20) async throws -> Response {
        var request = try request(url, accept: accept)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as UpdateNetworkError {
            throw error
        } catch {
            throw UpdateNetworkError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw UpdateNetworkError.transport("Not an HTTP response.") }
        switch http.statusCode {
        case 200..<300, 304: break
        case 300..<400: throw UpdateNetworkError.hostNotAllowed(Self.redirectHost(http))
        case 404: throw UpdateNetworkError.noRelease
        case 403, 429: throw UpdateNetworkError.rateLimited
        default: throw UpdateNetworkError.httpStatus(http.statusCode)
        }
        guard data.count <= limit else { throw UpdateNetworkError.tooLarge }
        return Response(status: http.statusCode, data: data, etag: http.value(forHTTPHeaderField: "ETag"))
    }

    /// Downloads `url` to `destination`, reporting (received, expected) bytes.
    func download(_ url: URL, to destination: URL, limit: Int64 = 300 << 20,
                  progress: @escaping (Int64, Int64?) -> Void) async throws -> URL {
        let request = try request(url, accept: "application/octet-stream")
        let task = session.downloadTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                downloads[task.taskIdentifier] = (progress, continuation, destination, limit)
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func takeDownload(_ id: Int) -> (progress: (Int64, Int64?) -> Void, continuation: CheckedContinuation<URL, Error>, destination: URL, limit: Int64)? {
        lock.lock(); defer { lock.unlock() }
        return downloads.removeValue(forKey: id)
    }

    private func peekDownload(_ id: Int) -> (progress: (Int64, Int64?) -> Void, continuation: CheckedContinuation<URL, Error>, destination: URL, limit: Int64)? {
        lock.lock(); defer { lock.unlock() }
        return downloads[id]
    }

    private static func redirectHost(_ response: HTTPURLResponse) -> String {
        response.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:))?.host ?? "a redirect outside GitHub"
    }

    // MARK: URLSession delegate

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Release downloads redirect from github.com to a githubusercontent.com host.
        if let url = request.url, policy.allows(url) {
            completionHandler(request)
        } else {
            // Not followed: the 3xx response itself completes the task and is
            // reported as a blocked redirect.
            completionHandler(nil)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let entry = peekDownload(downloadTask.taskIdentifier) else { return }
        if totalBytesWritten > entry.limit { downloadTask.cancel(); return }
        entry.progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let entry = takeDownload(downloadTask.taskIdentifier) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error: UpdateNetworkError
            switch status {
            case 300..<400: error = .hostNotAllowed((downloadTask.response as? HTTPURLResponse).map(Self.redirectHost) ?? "elsewhere")
            case 404: error = .noRelease
            default: error = .httpStatus(status)
            }
            entry.continuation.resume(throwing: error)
            return
        }
        do {
            // The temporary file is deleted when this method returns: move it now.
            try? FileManager.default.removeItem(at: entry.destination)
            try FileManager.default.moveItem(at: location, to: entry.destination)
            entry.continuation.resume(returning: entry.destination)
        } catch {
            entry.continuation.resume(throwing: UpdateNetworkError.transport("Couldn't save the download: \(error.localizedDescription)"))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let entry = takeDownload(task.taskIdentifier) else { return }
        if (error as? URLError)?.code == .cancelled {
            entry.continuation.resume(throwing: CancellationError())
        } else {
            entry.continuation.resume(throwing: UpdateNetworkError.transport(error.localizedDescription))
        }
    }
}
