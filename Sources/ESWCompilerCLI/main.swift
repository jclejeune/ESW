import Foundation
import ESWCompilerLib

func writeToStderr(_ message: String) {
#if os(Linux)
    FileHandle.standardError.write(Data(message.utf8))
#else
    fputs(message, stderr)
#endif
}

@main
struct ESWCompilerCLI {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            printUsageAndExit()
        }
        let inputPath = args[1]
        var outputPath: String?
        var emitSourceLocations = false
        var i = 2
        while i < args.count {
            switch args[i] {
            case "--output":
                guard i + 1 < args.count else {
                    writeToStderr("error: --output requires a path argument\n")
                    exit(1)
                }
                outputPath = args[i + 1]
                i += 2
            case "--source-location":
                emitSourceLocations = true
                i += 1
            default:
                writeToStderr("error: unknown argument '\(args[i])'\n")
                printUsageAndExit()
            }
        }
        do {
            let source = try String(contentsOfFile: inputPath, encoding: .utf8)
            let filename = URL(fileURLWithPath: inputPath).lastPathComponent
            let result = try ESWCompilerLib.compile(
                source: source,
                filename: filename,
                sourceFile: inputPath,
                emitSourceLocations: emitSourceLocations
            )
            if let outputPath {
                try result.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } else {
                print(result, terminator: "")
            }
        } catch let error as ESWTokenizerError {
            switch error {
            case .unterminatedTag(let file, let line, let column):
                writeToStderr("\(file):\(line):\(column): error: unterminated ESW tag\n")
                exit(1)
            case .malformedComponentTag(let file, let line, let column):
                writeToStderr("\(file):\(line):\(column): error: malformed component tag\n")
                exit(1)
            }
        } catch let error as ESWAssignsError {
            switch error {
            case .assignsNotFirst(let file, let line):
                writeToStderr("\(file):\(line): error: assigns block must be the first tag in the file\n")
                exit(1)
            case .invalidDeclaration(let file, let line, let text):
                writeToStderr("\(file):\(line): error: invalid declaration: \(text)\n")
                exit(1)
            }
        } catch let error as ESWComponentError {
            switch error {
            case .unterminatedComponent(let file, let line, let column):
                writeToStderr("\(file):\(line):\(column): error: unterminated component tag\n")
                exit(1)
            case .unmatchedComponentClose(let file, let line, let column):
                writeToStderr("\(file):\(line):\(column): error: unmatched component close tag\n")
                exit(1)
            case .unterminatedSlot(let file, let line, let column):
                writeToStderr("\(file):\(line):\(column): error: unterminated slot tag\n")
                exit(1)
            case .unmatchedSlotClose(let file, let line, let column):
                writeToStderr("\(file):\(line):\(column): error: unmatched slot close tag\n")
                exit(1)
            case .duplicateSlot(let name, let file, let line):
                writeToStderr("\(file):\(line): error: duplicate slot '\(name)'\n")
                exit(1)
            case .slotOutsideComponent(let file, let line, let column):
                writeToStderr("\(file):\(line):\(column): error: slot tag outside component\n")
                exit(1)
            }
        } catch {
            writeToStderr("error: \(error)\n")
            exit(1)
        }
    }

    static func printUsageAndExit() -> Never {
        writeToStderr("Usage: ESWCompilerCLI <input.esw> [--output <output.swift>] [--source-location]\n")
        exit(1)
    }
}