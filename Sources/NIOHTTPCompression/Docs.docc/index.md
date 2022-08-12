# ``NIOHTTPCompression``

Automatic compression and decompression of HTTP data.

## Overview

Channel handlers to support automatic compression and decompression of HTTP data.  Add the handlers to your pipeline to support the features you need.

`Content-Encoding`, `Content-Length`, and `accept-encoding` HTTP headers are set and respected where appropriate.

Be aware that this works best if there is sufficient data written between flushes.  This also performs compute on the event loop thread which could impact performance.

## Topics

### Client Channel Handlers

- ``NIOHTTPRequestCompressor``
- ``NIOHTTPResponseDecompressor``

### Server Channel Handlers
- ``NIOHTTPRequestDecompressor``
- ``HTTPResponseCompressor``

### Compression Methods

- ``NIOCompression``
- ``NIOHTTPDecompression``
