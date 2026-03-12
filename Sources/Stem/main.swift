import Foundation
import MCP
import MusicKit

// MARK: - Entry Point

let args = CommandLine.arguments

func log(_ msg: String) {
    FileHandle.standardError.write(Data("[stem] \(msg)\n".utf8))
}

if args.contains("setup") {
    await runSetup()
} else {
    do {
        log("starting server...")
        try await startServer()
    } catch {
        log("error: \(error)")
        exit(1)
    }
}

// MARK: - Setup Command

func runSetup() async {
    let binary = args[0]

    print("""

    Stem — Apple Music for your AI tools
    by Seaynic Labs

    """)

    let status = await MusicAuthorization.request()

    switch status {
    case .authorized:
        print("✓ Apple Music access granted\n")
    case .denied:
        print("✗ Apple Music access denied.")
        print("  Grant access in System Settings → Privacy & Security → Media & Apple Music\n")
        exit(1)
    case .restricted:
        print("✗ Apple Music access is restricted on this device.\n")
        exit(1)
    case .notDetermined:
        print("✗ Authorization was not determined. Try again.\n")
        exit(1)
    @unknown default:
        print("✗ Unknown authorization status.\n")
        exit(1)
    }

    print("""
    Add Stem to Claude Code:

      claude mcp add stem -- \(binary) serve

    Or add manually to ~/.claude.json:

      {
        "mcpServers": {
          "stem": {
            "command": "\(binary)",
            "args": ["serve"]
          }
        }
      }

    Setup complete. Try: "Search Apple Music for Tycho"
    """)
}

// MARK: - MCP Server

