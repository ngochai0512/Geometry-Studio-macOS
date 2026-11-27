import Testing
@testable import GeometryStudio

@Suite("Math labels")
struct MathLabelTests {
    @Test("plain text passes through")
    func plain() {
        #expect(MathLabel.parse("ABC") == [MathLabelRun(text: "ABC", script: .normal)])
        #expect(MathLabel.plainText("ABC") == "ABC")
    }

    @Test("scripts keep their run")
    func scripts() {
        let runs = MathLabel.parse("A^2 + B_{1}")
        #expect(runs == [
            MathLabelRun(text: "A", script: .normal),
            MathLabelRun(text: "2", script: .superscript),
            MathLabelRun(text: " + B", script: .normal),
            MathLabelRun(text: "1", script: .sub)
        ])
    }

    @Test("Greek commands become characters")
    func greek() {
        #expect(MathLabel.parse("\\alpha\\beta") == [MathLabelRun(text: "αβ", script: .normal)])
        #expect(MathLabel.plainText("\\Omega") == "Ω")
    }

    @Test("overline and arc add combining marks")
    func decorations() {
        #expect(MathLabel.plainText("\\overline{AB}") == "A\u{0305}B\u{0305}")
        #expect(MathLabel.plainText("\\widehat{AB}") == "A\u{0361}B")
    }

    @Test("unknown commands keep their letters")
    func unknown() {
        #expect(MathLabel.plainText("\\foo") == "foo")
        #expect(MathLabel.plainText("\\{x\\}") == "{x}")
    }
}
