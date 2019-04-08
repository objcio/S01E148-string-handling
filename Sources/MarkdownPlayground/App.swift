import CommonMark
import AppKit
import Ccmark

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // First instance becomes the shared document controller
        _ = MarkdownDocumentController()
    }
}

class MarkdownDocumentController: NSDocumentController {
    override var documentClassNames: [String] {
        return ["MarkdownDocument"]
    }
    
    override var defaultType: String? {
        return "MarkdownDocument"
    }
    
    override func documentClass(forType typeName: String) -> AnyClass? {
        return MarkdownDocument.self
    }
}

struct MarkdownError: Error { }

@objc(MarkdownDocument)
class MarkdownDocument: NSDocument {
    let contentViewController = ViewController()
    
    override class var readableTypes: [String] {
        return ["public.text"]
    }
    
    override class func isNativeType(_ name: String) -> Bool {
        return true
    }
    
    override func read(from data: Data, ofType typeName: String) throws {
        guard let str = String(data: data, encoding: .utf8) else {
            throw MarkdownError()
        }
        contentViewController.editor.string = str
    }
    
    override func data(ofType typeName: String) throws -> Data {
        contentViewController.editor.breakUndoCoalescing()
        return contentViewController.editor.string.data(using: .utf8)!
    }
    
    override func makeWindowControllers() {
        let window = NSWindow(contentViewController: contentViewController)
        window.setContentSize(NSSize(width: 800, height: 600))
        let wc = NSWindowController(window: window)
        wc.contentViewController = contentViewController
        addWindowController(wc)
        window.setFrameAutosaveName("windowFrame")
        window.makeKeyAndOrderFront(nil)
    }
}

extension String {
    var lineOffsets: [String.Index] {
        var result = [startIndex]
        for i in indices {
            let c = self[i]
            if c == "\n" || c == "\r" || c == "\r\n" {
                result.append(index(after: i))
            }
        }
        return result
    }
}

final class ViewController: NSViewController {
    let editor = NSTextView()
    let output = NSTextView()
    var observerToken: Any?
    var codeBlocks: [CodeBlock] = []
    var repl: REPL!
    
    override func loadView() {
        let editorSV = editor.configureAndWrapInScrollView(isEditable: true, inset: CGSize(width: 30, height: 10))
        let outputSV = output.configureAndWrapInScrollView(isEditable: false, inset: CGSize(width: 10, height: 10))
        outputSV.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        editor.allowsUndo = true
        
        self.view = splitView([editorSV, outputSV])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        repl = REPL(onStdOut: { [unowned output] text in
            output.textStorage?.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: NSColor.textColor
            ]))
        }, onStdErr: { [unowned output] text in
            output.textStorage?.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: NSColor.red
            ]))
        })
        observerToken = NotificationCenter.default.addObserver(forName: NSTextView.didChangeNotification, object: editor, queue: nil) { [unowned self] _ in
            self.parse()
        }
        self.parse()        
    }
    
    func parse() {
        guard let attributedString = editor.textStorage else { return }
        codeBlocks = attributedString.highlightMarkdown()
    }
    
    @objc func execute() {
        let pos = editor.selectedRange().location
        guard let block = codeBlocks.first(where: { $0.range.contains(pos) }) else { return }
        repl.execute(block.text)
    }
    
    deinit {
        if let t = observerToken { NotificationCenter.default.removeObserver(t) }
    }
}

struct REPLBuffer {
    private var buffer = Data()
    
    mutating func append(_ data: Data) -> String? {
        buffer.append(data)
        if let string = String(data: buffer, encoding: .utf8), string.last?.isNewline == true {
            buffer.removeAll()
            return string
        }
        return nil
    }
}

final class REPL {
    private let process = Process()
    private let stdIn = Pipe()
    private let stdErr = Pipe()
    private let stdOut = Pipe()
    
    private var stdOutToken: Any?
    private var stdErrToken: Any?

    init(onStdOut: @escaping (String) -> (), onStdErr: @escaping (String) -> ()) {
        process.launchPath = "/usr/bin/swift"
        process.standardInput = stdIn.fileHandleForReading
        process.standardOutput = stdOut.fileHandleForWriting
        process.standardError = stdErr.fileHandleForWriting
        
        var stdOutBuffer = REPLBuffer()
        stdOutToken = NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable, object: stdOut.fileHandleForReading, queue: nil, using: { [unowned self] note in
            if let string = stdOutBuffer.append(self.stdOut.fileHandleForReading.availableData) {
                onStdOut(string)
            }
            self.stdOut.fileHandleForReading.waitForDataInBackgroundAndNotify()
        })

        var stdErrBuffer = REPLBuffer()
        stdErrToken = NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable, object: stdErr.fileHandleForReading, queue: nil, using: { [unowned self] note in
            if let string = stdErrBuffer.append(self.stdErr.fileHandleForReading.availableData) {
                onStdErr(string)
            }
            self.stdErr.fileHandleForReading.waitForDataInBackgroundAndNotify()
        })

        process.launch()
        stdOut.fileHandleForReading.waitForDataInBackgroundAndNotify()
        stdErr.fileHandleForReading.waitForDataInBackgroundAndNotify()
    }
    
    func execute(_ code: String) {
        stdIn.fileHandleForWriting.write(code.data(using: .utf8)!)
    }
}

extension CommonMark.Node {
    /// When visiting a node, you can modify the state, and the modified state gets passed on to all children.
    func visitAll<State>(_ initial: State, _ callback: (Node, inout State) -> ()) {
        for c in children {
            var copy = initial
            callback(c, &copy)
            c.visitAll(copy, callback)
        }
    }
}

public func runApplication() {
    let delegate = AppDelegate()
    let app = application(delegate: delegate)
    app.run()
}
