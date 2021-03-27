#if !(os(iOS) && (arch(i386) || arch(arm)))

@_exported import Foundation // Clang module
import Combine
import StoreKit

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension SKPaymentQueue {
    
    public var updatedTransactionsPublisher: SKPaymentQueue.Publisher {
        Publisher(queue: self, desire: .updates)
    }
    
    public var removedTransactionsPublisher: SKPaymentQueue.Publisher {
        Publisher(queue: self, desire: .deletions)
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension SKPaymentQueue {
    public struct Publisher: Combine.Publisher {
        public typealias Output = [SKPaymentTransaction]
        public typealias Failure = Swift.Error
        
        fileprivate enum Desire {
            case updates
            case deletions
        }
        
        fileprivate let queue: SKPaymentQueue
        fileprivate let desire: Desire
        
        fileprivate init(queue: SKPaymentQueue, desire: Desire) {
            self.queue = queue
            self.desire = desire
        }
        
        public init(queue: SKPaymentQueue) {
            self.queue = queue
            self.desire = .updates
        }
        
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            subscriber.receive(subscription: SKPaymentQueue.Subscription(paymentQueue: queue, desire: desire, next: subscriber))
        }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension SKPaymentQueue.Publisher: Equatable {
    public static func == (
        lhs: SKPaymentQueue.Publisher,
        rhs: SKPaymentQueue.Publisher
    ) -> Bool {
        lhs.queue === rhs.queue
            && lhs.desire == rhs.desire
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension SKPaymentQueue {
    fileprivate final class Subscription<S: Subscriber>: NSObject, Combine.Subscription, CustomReflectable, CustomPlaygroundDisplayConvertible
        where
        S.Input == [SKPaymentTransaction],
        S.Failure == Swift.Error
    {
        typealias Desire = SKPaymentQueue.Publisher.Desire
        
        private let lock = Lock()
        
        // This lock can only be held for the duration of downstream callouts
        private let downstreamLock = RecursiveLock()
        
        private var demand: Subscribers.Demand      // GuardedBy(lock)
        
        private var queue: SKPaymentQueue?          // GuardedBy(lock)
        private var observer: PaymentTransactionObserver?
        private var desire: Desire?                 // GuardedBy(lock)
        private var next: S?
        
        override var description: String { return "SKPaymentQueue Observer" }
        var customMirror: Mirror {
            lock.lock()
            defer { lock.unlock() }
            return Mirror(self, children: [
                "queue": queue as Any,
                "desire": desire as Any,
                "demand": demand
            ])
        }
        var playgroundDescription: Any { return description }
        
        init(paymentQueue: SKPaymentQueue, desire: Desire, next: S) {
            self.queue = paymentQueue
            self.demand = .unlimited
            self.next = next
            self.desire = desire
            
            super.init()
            
            self.observer = PaymentTransactionObserver(
                didUpdateTransactions: { transactions in
                    self.handleTransactions(transactions, forExpectedDesire: .updates)
                },
                didRemoveTransactions: { transactions in
                    self.handleTransactions(transactions, forExpectedDesire: .deletions)
                },
                didUpdateDownloads: { _ in },
                didFail: { error in
                    self.lock.lock()
                    
                    let demand = self.demand
                    if demand > 0 {
                        self.demand -= 1
                    }
                    
                    self.lock.unlock()
                    
                    self.downstreamLock.lock()
                    next.receive(completion: .failure(error))
                    self.downstreamLock.unlock()
                }
            )
            
            self.queue?.add(observer!)
        }
        
        deinit {
            lock.lock()
            if let observer = self.observer {
                self.queue?.remove(observer)
                self.observer = nil
            }
            self.queue = nil
            lock.unlock()
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
            guard let observer = self.observer, self.desire != nil else {
                lock.unlock()
                return
            }
            self.desire = nil
            self.queue?.remove(observer)
            self.observer = nil
            self.queue = nil
            
            lock.unlock()
        }
        
        private func handleTransactions(_ transactions: [SKPaymentTransaction], forExpectedDesire expectedDesire: Desire) {
            self.lock.lock()
            guard let desire = self.desire, desire == expectedDesire else {
                self.lock.unlock()
                preconditionFailure("Expected \(expectedDesire), but got \(String(describing: self.desire)) instead.")
            }
            
            let demand = self.demand
            if demand > 0 {
                self.demand -= 1
            }
            
            self.lock.unlock()
            
            if demand > 0 {
                self.downstreamLock.lock()
                let additionalDemand = next?.receive(transactions)
                self.downstreamLock.unlock()
                
                if let additionalDemand = additionalDemand, additionalDemand > 0 {
                    self.lock.lock()
                    self.demand += additionalDemand
                    self.lock.unlock()
                }
            } else {
                // Drop it on the floor
            }
        }
    }
    
    fileprivate final class PaymentTransactionObserver: NSObject, SKPaymentTransactionObserver {
        let didUpdateTransactions: ([SKPaymentTransaction]) -> Void
        let didRemoveTransactions: ([SKPaymentTransaction]) -> Void
        let didUpdateDownloads: ([SKDownload]) -> Void
        let didFail: (Swift.Error) -> Void
    
        init(didUpdateTransactions: @escaping ([SKPaymentTransaction]) -> Void,
             didRemoveTransactions: @escaping ([SKPaymentTransaction]) -> Void,
             didUpdateDownloads: @escaping ([SKDownload]) -> Void,
             didFail: @escaping (Swift.Error) -> Void
        ) {
            self.didUpdateTransactions = didUpdateTransactions
            self.didRemoveTransactions = didRemoveTransactions
            self.didUpdateDownloads = didUpdateDownloads
            self.didFail = didFail
        }
    
        func paymentQueue(
            _ queue: SKPaymentQueue,
            updatedTransactions transactions: [SKPaymentTransaction]
        ) {
            didUpdateTransactions(transactions)
        }
    
        // MARK: - Optional
    
        func paymentQueue(
            _ queue: SKPaymentQueue,
            removedTransactions transactions: [SKPaymentTransaction]
        ) {
            didRemoveTransactions(transactions)
        }
    
        func paymentQueue(
            _ queue: SKPaymentQueue,
            restoreCompletedTransactionsFailedWithError error: Error
        ) {
            didFail(error)
        }
    
        func paymentQueueRestoreCompletedTransactionsFinished(
            _ queue: SKPaymentQueue
        ) { }
    
        func paymentQueue(
            _ queue: SKPaymentQueue,
            updatedDownloads downloads: [SKDownload]
        ) {
            didUpdateDownloads(downloads)
        }
    
        func paymentQueue(
            _ queue: SKPaymentQueue,
            shouldAddStorePayment payment: SKPayment,
            for product: SKProduct
        ) -> Bool { true }
    
        func paymentQueueDidChangeStorefront(
            _ queue: SKPaymentQueue
        ) { }
    }
}

#endif /* !(os(iOS) && (arch(i386) || arch(arm))) */