func startServer() async throws {
    // Skip MusicKit auth check — it hangs in non-interactive/headless contexts.
    // MusicKit API calls will fail individually if not authorized.
    // Run 'stem setup' in a terminal first to grant access.

    let server = Server(
        name: "stem",
        version: "0.1.0",
        capabilities: Server.Capabilities(
            tools: .init()
        )
    )

    // Register tool list handler
    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: [
            Tool(
                name: "search_catalog",
                description: "Search the Apple Music catalog for songs, albums, or artists",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search query")
                        ]),
                        "type": .object([
                            "type": .string("string"),
                            "description": .string("Type to search: song, album, or artist. Defaults to song.")
                        ]),
                        "limit": .object([
                            "type": .string("number"),
                            "description": .string("Max results to return (1-25, default 10)")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ),
            Tool(
                name: "get_song_details",
                description: "Get full details for a song by its Apple Music catalog ID",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Apple Music catalog song ID")
                        ])
                    ]),
                    "required": .array([.string("id")])
                ])
            ),
            Tool(
                name: "get_album_details",
                description: "Get full details for an album by its Apple Music catalog ID",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Apple Music catalog album ID")
                        ])
                    ]),
                    "required": .array([.string("id")])
                ])
            ),
            Tool(
                name: "get_now_playing",
                description: "Get the currently playing track in Apple Music",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ),
            Tool(
                name: "play_pause",
                description: "Toggle play/pause on Apple Music",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ),
            Tool(
                name: "skip_next",
                description: "Skip to the next track",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ),
            Tool(
                name: "skip_previous",
                description: "Go back to the previous track",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ),
            Tool(
                name: "play_song",
                description: "Play a specific song by its Apple Music catalog ID",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Apple Music catalog song ID")
                        ])
                    ]),
                    "required": .array([.string("id")])
                ])
            ),
            Tool(
                name: "get_queue",
                description: "Get the current playback queue",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ),
            Tool(
                name: "set_queue",
                description: "Set the playback queue to specific songs and start playing",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "ids": .object([
                            "type": .string("array"),
                            "description": .string("Array of Apple Music catalog song IDs"),
                            "items": .object([
                                "type": .string("string")
                            ])
                        ])
                    ]),
                    "required": .array([.string("ids")])
                ])
            ),
            Tool(
                name: "get_library_playlists",
                description: "List the user's Apple Music library playlists",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "limit": .object([
                            "type": .string("number"),
                            "description": .string("Max playlists to return (default 25)")
                        ])
                    ])
                ])
            ),
            Tool(
                name: "get_recently_played",
                description: "Get recently played tracks",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "limit": .object([
                            "type": .string("number"),
                            "description": .string("Max tracks to return (default 10)")
                        ])
                    ])
                ])
            ),
            Tool(
                name: "create_playlist",
                description: "Create a new playlist in the user's Apple Music library",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Name for the new playlist")
                        ]),
                        "description": .object([
                            "type": .string("string"),
                            "description": .string("Optional description for the playlist")
                        ])
                    ]),
                    "required": .array([.string("name")])
                ])
            ),
            Tool(
                name: "add_to_playlist",
                description: "Add songs to an existing playlist by playlist ID",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "playlist_id": .object([
                            "type": .string("string"),
                            "description": .string("The playlist's library ID")
                        ]),
                        "song_ids": .object([
                            "type": .string("array"),
                            "description": .string("Array of Apple Music catalog song IDs to add"),
                            "items": .object([
                                "type": .string("string")
                            ])
                        ])
                    ]),
                    "required": .array([.string("playlist_id"), .string("song_ids")])
                ])
            ),
            Tool(
                name: "ping",
                description: "Check if Stem is running and Apple Music is authorized",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            )
        ])
    }

    // Register tool call handler
    await server.withMethodHandler(CallTool.self) { params in
        switch params.name {
        case "ping":
            return .init(content: [.text("Stem v0.1.0 is running. Apple Music is authorized.")])

        case "search_catalog":
            do {
                return try await handleSearchCatalog(params: params)
            } catch {
                return .init(content: [.text("Search error: \(error)")], isError: true)
            }

        case "get_song_details":
            return try await handleGetSongDetails(params: params)

        case "get_album_details":
            return try await handleGetAlbumDetails(params: params)

        case "get_now_playing":
            return await handleGetNowPlaying()

        case "play_pause":
            return await handlePlayPause()

        case "skip_next":
            return await handleSkipNext()

        case "skip_previous":
            return await handleSkipPrevious()

        case "play_song":
            return try await handlePlaySong(params: params)

        case "get_queue":
            return await handleGetQueue()

        case "set_queue":
            return try await handleSetQueue(params: params)

        case "get_library_playlists":
            return try await handleGetLibraryPlaylists(params: params)

        case "get_recently_played":
            return try await handleGetRecentlyPlayed(params: params)

        case "create_playlist":
            return try await handleCreatePlaylist(params: params)

        case "add_to_playlist":
            return try await handleAddToPlaylist(params: params)

        default:
            return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
        }
    }

    // Start stdio transport
    let transport = StdioTransport()
    try await server.start(transport: transport)

    // Keep the server alive — the StdioTransport handles stdin/stdout.
    // Use an async stream that never yields to block without consuming resources.
    for await _ in AsyncStream<Never>(unfolding: { nil }) { }
}

// MARK: - Tool Handlers

func handleSearchCatalog(params: CallTool.Parameters) async throws -> CallTool.Result {
    guard let query = params.arguments?["query"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: query")], isError: true)
    }

    let limit = params.arguments?["limit"]?.intValue ?? 10
    let typeStr = params.arguments?["type"]?.stringValue ?? "song"
    let clampedLimit = min(max(limit, 1), 25)

    var results: [String] = []

    switch typeStr {
    case "album":
        var request = MusicCatalogSearchRequest(term: query, types: [Album.self])
        request.limit = clampedLimit
        let response = try await request.response()
        for album in response.albums {
            results.append("[\(album.id)] \(album.title) by \(album.artistName) (\(album.releaseDate?.formatted(.dateTime.year()) ?? "unknown"))")
        }

    case "artist":
        var request = MusicCatalogSearchRequest(term: query, types: [Artist.self])
        request.limit = clampedLimit
        let response = try await request.response()
        for artist in response.artists {
            results.append("[\(artist.id)] \(artist.name)")
        }

    default:
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = clampedLimit
        let response = try await request.response()
        for song in response.songs {
            results.append("[\(song.id)] \(song.title) by \(song.artistName) — \(song.albumTitle ?? "unknown album")")
        }
    }

    if results.isEmpty {
        return .init(content: [.text("No results found for '\(query)'")])
    }

    return .init(content: [.text(results.joined(separator: "\n"))])
}

