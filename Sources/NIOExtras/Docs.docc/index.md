# ``NIOExtras``

A collection of helpful utilities to assist in building and debugging Swift-NIO based applications.

## Overview

A collection of helpful utilities to assist in building and debugging Swift-NIO based applications.  Topics covered include packet capture, the logging of channel pipeline events, frame decoding of various common forms and helpful data types.

Debugging aids include `ChannelHandler`s to log channel pipeline events both inbound and outbound; and a `ChannelHandler` to log data in packet capture format.

To support encoding and decoding helpers are provided for data frames which have fixed length; are new line terminated; contain a length prefix; or are defined by a `context-length` header.

To help simplify building a robust pipeline the ``ServerQuiescingHelper`` makes it easy to collect all child `Channel`s that a given server `Channel` accepts.

Easy request response flows can be built using the ``RequestResponseHandler`` which takes a request and a promise which is fulfilled when an expected response is received.

## Topics

### Debugging Aids

- ``DebugInboundEventsHandler``
- ``DebugOutboundEventsHandler``
- ``NIOWritePCAPHandler``
- ``NIOPCAPRingBuffer``

### Encoding and Decoding

- ``FixedLengthFrameDecoder``
- ``NIOJSONRPCFraming``
- ``LengthFieldBasedFrameDecoder``
- ``NIOLengthFieldBasedFrameDecoderError``
- ``LengthFieldPrepender``
- ``LengthFieldPrependerError``
- ``LineBasedFrameDecoder``
- ``NIOExtrasErrors``
- ``NIOExtrasError``

### Channel Pipeline Aids
- ``ServerQuiescingHelper``
- ``RequestResponseHandler``

### Data Types
- ``NIOLengthFieldBitLength``
