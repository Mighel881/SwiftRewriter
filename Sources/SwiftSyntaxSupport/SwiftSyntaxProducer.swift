import SwiftSyntax
import Intentions
import SwiftAST
import KnownType

public class SwiftSyntaxProducer {
    var indentationMode: TriviaPiece = .spaces(4)
    var indentationLevel: Int = 0
    
    var extraLeading: Trivia?
    
    public init() {
        
    }
    
    func indentation() -> Trivia {
        return Trivia(pieces: Array(repeating: indentationMode, count: indentationLevel))
    }
    
    func indent() {
        indentationLevel += 1
    }
    func deindent() {
        indentationLevel -= 1
    }
    
    func addExtraLeading(_ trivia: Trivia) {
        if let lead = extraLeading {
            extraLeading = lead + trivia
        } else {
            extraLeading = trivia
        }
    }
}

// MARK: - Identation
extension SwiftSyntaxProducer {
    public func generateFile(_ file: FileGenerationIntention) -> SourceFileSyntax {
        return SourceFileSyntax { builder in
            
            iterateWithBlankLineAfter(file.globalFunctionIntentions) { function in
                let syntax = generateFunction(function)
                
                let codeBlock = CodeBlockItemSyntax { $0.useItem(syntax) }
                
                builder.addCodeBlockItem(codeBlock)
            }
            
            iterateWithBlankLineAfter(file.protocolIntentions) { _protocol in
                let syntax = generateProtocol(_protocol)
                
                let codeBlock = CodeBlockItemSyntax { $0.useItem(syntax) }
                
                builder.addCodeBlockItem(codeBlock)
            }
            
            iterateWithBlankLineAfter(file.structIntentions) { _struct in
                let syntax = generateStruct(_struct)
                
                let codeBlock = CodeBlockItemSyntax { $0.useItem(syntax) }
                
                builder.addCodeBlockItem(codeBlock)
            }
            
            iterateWithBlankLineAfter(file.classIntentions) { _class in
                let syntax = generateClass(_class)
                
                let codeBlock = CodeBlockItemSyntax { $0.useItem(syntax) }
                
                builder.addCodeBlockItem(codeBlock)
            }
        }
    }
}

// MARK: - Class Generation
extension SwiftSyntaxProducer {
    func generateClass(_ type: ClassGenerationIntention) -> ClassDeclSyntax {
        return ClassDeclSyntax { builder in
            addExtraLeading(indentation())
            
            builder.useClassKeyword(
                makeStartToken(SyntaxFactory.makeClassKeyword).addingTrailingSpace())
            
            let identifier = makeIdentifier(type.typeName)
            
            if let inheritanceClause = generateInheritanceClause(type) {
                builder.useIdentifier(identifier)
                
                builder.useInheritanceClause(inheritanceClause)
            } else {
                builder.useIdentifier(identifier.withTrailingSpace())
            }
            
            indent()
            
            let members = generateMembers(type)
            
            deindent()
            
            builder.useMembers(members)
        }
    }
    
    public func generateInheritanceClause(_ type: KnownType) -> TypeInheritanceClauseSyntax? {
        var inheritances: [String] = []
        if let supertype = type.supertype?.asTypeName {
            inheritances.append(supertype)
        }
        inheritances.append(contentsOf:
            type.knownProtocolConformances.map { $0.protocolName }
        )
        
        if inheritances.isEmpty {
            return nil
        }
        
        return TypeInheritanceClauseSyntax { builder in
            builder.useColon(SyntaxFactory.makeColonToken().withTrailingSpace())
            
            for (i, inheritance) in inheritances.enumerated() {
                let type = InheritedTypeSyntax { builder in
                    var identifier = makeIdentifier(inheritance)
                    
                    if i != inheritances.count - 1 {
                        builder.useTrailingComma(SyntaxFactory.makeCommaToken().withTrailingSpace())
                    } else {
                        identifier = identifier.withTrailingSpace()
                    }
                    
                    builder.useTypeName(SyntaxFactory
                        .makeSimpleTypeIdentifier(
                            name: identifier,
                            genericArgumentClause: nil
                        )
                    )
                }
                
                builder.addInheritedType(type)
            }
        }
    }
}

