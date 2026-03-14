import Foundation
import MCP
import MusicKit
import StemCore

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
        name: Stem.serverName,
        version: Stem.serverVersion,
        capabilities: Server.Capabilities(
            tools: .init()
        )
    )

    // Register tool list handler
    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: Stem.tools)
    }

    // Register tool call handler
    await server.withMethodHandler(CallTool.self) { params in
        switch params.name {
        case "ping":
            return .init(content: [.text(Stem.pingResponse)])

        case "search_catalog":
            do {
                return try await handleSearchCatalog(params: params)
            } catch {
                return .init(content: [.text("Search error: \(error)")], isError: true)
            }

        case "get_song_details":
            do {
                return try await handleGetSongDetails(params: params)
            } catch {
                return .init(content: [.text("Error getting song details: \(error.localizedDescription)")], isError: true)
            }

        case "get_album_details":
            do {
                return try await handleGetAlbumDetails(params: params)
            } catch {
                return .init(content: [.text("Error getting album details: \(error.localizedDescription)")], isError: true)
            }

        case "get_now_playing":
            return await handleGetNowPlaying()

        case "play_pause":
            return await handlePlayPause()

        case "skip_next":
            return await handleSkipNext()

        case "skip_previous":
            return await handleSkipPrevious()

        case "play_song":
            do {
                return try await handlePlaySong(params: params)
            } catch {
                return .init(content: [.text(playbackErrorMessage(error))], isError: true)
            }

        case "get_queue":
            return await handleGetQueue()

        case "set_queue":
            do {
                return try await handleSetQueue(params: params)
            } catch {
                return .init(content: [.text(playbackErrorMessage(error))], isError: true)
            }

        case "get_library_playlists":
            do {
                return try await handleGetLibraryPlaylists(params: params)
            } catch {
                return .init(content: [.text("Error fetching playlists: \(error.localizedDescription)")], isError: true)
            }

        case "get_recently_played":
            do {
                return try await handleGetRecentlyPlayed(params: params)
            } catch {
                return .init(content: [.text("Error fetching recently played: \(error.localizedDescription)")], isError: true)
            }

        case "create_playlist":
            do {
                return try await handleCreatePlaylist(params: params)
            } catch {
                return .init(content: [.text("Error creating playlist: \(error.localizedDescription)")], isError: true)
            }

        case "add_to_playlist":
            do {
                return try await handleAddToPlaylist(params: params)
            } catch {
                return .init(content: [.text("Error adding to playlist: \(error.localizedDescription)")], isError: true)
            }

        default:
            return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
        }
    }

    // Start stdio transport
    let transport = StdioTransport()
    try await server.start(transport: transport)

    // Keep the process alive until the transport disconnects.
    await server.waitUntilCompleted()
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

    case "song":
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = clampedLimit
        let response = try await request.response()
        for song in response.songs {
            results.append("[\(song.id)] \(song.title) by \(song.artistName) — \(song.albumTitle ?? "unknown album")")
        }

    default:
        return .init(content: [.text("Unsupported search type: '\(typeStr)'. Use 'song', 'album', or 'artist'.")], isError: true)
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
    guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists?limit=\(clampedLimit)") else {
        return .init(content: [.text("Failed to construct API URL.")], isError: true)
    }
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

    guard let url = URL(string: "https://api.music.apple.com/v1/me/recent/played/tracks?limit=\(clampedLimit)") else {
        return .init(content: [.text("Failed to construct API URL.")], isError: true)
    }
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

    guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists") else {
        return .init(content: [.text("Failed to construct API URL.")], isError: true)
    }
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

    // Validate playlist ID format (alphanumeric with dots, e.g. "p.XXXXXXXXX")
    let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "."))
    guard playlistID.unicodeScalars.allSatisfy({ allowedChars.contains($0) }) else {
        return .init(content: [.text("Invalid playlist ID format: \(playlistID)")], isError: true)
    }

    // POST directly to the REST API — MusicLibraryRequest doesn't reliably
    // find playlists on macOS, especially newly created ones.
    let trackData = songIds.map { id -> [String: Any] in
        ["id": id, "type": "songs"]
    }

    let body: [String: Any] = ["data": trackData]
    let bodyData = try JSONSerialization.data(withJSONObject: body)

    guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistID)/tracks") else {
        return .init(content: [.text("Failed to construct API URL.")], isError: true)
    }
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