func handleGetSongDetails(params: CallTool.Parameters) async throws -> CallTool.Result {
    guard let songID = params.arguments?["id"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: id")], isError: true)
    }

    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songID))
    let response = try await request.response()

    guard let song = response.items.first else {
        return .init(content: [.text("No song found with ID: \(songID)")], isError: true)
    }

    var lines: [String] = [
        "Title: \(song.title)",
        "Artist: \(song.artistName)",
        "Album: \(song.albumTitle ?? "Unknown")",
    ]
    if let duration = song.duration {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        lines.append("Duration: \(mins):\(String(format: "%02d", secs))")
    }
    if let genres = song.genreNames.first {
        lines.append("Genre: \(genres)")
    }
    if let releaseDate = song.releaseDate {
        lines.append("Released: \(releaseDate.formatted(.dateTime.year().month().day()))")
    }
    if let disc = song.discNumber { lines.append("Disc: \(disc)") }
    if let track = song.trackNumber { lines.append("Track: \(track)") }

    return .init(content: [.text(lines.joined(separator: "\n"))])
}

func handleGetAlbumDetails(params: CallTool.Parameters) async throws -> CallTool.Result {
    guard let albumID = params.arguments?["id"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: id")], isError: true)
    }

    var request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(albumID))
    request.properties = [.tracks]
    let response = try await request.response()

    guard let album = response.items.first else {
        return .init(content: [.text("No album found with ID: \(albumID)")], isError: true)
    }

    var lines: [String] = [
        "Album: \(album.title)",
        "Artist: \(album.artistName)",
    ]
    if let releaseDate = album.releaseDate {
        lines.append("Released: \(releaseDate.formatted(.dateTime.year().month().day()))")
    }
    if let genre = album.genreNames.first {
        lines.append("Genre: \(genre)")
    }
    lines.append("Track Count: \(album.trackCount)")

    if let tracks = album.tracks {
        lines.append("")
        lines.append("Tracks:")
        for (i, track) in tracks.enumerated() {
            let duration = track.duration.map { d in
                let m = Int(d) / 60
                let s = Int(d) % 60
                return " (\(m):\(String(format: "%02d", s)))"
            } ?? ""
            lines.append("  \(i + 1). [\(track.id)] \(track.title)\(duration)")
        }
    }

    return .init(content: [.text(lines.joined(separator: "\n"))])
}

func handleGetNowPlaying() async -> CallTool.Result {
    let player = ApplicationMusicPlayer.shared

    guard let entry = player.queue.currentEntry else {
        return .init(content: [.text("Nothing is currently playing.")])
    }

    let state = player.state.playbackStatus == .playing ? "Playing" : "Paused"

    if case .song(let song) = entry.item {
        return .init(content: [.text("\(state): \(song.title) by \(song.artistName) — \(song.albumTitle ?? "")")])
    }

    return .init(content: [.text("\(state): \(entry.title)")])
}

func handlePlayPause() async -> CallTool.Result {
    let player = ApplicationMusicPlayer.shared

    do {
        if player.state.playbackStatus == .playing {
            player.pause()
            return .init(content: [.text("Paused.")])
        } else {
            try await player.play()
            return .init(content: [.text("Playing.")])
        }
    } catch {
        return .init(content: [.text(playbackErrorMessage(error))], isError: true)
    }
}

func handleSkipNext() async -> CallTool.Result {
    let player = ApplicationMusicPlayer.shared
    do {
        try await player.skipToNextEntry()
        // Small delay for the queue to update
        try? await Task.sleep(for: .milliseconds(200))
        return await handleGetNowPlaying()
    } catch {
        return .init(content: [.text(playbackErrorMessage(error))], isError: true)
    }
}

