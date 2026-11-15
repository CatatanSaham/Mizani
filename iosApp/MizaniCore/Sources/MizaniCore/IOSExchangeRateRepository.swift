import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A daily reference-rate observation, kept as decimal text so callers never need to use
/// binary floating point for money conversion.
public struct IOSExchangeRateQuote: Codable, Equatable, Sendable {
    public let baseCurrencyCode: String
    public let quoteCurrencyCode: String
    public let rate: String
    public let date: String

    public init(
        baseCurrencyCode: String,
        quoteCurrencyCode: String,
        rate: String,
        date: String
    ) {
        self.baseCurrencyCode = baseCurrencyCode
        self.quoteCurrencyCode = quoteCurrencyCode
        self.rate = rate
        self.date = date
    }
}

public enum IOSExchangeRateRepositoryError: Error, Equatable, Sendable {
    case invalidCurrencyCode
    case currenciesMustDiffer
    case invalidRequest
    case transportFailure
    case responseTooLarge
    case redirectRejected
    case cookiesRejected
    case unavailable
    case httpStatus(Int)
    case malformedResponse
    case currencyPairMismatch
    case invalidRate
    case dateInvalid
    case dateInFuture
    case dateTooOld
}

/// Synchronous storage keeps the repository usable while offline. The repository calls it only
/// from its actor, so implementations should avoid doing network or long-running work here.
public protocol IOSExchangeRateStorage: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

/// The small response abstraction makes validation tests deterministic without a live network.
public struct IOSExchangeRateHTTPResponse: Sendable {
    public let statusCode: Int
    public let url: URL?
    public let headers: [String: String]
    public let data: Data

    public init(
        statusCode: Int,
        url: URL? = nil,
        headers: [String: String] = [:],
        data: Data
    ) {
        self.statusCode = statusCode
        self.url = url
        self.headers = headers
        self.data = data
    }
}

public protocol IOSExchangeRateHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> IOSExchangeRateHTTPResponse
}

/// App-private UserDefaults storage. It is intentionally separate from the encrypted finance DB:
/// the cache contains only a public currency pair, rate and provider date.
public final class IOSUserDefaultsExchangeRateStorage: IOSExchangeRateStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

