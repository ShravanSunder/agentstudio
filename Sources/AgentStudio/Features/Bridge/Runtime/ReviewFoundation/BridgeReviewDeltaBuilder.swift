import Foundation

struct BridgeReviewDeltaBuildRequest: Equatable, Sendable {
    let currentPackage: BridgeReviewPackage
    let nextPackage: BridgeReviewPackage
    let currentRevision: Int
}

enum BridgeReviewDeltaBuilderError: Error, Equatable, Sendable {
    case packageMismatch(current: String, next: String)
    case reviewGenerationMismatch(current: BridgeReviewGeneration, next: BridgeReviewGeneration)
}

enum BridgeReviewDeltaBuilder {
    static func build(_ request: BridgeReviewDeltaBuildRequest) throws -> BridgeReviewDelta? {
        guard request.currentPackage.packageId == request.nextPackage.packageId else {
            throw BridgeReviewDeltaBuilderError.packageMismatch(
                current: request.currentPackage.packageId,
                next: request.nextPackage.packageId
            )
        }
        guard request.currentPackage.reviewGeneration == request.nextPackage.reviewGeneration else {
            throw BridgeReviewDeltaBuilderError.reviewGenerationMismatch(
                current: request.currentPackage.reviewGeneration,
                next: request.nextPackage.reviewGeneration
            )
        }

        let currentItems = request.currentPackage.itemsById
        let nextItems = request.nextPackage.itemsById
        let currentItemIds = Set(currentItems.keys)
        let nextItemIds = Set(nextItems.keys)

        let addedItemIds = nextPackageOrder(request.nextPackage).filter { !currentItemIds.contains($0) }
        let currentOrderedItemIds = nextPackageOrder(request.currentPackage)
        let nextOrderedItemIds = nextPackageOrder(request.nextPackage)
        let removedItemIds = currentOrderedItemIds.filter { !nextItemIds.contains($0) }
        let updatedItemIds = nextPackageOrder(request.nextPackage).filter { itemId in
            guard currentItemIds.contains(itemId),
                let currentItem = currentItems[itemId],
                let nextItem = nextItems[itemId]
            else {
                return false
            }
            return currentItem != nextItem
        }
        let movedItemIds = movedItemIds(
            currentOrder: currentOrderedItemIds,
            nextOrder: nextOrderedItemIds
        )

        let updateGroups =
            request.currentPackage.groups == request.nextPackage.groups
            ? nil
            : request.nextPackage.groups
        let updateSummary =
            request.currentPackage.summary == request.nextPackage.summary
            ? nil
            : request.nextPackage.summary
        let invalidateContent = invalidatedContentHandleIds(
            currentItems: currentItems,
            nextItems: nextItems,
            removedItemIds: removedItemIds,
            updatedItemIds: updatedItemIds
        )

        let operations = BridgeReviewDelta.Operations(
            addItems: addedItemIds.compactMap { nextItems[$0] },
            updateItems: updatedItemIds.compactMap { itemId in
                guard let nextItem = nextItems[itemId],
                    let currentItem = currentItems[itemId]
                else {
                    return nil
                }
                return descriptorForDelta(nextItem, after: currentItem)
            },
            removeItems: removedItemIds,
            moveItems: movedItemIds,
            updateGroups: updateGroups,
            updateSummary: updateSummary,
            invalidateContent: invalidateContent
        )

        guard !operations.isEmpty else { return nil }
        return BridgeReviewDelta(
            packageId: request.currentPackage.packageId,
            reviewGeneration: request.currentPackage.reviewGeneration,
            revision: request.currentRevision + 1,
            operations: operations
        )
    }

    private static func nextPackageOrder(_ package: BridgeReviewPackage) -> [String] {
        var seen = Set<String>()
        var orderedIds: [String] = []
        for itemId in package.orderedItemIds where seen.insert(itemId).inserted {
            orderedIds.append(itemId)
        }
        for itemId in package.itemsById.keys.sorted() where seen.insert(itemId).inserted {
            orderedIds.append(itemId)
        }
        return orderedIds
    }

    private static func movedItemIds(
        currentOrder: [String],
        nextOrder: [String]
    ) -> [String] {
        guard currentOrder != nextOrder else { return [] }
        return nextOrder
    }

    private static func invalidatedContentHandleIds(
        currentItems: [String: BridgeReviewItemDescriptor],
        nextItems: [String: BridgeReviewItemDescriptor],
        removedItemIds: [String],
        updatedItemIds: [String]
    ) -> [String] {
        var invalidated = Set<String>()
        for itemId in removedItemIds {
            for handle in currentItems[itemId]?.contentRoles.allHandles ?? [] {
                invalidated.insert(handle.handleId)
            }
        }
        for itemId in updatedItemIds {
            for handle in currentItems[itemId]?.contentRoles.allHandles ?? [] {
                invalidated.insert(handle.handleId)
            }
            for handle in nextItems[itemId]?.contentRoles.allHandles ?? [] {
                invalidated.insert(handle.handleId)
            }
        }
        return invalidated.sorted()
    }

    private static func descriptorForDelta(
        _ nextItem: BridgeReviewItemDescriptor,
        after currentItem: BridgeReviewItemDescriptor
    ) -> BridgeReviewItemDescriptor {
        let nextVersion = max(nextItem.itemVersion, currentItem.itemVersion + 1)
        guard nextVersion != nextItem.itemVersion else { return nextItem }
        return BridgeReviewItemDescriptor(
            itemId: nextItem.itemId,
            itemKind: nextItem.itemKind,
            itemVersion: nextVersion,
            basePath: nextItem.basePath,
            headPath: nextItem.headPath,
            changeKind: nextItem.changeKind,
            fileClass: nextItem.fileClass,
            language: nextItem.language,
            extension: nextItem.extension,
            sizeBytes: nextItem.sizeBytes,
            baseContentHash: nextItem.baseContentHash,
            headContentHash: nextItem.headContentHash,
            contentHashAlgorithm: nextItem.contentHashAlgorithm,
            additions: nextItem.additions,
            deletions: nextItem.deletions,
            isHiddenByDefault: nextItem.isHiddenByDefault,
            hiddenReason: nextItem.hiddenReason,
            reviewPriority: nextItem.reviewPriority,
            contentRoles: nextItem.contentRoles,
            cacheKey: nextItem.cacheKey,
            provenance: nextItem.provenance,
            annotationSummary: nextItem.annotationSummary,
            reviewState: nextItem.reviewState,
            collapsed: nextItem.collapsed
        )
    }
}

extension BridgeReviewDelta.Operations {
    fileprivate var isEmpty: Bool {
        addItems.isEmpty
            && updateItems.isEmpty
            && removeItems.isEmpty
            && moveItems.isEmpty
            && updateGroups == nil
            && updateSummary == nil
            && invalidateContent.isEmpty
    }
}
