# NIOExtras

NIOExtras is a good place for code that is related to NIO but not core. It can also be used to incubate APIs for tasks that are possible with core-NIO but are cumbersome today.

What makes a good contribution to NIOExtras?

- a protocol encoder/decoder pair (also called "codec") that is often used but is small enough so it doesn't need its own repository
- a helper to achieve a task that is harder-than-necessary to achieve with core-NIO

## Code Quality / Stability

All code will go through code review like in the other repositories related to the SwiftNIO project.

`swift-nio-extras` part of the SwiftNIO 2 family of repositories and depends on the following:

- [`swift-nio`](https://github.com/apple/swift-nio), version 2.30.0 or better.
- Swift 5.4.
- `zlib` and its development headers installed on the system. But don't worry, you'll find `zlib` on pretty much any UNIX system that can compile any sort of code.

To depend on `swift-nio-extras`, put the following in the `dependencies` of your `Package.swift`:

```swift
.package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
```

### Support for older Swift versions

Earlier versions of SwiftNIO (2.39.x and lower) and SwiftNIOExtras (1.10.x and lower) supported Swift 5.2 and 5.3, SwiftNIO (2.29.x and lower) and SwiftNIOExtras (1.9.x and lower) supported Swift 5.0 and 5.1. 

On the [`nio-extras-0.1`](https://github.com/apple/swift-nio-extras/tree/nio-extras-0.1) branch, you can find the `swift-nio-extras` version for the SwiftNIO 1 family. It requires Swift 4.1 or better.

## Current Contents

- [`QuiescingHelper`](Sources/NIOExtras/QuiescingHelper.swift): Helps to quiesce
  a server by notifying user code when all previously open connections have closed.
- [`LineBasedFrameDecoder`](Sources/NIOExtras/LineBasedFrameDecoder.swift) Splits incoming `ByteBuffer`s on line endings.
- [`FixedLengthFrameDecoder`](Sources/NIOExtras/FixedLengthFrameDecoder.swift) Splits incoming `ByteBuffer`s by a fixed number of bytes.
- [`LengthFieldBasedFrameDecoder`](Sources/NIOExtras/LengthFieldBasedFrameDecoder.swift) Splits incoming `ByteBuffer`s by a number of bytes specified in a fixed length header contained within the buffer.
- [`LengthFieldPrepender`](Sources/NIOExtras/LengthFieldPrepender.swift) Prepends the number of bytes to outgoing `ByteBuffer`s as a fixed length header. Can be used in a codec pair with the `LengthFieldBasedFrameDecoder`.
- [`RequestResponseHandler`](Sources/NIOExtras/RequestResponseHandler.swift) Matches a request and a promise with the corresponding response.
- [`HTTPResponseCompressor`](Sources/NIOHTTPCompression/HTTPResponseCompressor.swift) Compresses the body of every HTTP/1 response message.
- [`DebugInboundsEventHandler`](Sources/NIOExtras/DebugInboundEventsHandler.swift) Prints out all inbound events that travel through the `ChannelPipeline`.
- [`DebugOutboundsEventHandler`](Sources/NIOExtras/DebugOutboundEventsHandler.swift) Prints out all outbound events that travel through the `ChannelPipeline`.
- [`WritePCAPHandler`](Sources/NIOExtras/WritePCAPHandler.swift) A `ChannelHandler` that writes `.pcap` containing the traffic of the `ChannelPipeline` that you can inspect with Wireshark/tcpdump.
