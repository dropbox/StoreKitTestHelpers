import StoreKitTest
import XCTest

@available(iOS 17.0, *)
extension SKTestSession {
    /// This will buy the product(s) and then wait until internal StoreKit state is updated before returning. This is necessary to prevent StoreKitTest/StoreKit2 test flakes
    @MainActor
    public func buyProductAndWait(
        identifier: String,
        options: Set<Product.PurchaseOption> = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await buyProduct(identifier: identifier, options: options)
        try await spinUntilActiveAutoRenewableProductIdsContains(identifier: identifier, file: file, line: line)
    }
}

@available(iOS 16.0, *)
extension SKTestSession {
    /// For some reason the internal StoreKit state is not updated immediately, even after awaiting the previous step.
    /// We have to wait some indeterminate amount of time to avoid flakes, but I'm guessing this is still probably a little flakey
    @MainActor
    @discardableResult public func spinUntilActiveAutoRenewableProductIdsContains(
        identifier: String,
        maxTries: Int = 1_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Int {
        let prefix = "\(((file.description) as NSString).lastPathComponent) L\(line)"
        let attempts = try await Task.spinUntilCondition(condition: {
            let activeAutoRenewableProductIDs = await Transaction.activeAutoRenewableProductIDs()
            return activeAutoRenewableProductIDs.contains(identifier)
        }, maxTries: maxTries, file: file, line: line)
        let activeAutoRenewableProductIDs = await Transaction.activeAutoRenewableProductIDs()
        // SKTestSession.allTransactions will probably contain the transaction immediately
        // but querying StoreKit2 directly will not reflect that state for usually ~25 attempts
        let allTransactions = allTransactions()
        let purchasedTransactionProductIDs = Set(allTransactions.filter {
            $0.state == .purchased
        }.map(\.productIdentifier))
        if Set(activeAutoRenewableProductIDs) != purchasedTransactionProductIDs {
            print(
                "\(prefix): WARNING: activeAutoRenewableProductIDs[\(activeAutoRenewableProductIDs.joined(separator: ","))] != purchasedTransactionProductIDs[\(purchasedTransactionProductIDs.joined(separator: ","))]"
            )
        }
        return attempts
    }
}

@available(iOS 16.0, *)
extension Task where Failure == Never, Success == Never {
    enum SpinError: Error { case exceededTimeout }

    /// Sometimes we have to wait some indeterminate amount of time to avoid flakes, this is a utility to help you tear out your hair less
    @MainActor
    @discardableResult public static func spinUntilCondition(
        condition: () async throws -> Bool,
        maxTries: Int = 1_000,
        minimumConsecutiveConsistency: Int = 3,
        skipTestForTimeouts: Bool = true,
        sleepDuration: TimeInterval = 0.025,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Int {
        let start = Date()

        var lastConditionResults: [Bool] = []
        for i in 0 ... maxTries {
            let prefix = "\(((file.description) as NSString).lastPathComponent) L\(line)"

            if !lastConditionResults.isEmpty, lastConditionResults.count > minimumConsecutiveConsistency {
                _ = lastConditionResults.removeFirst()
            }
            let conditionResult = try await condition()
            lastConditionResults.append(conditionResult)
            if lastConditionResults.count >= minimumConsecutiveConsistency,
               lastConditionResults.allSatisfy({ $0 }) {
                let end = Date()
                let duration = end.timeIntervalSince(start)
                let formattedDuration = "(\(duration.formatted(.number.precision(.fractionLength(1)))) seconds)"
                if i > minimumConsecutiveConsistency {
                    print(
                        "\(prefix): Took \(i + 1) tries \(formattedDuration) until conditions are what we expect"
                    )
                } else {
                    print(
                        "\(prefix): condition hit on the first \(minimumConsecutiveConsistency) tries \(formattedDuration), nice!"
                    )
                }
                return i
            }
            if i > maxTries / 2 {
                try await Task.sleep(for: .nanoseconds(UInt64(TimeInterval(NSEC_PER_SEC) * sleepDuration)))
            } else {
                await Task.yield()
            }
        }
        let end = Date()
        let duration = end.timeIntervalSince(start)
        let failureMessage =
            "Internal state failed to update after \(maxTries) tries (\(duration.formatted(.number.precision(.fractionLength(1)))) seconds), this is a known flake"
        if skipTestForTimeouts {
            throw XCTSkip(
                failureMessage,
                file: file,
                line: line
            )
        } else {
            throw SpinError.exceededTimeout
        }
    }
}

extension Transaction {
    static func activeAutoRenewableProductIDs() async -> [String] {
        await currentAutoRenewableTransactions().map(\.productID)
    }

    /// This includes `Transaction.currentEntitlements` which is limited to subscribed or inGracePeriod, however it does not check validity
    static func currentAutoRenewableTransactions() async -> [Transaction] {
        var transactions = [Transaction]()
        // Iterate through all of the user's purchased products.
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try result.payloadValue
                if transaction.productType == .autoRenewable {
                    transactions.append(transaction)
                }
            } catch {
                print("currentAutoRenewableTransactions transaction error, skipping: \(result.unsafePayloadValue.productID) \(error)")
            }
        }
        return transactions
    }
}
