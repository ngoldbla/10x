// PhotoKitPlus — photo library access + curation (PRD §5.4).
//
// Apps never touch PHImageManager. They call a curation query, get
// `CuratedPhoto` values, and call `load()`. When the library is unauthorized
// or empty, every query silently returns DemoArt-backed photos instead, so
// each app works — and demos beautifully — with zero permissions.
#if os(tvOS)
import SwiftUI
import CouchCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(Photos)
import Photos
#endif
#if canImport(UIKit)
import UIKit
#endif

public enum CouchPhotoError: Error, Sendable {
    case assetUnavailable
    case loadFailed
}

/// One curated photo, sized on demand. Real library assets and procedural
/// demo art share this shape, so app code never branches on the source.
public struct CuratedPhoto: Identifiable, Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// Backed by a `DemoArt` recipe id.
        case demo(recipeID: String)
        /// Backed by a `PHAsset` local identifier.
        case asset(localIdentifier: String)
    }

    public let id: String
    public let displayDate: Date
    /// Human place name if known ("Lake Tahoe"); demo photos carry their
    /// fake locations. Real assets return `nil` in v1 (no geocoding).
    public let locationLabel: String?
    public let source: Source

    public init(id: String, displayDate: Date, locationLabel: String?, source: Source) {
        self.id = id
        self.displayDate = displayDate
        self.locationLabel = locationLabel
        self.source = source
    }

    /// Fetch pixels at the requested size (long edge). iCloud download is
    /// allowed; callers should show the previous frame until this resolves.
    public func load(maxDimension: Int = 1920) async throws -> CGImage {
        switch source {
        case .demo(let recipeID):
            guard let recipe = DemoArt.recipe(id: recipeID) else {
                throw CouchPhotoError.assetUnavailable
            }
            let width = maxDimension
            let height = max(1, maxDimension * 9 / 16)
            let buffer = DemoArt.render(recipe, width: width, height: height)
            guard let image = AsciiEngine.cgImage(from: buffer) else {
                throw CouchPhotoError.loadFailed
            }
            return image
        case .asset(let localIdentifier):
            #if canImport(Photos) && canImport(UIKit)
            return try await PhotoAccess.loadAsset(
                localIdentifier: localIdentifier, maxDimension: maxDimension
            )
            #else
            throw CouchPhotoError.assetUnavailable
            #endif
        }
    }
}

// MARK: - Authorization

public enum PhotoAccess {
    /// Read access granted (full or limited)?
    public static var isAuthorized: Bool {
        #if canImport(Photos)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
        #else
        return false
        #endif
    }

    /// Whether asking would show the system prompt (status not determined).
    public static var canPrompt: Bool {
        #if canImport(Photos)
        return PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined
        #else
        return false
        #endif
    }

    /// Run the system authorization prompt. Returns the resulting grant.
    @discardableResult
    public static func request() async -> Bool {
        #if canImport(Photos)
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
        #else
        return false
        #endif
    }

    #if canImport(Photos) && canImport(UIKit)
    static func loadAsset(localIdentifier: String, maxDimension: Int) async throws -> CGImage {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { throw CouchPhotoError.assetUnavailable }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        let side = CGFloat(maxDimension)
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                // highQualityFormat delivers exactly one result.
                if let cgImage = image?.cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: CouchPhotoError.loadFailed)
                }
            }
        }
    }
    #endif
}

// MARK: - Curation queries

/// The suite's curation vocabulary. Every query falls back to demo art when
/// the library is unauthorized or the fetch comes back empty.
public enum CouchPhotos {

    /// Photos taken on today's month/day across all years.
    public static func onThisDay(limit: Int = 24) async -> [CuratedPhoto] {
        #if canImport(Photos)
        if isUsable {
            let calendar = Calendar.current
            let today = calendar.dateComponents([.month, .day], from: Date())
            let photos = fetchAssets(limit: 4000).filter { asset in
                guard let created = asset.creationDate else { return false }
                let c = calendar.dateComponents([.month, .day], from: created)
                return c.month == today.month && c.day == today.day
            }
            if !photos.isEmpty {
                return Array(photos.prefix(limit)).map(curated)
            }
        }
        #endif
        return demoPhotos(limit: limit, seed: 0x0DAE)
    }

