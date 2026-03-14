<p align="center">
  <img src="docs/assets/stem-logo.png" alt="Stem" width="200">
</p>

<h1 align="center">Stem</h1>

<p align="center"><strong>Apple Music for your AI tools.</strong></p>

Stem is a native macOS [MCP server](https://modelcontextprotocol.io) that lets AI tools like Claude Code, Cursor, and Windsurf search, play, and manage Apple Music through natural language.

No API keys. No browser auth flows. One command to install, one prompt to set up.

## What it does

| Tool | Description |
|------|-------------|
| `search_catalog` | Search Apple Music for songs, albums, or artists |
| `get_song_details` | Get full metadata for a song |
| `get_album_details` | Get album info with track listing |
| `play_song` | Play a specific song by catalog ID |
| `play_pause` | Toggle playback |
| `skip_next` / `skip_previous` | Track navigation |
| `get_now_playing` | Current track info and playback state |
| `get_queue` / `set_queue` | Read or replace the playback queue |
| `get_library_playlists` | List your playlists |
| `get_recently_played` | Recent listening history |
| `create_playlist` | Create a new playlist |
| `add_to_playlist` | Add songs to a playlist |
| `ping` | Health check |

## Requirements

- macOS 14+ (Sonoma or later)
- Apple Music subscription (for playback; catalog search works without one)
- An MCP-compatible AI tool (Claude Code, Cursor, Windsurf, etc.)

## Install

### Homebrew (recommended)

```bash
brew install seayniclabs/tap/stem
```

### From source

```bash
git clone https://github.com/seayniclabs/stem.git
cd stem
swift build -c release
```

The binary is at `.build/release/Stem`.

### First-time setup

Run the setup command to grant Apple Music access:

```bash
stem setup
```

This triggers the macOS permission prompt. You only need to do this once.

### Add to Claude Code

```bash
claude mcp add stem -- $(which stem)
```

Or add manually to `~/.claude.json`:

```json
{
  "mcpServers": {
    "stem": {
      "command": "/path/to/stem",
      "args": ["serve"]
    }
  }
}
```

## Usage

Once connected, just talk to your AI tool:

- "Search Apple Music for Tycho"
- "Play Everlong by Foo Fighters"
- "Create a playlist called Focus and add these tracks"
- "What's playing right now?"
- "Skip to the next track"

## How it works

Stem uses Apple's [MusicKit](https://developer.apple.com/musickit/) framework to interact with Apple Music natively on macOS. It communicates with AI tools over stdio using the [Model Context Protocol](https://modelcontextprotocol.io) (JSON-RPC).

```
AI Tool  --stdio/JSON-RPC-->  Stem  --MusicKit-->  Apple Music
                                    --ApplicationMusicPlayer-->  Music.app
```

Auth is handled by macOS — the binary has an embedded bundle identifier (`com.seayniclabs.stem`) and the MusicKit entitlement. Users just click "Allow" once when prompted. No tokens, no refresh logic, no config files.

## Building

```bash
swift build           # debug build
swift build -c release  # release build
```

Stem requires Swift 6.1+ and targets macOS 14+.

## License

MIT

## Credits

Built by [Seaynic Labs](https://seayniclabs.com).
