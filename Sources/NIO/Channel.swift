//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Future
import Sockets

#if os(Linux)
import Glibc
#else
import Darwin
#endif

fileprivate class PendingWrites {
    
    private var head: PendingWrite?
    private var tail: PendingWrite?
    
    private(set) var outstanding: UInt64 = 0
    
    var isEmpty: Bool {
        return tail == nil
    }
    
    func add(buffer: ByteBuffer, promise: Promise<Void>) {
        let pending: PendingWrite = PendingWrite(buffer: buffer, promise: promise)
        if let last = tail {
            assert(head != nil)
            last.next = pending
        } else {
            assert(tail == nil)
            head = pending
            tail = pending
        }
        outstanding += UInt64(buffer.readableBytes)
    }
    
    private var hasMultiple: Bool {
        return head?.next != nil
    }
    
    /*
     Function that takes two closures and based on if there are more then one ByteBuffer pending calls either one or the other.
    */
    func consume(oneBody: (UnsafePointer<UInt8>, Int) throws -> Int?, multipleBody: ([(UnsafePointer<UInt8>, Int)]) throws -> Int?) rethrows -> Bool? {
        if hasMultiple {
            // Holds multiple pending writes, use consumeMultiple which will allow us to us writev (a.k.a gathering writes)
            return try consumeMultiple(body: multipleBody)
        }
        return try consumeOne(body: oneBody)
    }
    
    private func updateNodes(pending: PendingWrite) {
        head = pending.next
        if head == nil {
            tail = nil
        }
    }
    
    private func consumeOne(body: (UnsafePointer<UInt8>, Int) throws -> Int?) rethrows -> Bool? {
        if let pending = head {
            if let written = try pending.buffer.withReadPointer(body: body) {
                outstanding -= UInt64(written)
                
                if (pending.buffer.readableBytes == written) {
                    // Directly update nodes as a promise may trigger a callback that will access the PendingWrites class.
                    updateNodes(pending: pending)
                    
                    // buffer was completely written
                    pending.promise.succeed(result: ())
                    if (isEmpty) {
                        // return nil to signal to the caller that there are no more buffers to consume
                        return nil
                    }
                    return true
                } else {
                    pending.buffer.skipBytes(num: written)
                }
            }
            // could not write the complete buffer
            return false
        }
        
        // empty
        return nil
    }
    
    private func consumeMultiple(body: ([(UnsafePointer<UInt8>, Int)]) throws -> Int?) rethrows -> Bool? {
        if let pending = head {
            var pointers: [(UnsafePointer<UInt8>, Int)] = []
            
            func consumeNext0(pendingWrite: PendingWrite?, count: Int, body: ([(UnsafePointer<UInt8>, Int)]) throws -> Int?) rethrows -> Int? {
                // TODO: 1024 should be replaced by UIO_MAXIOV once its exported by Swift.
                //       Working on a patch for Swift to do so...
                if let pending = pendingWrite, count <= Socket.writevLimit {
                    
                    // Using withReadPointer as we not want to adjust the readerIndex yet. We will do this at a higher level
                    let written = try pending.buffer.withReadPointer(body: { (pointer: UnsafePointer<UInt8>, size: Int) -> Int? in
                        pointers.append((pointer, size))
                        return try consumeNext0(pendingWrite: pending.next, count: count + 1, body: body)
                    })
                    return written
                }
                return try body(pointers)
            }

            if let written = try consumeNext0(pendingWrite: pending, count: 0, body: body) {
                
                // Calculate the amount of data we expect to write with one syscall.
                var expected = 0
                for p in pointers {
                    expected += p.1
                }
                
                outstanding -= UInt64(written)
                
                if written >= pending.buffer.readableBytes {
                    var w = written - pending.buffer.readableBytes
                    
                    // Directly update nodes as a promise may trigger a callback that will access the PendingWrites class.
                    updateNodes(pending: pending)
                    
                    // buffer was completely written
                    pending.promise.succeed(result: ())

                    while let p = head {
                        if w >= p.buffer.readableBytes {
                            w -= p.buffer.readableBytes
                            
                            // Directly update nodes as a promise may trigger a callback that will access the PendingWrites class.
                            updateNodes(pending: p)

                            // buffer was completely written
                            p.promise.succeed(result: ())
                        } else {
                            // Only partly written, so update the readerIndex.
                            p.buffer.skipBytes(num: w)
                            break
                        }
                    }
                }
                
                if (isEmpty) {
                    // return nil to signal to the caller that there are no more buffers to consume
                    return nil
                }
                
                // check if we were able to write everything or not
                return expected == written
            }
            // could not write the complete buffer
            return false
        }
        
        // empty
        return nil
    }
    
    func failAll(error: Error) {
        while let pending = head {
            outstanding -= UInt64(pending.buffer.readableBytes)
            updateNodes(pending: pending)
            pending.promise.fail(error: error)
        }
        assert(head == nil)
        assert(tail == nil)
        assert(outstanding == 0)
    }

    private class PendingWrite {
        var next: PendingWrite?
        var buffer: ByteBuffer
        let promise: Promise<Void>
        
        init(buffer: ByteBuffer, promise: Promise<Void>) {
            self.buffer = buffer
            self.promise = promise
        }
    }
}

