# CombineStoreKit

An attempt to extend StoreKit with Combine.

*IMPORTANT: This is not production ready and barely tested, so please don't use it in a real app...*

## Goal

The current way to use StoreKit is by first retrive the `SKProduct`'s from Apple by the use of `SKProductsRequest` and use them to display information about your In-App-Purchases and Subscriptions.

`SKProductsRequest` itself needs a delegate to be notified of any `SKProduct` objects returend from Apple's servers. 
The Goal here is to use Combine to abstract away the delegate pattern and expose a publisher for easy usage.

### Using SKProductsRequest

    let productsPublisher = SKProductsRequest(productIdentifiers: productIdentifiers).publisher
    
or

    let productsPublisher = SKProductsRequest.publisher(for: productIdentifiers)

You can use `sink(receiveCompletion:receiveValue:)` like with any publisher.

