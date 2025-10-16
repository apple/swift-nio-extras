# NIOExtras

NIOExtras is a good place for code that is related to NIO but not core. It can also be used to incubate APIs for tasks that are possible with core-NIO but are cumbersome today.

What makes a good contribution to NIOExtras?

- a protocol encoder/decoder pair (also called "codec") that is often used but is small enough so it doesn't need its own repository
- a helper to achieve a task that is harder-than-necessary to achieve with core-NIO

## Code Quality / Stability

All code will go through code review like in the other repositories related to the SwiftNIO project.

`swift-nio-extras` part of the SwiftNIO 2 family of repositories and depends on the following:

- [`swift-nio`](https://github.com/apple/swift-nio), version 2.30.0 or better.
- Swift 5.7.1
- `zlib` and its development headers installed on the system. But don't worry, you'll find `zlib` on pretty much any UNIX system that can compile any sort of code.

To depend on `swift-nio-extras`, put the following in the `dependencies` of your `Package.swift`:

```swift
.package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
```

### Support for older Swift versions

The most recent versions of SwiftNIO Extras support Swift 5.7.1 and newer. The minimum Swift version supported by SwiftNIO Extras releases are detailed below:

SwiftNIO Extras     | Minimum Swift Version
--------------------|----------------------
`1.0.0 ..< 1.10.0`  | 5.0
`1.10.0 ..< 1.11.0` | 5.2
`1.11.0 ..< 1.14.0` | 5.4
`1.14.0 ..< 1.19.0` | 5.5.2
`1.19.0 ..< 1.20.0` | 5.6
`1.20.0 ..< 1.23.0` | 5.7.1
`1.23.0 ..< 1.27.0` | 5.8
`1.27.0 ..< 1.30.0` | 5.10
`1.30.0 ...`        | 6.0

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
- [`HTTP1ToHTTPClientCodec`](Sources/NIOHTTPTypesHTTP1/HTTP1ToHTTPCodec.swift) A `ChannelHandler` that translates HTTP/1 messages into shared HTTP types for the client side.
- [`HTTP1ToHTTPServerCodec`](Sources/NIOHTTPTypesHTTP1/HTTP1ToHTTPCodec.swift) A `ChannelHandler` that translates HTTP/1 messages into shared HTTP types for the server side.
- [`HTTPToHTTP1ClientCodec`](Sources/NIOHTTPTypesHTTP1/HTTPToHTTP1Codec.swift) A `ChannelHandler` that translates shared HTTP types into HTTP/1 messages for the client side for compatibility purposes.
- [`HTTPToHTTP1ServerCodec`](Sources/NIOHTTPTypesHTTP1/HTTPToHTTP1Codec.swift) A `ChannelHandler` that translates shared HTTP types into HTTP/1 messages for the server side for compatibility purposes.
- [`HTTP2FramePayloadToHTTPClientCodec`](Sources/NIOHTTPTypesHTTP2/HTTP2ToHTTPCodec.swift) A `ChannelHandler` that translates HTTP/2 concepts into shared HTTP types for the client side.
- [`HTTP2FramePayloadToHTTPServerCodec`](Sources/NIOHTTPTypesHTTP2/HTTP2ToHTTPCodec.swift) A `ChannelHandler` that translates HTTP/2 concepts into shared HTTP types for the server side.
- [`HTTPResumableUploadHandler`](Sources/NIOResumableUpload/HTTPResumableUploadHandler.swift) A `ChannelHandler` that translates HTTP resumable uploads to regular uploads.
- [`HTTPDrippingDownloadHandler`](Sources/NIOHTTPResponsiveness/HTTPDrippingDownloadHandler.swift) A `ChannelHandler` that sends a configurable stream of zeroes to a client.
- [`HTTPReceiveDiscardHandler`](Sources/NIOHTTPResponsiveness/HTTPReceiveDiscardHandler.swift) A `ChannelHandler` that receives arbitrary bytes from a client and discards them.
