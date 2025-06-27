//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

// MARK: - ResponsePromiseBuffer

/// Protocol to expose the stored `Value` type inside `EventLoopPromise` letting
/// generic code refer to it for additional constraints.
protocol ResponsePromise {
    associatedtype Response
}

extension EventLoopPromise: ResponsePromise {
    typealias Response = Value
}

extension EventLoopPromise.Isolated: ResponsePromise {
    typealias Response = Value
}

/// A storage abstraction for outstanding response promises.
///
/// The state-machine never assumes how the promises are stored,
/// any type that conforms to this protocol is acceptable by the state machine.
protocol ResponsePromiseBuffer {
    associatedtype ID
    associatedtype Promise

    /// Number of promises that are currently in the buffer.
    var count: Int { get }

    /// Create an empty buffer with storage allocated for `initialBufferCapacity` number of elements.
    init(initialBufferCapacity: Int)

    /// Store `response` under `key`.
    mutating func insert(key: ID, _ promise: Promise)

    /// Remove and return the promise for `key` or `nil` if no promise with the given `ID` exists.
    mutating func remove(key: ID) -> Promise?

    /// Remove all stored promises and return them so they can be failed/succeeded.
    mutating func removeAll() -> [Promise]
}

/// Buffer implementation using the `CircularBuffer` type provided in NIO.
/// `ID` is `Void` as the `CircularBuffer` is FIFO.
struct ResponseCircularBuffer<P: ResponsePromise>: ResponsePromiseBuffer {
    typealias ID = Void
    typealias Promise = P

    private var buffer: CircularBuffer<Promise>

    var count: Int {
        buffer.count
    }

    public init(initialBufferCapacity: Int) {
        buffer = CircularBuffer(initialCapacity: initialBufferCapacity)
    }

    mutating func insert(key: ID = (), _ promise: Promise) {
        self.buffer.append(promise)
    }

    mutating func remove(key: ID = ()) -> Promise? {
        self.buffer.popFirst()
    }

    mutating func removeAll() -> [Promise] {
        defer {
            self.buffer.removeAll()
        }
        return Array(buffer)
    }
}

/// Buffer implementation using a `Dictionary` to store the promises.
///
/// The promise (`P`) `Value` must be `NIORequestIdentifiable` to
/// provide the `Dictionary` a key to store the promise ('P') under.
struct ResponseDictionaryBuffer<P: ResponsePromise>: ResponsePromiseBuffer
where P.Response: NIORequestIdentifiable {
    typealias ID = P.Response.RequestID
    typealias Promise = P

    private var buffer: [ID: Promise]

    var count: Int {
        buffer.count
    }

    public init(initialBufferCapacity: Int) {
        buffer = [:]
        buffer.reserveCapacity(initialBufferCapacity)
    }

    mutating func insert(key: ID, _ promise: Promise) {
        self.buffer[key] = promise
    }

    mutating func remove(key: ID) -> Promise? {
        self.buffer.removeValue(forKey: key)
    }

    mutating func removeAll() -> [Promise] {
        defer {
            self.buffer.removeAll()
        }
        return Array(buffer.values)
    }
}

// MARK: - RequestResponseHandler State Machine

/// Enum based FSM that owns a buffer of promises and transitions between
/// *operational*, *inactive* (handler closed gracefully) and *error* states.
struct RequestResponseHandlerState<PromiseBuffer: ResponsePromiseBuffer> {
    private enum State {
        case operational
        case inactive
        case error(Error)

        var isOperational: Bool {
            switch self {
            case .operational:
                return true
            case .error, .inactive:
                return false
            }
        }
    }

    private var state: State
    private var promiseBuffer: PromiseBuffer

    init(initialBufferCapacity: Int = 4) {
        self.state = .operational
        self.promiseBuffer = PromiseBuffer(initialBufferCapacity: initialBufferCapacity)
    }

    enum DeactiveChannelAction {
        case fireInactive  // propagate channelInactive to the context
        // fail the promises and propagate channelInactive to the context
        case failPromisesAndFireInactive([PromiseBuffer.Promise])
        case `return`  // do nothing
    }

    /// Handle `channelInactive`. Drains the buffer if the state machine is still operational.
    mutating func deactivateChannel() -> DeactiveChannelAction {
        switch self.state {
        case .error:
            // We failed any outstanding promises when we entered the error state and will fail any
            // new promises in write.
            assert(self.promiseBuffer.count == 0)
            return .fireInactive
        case .inactive:
            assert(self.promiseBuffer.count == 0)
            // This is weird, we shouldn't get this more than once but it's not the end of the world either. But in
            // debug we probably want to crash.
            assertionFailure("Received channelInactive on an already-inactive handler")
            return .return
        case .operational:
            self.state = .inactive
            return .failPromisesAndFireInactive(self.promiseBuffer.removeAll())
        }
    }

    enum ErrorCaughtAction {
        // fail the promises and close the context as we received an error
        case failPromisesAndCloseContext([PromiseBuffer.Promise])
        case `return`  // do nothing
    }

    /// Handle `errorCaught`. Transitions to `.error` exacly once as there is no way to make the handler operational again.
    mutating func errorCaught(error: Error) -> ErrorCaughtAction {
        guard self.state.isOperational else {
            assert(self.promiseBuffer.count == 0)
            return .return
        }
        self.state = .error(error)
        return .failPromisesAndCloseContext(self.promiseBuffer.removeAll())
    }

    enum ReadPromiseAction {
        // succeed the returned promise
        case succeed(PromiseBuffer.Promise)
        case promiseNotFound  // no matching promise found
        case bufferEmpty  // buffer is empty
        case `return`  // ignore (not operational)
    }

    /// Remove and return the promise for `id` if it is present in the buffer.
    mutating func readPromise(id: PromiseBuffer.ID) -> ReadPromiseAction {
        guard self.state.isOperational else {
            assert(self.promiseBuffer.count == 0)
            return .return
        }

        if let promise = self.promiseBuffer.remove(key: id) {
            return .succeed(promise)
        } else {
            if self.promiseBuffer.count == 0 {
                return .bufferEmpty
            } else {
                return .promiseNotFound
            }
        }
    }

    enum WritePromiseAction {
        case failWith(error: Error)  // do not write, fail promise with error
        case writeContext  // write the promise to the context
    }

    /// Buffer the promise or fail it immediately, depending on current state.
    mutating func writePromise(
        id: PromiseBuffer.ID,
        responsePromise: PromiseBuffer.Promise
    ) -> WritePromiseAction {
        switch self.state {
        case .error(let error):
            assert(self.promiseBuffer.count == 0)
            return .failWith(error: error)
        case .inactive:
            assert(self.promiseBuffer.count == 0)
            return .failWith(error: ChannelError.ioOnClosedChannel)
        case .operational:
            self.promiseBuffer.insert(key: id, responsePromise)
            return .writeContext
        }
    }
}

extension NIOExtrasErrors {
    public struct IsolatedPromiseUsedFromDifferentEventLoop: NIOExtrasError {}

    public struct ResponseOnEmptyBuffer: NIOExtrasError {}
}