/// Fetches Frankfurter's daily reference rate and retains a short-lived local cache for offline
/// use. The actor serializes cache access and coalesces concurrent refreshes for the same pair.
public actor IOSExchangeRateRepository {
    private struct CacheEnvelope: Codable, Sendable {
        let quote: IOSExchangeRateQuote
        let fetchedAtMilliseconds: Int64
    }

    private struct ProviderPayload: Decodable {
        let base: String
        let quote: String
        let rate: ProviderRate
        let date: String
    }

    private struct ProviderRate: Decodable {
        let text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self.text = text
                return
            }
            let decimal = try container.decode(Decimal.self)
            self.text = NSDecimalNumber(decimal: decimal).stringValue
        }
    }

    private let httpClient: any IOSExchangeRateHTTPClient
    private let storage: any IOSExchangeRateStorage
    private let now: @Sendable () -> Date
    private var refreshTasks: [String: Task<IOSExchangeRateQuote, Error>] = [:]

    public init(
        httpClient: (any IOSExchangeRateHTTPClient)? = nil,
        storage: (any IOSExchangeRateStorage)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.httpClient = httpClient ?? IOSExchangeRateURLSessionClient()
        self.storage = storage ?? IOSUserDefaultsExchangeRateStorage()
        self.now = now
    }

    /// Returns a cached quote only when its provider observation is no more than seven days old.
    /// A stale or malformed cache is treated as unavailable, allowing callers to use the offline
    /// path only with a bounded, validated observation.
    public func cachedRate(
        baseCurrencyCode: String,
        quoteCurrencyCode: String
    ) throws -> IOSExchangeRateQuote? {
        let pair = try normalizedPair(baseCurrencyCode: baseCurrencyCode, quoteCurrencyCode: quoteCurrencyCode)
        guard let envelope = readCache(for: pair) else { return nil }
        guard let quote = try? validatedCachedQuote(envelope.quote, pair: pair),
              (try? validateDate(quote.date, now: now())) != nil else {
            return nil
        }
        return quote
    }

    /// Returns true when no valid cache exists or the fetch timestamp is at least twelve hours old.
    public func shouldRefresh(
        baseCurrencyCode: String,
        quoteCurrencyCode: String
    ) throws -> Bool {
        let pair = try normalizedPair(baseCurrencyCode: baseCurrencyCode, quoteCurrencyCode: quoteCurrencyCode)
        guard let envelope = readCache(for: pair),
              let quote = try? validatedCachedQuote(envelope.quote, pair: pair),
              (try? validateDate(quote.date, now: now())) != nil else {
            return true
        }
        let currentMilliseconds = epochMilliseconds(now())
        guard currentMilliseconds >= envelope.fetchedAtMilliseconds else { return true }
        let (age, overflowed) = currentMilliseconds.subtractingReportingOverflow(envelope.fetchedAtMilliseconds)
        return overflowed || age >= cacheTTLMilliseconds
    }

    /// Fetches and persists a fresh quote. On a transport failure this throws; callers can still
    /// use `cachedRate` to continue an offline flow when a recent quote is available.
    public func refreshRate(
        baseCurrencyCode: String,
        quoteCurrencyCode: String
    ) async throws -> IOSExchangeRateQuote {
        let pair = try normalizedPair(baseCurrencyCode: baseCurrencyCode, quoteCurrencyCode: quoteCurrencyCode)
        let key = cacheKey(for: pair)
        if let existing = refreshTasks[key] {
            return try await existing.value
        }

        let task: Task<IOSExchangeRateQuote, Error> = Task { [self] in
            try await fetchAndCache(pair: pair)
        }
        refreshTasks[key] = task
        defer { refreshTasks[key] = nil }
        return try await task.value
    }

    private func fetchAndCache(pair: (String, String)) async throws -> IOSExchangeRateQuote {
        let (base, quote) = pair
        guard let endpoint = URL(string: "https://api.frankfurter.dev/v2/rate/\(base)/\(quote)") else {
            throw IOSExchangeRateRepositoryError.invalidRequest
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = requestTimeoutSeconds
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: IOSExchangeRateHTTPResponse
        do {
            response = try await httpClient.send(request)
        } catch let error as IOSExchangeRateRepositoryError {
            throw error
        } catch {
            throw IOSExchangeRateRepositoryError.transportFailure
        }

        guard let responseURL = response.url,
              responseURL.scheme?.lowercased() == "https",
              responseURL.host?.lowercased() == "api.frankfurter.dev",
              responseURL.path == endpoint.path,
              responseURL.query == nil,
              responseURL.fragment == nil,
              responseURL.user == nil,
              responseURL.password == nil else {
            throw IOSExchangeRateRepositoryError.invalidRequest
        }

        if response.data.count > maxResponseBytes {
            throw IOSExchangeRateRepositoryError.responseTooLarge
        }
        if response.headers.keys.contains(where: isCookieHeader) {
            throw IOSExchangeRateRepositoryError.cookiesRejected
        }
        if (300..<400).contains(response.statusCode) {
            throw IOSExchangeRateRepositoryError.redirectRejected
        }
        if response.statusCode == 404 || response.statusCode == 422 {
            throw IOSExchangeRateRepositoryError.unavailable
        }
        guard response.statusCode == 200 else {
            throw IOSExchangeRateRepositoryError.httpStatus(response.statusCode)
        }

        let payload: ProviderPayload
        do {
            payload = try JSONDecoder().decode(ProviderPayload.self, from: response.data)
        } catch {
            throw IOSExchangeRateRepositoryError.malformedResponse
        }

        guard uppercasedCode(payload.base) == base,
              uppercasedCode(payload.quote) == quote else {
            throw IOSExchangeRateRepositoryError.currencyPairMismatch
        }
        let rate = try canonicalPositiveRate(payload.rate.text)
        try validateDate(payload.date, now: now())
        let result = IOSExchangeRateQuote(
            baseCurrencyCode: base,
            quoteCurrencyCode: quote,
            rate: rate,
            date: payload.date
        )
        let envelope = CacheEnvelope(
            quote: result,
            fetchedAtMilliseconds: epochMilliseconds(now())
        )
        if let data = try? JSONEncoder().encode(envelope) {
            storage.set(data, forKey: cacheKey(for: pair))
        }
        return result
    }

    private func readCache(for pair: (String, String)) -> CacheEnvelope? {
        guard let data = storage.data(forKey: cacheKey(for: pair)) else { return nil }
        return try? JSONDecoder().decode(CacheEnvelope.self, from: data)
    }

    private func validatedCachedQuote(
        _ quote: IOSExchangeRateQuote,
        pair: (String, String)
    ) throws -> IOSExchangeRateQuote {
        guard quote.baseCurrencyCode == pair.0,
              quote.quoteCurrencyCode == pair.1,
              isISODate(quote.date) else {
            throw IOSExchangeRateRepositoryError.malformedResponse
        }
        return IOSExchangeRateQuote(
            baseCurrencyCode: pair.0,
            quoteCurrencyCode: pair.1,
            rate: try canonicalPositiveRate(quote.rate),
            date: quote.date
        )
    }

    private func normalizedPair(
        baseCurrencyCode: String,
        quoteCurrencyCode: String
    ) throws -> (String, String) {
        let base = try normalizedCode(baseCurrencyCode)
        let quote = try normalizedCode(quoteCurrencyCode)
        guard base != quote else { throw IOSExchangeRateRepositoryError.currenciesMustDiffer }
        return (base, quote)
    }

    private func normalizedCode(_ value: String) throws -> String {
        let code = uppercasedCode(value)
        guard code.utf8.count == 3,
              code.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw IOSExchangeRateRepositoryError.invalidCurrencyCode
        }
        return code
    }

    private func cacheKey(for pair: (String, String)) -> String {
        "mizani_exchange_rate_v1_\(pair.0)_\(pair.1)"
    }

    private func uppercasedCode(_ value: String) -> String {
        value.uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func canonicalPositiveRate(_ text: String) throws -> String {
        guard text.utf8.count <= maxRateTextLength, isDecimalText(text),
              let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              NSDecimalNumber(decimal: decimal).compare(NSDecimalNumber.zero) == .orderedDescending else {
            throw IOSExchangeRateRepositoryError.invalidRate
        }
        return NSDecimalNumber(decimal: decimal).stringValue
    }

    private func validateDate(_ text: String, now: Date) throws {
        guard let date = parseISODate(text) else {
            throw IOSExchangeRateRepositoryError.dateInvalid
        }
        let today = utcCalendar.startOfDay(for: now)
        if date > today {
            throw IOSExchangeRateRepositoryError.dateInFuture
        }
        guard let age = utcCalendar.dateComponents([.day], from: date, to: today).day,
              age <= maxRateAgeDays else {
            throw IOSExchangeRateRepositoryError.dateTooOld
        }
    }

    private func isISODate(_ text: String) -> Bool {
        parseISODate(text) != nil
    }

    private func parseISODate(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }) else {
            return nil
        }
        let year = Int(bytes[0]) * 1_000 + Int(bytes[1]) * 100 + Int(bytes[2]) * 10 + Int(bytes[3])
        let month = Int(bytes[5]) * 10 + Int(bytes[6])
        let day = Int(bytes[8]) * 10 + Int(bytes[9])
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = utcCalendar.date(from: components) else { return nil }
        let roundTrip = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
        return date
    }

    private func isDecimalText(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return false }
        var index = 0
        if bytes[index] == 43 || bytes[index] == 45 {
            index += 1
            guard index < bytes.count else { return false }
        }

        var digits = 0
        while index < bytes.count, (48...57).contains(bytes[index]) {
            digits += 1
            index += 1
        }
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            while index < bytes.count, (48...57).contains(bytes[index]) {
                digits += 1
                index += 1
            }
        }
        guard digits > 0 else { return false }
        if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            var exponentDigits = 0
            while index < bytes.count, (48...57).contains(bytes[index]) {
                exponentDigits += 1
                index += 1
            }
            guard exponentDigits > 0 else { return false }
        }
        return index == bytes.count
    }

    private func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private func isCookieHeader(_ key: String) -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "set-cookie" || normalized == "set-cookie2" || normalized == "cookie"
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private let cacheTTLMilliseconds: Int64 = 12 * 60 * 60 * 1_000
    private let maxRateAgeDays = 7
    private let maxResponseBytes = 16 * 1024
    private let maxRateTextLength = 256
    private let requestTimeoutSeconds: TimeInterval = 8
}

