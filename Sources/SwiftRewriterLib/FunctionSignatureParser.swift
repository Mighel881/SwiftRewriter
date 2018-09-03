import SwiftAST
import MiniLexer
import Utils

/// Provides capabilities of parsing function signatures and argument arrays
/// from input strings.
public final class FunctionSignatureParser {
    private typealias Tokenizer = TokenizerLexer<FullToken<Token>>
    
    /// Parses a function signature from a given input string.
    ///
    /// Parsing begins at the function name and the input should not start with
    /// a `func` keyword.
    ///
    /// formal grammar of a function signature:
    ///
    /// ```
    /// function-signature
    ///     : 'mutating'? identifier parameter-signature return-type?
    ///     : 'mutating'? identifier parameter-signature 'throws' return-type?
    ///     : 'mutating'? identifier parameter-signature 'rethrows' return-type?
    ///     ;
    ///
    /// return-type
    ///     : '->' swift-type
    /// ```
    ///
    /// Support for parsing Swift types is borrowed from `SwiftTypeParser`.
    ///
    /// - Parameter string: The input string to parse, containing the function
    /// signature, starting at the function identifier name.
    /// - Returns: A function signature, with name, parameters and a return type.
    /// - Throws: Lexing errors, if string is malformed.
    public static func parseSignature(from string: String) throws -> FunctionSignature {
        let tokenizer = Tokenizer(input: string)
        
        // 'mutating'?
        var isMutating = false
        if tokenizer.consumeToken(ifTypeIs: .mutating) != nil {
            isMutating = true
        }
        
        let identifier = try tokenizer.advance(overTokenType: .identifier)
        let parameters = try parseParameterList(tokenizer: tokenizer)
        
        // `throws` | `rethrows`
        if tokenizer.tokenType(is: .throws) || tokenizer.tokenType(is: .rethrows) {
            tokenizer.skipToken()
        }
        
        // Return type (optional)
        var returnType: SwiftType = .void
        if tokenizer.tokenType(is: .functionArrow) {
            tokenizer.skipToken()
            
            returnType = try SwiftTypeParser.parse(from: tokenizer.lexer)
        }
        
        // Verify extraneous input
        if !tokenizer.lexer.isEof() {
            let index = tokenizer.lexer.inputIndex
            let rem = tokenizer.lexer.consumeRemaining()
            
            throw LexerError.syntaxError(index, "Extraneous input '\(rem)'")
        }
        
        return
            FunctionSignature(
                name: String(identifier.value),
                parameters: parameters,
                returnType: returnType,
                isStatic: false,
                isMutating: isMutating
            )
    }
    
    /// Parses an array of parameter signatures from a given input string.
    ///
    /// Input must contain the argument list enclosed within their respective
    /// parenthesis - e.g. the following string produces the following parameter
    /// signatures:
    ///
    /// ```
    /// (_ arg0: Int, arg1: String?)
    /// ```
    /// resulting parameters:
    /// ```
    /// [
    ///   ParameterSignature(label: "_", name: "arg0", type: .typeName("Int")),
    ///   ParameterSignature(name: "arg1", type: .optional(.typeName("String")))
    /// ]
    /// ```
    ///
    /// Formal grammar of parameters signature:
    ///
    /// ```
    /// parameter-signature
    ///     : '(' parameter-list? ')'
    ///     ;
    ///
    /// parameter-list
    ///     : parameter (',' parameter)*
    ///     ;
    ///
    /// parameter
    ///     : parameter-name ':' parameter-attribute-list? swift-type ('=' 'default')?
    ///     ;
    ///
    /// parameter-name
    ///     : identifier? identifier
    ///     ;
    ///
    /// parameter-attribute-list
    ///     : parameter-attribute parameter-attribute-list?
    ///     : 'inout'
    ///     ;
    ///
    /// parameter-attribute
    ///     : '@' identifier
    ///     ;
    ///
    /// identifier
    ///     : [a-zA-Z_] [a-zA-Z_0-9]+
    ///     ;
    /// ```
    ///
    /// Support for parsing Swift types is borrowed from `SwiftTypeParser`.
    ///
    /// - Parameter string: The input string to parse, containing the parameter
    /// list enclosed within parenthesis.
    /// - Returns: An array of parameter signatures from the input string.
    /// - Throws: Lexing errors, if string is malformed.
    public static func parseParameters(from string: String) throws -> [ParameterSignature] {
        let tokenizer = Tokenizer(input: string)
        let params = try parseParameterList(tokenizer: tokenizer)
        
        // Verify extraneous input
        if !tokenizer.lexer.isEof() {
            let index = tokenizer.lexer.inputIndex
            let rem = tokenizer.lexer.consumeRemaining()
            
            throw LexerError.syntaxError(index, "Extraneous input '\(rem)'")
        }
        
        return params
    }
    
    private static func parseParameterList(tokenizer: Tokenizer) throws -> [ParameterSignature] {
        var parameters: [ParameterSignature] = []
        
        try tokenizer.advance(overTokenType: .openParens)
        
        var afterComma = false
        
        // Parse parameters one-by-one until no more parameters can be read:
        while !tokenizer.isEof {
            if tokenizer.tokenType(is: .underscore) || tokenizer.tokenType(is: .identifier) {
                afterComma = false
                
                let param = try parseParameter(tokenizer: tokenizer)
                
                parameters.append(param)
                
                if tokenizer.consumeToken(ifTypeIs: .comma) != nil {
                    afterComma = true
                }
                
                continue
            } else if tokenizer.tokenType(is: .closeParens) {
                break
            }
            
            throw LexerError.unexpectedCharacter(tokenizer.lexer.inputIndex,
                                                 char: try tokenizer.lexer.peek(),
                                                 message: "Expected ')'")
        }
        
        if afterComma {
            throw tokenizer.lexer.syntaxError("Expected argument after ','")
        }
        
        try tokenizer.advance(overTokenType: .closeParens)
        
        return parameters
    }
    
