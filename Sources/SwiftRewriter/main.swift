import SwiftRewriterLib
import Utility
import Foundation
import ExpressionPasses
import Console

let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())

let parser =
    ArgumentParser(usage: "<files>",
                   overview: "Automates part of convering Objective-C source code into Swift")

let filesArg: PositionalArgument<[String]> =
    parser.add(positional: "<files>", kind: [String].self, usage: "Objective-C file(s) to convert")

let colorArg: OptionArgument<Bool> =
    parser.add(option: "-colorize", kind: Bool.self, usage: "Pass this parameter as true to enable terminal colorization during output.")

do {
    if let result = try? parser.parse(arguments) {
        if let files = result.get(filesArg) {
            let input = FileInputProvider(files: files)
            let output = StdoutWriterOutput(colorize: result.get(colorArg) ?? false)
            
            let converter = SwiftRewriter(input: input, output: output)
            
            converter.syntaxNodeRewriters.append(AllocInitExpressionPass())
            converter.syntaxNodeRewriters.append(CoreGraphicsExpressionPass())
            converter.syntaxNodeRewriters.append(FoundationExpressionPass())
            converter.syntaxNodeRewriters.append(UIKitExpressionPass())
            
            try converter.rewrite()
            
            // Print diagnostics
            for diag in converter.diagnostics.diagnostics {
                switch diag {
                case .note:
                    print("// Note: \(diag)")
                case .warning:
                    print("// Warning: \(diag)")
                case .error:
                    print("// Error: \(diag)")
                }
            }
        } else {
            throw Utility.ArgumentParserError.expectedValue(option: "<files>")
        }
    } else {
        let output = StdoutWriterOutput(colorize: true)
        let service = SwiftRewriterServiceImpl(output: output)
        let console = Console()
        let menu = Menu(rewriterService: service, console: console)
        
        menu.main()
    }
} catch {
    print("Error: \(error)")
}
