import Foundation
import SwiftXMLCoder
import XCTest

// MARK: - Processing Instruction fidelity (inside elements)

final class XMLStructuralFidelityTests: XCTestCase {

    // MARK: - XMLTreeNode.processingInstruction (inside elements)

    func test_parser_processingInstruction_insideElement_isCaptured() throws {
        let xml = """
        <?xml version="1.0"?><root><?xml-stylesheet type="text/css" href="style.css"?><child/></root>
        """
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertEqual(doc.root.children.count, 2)
        guard case .processingInstruction(let target, let data) = doc.root.children[0] else {
            return XCTFail("Expected first child to be processing instruction.")
        }
        XCTAssertEqual(target, "xml-stylesheet")
        XCTAssertEqual(data, "type=\"text/css\" href=\"style.css\"")
    }

    func test_parser_processingInstruction_noData_isCaptured() throws {
        let xml = "<root><?pi-no-data?><child/></root>"
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertEqual(doc.root.children.count, 2)
        guard case .processingInstruction(let target, let data) = doc.root.children[0] else {
            return XCTFail("Expected first child to be processing instruction.")
        }
        XCTAssertEqual(target, "pi-no-data")
        XCTAssertNil(data)
    }

    func test_writer_processingInstruction_insideElement_roundtrips() throws {
        let xml = """
        <?xml version="1.0"?><root><?xml-stylesheet type="text/css" href="style.css"?></root>
        """
        let parser = XMLTreeParser()
        let writer = XMLTreeWriter()
        let parsed = try parser.parse(data: Data(xml.utf8))
        let roundtripped = try parser.parse(data: writer.writeData(parsed))
        guard case .processingInstruction(let target, let data) = roundtripped.root.children[0] else {
            return XCTFail("Expected first child to be processing instruction after roundtrip.")
        }
        XCTAssertEqual(target, "xml-stylesheet")
        XCTAssertEqual(data, "type=\"text/css\" href=\"style.css\"")
    }

    func test_parser_mixedChildren_preservesOrder() throws {
        let xml = """
        <root><?pi-first data="1"?><!--comment--><child/><?pi-last data="2"?></root>
        """
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertEqual(doc.root.children.count, 4)
        guard case .processingInstruction("pi-first", _) = doc.root.children[0] else {
            return XCTFail("Expected pi-first at index 0.")
        }
        guard case .comment("comment") = doc.root.children[1] else {
            return XCTFail("Expected comment at index 1.")
        }
        guard case .element(let child) = doc.root.children[2] else {
            return XCTFail("Expected element at index 2.")
        }
        XCTAssertEqual(child.name.localName, "child")
        guard case .processingInstruction("pi-last", _) = doc.root.children[3] else {
            return XCTFail("Expected pi-last at index 3.")
        }
    }

    // MARK: - Document-level prologue / epilogue

    func test_parser_prologuePI_isCaptured() throws {
        let xml = """
        <?xml version="1.0"?><?xml-stylesheet type="text/css" href="style.css"?><root/>
        """
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertEqual(doc.prologueNodes.count, 1)
        guard case .processingInstruction(let target, let data) = doc.prologueNodes[0] else {
            return XCTFail("Expected prologue PI.")
        }
        XCTAssertEqual(target, "xml-stylesheet")
        XCTAssertEqual(data, "type=\"text/css\" href=\"style.css\"")
        XCTAssertTrue(doc.epilogueNodes.isEmpty)
    }

    func test_parser_prologueComment_isCaptured() throws {
        let xml = "<?xml version=\"1.0\"?><!--doc comment--><root/>"
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertEqual(doc.prologueNodes.count, 1)
        guard case .comment(let value) = doc.prologueNodes[0] else {
            return XCTFail("Expected prologue comment.")
        }
        XCTAssertEqual(value, "doc comment")
    }

    func test_parser_epiloguePI_isCaptured() throws {
        let xml = "<?xml version=\"1.0\"?><root/><?app-specific data=\"val\"?>"
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertTrue(doc.prologueNodes.isEmpty)
        XCTAssertEqual(doc.epilogueNodes.count, 1)
        guard case .processingInstruction(let target, let data) = doc.epilogueNodes[0] else {
            return XCTFail("Expected epilogue PI.")
        }
        XCTAssertEqual(target, "app-specific")
        XCTAssertEqual(data, "data=\"val\"")
    }

    func test_parser_multipleDocumentLevelNodes_preservesOrder() throws {
        let xml = """
        <?xml version="1.0"?><!--pre1--><?pi-pre data="x"?><root/><!--post1--><?pi-post?>
        """
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertEqual(doc.prologueNodes.count, 2)
        guard case .comment("pre1") = doc.prologueNodes[0] else {
            return XCTFail("Expected prologue comment at index 0.")
        }
        guard case .processingInstruction("pi-pre", _) = doc.prologueNodes[1] else {
            return XCTFail("Expected prologue PI at index 1.")
        }
        XCTAssertEqual(doc.epilogueNodes.count, 2)
        guard case .comment("post1") = doc.epilogueNodes[0] else {
            return XCTFail("Expected epilogue comment at index 0.")
        }
        guard case .processingInstruction("pi-post", _) = doc.epilogueNodes[1] else {
            return XCTFail("Expected epilogue PI at index 1.")
        }
    }

