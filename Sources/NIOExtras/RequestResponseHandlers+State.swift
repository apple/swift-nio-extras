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

// MARK: - EventLoopPromiseEnum

/// A thin wrapper that lets the handlers treat the two promise types as an enum to allow for stronger abstraction.
enum EventLoopPromiseEnum<Response> {
    case nonisolated(EventLoopPromise<Response>)
    case isolated(EventLoopPromise<Response>.Isolated)

    /// Fail the stored `EventLoopPromise`
    /// - parameters:
    ///  - error: `Error` to use to fail the promise
    func fail(_ error: Error) {
        switch self {
        case .nonisolated(let promise):
            promise.fail(error)
        case .isolated(let promise):
            promise.nonisolated().fail(error)
        }
    }
}

// MARK: - ResponsePromiseBuffer

/// A storage abstraction for outstanding response promises.
///
/// The state-machine never assumes how the promises are stored,
/// any type that conforms to this protocol is acceptable by the state machine.
protocol ResponsePromiseBuffer {
    associatedtype Response
    associatedtype ID

    /// Number of promises that are currently in the buffer.
    var count: Int { get }

    /// Create an empty buffer with storage allocated for `initialBufferCapacity` number of elements.
    init(initialBufferCapacity: Int)

    /// Store `response` under `key`.
    mutating func insert(key: ID, _ response: EventLoopPromiseEnum<Response>)

    /// Remove and return the promise for `key` or `nil` if no promise with the given `ID` exists.
    mutating func remove(key: ID) -> EventLoopPromiseEnum<Response>?

    /// Fail **all** stored promises with `error` and empty the buffer.
    mutating func removeAll(failWith error: any Error)
}

/// Buffer implementation using the `CircularBuffer` type provided in NIO.
/// `ID` is `Void` as the `CircularBuffer` is FIFO
struct ResponseCircularBuffer<R>: ResponsePromiseBuffer {
    typealias Response = R
    typealias ID = Void
    private var buffer: CircularBuffer<EventLoopPromiseEnum<Response>>

    var count: Int {
        buffer.count
    }

    public init(initialBufferCapacity: Int) {
        buffer = CircularBuffer(initialCapacity: initialBufferCapacity)
    }

    mutating func insert(key: ID = (), _ response: EventLoopPromiseEnum<Response>) {
        self.buffer.append(response)
    }

    mutating func remove(key: ID = ()) -> EventLoopPromiseEnum<Response>? {
        self.buffer.removeFirst()
    }

    mutating func removeAll(failWith error: any Error) {
        let buffer = self.buffer
        self.buffer.removeAll()
        for promise in buffer {
            promise.fail(error)
        }
    }
}

/// Buffer implementation using a `Dictionary` to store the promises.
/// The response (`R`) must be `NIORequestIdentifiable` to
///     provide the `Dictionary` a key to store the promise under.
struct ResponseDictionaryBuffer<R: NIORequestIdentifiable>: ResponsePromiseBuffer {
    typealias Response = R
    typealias ID = R.RequestID

    private var buffer: [ID: EventLoopPromiseEnum<Response>]
    var count: Int {
        buffer.count
    }

    public init(initialBufferCapacity: Int) {
        buffer = [:]
        buffer.reserveCapacity(initialBufferCapacity)
    }

    mutating func insert(key: ID, _ response: EventLoopPromiseEnum<Response>) {
        self.buffer[key] = response
    }

    mutating func remove(key: ID) -> EventLoopPromiseEnum<Response>? {
        self.buffer.removeValue(forKey: key)
    }

    mutating func removeAll(failWith error: any Error) {
        let buffer = self.buffer
        self.buffer.removeAll()
        for (_, promise) in buffer {
            promise.fail(error)
        }
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
            self.promiseBuffer.removeAll(failWith: NIOExtrasErrors.ClosedBeforeReceivingResponse())
            return .fireInactive
        }
    }

    enum ErrorCaughtAction {
        case closeContext  // close the context as we received an error
        case `return`  // do nothing
    }

    /// Handle `errorCaught`. Transitions to `.error` exacly once as there is no way to make the handler operational again.
    mutating func errorCaught(error: Error) -> ErrorCaughtAction {
        guard self.state.isOperational else {
            assert(self.promiseBuffer.count == 0)
            return .return
        }
        self.state = .error(error)
        self.promiseBuffer.removeAll(failWith: error)
        return .closeContext
    }

    enum ReadPromiseAction {
        // succeed the returned promise
        case succeed(EventLoopPromiseEnum<PromiseBuffer.Response>)
        case error  // no matching promise found
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
            return .error
        }
    }

    enum WritePromiseAction {
        case failWith(error: Error)  // do not write, fail promise with error
        case writeContext  // write the promise to the context
    }

    /// Buffer the promise or fail it immediately, depending on current state.
    mutating func writePromise(
        id: PromiseBuffer.ID,
        responsePromise: EventLoopPromiseEnum<PromiseBuffer.Response>
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
