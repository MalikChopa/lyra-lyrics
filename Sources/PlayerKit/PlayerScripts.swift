import Foundation

/// Scripts compilés une fois (cache de `NSAppleScriptBackend`). Délai de 1 s dans chaque script.
/// Le résultat est une liste de 8 éléments : état, position (réel), nom, artiste, album, durée, identifiant, code d'erreur des propriétés du titre.
/// L'état est lu hors `try` (ses erreurs −1743/−600/−1712 remontent) ; chaque propriété du titre est dans son propre `try`.
public enum PlayerScripts {
    public static let spotifyRead = """
    with timeout of 1 second
    tell application id "com.spotify.client"
      set vState to (player state as text)
      set vPos to ""
      set vName to ""
      set vArtist to ""
      set vAlbum to ""
      set vDur to ""
      set vId to ""
      set vErr to 0
      try
        set vPos to player position
      end try
      try
        set vName to name of current track
      on error number n
        set vErr to n
      end try
      try
        set vArtist to artist of current track
      on error number n
        set vErr to n
      end try
      try
        set vAlbum to album of current track
      on error number n
        set vErr to n
      end try
      try
        set vDur to duration of current track
      on error number n
        set vErr to n
      end try
      try
        set vId to id of current track
      on error number n
        set vErr to n
      end try
      return {vState, vPos, vName, vArtist, vAlbum, vDur, vId, vErr}
    end tell
    end timeout
    """

    public static let musicRead = """
    with timeout of 1 second
    tell application id "com.apple.Music"
      set vState to (player state as text)
      set vPos to ""
      set vName to ""
      set vArtist to ""
      set vAlbum to ""
      set vDur to ""
      set vId to ""
      set vErr to 0
      try
        set vPos to player position
      end try
      try
        set vName to name of current track
      on error number n
        set vErr to n
      end try
      try
        set vArtist to artist of current track
      on error number n
        set vErr to n
      end try
      try
        set vAlbum to album of current track
      on error number n
        set vErr to n
      end try
      try
        set vDur to duration of current track
      on error number n
        set vErr to n
      end try
      try
        set vId to persistent ID of current track
      on error number n
        set vErr to n
      end try
      return {vState, vPos, vName, vArtist, vAlbum, vDur, vId, vErr}
    end tell
    end timeout
    """

    /// Lecture minimale (position seulement) pour le banc de transport (mesure 5).
    public static func positionOnly(_ player: PlayerID) -> String {
        """
        with timeout of 1 second
        tell application id "\(player.bundleID)" to return player position
        end timeout
        """
    }

    public static func readScript(for player: PlayerID) -> String {
        player == .spotify ? spotifyRead : musicRead
    }

    /// Interprète la liste de 8 éléments. Pure : testée avec des valeurs inventées.
    public static func parseReading(player: PlayerID, values: [ScriptValue]) -> Result<PlayerReading, ScriptError> {
        guard values.count == 8, let state = PlaybackState.parse(values[0].stringValue) else { return .failure(.invalidResult) }
        let errorCode = values[7].intValue ?? 0
        let name = values[2].stringValue
        let artist = values[3].stringValue
        let unreadable = errorCode != 0 || (state != .stopped && name == nil)
        var track: PlayerTrack?
        if let name {
            // Spotify : durée en millisecondes (mesuré en J1). Music : secondes.
            let raw = values[5].doubleValue
            let seconds = raw.map { player == .spotify ? $0 / 1000 : $0 }
            track = PlayerTrack(name: name, artist: artist ?? "", album: values[4].stringValue,
                                durationSeconds: seconds, trackID: values[6].stringValue)
        }
        return .success(PlayerReading(player: player, state: state, positionSeconds: values[1].doubleValue,
                                      track: track, trackUnreadable: unreadable))
    }
}

/// Notification Spotify `com.spotify.client.PlaybackStateChanged` (clés mesurées en J1 sur macOS 27).
public enum SpotifyNotificationParser {
    public static let notificationName = "com.spotify.client.PlaybackStateChanged"

    public static func parse(userInfo: [AnyHashable: Any]) -> PlayerReading? {
        guard let state = PlaybackState.parse(userInfo["Player State"] as? String) else { return nil }
        let name = userInfo["Name"] as? String
        var track: PlayerTrack?
        if let name, !name.isEmpty {
            let durationMs = (userInfo["Duration"] as? NSNumber)?.doubleValue
            track = PlayerTrack(name: name, artist: userInfo["Artist"] as? String ?? "", album: userInfo["Album"] as? String,
                                durationSeconds: durationMs.map { $0 / 1000 }, trackID: userInfo["Track ID"] as? String)
        }
        return PlayerReading(player: .spotify, state: state,
                             positionSeconds: (userInfo["Playback Position"] as? NSNumber)?.doubleValue, track: track)
    }
}
