# ``NIOSOCKS``

SOCKS v5 protocol implementation

## Overview

An implementation of SOCKS v5 protocol.  See [RFC1928](https://www.rfc-editor.org/rfc/rfc1928).

The username/password authentication method of [RFC1929](https://www.rfc-editor.org/rfc/rfc1929) is supported
by ``SOCKSClientHandler``: pass ``UsernamePasswordCredentials`` to ``SOCKSClientHandler/init(targetAddress:credentials:)``.
Servers built on ``SOCKSServerHandshakeHandler`` receive the framed sub-negotiation request as
``ClientMessage/authenticationData(_:)`` once they selected ``AuthenticationMethod/usernamePassword``, decode it with
`ByteBuffer.readUsernamePasswordRequest()` and answer with a ``UsernamePasswordResponse``.

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

### Username/password authentication
- ``UsernamePasswordCredentials``
- ``UsernamePasswordRequest``
- ``UsernamePasswordResponse``

### Supporting Types
- ``AuthenticationMethod``
- ``SOCKSServerReply``
- ``SOCKSCommand``
- ``SOCKSAddress``
- ``SOCKSProxyEstablishedEvent``
- ``SOCKSError``
