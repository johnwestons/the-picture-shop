# Private dedicated server prototype

This is a Windows x64, headless source prototype for hosting one persistent workshop
on fixed UDP port 22122 by default. The server process is the workshop authority and stores its save
under a separate LÖVE identity. The authority has an internal compatibility
actor for the current host simulation; that actor is omitted from player
welcome rosters and movement snapshots.

## Start the server

Run `tools/dedicated_server/Run-PrivateServer.ps1` from the project folder with LÖVE 11.5
and the native crypto candidate available. LÖVE 11.5 provides its own built-in `enet`
Lua module; a separate `enet.dll` is not required.
Defaults bind
to loopback only. To listen for clients outside the server's network, explicitly
set `-BindAddress '*' -PublicHost '<public DNS name or IP>'`, then configure the
host firewall/router for inbound UDP 22122. The launcher does not open firewall
rules or publish the endpoint. Use `-RunForSeconds <seconds>` for a bounded
private validation run; zero (the default) runs until shutdown.

The server creates `server-invite.txt` in its private save directory on first
start. It contains a persistent 32-byte pre-shared key and must be shared only
with invited players through a private channel. The key is never printed by the
server. Deleting or rotating that file changes who can authenticate.

Workshop data lives in
`%AppData%\LOVE\the-picture-shop-server-private\saves\slot1.lua`, with the
save system's normal recovery files and five-second checkpointing. The regular
game identities and settings are not used by the server.

## Join from a game client

Copy the invite file to a private location on a client, then run
`tools/dedicated_server/Join-PrivateServer.ps1 -InviteFile <path>`. The client
launches the game and joins through the encrypted transport. It uses the
separate `the-picture-shop-server-client-private` identity so prototype play
does not read or change ordinary local save slots.

The invitation is the admission credential: a client without the PSK cannot
complete the encrypted handshake. Any holder of the code can join while the
server is reachable. Reconnect attempts reuse the in-memory invite and back
off up to 30 seconds; restarting the server preserves its workshop and invite.
The client script accepts `-RunForSeconds <seconds>` for bounded join tests.

## Security status

This private prototype explicitly opts into the existing native crypto
candidate because `CryptoNative.productionReady` remains false. The production
Direct Play gate is unchanged. Keep this build private, limit UDP access at the
firewall to the intended testers where possible, and do not treat this as a
public release or a completed external security review.

## Current limits

- The current multiplayer protocol reserves worker ID 1 for the internal
  authority actor, so the prototype accepts up to three connected players.
- This source prototype does not create a standalone server installer. It uses
  LÖVE 11.5's built-in ENet module and needs the Windows x64 `tps_crypto.dll`
  candidate alongside the game source and LÖVE runtime. For AMP Docker on a
  Linux host, use a Wine-based AMP image for this Windows build; the default
  Debian image cannot load a Windows DLL. A native Linux container build needs
  a Linux crypto shared library and Linux LÖVE runtime instead.
- The same current game build must be used by all clients. Source protocol
  version is checked at runtime; older report version numbers are historical.
- Loopback join, disconnect, automatic reconnect after a server restart, valid
  save reload, backup recovery, and wrong-key rejection were validated locally.
  A join from outside the server's network and firewall/router scope still need
  validation against the actual public DNS name or IP. No public listener was
  opened for this prototype run.