// MARK: - Struct generation
extension SwiftSyntaxProducer {
    func generateStruct(_ type: StructGenerationIntention) -> StructDeclSyntax {
        return StructDeclSyntax { builder in
            addExtraLeading(indentation())
            
            builder.useStructKeyword(
                makeStartToken(SyntaxFactory.makeStructKeyword)
                    .addingTrailingSpace())
            
            let identifier = makeIdentifier(type.typeName)
            
            if let inheritanceClause = generateInheritanceClause(type) {
                builder.useIdentifier(identifier)
                
                builder.useInheritanceClause(inheritanceClause)
            } else {
                builder.useIdentifier(identifier.withTrailingSpace())
            }
            
            indent()
            
            let members = generateMembers(type)
            
            deindent()
            
            builder.useMembers(members)
        }
    }
}

// MARK: - Protocol generation
extension SwiftSyntaxProducer {
    func generateProtocol(_ type: ProtocolGenerationIntention) -> ProtocolDeclSyntax {
        return ProtocolDeclSyntax.init { builder in
            addExtraLeading(indentation())
            
            builder.useProtocolKeyword(
                makeStartToken(SyntaxFactory.makeProtocolKeyword).addingTrailingSpace())
            
            let identifier = makeIdentifier(type.typeName)
            
            if let inheritanceClause = generateInheritanceClause(type) {
                builder.useIdentifier(identifier)
                
                builder.useInheritanceClause(inheritanceClause)
            } else {
                builder.useIdentifier(identifier.withTrailingSpace())
            }
            
            indent()
            defer {
                deindent()
            }
            
            builder.useMembers(generateMembers(type))
        }
    }
}

// MARK: - Type member generation
extension SwiftSyntaxProducer {
    func generateMembers(_ intention: TypeGenerationIntention) -> MemberDeclBlockSyntax {
        return MemberDeclBlockSyntax { builder in
            builder.useLeftBrace(SyntaxFactory.makeLeftBraceToken())
            builder.useRightBrace(SyntaxFactory.makeRightBraceToken().onNewline())
            
            addExtraLeading(.newlines(1))
            
            // TODO: Probably shouldn't detect ivar containers like this.
            if let ivarHolder = intention as? InstanceVariableContainerIntention {
                iterateWithBlankLineAfter(ivarHolder.instanceVariables) { ivar in
                    addExtraLeading(indentation())
                    
                    builder.addDecl(generateInstanceVariable(ivar))
                }
            }
            
            iterateWithBlankLineAfter(intention.properties) { prop in
                addExtraLeading(indentation())
                
                builder.addDecl(generateProperty(prop))
            }
            
            iterateWithBlankLineAfter(intention.constructors) { _init in
                addExtraLeading(indentation())
                
                builder.addDecl(generateInitializer(_init))
            }
        }
    }
}

// MARK: - Variable/property syntax
extension SwiftSyntaxProducer {
    
    func generateInstanceVariable(_ intention: InstanceVariableGenerationIntention) -> DeclSyntax {
        return generateVariableDecl(intention)
    }
    
    func generateProperty(_ intention: PropertyGenerationIntention) -> DeclSyntax {
        return generateVariableDecl(intention)
    }
    
    func generateVariableDecl(_ intention: ValueStorageIntention & MemberGenerationIntention) -> DeclSyntax {
        return generateVariableDecl(name: intention.name,
                                    storage: intention.storage,
                                    attributes: intention.knownAttributes)
    }
    
    func generateVariableDecl(name: String,
                              storage: ValueStorage,
                              attributes: [KnownAttribute],
                              initialization: Expression? = nil) -> VariableDeclSyntax {
        
        return VariableDeclSyntax { builder in
            for attribute in attributes {
                builder.addAttribute(generateAttributeSyntax(attribute))
            }
            
            let letOrVar =
                storage.isConstant
                    ? SyntaxFactory.makeLetKeyword
                    : SyntaxFactory.makeVarKeyword
            
            builder.useLetOrVarKeyword(makeStartToken(letOrVar).addingTrailingSpace())
            
            builder.addPatternBinding(PatternBindingSyntax { builder in
                builder.usePattern(IdentifierPatternSyntax { builder in
                    builder.useIdentifier(makeIdentifier(name))
                })
                
                builder.useTypeAnnotation(TypeAnnotationSyntax { builder in
                    builder.useColon(SyntaxFactory.makeColonToken().withTrailingSpace())
                    builder.useType(makeTypeSyntax(storage.type))
                })
                
                if let initialization = initialization {
                    builder.useInitializer(InitializerClauseSyntax { builder in
                        builder.useEqual(SyntaxFactory.makeEqualToken().withLeadingSpace().withTrailingSpace())
                        builder.useValue(generateExpression(initialization))
                    })
                }
            })
        }
    }
}