public class Channel : ChannelOutboundInvoker {
    public private(set) var open: Bool = true

    public let eventLoop: EventLoop

    // Visible to access from EventLoop directly
    internal let socket: Socket
    internal var interestedEvent: InterestedEvent = .None

    private let pendingWrites: PendingWrites = PendingWrites()
    private var readPending: Bool = false

    public private(set) var allocator: ByteBufferAllocator = ByteBufferAllocator()
    private var recvAllocator: RecvByteBufferAllocator = FixedSizeRecvByteBufferAllocator(capacity: 8192)
    private var autoRead: Bool = true
    private var maxMessagesPerRead: UInt = 1

    public lazy var pipeline: ChannelPipeline = ChannelPipeline(channel: self)

    public func setOption<T: ChannelOption>(option: T, value: T.OptionType) throws {
        if option is SocketOption {
            let (level, name) = option.value as! (Int, Int32)
            try socket.setOption(level: Int32(level), name: name, value: value)
        } else if option is AllocatorOption {
            allocator = value as! ByteBufferAllocator
        } else if option is RecvAllocatorOption {
            recvAllocator = value as! RecvByteBufferAllocator
        } else if option is AutoReadOption {
            let auto = value as! Bool
            autoRead = auto
            if auto {
                startReading0()
            } else {
                stopReading0()
            }
        } else if option is MaxMessagesPerReadOption {
            maxMessagesPerRead = value as! UInt
        } else {
            fatalError("option \(option) not supported")
        }
    }
    
    public func getOption<T: ChannelOption>(option: T) throws -> T.OptionType {
        if option is SocketOption {
            let (level, name) = option.value as! (Int32, Int32)
            return try socket.getOption(level: level, name: name)
        }
        if option is AllocatorOption {
            return allocator as! T.OptionType
        }
        if option is RecvAllocatorOption {
            return recvAllocator as! T.OptionType
        }
        if option is AutoReadOption {
            return autoRead as! T.OptionType
        }
        if option is MaxMessagesPerReadOption {
            return maxMessagesPerRead as! T.OptionType
        }
        fatalError("option \(option) not supported")
    }
    
    public var localAddress: SocketAddress? {
        get {
            return socket.localAddress
        }
    }

    public var remoteAddress: SocketAddress? {
        get {
            return socket.remoteAddress
        }
    }

    internal func readIfNeeded() {
        if autoRead {
            read()
        }
    }

    public func bind(address: SocketAddress, promise: Promise<Void>) -> Future<Void> {
        return pipeline.bind(address: address, promise: promise)
    }
    
    public func write(data: Any, promise: Promise<Void>) -> Future<Void> {
        return pipeline.write(data: data, promise: promise)
    }
    
    public func flush() {
        pipeline.flush()
    }
    
    public func read() {
        pipeline.read()
    }
    
    public func writeAndFlush(data: Any, promise: Promise<Void>) -> Future<Void> {
        return pipeline.writeAndFlush(data: data, promise: promise)
    }
    
    public func close(promise: Promise<Void>) -> Future<Void> {
        return pipeline.close(promise: promise)
    }
    
    // Methods invoked from the HeadHandler of the ChannelPipeline
    func bind0(address: SocketAddress, promise: Promise<Void> ) {
        do {
            try socket.bind(address: address)
            promise.succeed(result: ())
        } catch let err {
            promise.fail(error: err)
        }
    }

    func write0(data: Any, promise: Promise<Void>) {
        guard open else {
            // Channel was already closed to fail the promise and not even queue it.
            promise.fail(error: IOError(errno: EBADF, reason: "Channel closed"))
            return
        }
        if let buffer = data as? ByteBuffer {
            pendingWrites.add(buffer: buffer, promise: promise)
        } else {
            // Only support ByteBuffer for now. 
            promise.fail(error: MessageError.unsupported)
        }
    }

    func flush0() {
        guard !isWritePending() else {
            return
        }
        
        if !flushNow() {
            guard open else {
                return
            }

            switch interestedEvent {
            case .Read:
                safeReregister(interested: .All)
            case .None:
                safeReregister(interested: .Write)
            default:
                break
            }
 
            pipeline.fireChannelWritabilityChanged(writable: false)
        }
    }
    
    func startReading0() {
        guard open else {
            return
        }
        readPending = true
        
        switch interestedEvent {
        case .Write:
            safeReregister(interested: .All)
        case .None:
            safeRegister(interested: .Read)
        default:
            break
        }
    }

