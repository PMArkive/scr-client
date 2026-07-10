# Source Chat Relay (scr-client)

SourceMod plugin that bridges in-game chat/events to a [scr-server](https://github.com/maxijabase/scr-server) relay over WebSocket, and displays messages relayed back from Discord in-game.

## Requirements

- SourceMod 1.11+ (`#pragma newdecls required`)
- [sm-ext-websocket](https://github.com/ProjectSky/sm-ext-websocket), the WebSocket client extension. Install the release matching your OS/SourceMod build.
- [sm-ripext](https://github.com/ErikMinekus/sm-ripext) ("REST in Pawn"), used to encode and decode the JSON messages sent over the WebSocket connection.
- SteamWorks extension (bundled with most SourceMod installs), used to key the persisted auth token file by public IP.

Install both extensions to `addons/sourcemod/extensions/` before loading this plugin.

> **Note:** this plugin deliberately avoids `sm-ext-websocket`'s own JSON mode, since the JSON extension it optionally relies on (`sm-ext-json`) declares `JSON`/`JSONObject`/`JSONArray` types that collide with ripext's own. Instead, the plugin connects in plain text mode and does its own JSON encoding/decoding with ripext, so `sm-ext-json` is never needed. The vendored `scripting/include/websocket*.inc` files are trimmed accordingly; see the comments at the top of each for details.

## Setup

1. Install the extensions above.
2. Load `scr.smx` (compiled from `scripting/scr.sp`).
3. Configure `cfg/sourcemod/scr.cfg` (auto-generated on first load):
   - `scr_host`: the `scr-server` relay's host (default `127.0.0.1`).
   - `scr_port`: the relay's WebSocket port (default `57452`, matching `scr-new`'s default `SCR_PORT`).
   - `scr_hostname`: display name sent with messages (falls back to the server's `hostname` convar if empty).
   - `scr_prefix` / `scr_flag`: optional chat prefix (and admin flag) required before a message is relayed. Leave `scr_prefix` empty to relay all chat.
   - `scr_event_player` / `scr_event_botplayer` / `scr_event_map`: enable player connect/disconnect and map start/end events.
   - `scr_chat_format` / `scr_event_format`: optional display format overrides for incoming Discord chat/events (see "Display formats" below). Leave empty to use the built-in default.
4. On first connect, the plugin generates and persists a random auth token in `addons/sourcemod/data/{publicIP}_{hostport}.data`. On the Discord side, once the server sends its first message, it'll show up by its `scr_hostname` in `/node list` and the `/link create` autocomplete, so there's no need to copy the raw token manually.
5. In Discord, run `/link create source:<this server> target:#your-channel direction:two_way types:chat,event` to start relaying.

## Display formats

By default, incoming Discord messages/events are printed to chat with a fixed color scheme. `scr_chat_format` and `scr_event_format` let you override this without writing a plugin, using ordered `%s` arguments (the same convention SourceMod's own `Format`/`PrintToChatAll` use) rather than named placeholders. This is intentional: a chat message that happens to contain a literal `%` (e.g. "boss is at 50% hp") is passed as a bound argument instead of being substituted into the template text, so it can never be misparsed as part of the format string.

- `scr_chat_format` arguments, in order: `(entity, name, message)`.
- `scr_event_format` arguments, in order: `(entity, event, data)`.

Both support [multicolors](https://github.com/qubka/Sourcemod-Multi-Colors)/[morecolors](https://forums.alliedmods.net/showthread.php?t=185015) color tags (e.g. `{gold}`) or raw color bytes, exactly like the built-in default. For reference, the built-in default for `scr_chat_format` is equivalent to setting it to:

```
{gold}[%s] {azure}%s{white}: {grey}%s
```

Leave either cvar empty (the default) to keep the built-in behavior unchanged.

## Notes

- The plugin auto-reconnects on disconnect (exponential backoff between 1 and 30 seconds), so no manual restart is needed if the relay server restarts.
- If the relay denies the auth token (e.g. it collides with an existing non-game-server node), the plugin logs the reason and unloads itself; fix the conflict via `/node`/`/link` commands in Discord and reload the plugin.
- Third-party plugins can still hook `SCR_OnMessageSend`/`SCR_OnMessageReceive`/`SCR_OnEventSend`/`SCR_OnEventReceive` and call `SCR_SendMessage`/`SCR_SendEvent`. This rewrite only changed the transport, not the public API in `scripting/include/scr.inc`.