// MARK: - Function syntax
extension SwiftSyntaxProducer {
    
    func generateInitializer(_ initializer: InitGenerationIntention) -> DeclSyntax {
        return InitializerDeclSyntax { builder in
            builder.useInitKeyword(makeStartToken(SyntaxFactory.makeInitKeyword))
            
            if initializer.isFailable {
                builder.useOptionalMark(SyntaxFactory.makeInfixQuestionMarkToken())
            }
            
            builder.useParameters(generateParameterList(initializer.parameters))
            
            if let body = initializer.functionBody {
                builder.useBody(generateFunctionBody(body))
            }
        }
    }
    
    func generateFunction(_ function: SignatureFunctionIntention) -> FunctionDeclSyntax {
        return FunctionDeclSyntax { builder in
            builder.useFuncKeyword(makeStartToken(SyntaxFactory.makeFuncKeyword).addingTrailingSpace())
            builder.useSignature(generateSignature(function.signature))
            builder.useIdentifier(makeIdentifier(function.signature.name))
            
            if function.signature.isMutating {
                builder.addModifier(SyntaxFactory
                    .makeDeclModifier(
                        name: makeIdentifier("mutating").withTrailingSpace(),
                        detail: nil
                    )
                )
            }
            if function.signature.isStatic {
                builder.addModifier(SyntaxFactory
                    .makeDeclModifier(
                        name: SyntaxFactory.makeStaticKeyword().withTrailingSpace(),
                        detail: nil
                    )
                )
            }
            
            if let body = function.functionBody {
                builder.useBody(generateFunctionBody(body))
            }
        }
    }
    
    func generateSignature(_ signature: FunctionSignature) -> FunctionSignatureSyntax {
        return FunctionSignatureSyntax { builder in
            builder.useInput(generateParameterList(signature.parameters))
            
            if signature.returnType != .void {
                builder.useOutput(generateReturn(signature.returnType))
            }
        }
    }
    
    func generateReturn(_ ret: SwiftType) -> ReturnClauseSyntax {
        return ReturnClauseSyntax { builder in
            builder.useArrow(SyntaxFactory.makeArrowToken().addingTrailingSpace())
            builder.useReturnType(makeTypeSyntax(ret))
        }
    }
    
    func generateParameterList(_ parameters: [ParameterSignature]) -> ParameterClauseSyntax {
        return ParameterClauseSyntax { builder in
            builder.useLeftParen(SyntaxFactory.makeLeftParenToken())
            builder.useRightParen(SyntaxFactory.makeRightParenToken())
            
            iterateWithComma(parameters) { (item, hasComma) in
                builder.addFunctionParameter(
                    generateParameter(item, withTrailingComma: hasComma)
                )
            }
        }
    }
    
    func generateParameter(_ parameter: ParameterSignature,
                           withTrailingComma: Bool) -> FunctionParameterSyntax {
        
        return FunctionParameterSyntax { builder in
            if parameter.label == parameter.name {
                builder.useFirstName(prepareStartToken(makeIdentifier(parameter.name)))
            } else if parameter.label == nil {
                builder.useFirstName(prepareStartToken(SyntaxFactory.makeWildcardKeyword()))
                builder.useSecondName(makeIdentifier(parameter.name))
            }
            
            builder.useColon(SyntaxFactory.makeColonToken().withTrailingSpace())
            
            builder.useType(makeTypeSyntax(parameter.type))
            
            if withTrailingComma {
                builder.useTrailingComma(SyntaxFactory.makeCommaToken().withTrailingSpace())
            }
        }
    }
    
    func generateFunctionBody(_ body: FunctionBodyIntention) -> CodeBlockSyntax {
        return generateCompound(body.body)
    }
    
    func generateAttributeListSyntax<S: Sequence>(_ attributes: S) -> AttributeListSyntax where S.Element == KnownAttribute {
        return SyntaxFactory.makeAttributeList(attributes.map(generateAttributeSyntax))
    }
    
    func generateAttributeSyntax(_ attribute: KnownAttribute) -> AttributeSyntax {
        return SyntaxFactory
            .makeAttribute(
                atSignToken: prepareStartToken(SyntaxFactory.makeAtSignToken()),
                attributeName: makeIdentifier(attribute.name),
                balancedTokens: SyntaxFactory.makeTokenList(attribute.parameters.map { [SyntaxFactory.makeIdentifier($0)] } ?? [])
        )
    }
}

// MARK: - Utilities
extension SwiftSyntaxProducer {
    