    func stopReading0() {
        guard open else {
            return
        }
        switch interestedEvent {
        case .Read:
            safeReregister(interested: .None)
        case .All:
            safeReregister(interested: .Write)
        default:
            break
        }
    }
    
    func close0(promise: Promise<Void> = Promise<Void>(), error: Error = IOError(errno: EBADF, reason: "Channel closed")) {
        guard open else {            

            // Already closed
            promise.succeed(result: ())
            return
        }
        
        open = false
        safeDeregister()

        do {
            try socket.close()
            promise.succeed(result: ())
        } catch let err {
            promise.fail(error: err)
        }
        pipeline.fireChannelUnregistered()
        pipeline.fireChannelInactive()
        
        
        // Fail all pending writes and so ensure all pending promises are notified
        pendingWrites.failAll(error: error)
    }
    
    func registerOnEventLoop(initPipeline: (ChannelPipeline) throws ->()) {
        // Was not registered yet so do it now.
        safeRegister(interested: .Read)
        
        do {
            try initPipeline(pipeline)
        
            pipeline.fireChannelRegistered()
        } catch let err {
            pipeline.fireErrorCaught(error: err)
            close0()
        }
    }

    // Methods invoked from the EventLoop itself
    func flushFromEventLoop() {
        assert(open)

        if flushNow() {
            // Everything was written, reregister again with InterestedEvent.Read so we are notified once there is more data on the socketto read.
            pipeline.fireChannelWritabilityChanged(writable: true)
            
            guard open else {
                return
            }
            if readPending {
                // Start reading again
                safeReregister(interested: .Read)
            } else {
                // No read pending so just deregister from the EventLoop for now.
                safeDeregister()
            }
        }
    }
    
    func readFromEventLoop() {
        assert(open)
        
        readPending = false
        defer {
            if open, !readPending {
                switch interestedEvent {
                case .Read:
                    safeReregister(interested: .None)
                case .All:
                    safeReregister(interested: .Write)
                default:
                    break
                }
            }
        }
        
        for _ in 1...maxMessagesPerRead {
            do {
                var buffer = try recvAllocator.buffer(allocator: allocator)
                
                if let bytesRead = try buffer.withMutableWritePointer { try self.socket.read(pointer: $0, size: $1) } {
                    if bytesRead > 0 {
                        pipeline.fireChannelRead(data: buffer)
                    } else {
                        // end-of-file
                        close0()
                        return
                    }
                }
            } catch let err {
                pipeline.fireErrorCaught(error: err)
            
                // Call before trigger the close of the Channel.
                pipeline.fireChannelReadComplete()

                close0(error: err)

                return
            }
        }
        pipeline.fireChannelReadComplete()
    }

    private func isWritePending() -> Bool {
        return interestedEvent == .Write || interestedEvent == .All
    }
    
    // Methods only used from within this class
    private func safeDeregister() {
        interestedEvent = .None
        do {
            try eventLoop.deregister(channel: self)
        } catch let err {
            pipeline.fireErrorCaught(error: err)
            close0(error: err)
        }
    }
    
    private func safeReregister(interested: InterestedEvent) {
        guard open else {
            interestedEvent = .None
            return
        }
        interestedEvent = interested
        do {
            try eventLoop.reregister(channel: self)
        } catch let err {
            pipeline.fireErrorCaught(error: err)
            close0(error: err)
        }

    }
    
    private func safeRegister(interested: InterestedEvent) {
        guard open else {
            interestedEvent = .None
            return
        }
        interestedEvent = interested
        do {
            try eventLoop.register(channel: self)
        } catch let err {
            pipeline.fireErrorCaught(error: err)
            close0(error: err)
        }
    }

    private func flushNow() -> Bool {
        while open {
            do {
                if let written = try pendingWrites.consume(oneBody: {
                    // normal write
                    return try self.socket.write(pointer: $0, size: $1)
                }, multipleBody: {
                    // gathering write
                    return try self.socket.writev(pointers: $0)
                }) {
                    if !written {
                        // Could not write the next buffer(s) completely
                        return false
                    }
                    // Consume the next buffer(s).
                } else {
                    // we handled all pending writes
                    return true
                }
                
            } catch let err {
                close0(error: err)
                
                // we handled all writes
                return true
            }
        }
        return true
    }
    
    init(socket: Socket, eventLoop: EventLoop) {
        self.socket = socket
        self.eventLoop = eventLoop
    }
    
    deinit {
        // We should never have any pending writes left as otherwise we may leak callbacks
        assert(pendingWrites.isEmpty)
    }
}

public protocol RecvByteBufferAllocator {
    func buffer(allocator: ByteBufferAllocator) throws -> ByteBuffer
}

public class FixedSizeRecvByteBufferAllocator : RecvByteBufferAllocator {
    let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public func buffer(allocator: ByteBufferAllocator) throws -> ByteBuffer {
        return try allocator.buffer(capacity: capacity)
    }
}

enum MessageError: Error {
    case unsupported
}
