# NIOSOCKS

SOCKS v5 protocol implementation

## Overview

An implementation of SOCKS v5 protocol.  See [RFC1928](https://www.rfc-editor.org/rfc/rfc1928).

Add the appropriate channel handler to the start of your channel pipeline to use this protocol.

For an example see the NIOSOCKSClient target.

## Topics

### Channel Handlers
- ``SOCKSClientHandler`` connects to a SOCKS server to establish a proxied connection to a host.
- ``SOCKSServerHandshakeHandler`` server side SOCKS channel handler.

### Client Messages
- ``ClientMessage`` message types from the client to the server.
- ``ClientGreeting`` client initiation of SOCKS handshake.
- ``SOCKSRequest`` the target host and how to connect.

### Server Messages
- ``ServerMessage`` message types from the server to the client.
- ``SelectedAuthenticationMethod`` the authentication method selected by the SOCKS server.
- ``SOCKSResponse`` the server response to the client request.

### Supporting Types
- ``AuthenticationMethod`` The SOCKS authentication method to use.
- ``SOCKSServerReply`` indicates the success or failure of connection.
- ``SOCKSCommand`` the type of connection to establish.
- ``SOCKSAddress`` the address used to connect to the target host.
- ``SOCKSProxyEstablishedEvent`` a user event that is sent when a SOCKS connection has been established.
- ``SOCKSError`` socks protocol errors which can be emitted.
