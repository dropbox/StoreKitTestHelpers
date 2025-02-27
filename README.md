# StoreKitTestHelpers

StoreKitTestHelpers is a little utility to help reduce test flakiness when using StoreKitTest. 

The root of the problem seems to be that Apple's StoreKitTest mock server sometimes does not get shut down properly between test runs, and can alternate between the correct response and stale incorrect response. This package provides some helpers to spin until StoreKit returns consistent results (by default, 3 times in a row).

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
.package(url: "https://github.com/dropbox/StoreKitTestHelpers.git", .upToNextMajor(from: "1.0.0")),
```

## Usage

```swift
import StoreKitTest
import StoreKitTestHelpers

func testBlockingExample() {
    // set up your test session
    let skTestSession = try SKTestSession.clearedNonInteractiveSession() 
    // buys product and waits until StoreKit has expected auto-renewable subscription
    try await skTestSession.buyProductAndWait(identifier: "com.example.product")
    // alternatively - make purchase other ways and wait
    try await skTestSession.spinUntilActiveAutoRenewableProductIdsContains("com.example.product")
    
    // you can also wait until arbitrary conditions are met X times in a row
    try await Task.spinUntilCondition {
        await example.shouldBlockPurchase()
    }
}
```