    private static func parseTypeAnnotations(tokenizer: Tokenizer) throws -> [BlockTypeAttribute] {
        var attributes: [BlockTypeAttribute] = []
        
        while tokenizer.consumeToken(ifTypeIs: .at) != nil {
            let token = try tokenizer.advance(overTokenType: .identifier)
            
            switch token.value {
            case "autoclosure":
                attributes.append(.autoclosure)
            case "escaping":
                attributes.append(.escaping)
            case "convention":
                // Parse convention type
                try tokenizer.advance(overTokenType: .openParens)
                let ident = try tokenizer.advance(overTokenType: .identifier)
                try tokenizer.advance(overTokenType: .closeParens)
                
                switch ident.value {
                case "c":
                    attributes.append(.convention(.c))
                case "block":
                    attributes.append(.convention(.block))
                case "swift":
                    break // "swift" calling convention is the default and is the
                          // same as not having any calling convention attributes
                default:
                    break
                }
                
            default:
                break
            }
        }
        
        // Inout marks the end of an attributes list
        tokenizer.consumeToken(ifTypeIs: .inout)
        
        return attributes
    }
    
    private static func parseParameter(tokenizer: Tokenizer) throws -> ParameterSignature {
        let label: String?
        let name: String
        var attributes: [BlockTypeAttribute] = []
        if tokenizer.tokenType(is: .underscore) {
            try tokenizer.advance(overTokenType: .underscore)
            label = nil
        } else {
            label = String(try tokenizer.advance(overTokenType: .identifier).value)
        }
        
        var type: SwiftType
        
        if tokenizer.consumeToken(ifTypeIs: .colon) != nil {
            guard let label = label else {
                throw tokenizer.lexer.syntaxError("Expected argument name after '_'")
            }
            
            name = label
        } else {
            name = String(try tokenizer.advance(overTokenType: .identifier).value)
            
            try tokenizer.advance(overTokenType: .colon)
        }
        
        attributes.append(contentsOf: try parseTypeAnnotations(tokenizer: tokenizer))
        type = try SwiftTypeParser.parse(from: tokenizer.lexer)
        
        // Append attributes
        switch type {
        case let .block(returnType, parameters, attr):
            type = .block(returnType: returnType,
                          parameters: parameters,
                          attributes: attr.union(attributes))
            
        default:
            break
        }
        
        return ParameterSignature(label: label, name: String(name), type: type)
    }
    
    private enum Token: String, TokenProtocol {
        private static let identifierLexer = (.letter | "_") + (.letter | "_" | .digit)*
        
        case openParens = "("
        case closeParens = ")"
        case colon = ":"
        case comma = ","
        case at = "@"
        case underscore = "_"
        case `inout`
        case mutating
        case identifier
        case `throws`
        case `rethrows`
        case functionArrow
        case eof
        
        func advance(in lexer: Lexer) throws {
            let len = length(in: lexer)
            guard len > 0 else {
                throw LexerError.miscellaneous("Cannot advance")
            }
            
            try lexer.advanceLength(len)
        }
        
        func length(in lexer: Lexer) -> Int {
            switch self {
            case .openParens, .closeParens, .colon, .comma, .underscore, .at:
                return 1
            case .functionArrow:
                return 2
            case .inout:
                return 5
            case .throws:
                return 6
            case .mutating:
                return 8
            case .rethrows:
                return 8
            case .identifier:
                return Token.identifierLexer.maximumLength(in: lexer) ?? 0
            case .eof:
                return 0
            }
        }
        
        var tokenString: String {
            return rawValue
        }
        
        static func tokenType(at lexer: Lexer) -> FunctionSignatureParser.Token? {
            if lexer.isEof() {
                return .eof
            }
            
            if lexer.safeIsNextChar(equalTo: "_") {
                return lexer.withTemporaryIndex {
                    try? lexer.advance()
                    
                    if lexer.safeNextCharPasses(with: { !Lexer.isLetter($0) && !Lexer.isDigit($0) && $0 != "_" }) {
                        return .underscore
                    }
                    
                    return .identifier
                }
            }
            
            if lexer.checkNext(matches: "->") {
                return .functionArrow
            }
            
            guard let next = try? lexer.peek() else {
                return nil
            }
            
            if Lexer.isLetter(next) {
                guard let ident = try? lexer.withTemporaryIndex(changes: {
                    try identifierLexer.consume(from: lexer)
                }) else {
                    return nil
                }
                
                if ident == "inout" {
                    return .inout
                }
                if ident == "throws" {
                    return .throws
                }
                if ident == "rethrows" {
                    return .rethrows
                }
                if ident == "mutating" {
                    return .mutating
                }
                
                return .identifier
            }
            
            if let token = Token(rawValue: String(next)) {
                return token
            }
            
            return nil
        }
        
        static var eofToken: Token = .eof
    }
}