private final class IOSExchangeRateURLSessionClient: IOSExchangeRateHTTPClient, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> IOSExchangeRateHTTPResponse {
        guard request.httpMethod == "GET", request.httpBody == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Cookie2") == nil else {
            throw IOSExchangeRateRepositoryError.invalidRequest
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let delegate = IOSExchangeRateDataDelegate(maximumResponseBytes: 16 * 1024)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await delegate.send(request, session: session)
    }
}

private final class IOSExchangeRateDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumResponseBytes: Int
    private let lock = NSLock()
    private var response: HTTPURLResponse?
    private var body = Data()
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<IOSExchangeRateHTTPResponse, Error>?
    private var finished = false

    init(maximumResponseBytes: Int) {
        self.maximumResponseBytes = maximumResponseBytes
    }

    func send(
        _ request: URLRequest,
        session: URLSession
    ) async throws -> IOSExchangeRateHTTPResponse {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<IOSExchangeRateHTTPResponse, Error>) in
            lock.lock()
            self.continuation = continuation
            let task = session.dataTask(with: request)
            self.task = task
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
        finish(.failure(IOSExchangeRateRepositoryError.redirectRejected))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(IOSExchangeRateRepositoryError.malformedResponse))
            return
        }
        if response.expectedContentLength > Int64(maximumResponseBytes) || hasCookieHeader(response) {
            completionHandler(.cancel)
            finish(.failure(
                response.expectedContentLength > Int64(maximumResponseBytes)
                    ? IOSExchangeRateRepositoryError.responseTooLarge
                    : IOSExchangeRateRepositoryError.cookiesRejected
            ))
            return
        }
        lock.lock()
        self.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        let exceedsLimit = data.count > maximumResponseBytes || body.count > maximumResponseBytes - data.count
        if !exceedsLimit {
            body.append(data)
        }
        lock.unlock()
        if exceedsLimit {
            dataTask.cancel()
            finish(.failure(IOSExchangeRateRepositoryError.responseTooLarge))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let response = self.response
        let body = self.body
        lock.unlock()
        guard let response else {
            finish(.failure(IOSExchangeRateRepositoryError.malformedResponse))
            return
        }
        finish(.success(IOSExchangeRateHTTPResponse(
            statusCode: response.statusCode,
            url: response.url,
            headers: headers(from: response),
            data: body
        )))
    }

    private func finish(_ result: Result<IOSExchangeRateHTTPResponse, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        lock.unlock()

        if case .failure = result { task?.cancel() }
        guard let continuation else { return }
        continuation.resume(with: result)
    }

    private func hasCookieHeader(_ response: HTTPURLResponse) -> Bool {
        response.allHeaderFields.keys.contains { key in
            guard let key = key as? String else { return false }
            let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "set-cookie" || normalized == "set-cookie2"
        }
    }

    private func headers(from response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String { result[key] = String(describing: value) }
        }
        return result
    }
}