    func makeStartToken(_ builder: (_ leading: Trivia, _ trailing: Trivia) -> TokenSyntax) -> TokenSyntax {
        return prepareStartToken(builder([], []))
    }
    
    func prepareStartToken(_ token: TokenSyntax) -> TokenSyntax {
        return token.withExtraLeading(consuming: &extraLeading)
    }
    
    func iterateWithBlankLineAfter<T>(_ elements: [T],
                                      postSeparator: Trivia = .newlines(2),
                                      do block: (T) -> Void) {
        
        for item in elements {
            block(item)
        }
        
        if !elements.isEmpty {
            addExtraLeading(postSeparator)
        }
    }
    
    func iterateWithComma<T>(_ elements: [T],
                             postSeparator: Trivia = .newlines(1),
                             do block: (T, Bool) -> Void) {
        
        for (i, item) in elements.enumerated() {
            block(item, i < elements.count - 1)
        }
    }
}

// MARK: - General/commons
func makeIdentifier(_ identifier: String) -> TokenSyntax {
    return SyntaxFactory.makeIdentifier(identifier)
}

func makeTypeSyntax(_ type: SwiftType) -> TypeSyntax {
    switch type {
    case .nominal(let nominal):
        return makeNominalTypeSyntax(nominal)
        
    case .implicitUnwrappedOptional(let type),
         .nullabilityUnspecified(let type):
        return SyntaxFactory
            .makeImplicitlyUnwrappedOptionalType(
                wrappedType: makeTypeSyntax(type),
                exclamationMark: SyntaxFactory.makeExclamationMarkToken()
            )
        
    case .optional(let type):
        return SyntaxFactory
            .makeOptionalType(
                wrappedType: makeTypeSyntax(type),
                questionMark: SyntaxFactory.makePostfixQuestionMarkToken()
            )
        
    case .metatype(let type):
        return SyntaxFactory
            .makeMetatypeType(
                baseType: makeTypeSyntax(type),
                period: SyntaxFactory.makePeriodToken(),
                typeOrProtocol: SyntaxFactory.makeTypeToken()
            )
        
    case .nested(let nested):
        
        return makeNestedTypeSyntax(nested)
        
    case let .block(returnType, parameters, attributes):
        let attributes = attributes.sorted(by: { $0.description < $1.description })
        
        return AttributedTypeSyntax { builder in
            let functionType = FunctionTypeSyntax { builder in
                builder.useArrow(SyntaxFactory.makeArrowToken())
                builder.useLeftParen(SyntaxFactory.makeLeftParenToken())
                builder.useRightParen(SyntaxFactory.makeRightParenToken())
                builder.useReturnType(makeTypeSyntax(returnType))
                
                // Parameters
                makeTupleTypeSyntax(parameters)
                    .elements
                    .forEach { builder.addTupleTypeElement($0) }
            }
            
            builder.useBaseType(functionType)
            
            for attribute in attributes {
                switch attribute {
                case .autoclosure:
                    builder.addAttribute(SyntaxFactory
                        .makeAttribute(
                            atSignToken: SyntaxFactory.makeAtSignToken(),
                            attributeName: makeIdentifier("autoclosure"),
                            balancedTokens: SyntaxFactory.makeBlankTokenList()
                        )
                    )
                    
                case .escaping:
                    builder.addAttribute(SyntaxFactory
                        .makeAttribute(
                            atSignToken: SyntaxFactory.makeAtSignToken(),
                            attributeName: makeIdentifier("escaping"),
                            balancedTokens: SyntaxFactory.makeBlankTokenList()
                        )
                    )
                    
                case .convention(let convention):
                    builder.addAttribute(SyntaxFactory
                        .makeAttribute(
                            atSignToken: SyntaxFactory.makeAtSignToken(),
                            attributeName: makeIdentifier("convention"),
                            balancedTokens: SyntaxFactory.makeTokenList([makeIdentifier(convention.rawValue)])
                        )
                    )
                }
            }
        }
        
    case .tuple(let tuple):
        switch tuple {
        case .types(let types):
            return makeTupleTypeSyntax(types)
            
        case .empty:
            return SyntaxFactory.makeTypeIdentifier("Void")
        }
        
    case .protocolComposition(let composition):
        return CompositionTypeSyntax { builder in
            let count = composition.count
            
            for (i, type) in composition.enumerated() {
                builder.addCompositionTypeElement(CompositionTypeElementSyntax { builder in
                    
                    switch type {
                    case .nested(let nested):
                        builder.useType(makeNestedTypeSyntax(nested))
                        
                    case .nominal(let nominal):
                        builder.useType(makeNominalTypeSyntax(nominal))
                    }
                    
                    if i != count - 1 {
                        builder.useAmpersand(SyntaxFactory.makePrefixAmpersandToken())
                    }
                })
            }
        }
    }
}