func handleSkipPrevious() async -> CallTool.Result {
    let player = ApplicationMusicPlayer.shared
    do {
        try await player.skipToPreviousEntry()
        try? await Task.sleep(for: .milliseconds(200))
        return await handleGetNowPlaying()
    } catch {
        return .init(content: [.text(playbackErrorMessage(error))], isError: true)
    }
}

// MARK: - Phase 3: play_song, queue

func handlePlaySong(params: CallTool.Parameters) async throws -> CallTool.Result {
    guard let songID = params.arguments?["id"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: id")], isError: true)
    }

    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songID))
    let response = try await request.response()

    guard let song = response.items.first else {
        return .init(content: [.text("No song found with ID: \(songID)")], isError: true)
    }

    let player = ApplicationMusicPlayer.shared
    player.queue = [song]

    do {
        try await player.play()
        return .init(content: [.text("Now playing: \(song.title) by \(song.artistName)")])
    } catch {
        return .init(content: [.text(playbackErrorMessage(error))], isError: true)
    }
}

func handleGetQueue() async -> CallTool.Result {
    let player = ApplicationMusicPlayer.shared
    let entries = player.queue.entries

    if entries.isEmpty {
        return .init(content: [.text("Queue is empty.")])
    }

    var lines: [String] = []
    for (i, entry) in entries.enumerated() {
        let prefix = entry == player.queue.currentEntry ? "▶ " : "  "
        if case .song(let song) = entry.item {
            lines.append("\(prefix)\(i + 1). \(song.title) by \(song.artistName)")
        } else {
            lines.append("\(prefix)\(i + 1). \(entry.title)")
        }
    }

    return .init(content: [.text(lines.joined(separator: "\n"))])
}

func handleSetQueue(params: CallTool.Parameters) async throws -> CallTool.Result {
    guard let idsValue = params.arguments?["ids"],
          case .array(let idsArray) = idsValue else {
        return .init(content: [.text("Missing required parameter: ids (array of song IDs)")], isError: true)
    }

    let ids = idsArray.compactMap { value -> String? in
        if case .string(let s) = value { return s }
        return nil
    }

    if ids.isEmpty {
        return .init(content: [.text("No valid song IDs provided.")], isError: true)
    }

    // Fetch all songs by ID
    var songs: [Song] = []
    for id in ids {
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        if let song = response.items.first {
            songs.append(song)
        }
    }

    if songs.isEmpty {
        return .init(content: [.text("None of the provided IDs matched songs in the catalog.")], isError: true)
    }

    let player = ApplicationMusicPlayer.shared
    player.queue = ApplicationMusicPlayer.Queue(for: songs)

    do {
        try await player.play()
        return .init(content: [.text("Queue set with \(songs.count) songs. Now playing: \(songs[0].title) by \(songs[0].artistName)")])
    } catch {
        return .init(content: [.text(playbackErrorMessage(error))], isError: true)
    }
}

// MARK: - Phase 4: Library Operations

func handleGetLibraryPlaylists(params: CallTool.Parameters) async throws -> CallTool.Result {
    let limit = params.arguments?["limit"]?.intValue ?? 25
    let clampedLimit = min(max(limit, 1), 100)

    // Use REST API — MusicLibraryRequest<Playlist> returns empty on macOS CLI
    let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists?limit=\(clampedLimit)")!
    let dataRequest = MusicDataRequest(urlRequest: URLRequest(url: url))
    let response = try await dataRequest.response()

    let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
    let data = json?["data"] as? [[String: Any]] ?? []

    if data.isEmpty {
        return .init(content: [.text("No playlists found in your library.")])
    }

    var lines: [String] = []
    for item in data {
        let id = item["id"] as? String ?? "?"
        let attrs = item["attributes"] as? [String: Any] ?? [:]
        let name = attrs["name"] as? String ?? "Untitled"
        lines.append("[\(id)] \(name)")
    }

    return .init(content: [.text(lines.joined(separator: "\n"))])
}

