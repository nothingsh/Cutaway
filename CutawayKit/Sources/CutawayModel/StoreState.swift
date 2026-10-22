import Combine

/// A property of a store that publishes each new value once the property holds it.
///
/// `@Published` publishes as the value is about to be set: whoever follows it and reads the
/// store meanwhile finds the value before. With this, the store already holds what it sends,
/// so a subscriber may read the store rather than keep a copy of what was sent last.
///
/// `$property` is used as `@Published`'s is: it sends the value there is now to each new
/// subscriber, then every value set, on the thread it is set on. Setting the same value sends
/// it again; a store publishes only what changed. The stores are main-actor objects, and
/// their properties are set and followed there.
@propertyWrapper
public struct StoreState<Value> {
    private let subject: CurrentValueSubject<Value, Never>

    public init(wrappedValue: Value) {
        subject = CurrentValueSubject(wrappedValue)
    }

    public var wrappedValue: Value {
        get { subject.value }
        // `CurrentValueSubject` keeps the value before it sends it on.
        nonmutating set { subject.value = newValue }
    }

    public var projectedValue: Publisher {
        Publisher(subject: subject)
    }

    /// The values of a `StoreState` property: the one it holds, then each one it is set to.
    public struct Publisher: Combine.Publisher {
        public typealias Output = Value
        public typealias Failure = Never

        let subject: CurrentValueSubject<Value, Never>

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Value, S.Failure == Never {
            subject.receive(subscriber: subscriber)
        }
    }
}
