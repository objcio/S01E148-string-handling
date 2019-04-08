import XCTest
@testable import MarkdownPlayground

final class MarkdownPlaygroundTests: XCTestCase {
    func testLineBreaks() throws {
        let str = "1\n2\r3\r\n4"
        XCTAssertEqual(str.lineOffsets.count, 4)
    }
    
    func testEmoji() throws {
        let str = "👨‍👩‍👧‍👦"
        let att = NSMutableAttributedString(string: str)
        _ = att.highlightMarkdown()
    }
    
    func testOutOfBounds() throws {
        let str = "a`"
        let att = NSMutableAttributedString(string: str)
        _ = att.highlightMarkdown()
    }
}