    func test_writer_prologueAndEpilogueNodes_roundtrip() throws {
        let xml = """
        <?xml version="1.0"?><!--pre--><?pi-pre x="1"?><root/><?pi-post?><!--post-->
        """
        let parser = XMLTreeParser()
        let writer = XMLTreeWriter()
        let parsed = try parser.parse(data: Data(xml.utf8))
        let written = try writer.writeData(parsed)
        let roundtripped = try parser.parse(data: written)

        XCTAssertEqual(roundtripped.prologueNodes.count, 2)
        guard case .comment("pre") = roundtripped.prologueNodes[0] else {
            return XCTFail("Expected prologue comment 'pre'.")
        }
        guard case .processingInstruction("pi-pre", let preData) = roundtripped.prologueNodes[1] else {
            return XCTFail("Expected prologue PI 'pi-pre'.")
        }
        XCTAssertEqual(preData, "x=\"1\"")

        XCTAssertEqual(roundtripped.epilogueNodes.count, 2)
        guard case .processingInstruction("pi-post", _) = roundtripped.epilogueNodes[0] else {
            return XCTFail("Expected epilogue PI 'pi-post'.")
        }
        guard case .comment("post") = roundtripped.epilogueNodes[1] else {
            return XCTFail("Expected epilogue comment 'post'.")
        }
    }

    func test_parser_noDocumentLevelNodes_emptyArrays() throws {
        let xml = "<root><child/></root>"
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertTrue(doc.prologueNodes.isEmpty)
        XCTAssertTrue(doc.epilogueNodes.isEmpty)
    }

    // MARK: - DOCTYPE / doctype metadata

    func test_parser_systemDoctype_isCaptured() throws {
        let xml = """
        <?xml version="1.0"?><!DOCTYPE root SYSTEM "root.dtd"><root/>
        """
        // DTD loading is off by default; we parse the declaration itself without loading the DTD.
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertNotNil(doc.metadata.doctype)
        XCTAssertEqual(doc.metadata.doctype?.name, "root")
        XCTAssertEqual(doc.metadata.doctype?.systemID, "root.dtd")
        XCTAssertNil(doc.metadata.doctype?.publicID)
    }

    func test_parser_publicDoctype_isCaptured() throws {
        let xml = """
        <?xml version="1.0"?><!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"><html/>
        """
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertNotNil(doc.metadata.doctype)
        XCTAssertEqual(doc.metadata.doctype?.name, "html")
        XCTAssertEqual(doc.metadata.doctype?.publicID, "-//W3C//DTD XHTML 1.0 Strict//EN")
        XCTAssertEqual(doc.metadata.doctype?.systemID, "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd")
    }

    func test_parser_noDoctype_isNil() throws {
        let xml = "<root/>"
        let doc = try XMLTreeParser().parse(data: Data(xml.utf8))
        XCTAssertNil(doc.metadata.doctype)
    }

    func test_writer_systemDoctype_roundtrips() throws {
        let xml = """
        <?xml version="1.0"?><!DOCTYPE root SYSTEM "root.dtd"><root/>
        """
        let parser = XMLTreeParser()
        let writer = XMLTreeWriter()
        let parsed = try parser.parse(data: Data(xml.utf8))
        let written = try writer.writeData(parsed)
        let roundtripped = try parser.parse(data: written)
        XCTAssertEqual(roundtripped.metadata.doctype?.name, "root")
        XCTAssertEqual(roundtripped.metadata.doctype?.systemID, "root.dtd")
        XCTAssertNil(roundtripped.metadata.doctype?.publicID)
    }

    // MARK: - XMLTreeDocument equality with new fields

    func test_xmlTreeDocument_withPrologueEpilogue_equality() {
        let root = XMLTreeElement(name: XMLQualifiedName(localName: "root"))
        let doc1 = XMLTreeDocument(
            root: root,
            prologueNodes: [.processingInstruction(target: "pi", data: "x=1")],
            epilogueNodes: [.comment("end")]
        )
        let doc2 = XMLTreeDocument(
            root: root,
            prologueNodes: [.processingInstruction(target: "pi", data: "x=1")],
            epilogueNodes: [.comment("end")]
        )
        let doc3 = XMLTreeDocument(
            root: root,
            prologueNodes: [.processingInstruction(target: "pi", data: "x=2")],
            epilogueNodes: [.comment("end")]
        )
        XCTAssertEqual(doc1, doc2)
        XCTAssertNotEqual(doc1, doc3)
    }
}
