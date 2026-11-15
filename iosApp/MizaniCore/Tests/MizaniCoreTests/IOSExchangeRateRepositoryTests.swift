import Foundation
import XCTest
@testable import MizaniCore

final class IOSExchangeRateRepositoryTests: XCTestCase {
    func testRefreshValidatesRequestCachesQuoteAndUsesTwelveHourTTL() async throws {
        let clock = TestClock(date: utcDate(year: 2026, month: 11, day: 15, hour: 10))
        let storage = InMemoryStorage()
        let client = StubHTTPClient(response: response(
            statusCode: 200,
            body: #"{"base":"eur","quote":"usd","rate":1.2500,"date":"2026-11-14"}"#
        ))
        let repository = IOSExchangeRateRepository(
            httpClient: client,
            storage: storage,
            now: { clock.date }
        )

        let quote = try await repository.refreshRate(baseCurrencyCode: "eur", quoteCurrencyCode: "usd")

        XCTAssertEqual(quote, IOSExchangeRateQuote(
            baseCurrencyCode: "EUR",
            quoteCurrencyCode: "USD",
            rate: "1.25",
            date: "2026-11-14"
        ))
        XCTAssertEqual(client.request?.url?.absoluteString, "https://api.frankfurter.dev/v2/rate/EUR/USD")
        XCTAssertEqual(client.request?.httpMethod, "GET")
        XCTAssertEqual(client.request?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(client.request?.httpBody)
        XCTAssertFalse(client.request?.httpShouldHandleCookies ?? true)
        let shouldRefreshBeforeTTL = try await repository.shouldRefresh(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        let cachedQuote = try await repository.cachedRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        XCTAssertFalse(shouldRefreshBeforeTTL)
        XCTAssertEqual(cachedQuote, quote)

        clock.date = clock.date.addingTimeInterval(12 * 60 * 60)
        let shouldRefreshAfterTTL = try await repository.shouldRefresh(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        XCTAssertTrue(shouldRefreshAfterTTL)
    }

    func testRefreshCoalescesConcurrentRequestsForTheSamePair() async throws {
        let client = StubHTTPClient(response: response(
            statusCode: 200,
            body: #"{"base":"EUR","quote":"USD","rate":1.2,"date":"2026-11-14"}"#
        ))
        let clock = TestClock(date: utcDate(year: 2026, month: 11, day: 15, hour: 10))
        let repository = IOSExchangeRateRepository(
            httpClient: client,
            storage: InMemoryStorage(),
            now: { clock.date }
        )

        async let first = repository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        async let second = repository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        let results = try await [first, second]

        XCTAssertEqual(results[0], results[1])
        XCTAssertEqual(client.sendCount, 1)
    }

    func testRejectsInvalidPairRateAndDateBoundaries() async throws {
        let clock = TestClock(date: utcDate(year: 2026, month: 11, day: 15, hour: 10))
        let storage = InMemoryStorage()

        let pairClient = StubHTTPClient(response: response(
            statusCode: 200,
            body: #"{"base":"GBP","quote":"USD","rate":1.2,"date":"2026-11-15"}"#
        ))
        let pairRepository = IOSExchangeRateRepository(httpClient: pairClient, storage: storage, now: { clock.date })
        await assertError(.currencyPairMismatch) {
            _ = try await pairRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }

        let invalidRateClient = StubHTTPClient(response: response(
            statusCode: 200,
            body: #"{"base":"EUR","quote":"USD","rate":0,"date":"2026-11-15"}"#
        ))
        let invalidRateRepository = IOSExchangeRateRepository(
            httpClient: invalidRateClient,
            storage: storage,
            now: { clock.date }
        )
        await assertError(.invalidRate) {
            _ = try await invalidRateRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }

        let oldDateClient = StubHTTPClient(response: response(
            statusCode: 200,
            body: #"{"base":"EUR","quote":"USD","rate":1.2,"date":"2026-11-07"}"#
        ))
        let oldDateRepository = IOSExchangeRateRepository(
            httpClient: oldDateClient,
            storage: storage,
            now: { clock.date }
        )
        await assertError(.dateTooOld) {
            _ = try await oldDateRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }

        let futureDateClient = StubHTTPClient(response: response(
            statusCode: 200,
            body: #"{"base":"EUR","quote":"USD","rate":1.2,"date":"2026-11-16"}"#
        ))
        let futureDateRepository = IOSExchangeRateRepository(
            httpClient: futureDateClient,
            storage: storage,
            now: { clock.date }
        )
        await assertError(.dateInFuture) {
            _ = try await futureDateRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }

        let invalidDateClient = StubHTTPClient(response: response(
            statusCode: 200,
            body: #"{"base":"EUR","quote":"USD","rate":1.2,"date":"2026-11-15T00:00:00Z"}"#
        ))
        let invalidDateRepository = IOSExchangeRateRepository(
            httpClient: invalidDateClient,
            storage: storage,
            now: { clock.date }
        )
        await assertError(.dateInvalid) {
            _ = try await invalidDateRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }
    }

    func testRejectsRedirectCookiesOversizedResponsesAndInvalidCodes() async throws {
        let clock = TestClock(date: utcDate(year: 2026, month: 11, day: 15, hour: 10))
        let redirectRepository = IOSExchangeRateRepository(
            httpClient: StubHTTPClient(response: response(statusCode: 302, body: "")),
            now: { clock.date }
        )
        await assertError(.redirectRejected) {
            _ = try await redirectRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }

        let cookieRepository = IOSExchangeRateRepository(
            httpClient: StubHTTPClient(response: response(
                statusCode: 200,
                headers: ["Set-Cookie": "session=unexpected"],
                body: #"{"base":"EUR","quote":"USD","rate":1.2,"date":"2026-11-15"}"#
            )),
            now: { clock.date }
        )
        await assertError(.cookiesRejected) {
            _ = try await cookieRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }

        let oversizedRepository = IOSExchangeRateRepository(
            httpClient: StubHTTPClient(response: response(statusCode: 200, body: String(repeating: "x", count: 16 * 1024 + 1))),
            now: { clock.date }
        )
        await assertError(.responseTooLarge) {
            _ = try await oversizedRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }

        await assertError(.invalidCurrencyCode) {
            _ = try await oversizedRepository.refreshRate(baseCurrencyCode: "EU", quoteCurrencyCode: "USD")
        }
        await assertError(.currenciesMustDiffer) {
            _ = try await oversizedRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "eur")
        }

        let mismatchedHostRepository = IOSExchangeRateRepository(
            httpClient: StubHTTPClient(response: response(
                statusCode: 200,
                url: URL(string: "https://example.invalid/v2/rate/EUR/USD"),
                body: #"{"base":"EUR","quote":"USD","rate":1.2,"date":"2026-11-15"}"#
            )),
            now: { clock.date }
        )
        await assertError(.invalidRequest) {
            _ = try await mismatchedHostRepository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        }
    }

    func testCachedRateIsUnavailableAfterSevenDaysButRemainsStoredForRefresh() async throws {
        let clock = TestClock(date: utcDate(year: 2026, month: 11, day: 15, hour: 10))
        let storage = InMemoryStorage()
        let repository = IOSExchangeRateRepository(
            httpClient: StubHTTPClient(response: response(
                statusCode: 200,
                body: #"{"base":"EUR","quote":"USD","rate":1.2,"date":"2026-11-15"}"#
            )),
            storage: storage,
            now: { clock.date }
        )
        _ = try await repository.refreshRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        clock.date = utcDate(year: 2026, month: 11, day: 23, hour: 10)

        let staleCachedQuote = try await repository.cachedRate(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        let shouldRefresh = try await repository.shouldRefresh(baseCurrencyCode: "EUR", quoteCurrencyCode: "USD")
        XCTAssertNil(staleCachedQuote)
        XCTAssertTrue(shouldRefresh)
    }

    private func response(
        statusCode: Int,
        headers: [String: String] = [:],
        url: URL? = URL(string: "https://api.frankfurter.dev/v2/rate/EUR/USD"),
        body: String
    ) -> IOSExchangeRateHTTPResponse {
        IOSExchangeRateHTTPResponse(
            statusCode: statusCode,
            url: url,
            headers: headers,
            data: Data(body.utf8)
        )
    }

    private func assertError(
        _ expected: IOSExchangeRateRepositoryError,
        operation: @escaping () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected), but operation succeeded")
        } catch let error as IOSExchangeRateRepositoryError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Expected \(expected), got \(error)")
        }
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

private final class InMemoryStorage: IOSExchangeRateStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { values[key] }

    func set(_ data: Data, forKey key: String) { values[key] = data }
}

private final class StubHTTPClient: IOSExchangeRateHTTPClient, @unchecked Sendable {
    let response: IOSExchangeRateHTTPResponse
    private(set) var request: URLRequest?
    private(set) var sendCount = 0

    init(response: IOSExchangeRateHTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> IOSExchangeRateHTTPResponse {
        self.request = request
        sendCount += 1
        return response
    }
}

private final class TestClock: @unchecked Sendable {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}
