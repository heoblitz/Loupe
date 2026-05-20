import Foundation
import LoupeCore

struct BatchMutationPlan: Equatable {
    var targetRef: String
    var mutationRefs: [String]
    var value: LoupeMutationValue
    var frame: LoupeRect?
}

enum BatchMutationPlanner {
    static func makePlan(snapshot: LoupeSnapshot, options: BatchMutationOptions) -> [BatchMutationPlan] {
        selectedNodes(snapshot: snapshot, options: options)
            .sorted { lhs, rhs in
                let lhsFrame = lhs.frame
                let rhsFrame = rhs.frame
                if (lhsFrame?.y ?? 0) == (rhsFrame?.y ?? 0) {
                    return (lhsFrame?.x ?? 0) < (rhsFrame?.x ?? 0)
                }
                return (lhsFrame?.y ?? 0) < (rhsFrame?.y ?? 0)
            }
            .enumerated()
            .map { index, node in
                let childRefs = node.children.prefix(options.includeChildren)
                let mutationRefs = [node.ref] + childRefs
                return BatchMutationPlan(
                    targetRef: node.ref,
                    mutationRefs: Array(mutationRefs),
                    value: options.values[index % options.values.count],
                    frame: node.frame
                )
            }
    }

    private static func selectedNodes(snapshot: LoupeSnapshot, options: BatchMutationOptions) -> [LoupeNode] {
        switch options.selector {
        case let .refs(refs):
            return refs.compactMap { snapshot.nodes[$0] }.filter { matchesFilters($0, options: options) }
        case let .typeName(typeName):
            return snapshot.nodes.values.filter { $0.typeName == typeName && matchesFilters($0, options: options) }
        case let .role(role):
            return snapshot.nodes.values.filter { $0.role == role && matchesFilters($0, options: options) }
        case nil:
            return []
        }
    }

    private static func matchesFilters(_ node: LoupeNode, options: BatchMutationOptions) -> Bool {
        if options.visibleOnly, !node.isVisible {
            return false
        }
        if let yRange = options.yRange {
            guard let y = node.frame?.y, yRange.contains(y) else {
                return false
            }
        }
        return true
    }
}
