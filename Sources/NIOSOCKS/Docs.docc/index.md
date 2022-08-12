# ``NIOSOCKS``

SOCKS v5 protocol implementation

## Overview

An implementation of SOCKS v5 protocol.  See [RFC1928](https://www.rfc-editor.org/rfc/rfc1928).

Add the appropriate channel handler to the start of your channel pipeline to use this protocol.

For an example see the NIOSOCKSClient target.

## Topics

### Channel Handlers
- ``SOCKSClientHandler``
- ``SOCKSServerHandshakeHandler``

### Client Messages
- ``ClientMessage``
- ``ClientGreeting``
- ``SOCKSRequest``

### Server Messages
- ``ServerMessage``
- ``SelectedAuthenticationMethod``
- ``SOCKSResponse``

### Supporting Types
- ``AuthenticationMethod``
- ``SOCKSServerReply``
- ``SOCKSCommand``
- ``SOCKSAddress``
- ``SOCKSProxyEstablishedEvent``
- ``SOCKSError``