func handleGetRecentlyPlayed(params: CallTool.Parameters) async throws -> CallTool.Result {
    let limit = params.arguments?["limit"]?.intValue ?? 10
    let clampedLimit = min(max(limit, 1), 25)

    let url = URL(string: "https://api.music.apple.com/v1/me/recent/played/tracks")!
    let dataRequest = MusicDataRequest(urlRequest: URLRequest(url: url))
    let response = try await dataRequest.response()

    // Parse the JSON response
    let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
    let data = json?["data"] as? [[String: Any]] ?? []

    if data.isEmpty {
        return .init(content: [.text("No recently played tracks found.")])
    }

    var lines: [String] = []
    for (i, item) in data.prefix(clampedLimit).enumerated() {
        let attrs = item["attributes"] as? [String: Any] ?? [:]
        let name = attrs["name"] as? String ?? "Unknown"
        let artist = attrs["artistName"] as? String ?? "Unknown"
        let album = attrs["albumName"] as? String ?? ""
        lines.append("\(i + 1). \(name) by \(artist) — \(album)")
    }

    return .init(content: [.text(lines.joined(separator: "\n"))])
}

func handleCreatePlaylist(params: CallTool.Parameters) async throws -> CallTool.Result {
    guard let name = params.arguments?["name"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: name")], isError: true)
    }

    let description = params.arguments?["description"]?.stringValue

    // MusicLibrary.createPlaylist is unavailable on macOS — use REST API
    var attributes: [String: Any] = ["name": name]
    if let description = description {
        attributes["description"] = description
    }

    let body: [String: Any] = [
        "attributes": attributes
    ]

    let bodyData = try JSONSerialization.data(withJSONObject: body)

    let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists")!
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = bodyData
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let dataRequest = MusicDataRequest(urlRequest: urlRequest)
    let response = try await dataRequest.response()

    // Parse response to get playlist ID
    if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
       let data = json["data"] as? [[String: Any]],
       let first = data.first,
       let id = first["id"] as? String,
       let attrs = first["attributes"] as? [String: Any],
       let playlistName = attrs["name"] as? String {
        return .init(content: [.text("Created playlist: \(playlistName) [ID: \(id)]")])
    }

    return .init(content: [.text("Playlist created, but could not parse response. Check Music.app.")])
}

func handleAddToPlaylist(params: CallTool.Parameters) async throws -> CallTool.Result {
    guard let playlistID = params.arguments?["playlist_id"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: playlist_id")], isError: true)
    }

    guard let songIdsValue = params.arguments?["song_ids"],
          case .array(let songIdsArray) = songIdsValue else {
        return .init(content: [.text("Missing required parameter: song_ids (array of song IDs)")], isError: true)
    }

    let songIds = songIdsArray.compactMap { value -> String? in
        if case .string(let s) = value { return s }
        return nil
    }

    if songIds.isEmpty {
        return .init(content: [.text("No valid song IDs provided.")], isError: true)
    }

    // POST directly to the REST API — MusicLibraryRequest doesn't reliably
    // find playlists on macOS, especially newly created ones.
    let trackData = songIds.map { id -> [String: Any] in
        ["id": id, "type": "songs"]
    }

    let body: [String: Any] = ["data": trackData]
    let bodyData = try JSONSerialization.data(withJSONObject: body)

    let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistID)/tracks")!
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = bodyData
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let dataRequest = MusicDataRequest(urlRequest: urlRequest)
    _ = try await dataRequest.response()

    return .init(content: [.text("Added \(songIds.count) songs to playlist \(playlistID).")])
}

// MARK: - Error Handling

func playbackErrorMessage(_ error: Error) -> String {
    let message = error.localizedDescription.lowercased()

    if message.contains("subscription") || message.contains("not subscribed") || message.contains("offer") {
        return "Playback requires an active Apple Music subscription. Catalog search and library access still work without one."
    }

    if message.contains("queue") || message.contains("empty") {
        return "Nothing in the playback queue. Try playing a specific song first."
    }

    return "Playback error: \(error.localizedDescription)"
}
