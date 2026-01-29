import Foundation

enum SortOption: String, CaseIterable {
    case name, duration, recent, size, mostWatched

    var defaultAscending: Bool {
        self == .name
    }
}

extension Array where Element == Video {
    func filtered(by searchText: String) -> [Video] {
        if searchText.isEmpty {
            return self
        } else {
            return filter { video in
                let name = video.name.folding(options: .diacriticInsensitive, locale: .current)
                let query = searchText.folding(options: .diacriticInsensitive, locale: .current)
                return name.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func sorted(by option: SortOption, ascending: Bool) -> [Video] {
        sorted { v1, v2 in
            switch option {
            case .name:
                return ascending ? v1.name < v2.name : v1.name > v2.name
            case .duration:
                return ascending ? v1.duration < v2.duration : v1.duration > v2.duration
            case .recent:
                if v1.isWatched != v2.isWatched {
                    return !v1.isWatched
                }
                return ascending ? v1.dateAdded < v2.dateAdded : v1.dateAdded > v2.dateAdded
            case .size:
                return ascending ? v1.fileSize < v2.fileSize : v1.fileSize > v2.fileSize
            case .mostWatched:
                return ascending ? v1.watchCount < v2.watchCount : v1.watchCount > v2.watchCount
            }
        }
    }
}
