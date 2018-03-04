import XCTest
import IntentionPasses
import SwiftRewriterLib

class IntentionPassesTests: XCTestCase {
    func testDefaultIntentionPasses() {
        let intents = DefaultIntentionPasses().intentionPasses
        
        XCTAssertEqual(intents.count, 6)
        
        XCTAssert(intents[0] is FileTypeMergingIntentionPass)
        XCTAssert(intents[1] is StoredPropertyToNominalTypesIntentionPass)
        XCTAssert(intents[2] is ProtocolNullabilityPropagationToConformersIntentionPass)
        XCTAssert(intents[3] is PropertyMergeIntentionPass)
        XCTAssert(intents[4] is SwiftifyMethodSignaturesIntentionPass)
        XCTAssert(intents[5] is ImportDirectiveIntentionPass)
    }
}

// Helper method for constructing intention pass contexts for tests
func makeContext(intentions: IntentionCollection) -> IntentionPassContext {
    let system = IntentionCollectionTypeSystem(intentions: intentions)
    let invoker = DefaultTypeResolverInvoker(typeSystem: system)
    let typeMapper = DefaultTypeMapper(context: TypeConstructionContext(typeSystem: system))
    
    return IntentionPassContext(typeSystem: system, typeMapper: typeMapper, typeResolverInvoker: invoker)
}
