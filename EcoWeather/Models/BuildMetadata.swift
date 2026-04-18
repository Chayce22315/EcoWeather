import Foundation

struct BuildMetadata: Codable, Equatable {
    let buildTime: String
    let runNumber: Int
    let carbonCommit: String

    enum CodingKeys: String, CodingKey {
        case buildTime = "build_time"
        case runNumber = "run_number"
        case carbonCommit = "carbon_commit"
    }

    static func loadFromBundle() -> BuildMetadata? {
        guard let url = Bundle.main.url(forResource: "build_metadata", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(BuildMetadata.self, from: data)
        } catch {
            return nil
        }
    }
}
