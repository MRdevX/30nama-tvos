#if DEBUG
import Foundation

/// Development aid: the trending rows need a TMDB token, so this stands in for TMDB and lets the
/// rows be tried without one. Launch with the environment variable `NAMA_TMDB_MOCK` set to a folder
/// of saved TMDB responses named `trending.json`, `on_the_air.json` and `now_playing.json` (the
/// Tizen client keeps such a set in tizen-app/tools/fixtures). 30nama itself is still asked for
/// real, so the matching and the rows are the genuine article. Not compiled into release builds.
enum DemoTrending {
    static var transport: Transport? {
        guard let folder = ProcessInfo.processInfo.environment["NAMA_TMDB_MOCK"], !folder.isEmpty else { return nil }
        return { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let name = url.path.contains("/trending/") ? "trending" : url.path.contains("/discover/tv") ? "on_the_air" : "now_playing"
            let data = try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(name + ".json"))
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { throw URLError(.badServerResponse) }
            return (data, response)
        }
    }
}
#endif
