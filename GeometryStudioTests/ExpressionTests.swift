import Testing
@testable import GeometryStudio

@Suite("Expression parser")
struct ExpressionTests {
    private func value(_ source: String, x: Double = 0, unit: AngleUnit = .radians) throws -> Double? {
        var expression = try #require(Expression(source))
        expression.setAngleUnit(unit)
        return expression.evaluate(x: x)
    }

    @Test("operator precedence and associativity")
    func precedence() throws {
        #expect(try value("1+2*3") == 7)
        #expect(try value("(1+2)*3") == 9)
        #expect(try value("2^3^2") == 512)
        #expect(try value("-3+5") == 2)
    }

    @Test("built-in functions")
    func functions() throws {
        #expect(try value("sqrt(9)") == 3)
        #expect(try value("abs(-2)") == 2)
        #expect(abs(try #require(try value("ln(e)")) - 1) < 1e-12)
    }

    @Test("trigonometry follows the angle unit")
    func angleUnit() throws {
        #expect(abs(try #require(try value("sin(0)")) - 0) < 1e-12)
        #expect(abs(try #require(try value("sin(90)", unit: .degrees)) - 1) < 1e-12)
        #expect(abs(try #require(try value("cos(180)", unit: .degrees)) + 1) < 1e-12)
        #expect(abs(try #require(try value("sin(pi/2)")) - 1) < 1e-12)
    }

    @Test("x is bound from the argument")
    func xBinding() throws {
        #expect(try value("x*2", x: 3) == 6)
    }

    @Test("undefined results are nil, not zero")
    func undefined() throws {
        #expect(try value("1/0") == nil)
        #expect(try value("ln(0)") == nil)
        #expect(try value("sqrt(-1)") == nil)
        #expect(try value("unknown") == nil)
    }

    @Test("an unknown character is rejected at parse time")
    func invalidSource() {
        #expect(Expression("1$2") == nil)
        #expect(Expression("") == nil)
    }
}