    /// Favorites, seeded-shuffled so a session revisits differently each seed.
    public static func randomMemorable(limit: Int = 24, seed: UInt64 = 0) async -> [CuratedPhoto] {
        #if canImport(Photos)
        if isUsable {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "favorite == YES")
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let favorites = fetchAssets(limit: 2000, options: options)
            if !favorites.isEmpty {
                var planner = SequencePlanner(
                    count: favorites.count,
                    window: min(favorites.count - 1, limit),
                    seed: seed
                )
                var picked = [CuratedPhoto]()
                for _ in 0..<min(limit, favorites.count) {
                    picked.append(curated(favorites[planner.next()]))
                }
                return picked
            }
        }
        #endif
        return demoPhotos(limit: limit, seed: seed &+ 0x3E30)
    }

    /// The newest photos, newest first.
    public static func recentHighlights(limit: Int = 24) async -> [CuratedPhoto] {
        #if canImport(Photos)
        if isUsable {
            let photos = fetchAssets(limit: limit)
            if !photos.isEmpty { return photos.map(curated) }
        }
        #endif
        return demoPhotos(limit: limit, seed: 0x4EC0)
    }

    /// Contents of a named user album, newest first.
    public static func album(named name: String, limit: Int = 60) async -> [CuratedPhoto] {
        #if canImport(Photos)
        if isUsable {
            let collectionOptions = PHFetchOptions()
            collectionOptions.predicate = NSPredicate(format: "localizedTitle == %@", name)
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: collectionOptions
            )
            if let album = collections.firstObject {
                let options = PHFetchOptions()
                options.fetchLimit = limit
                options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let fetch = PHAsset.fetchAssets(in: album, options: options)
                if fetch.count > 0 {
                    var photos = [CuratedPhoto]()
                    fetch.enumerateObjects { asset, _, _ in photos.append(curated(asset)) }
                    return photos
                }
            }
        }
        #endif
        return demoPhotos(limit: limit, seed: UInt64(truncatingIfNeeded: name.hashValue))
    }

    /// The demo channel directly (what unauthorized queries return).
    public static func demoPhotos(limit: Int = 24, seed: UInt64 = 0) -> [CuratedPhoto] {
        let recipes = DemoArt.recipes
        guard limit > 0 else { return [] }
        var planner = SequencePlanner(
            count: recipes.count, window: min(4, recipes.count - 1), seed: seed
        )
        return (0..<min(limit, recipes.count)).map { _ in
            let recipe = recipes[planner.next()]
            return CuratedPhoto(
                id: "demo-\(recipe.id)",
                displayDate: recipe.displayDate,
                locationLabel: recipe.locationLabel,
                source: .demo(recipeID: recipe.id)
            )
        }
    }

    // MARK: Internals

    #if canImport(Photos)
    static var isUsable: Bool { PhotoAccess.isAuthorized }

    static func fetchAssets(limit: Int, options: PHFetchOptions? = nil) -> [PHAsset] {
        let fetchOptions = options ?? {
            let o = PHFetchOptions()
            o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            return o
        }()
        if fetchOptions.fetchLimit == 0 { fetchOptions.fetchLimit = limit }
        if fetchOptions.predicate == nil {
            fetchOptions.predicate = NSPredicate(
                format: "mediaType == %d", PHAssetMediaType.image.rawValue
            )
        }
        let fetch = PHAsset.fetchAssets(with: fetchOptions)
        var assets = [PHAsset]()
        assets.reserveCapacity(min(limit, fetch.count))
        fetch.enumerateObjects { asset, index, stop in
            assets.append(asset)
            if index + 1 >= limit { stop.pointee = true }
        }
        return assets
    }

    static func curated(_ asset: PHAsset) -> CuratedPhoto {
        CuratedPhoto(
            id: asset.localIdentifier,
            displayDate: asset.creationDate ?? Date(timeIntervalSince1970: 0),
            locationLabel: nil,
            source: .asset(localIdentifier: asset.localIdentifier)
        )
    }
    #endif
}

// MARK: - PhotoPermissionView

/// The single beautiful pre-prompt: glass, one sentence, one button.
/// Show it only when `PhotoAccess.canPrompt`; apps remain fully usable
/// without it thanks to the demo channel.
public struct PhotoPermissionView: View {
    private let onResolved: @MainActor (Bool) -> Void

    public init(onResolved: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.onResolved = onResolved
    }

    public var body: some View {
        VStack(spacing: 44) {
            Text("Your photos, as living pixel art.")
                .couchText(CouchTypography.title)
                .multilineTextAlignment(.center)
            Button("Allow Photo Access") {
                Task { @MainActor in
                    let granted = await PhotoAccess.request()
                    onResolved(granted)
                }
            }
            .font(CouchTypography.body)
        }
        .padding(72)
        .couchGlass(in: RoundedRectangle(cornerRadius: 56, style: .continuous))
    }
}
#endif
