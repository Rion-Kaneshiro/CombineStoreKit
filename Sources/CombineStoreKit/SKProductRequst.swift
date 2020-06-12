#if !(os(iOS) && (arch(i386) || arch(arm)))

@_exported import Foundation // Clang module
import Combine
import StoreKit

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension SKProductsRequest {
    
    public static func publisher(for productIdentifiers: Set<String>) -> SKProductsRequest.Publisher {
        SKProductsRequest(productIdentifiers: productIdentifiers).publisher
    }
    
    public var publisher: SKProductsRequest.Publisher {
        Publisher(request: self)
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension SKProductsRequest {
    public struct Publisher: Combine.Publisher {
        public typealias Output = SKProductsResponse
        public typealias Failure = Never
        
        private let request: SKProductsRequest
        
        public init(request: SKProductsRequest) {
            self.request = request
        }
        
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            subscriber.receive(subscription: SKProductsRequest.Subscription(request: request, next: subscriber))
        }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension SKProductsRequest.Publisher: Equatable {
    public static func == (
        lhs: SKProductsRequest.Publisher,
        rhs: SKProductsRequest.Publisher
    ) -> Bool {
        lhs.request === rhs.request
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension SKProductsRequest {
    fileprivate final class Subscription<S: Subscriber>: NSObject, Combine.Subscription, CustomReflectable, CustomPlaygroundDisplayConvertible, SKProductsRequestDelegate
        where
        S.Input == SKProductsResponse,
        S.Failure == Never
    {
        private let lock = Lock()
        
        // This lock can only be held for the duration of downstream callouts
        private let downstreamLock = RecursiveLock()
        
        private var demand: Subscribers.Demand      // GuardedBy(lock)
        
        private var request: SKProductsRequest?     // GuardedBy(lock)
        private var next: S?
        
        override var description: String { return "SKProductsRequest Observer" }
        var customMirror: Mirror {
            lock.lock()
            defer { lock.unlock() }
            return Mirror(self, children: [
                "request": request as Any,
                "demand": demand
            ])
        }
        var playgroundDescription: Any { return description }
        
        init(request: SKProductsRequest, next: S) {
            self.demand = .max(1)
            self.next = next
            self.request = request
            
            super.init()
            
            self.request?.delegate = self
            self.request?.start()
        }
        
        deinit {
            lock.cleanupLock()
            downstreamLock.cleanupLock()
        }
        
        func request(_ d: Subscribers.Demand) {
            lock.lock()
            demand += d
            lock.unlock()
        }
        
        func cancel() {
            lock.lock()
            guard self.request != nil else {
                lock.unlock()
                return
            }
            self.request?.cancel()
            self.request = nil
            lock.unlock()
        }
        
        func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
            lock.lock()
            
            let demand = self.demand
            if demand > 0 {
                self.demand -= 1
            }
            
            lock.unlock()
            
            downstreamLock.lock()
            
            _ = next?.receive(response)
            next?.receive(completion: .finished)
            
            downstreamLock.unlock()
        }
    }
}

#endif /* !(os(iOS) && (arch(i386) || arch(arm))) */
