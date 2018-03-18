import SwiftAST

/// Helper known-type builder used to come up with default types and during testing
/// as well
public class KnownTypeBuilder {
    public typealias ParameterTuple = (label: String, type: SwiftType)
    
    private let type: DummyType
    
    public init(typeName: String, supertype: KnownSupertypeConvertible? = nil,
                kind: KnownTypeKind = .class, file: String = #file,
                line: Int = #line) {
        type = DummyType(typeName: typeName, supertype: supertype)
        
        type.kind = kind
        type.origin = "Synthesized with \(KnownTypeBuilder.self) at \(file) line \(line)"
    }
    
    /// Sets the supertype of the type being constructed on this known type builder
    public func settingSupertype(_ supertype: KnownSupertypeConvertible?) -> KnownTypeBuilder {
        type.supertype = supertype?.asKnownSupertype
        return self
    }
    
    /// Sets the kind of the type being built
    public func settingKind(_ kind: KnownTypeKind) -> KnownTypeBuilder {
        type.kind = kind
        return self
    }
    
    /// Adds a parameter-less constructor to this type
    public func constructor() -> KnownTypeBuilder {
        assert(!type.knownConstructors.contains { $0.parameters.isEmpty },
               "An empty constructor is already provided")
        
        return constructor(withParameters: [])
    }
    
    /// Adds a new constructor to this type
    public func constructor(shortParameters shortParams: [ParameterTuple]) -> KnownTypeBuilder {
        let parameters =
            shortParams.map { tuple in
                ParameterSignature(name: tuple.label, type: tuple.type)
            }
        
        return constructor(withParameters: parameters)
    }
    
    /// Adds a new constructor to this type
    public func constructor(withParameters parameters: [ParameterSignature]) -> KnownTypeBuilder {
        let ctor = DummyConstructor(parameters: parameters)
        
        type.knownConstructors.append(ctor)
        
        return self
    }
    
    /// Adds an instance method with a given return type, and a flag
    /// specifying whether the method is an optional protocol conformance method
    public func method(named name: String, shortParams: [ParameterTuple] = [],
                       returning returnType: SwiftType = .void,
                       optional: Bool = false,
                       useSwiftSignatureMatching: Bool = false) -> KnownTypeBuilder {
        let parameters =
            shortParams.map { tuple in
                ParameterSignature(name: tuple.label, type: tuple.type)
        }
        
        let signature = FunctionSignature(name: name, parameters: parameters,
                                          returnType: returnType)
        
        return method(withSignature: signature, optional: optional,
                      useSwiftSignatureMatching: useSwiftSignatureMatching)
    }
    
    /// Adds a method with a given signature, and a flag specifying whether the
    /// method is an optional protocol conformance method
    public func method(withSignature signature: FunctionSignature,
                       optional: Bool = false, useSwiftSignatureMatching: Bool = false) -> KnownTypeBuilder {
        // Check duplicates
        if useSwiftSignatureMatching {
            if type.knownMethods.contains(where: { $0.signature.matchesAsSwiftFunction(signature) }) {
                return self
            }
        } else if type.knownMethods.contains(where: { $0.signature.matchesAsSelector(signature) }) {
            return self
        }
        
        let method = DummyMethod(ownerType: type, body: nil, signature: signature,
                                 optional: optional)
        
        type.knownMethods.append(method)
        
        return self
    }
    
    /// Adds a strong property with no attributes with a given name and type, and
    /// a flag specifying whether the property is an optional protocol conformance
    /// property
    public func property(named name: String, type: SwiftType, ownership: Ownership = .strong,
                         isStatic: Bool = false, optional: Bool = false,
                         accessor: KnownPropertyAccessor = .getterAndSetter) -> KnownTypeBuilder {
        let storage = ValueStorage(type: type, ownership: ownership, isConstant: false)
        
        return property(named: name, storage: storage, isStatic: isStatic,
                              optional: optional, accessor: accessor)
    }
    
    /// Adds a property with no attributes with a given name and storage, and a
    /// flag specifying whether the property is an optional protocol conformance
    /// property
    public func property(named name: String, storage: ValueStorage, isStatic: Bool = false,
                         optional: Bool = false, accessor: KnownPropertyAccessor = .getterAndSetter) -> KnownTypeBuilder {
        // Check duplicates
        guard !type.knownProperties.contains(where: {
            $0.name == name && $0.storage == storage && $0.isStatic == isStatic
        }) else {
            return self
        }
        
        let property = DummyProperty(ownerType: type, name: name, storage: storage,
                                     attributes: [], isStatic: isStatic,
                                     optional: optional, accessor: accessor)
        
        type.knownProperties.append(property)
        
        return self
    }
    
    /// Adds a strong field with no attributes with a given name and type
    public func field(named name: String, type: SwiftType, isConstant: Bool = false,
                      isStatic: Bool = false) -> KnownTypeBuilder {
        let storage = ValueStorage(type: type, ownership: .strong, isConstant: isConstant)
        
        return field(named: name, storage: storage, isStatic: isStatic)
    }
    
    /// Adds a property with no attributes with a given name and storage
    public func field(named name: String, storage: ValueStorage, isStatic: Bool = false) -> KnownTypeBuilder {
        // Check duplicates
        guard !type.knownFields.contains(where: {
            $0.name == name && $0.storage == storage && $0.isStatic == isStatic
        }) else {
            return self
        }
        
        let property = DummyProperty(ownerType: type, name: name, storage: storage,
                                     attributes: [], isStatic: isStatic,
                                     optional: false, accessor: .getterAndSetter)
        
        type.knownFields.append(property)
        
        return self
    }
    
    public func protocolConformance(protocolName: String) -> KnownTypeBuilder {
        // Check duplicates
        guard !type.knownProtocolConformances.contains(where: { $0.protocolName == protocolName }) else {
            return self
        }
        
        let conformance = DummyProtocolConformance(protocolName: protocolName)
        
        type.knownProtocolConformances.append(conformance)
        
        return self
    }
    
    /// Returns the constructed KnownType instance from this builder, with all
    /// methods and properties associated with `with[...]()` method calls.
    public func build() -> KnownType {
        return type
    }
}

private class DummyType: KnownType {
    var origin: String
    var typeName: String
    var kind: KnownTypeKind = .class
    var knownConstructors: [KnownConstructor] = []
    var knownMethods: [KnownMethod] = []
    var knownProperties: [KnownProperty] = []
    var knownFields: [KnownProperty] = []
    var knownProtocolConformances: [KnownProtocolConformance] = []
    var supertype: KnownSupertype?
    
    init(typeName: String, supertype: KnownSupertypeConvertible? = nil) {
        self.origin = "Synthesized type"
        self.typeName = typeName
        self.supertype = supertype?.asKnownSupertype
    }
}

private struct DummyConstructor: KnownConstructor {
    var parameters: [ParameterSignature]
}

private struct DummyMethod: KnownMethod {
    var ownerType: KnownType?
    var body: KnownMethodBody?
    var signature: FunctionSignature
    var optional: Bool
}

private struct DummyProperty: KnownProperty {
    var ownerType: KnownType?
    var name: String
    var storage: ValueStorage
    var attributes: [PropertyAttribute]
    var isStatic: Bool
    var optional: Bool
    var accessor: KnownPropertyAccessor
}

private struct DummyProtocolConformance: KnownProtocolConformance {
    var protocolName: String
}