func makeTupleTypeSyntax<C: Collection>(_ types: C) -> TupleTypeSyntax where C.Element == SwiftType {
    return TupleTypeSyntax { builder in
        for (i, type) in types.enumerated() {
            let syntax = TupleTypeElementSyntax { builder in
                builder.useType(makeTypeSyntax(type))
                
                if i == types.count - 1 {
                    builder.useTrailingComma(SyntaxFactory.makeCommaToken())
                }
            }
            
            builder.addTupleTypeElement(syntax)
        }
    }
}

func makeNestedTypeSyntax(_ nestedType: NestedSwiftType) -> MemberTypeIdentifierSyntax {
    
    let produce: (MemberTypeIdentifierSyntax, NominalSwiftType) -> MemberTypeIdentifierSyntax = { (previous, type) in
        let typeSyntax = makeNominalTypeSyntax(type)
        
        return SyntaxFactory
            .makeMemberTypeIdentifier(
                baseType: previous,
                period: SyntaxFactory.makePeriodToken(),
                name: typeSyntax.name,
                genericArgumentClause: typeSyntax.genericArgumentClause
        )
    }
    
    let typeSyntax = makeNominalTypeSyntax(nestedType.second)
    
    let initial = SyntaxFactory
        .makeMemberTypeIdentifier(
            baseType: makeNominalTypeSyntax(nestedType.first),
            period: SyntaxFactory.makePeriodToken(),
            name: typeSyntax.name,
            genericArgumentClause: typeSyntax.genericArgumentClause
        )
    
    return nestedType.reduce(initial, produce)
}

func makeNominalTypeSyntax(_ nominal: NominalSwiftType) -> SimpleTypeIdentifierSyntax {
    switch nominal {
    case .typeName(let name):
        return SyntaxFactory
            .makeSimpleTypeIdentifier(
                name: SyntaxFactory.makeIdentifier(name),
                genericArgumentClause: nil
            )
        
    case let .generic(name, parameters):
        let types = parameters.map(makeTypeSyntax)
        
        let genericArgumentList =
            SyntaxFactory
                .makeGenericArgumentList(types.enumerated().map {
                    let (index, type) = $0
                    
                    return SyntaxFactory
                        .makeGenericArgument(
                            argumentType: type,
                            trailingComma: index == types.count - 1 ? nil : SyntaxFactory.makeCommaToken()
                        )
                })
        
        let genericArgumentClause = SyntaxFactory
            .makeGenericArgumentClause(
                leftAngleBracket: SyntaxFactory.makeLeftAngleToken(),
                arguments: genericArgumentList,
                rightAngleBracket: SyntaxFactory.makeRightAngleToken()
            )
        
        return SyntaxFactory.makeSimpleTypeIdentifier(
            name: SyntaxFactory.makeIdentifier(name),
            genericArgumentClause: genericArgumentClause
        )
    }
}

extension TokenSyntax {
    func withExtraLeading(consuming trivia: inout Trivia?) -> TokenSyntax {
        if let t = trivia {
            trivia = nil
            return withLeadingTrivia(t + leadingTrivia)
        }
        
        return self
    }
    func withLeadingSpace(count: Int = 1) -> TokenSyntax {
        return withLeadingTrivia(.spaces(count))
    }
    
    func withTrailingSpace(count: Int = 1) -> TokenSyntax {
        return withTrailingTrivia(.spaces(count))
    }
    
    func addingLeadingSpace(count: Int = 1) -> TokenSyntax {
        return addingLeadingTrivia(.spaces(count))
    }
    
    func addingTrailingSpace(count: Int = 1) -> TokenSyntax {
        return addingTrailingTrivia(.spaces(count))
    }
    
    func addingLeadingTrivia(_ trivia: Trivia) -> TokenSyntax {
        return withLeadingTrivia(leadingTrivia + trivia)
    }
    
    func addingTrailingTrivia(_ trivia: Trivia) -> TokenSyntax {
        return withTrailingTrivia(trailingTrivia + trivia)
    }
    
    func onNewline() -> TokenSyntax {
        return withLeadingTrivia(.newlines(1))
    }
}
