# NIOExtras

A collection of helpful utilities to assist in building and debugging Swift-NIO based applications.

## Overview

A collection of helpful utilities to assist in building and debugging Swift-NIO based applications.  Topics covered include packet capture, the logging of channel pipeline events, frame decoding of various common forms and helpful data types.

Debugging aids include `ChannelHandler`s to log channel pipeline events both inbound and outbound; and a `ChannelHandler` to log data in packet capture format.

To support encoding and decoding helpers are provided for data frames which have fixed length; are new line terminated; contain a length prefix; or are defined by a `context-length` header.

To help simplify building a robust pipeline the ``ServerQuiescingHelper`` makes it easy to collect all child `Channel`s that a given server `Channel` accepts.

Easy request response flows can be built using the ``RequestResponseHandler`` which takes a request and a promise which is fulfilled when an expected response is received.

## Topics

### Debugging Aids

- ``DebugInboundEventsHandler`` allows logging of inbound channel pipeline events.
- ``DebugOutboundEventsHandler`` allows logging of outbound channel pipeline events.
- ``NIOWritePCAPHandler``captures data from the channel pipeline in PCAP format.
- ``NIOPCAPRingBuffer`` stores captured packet data.

### Encoding and Decoding

- ``FixedLengthFrameDecoder`` splits received data into frames of a fixed number of bytes.
- ``NIOJSONRPCFraming`` emits JSON-RPC wire protocol with 'Content-Length' HTTP-like headers.
- ``LengthFieldBasedFrameDecoder`` splits received data into frames based on a length header in the data stream.
- ``NIOLengthFieldBasedFrameDecoderError`` contains errors emitted from ``LengthFieldBasedFrameDecoder``
- ``LengthFieldPrepender`` is an encoder that takes a `ByteBuffer` message and prepends the number of bytes in the message.
- ``LengthFieldPrependerError`` contains errors emitted from ``LengthFieldPrepender``
- ``LineBasedFrameDecoder`` splits received data into frames terminated by new lines.
- ``NIOExtrasErrors`` contains errors emitted from the NIOExtras decoders.
- ``NIOExtrasError`` base type for ``NIOExtrasErrors``

### Channel Pipeline Aids
- ``ServerQuiescingHelper`` makes it easy to collect all child `Channel`s that a given server `Channel` accepts.
- ``RequestResponseHandler`` takes a request and a promise which is fulfilled when expected response is received.

### Data Types
- ``NIOLengthFieldBitLength`` describes the length of a piece of data in bits
