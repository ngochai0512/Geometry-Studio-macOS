import Foundation

// MARK: - Expression parser

struct Expression {
    private let tokens: [Token]
    private var index = 0
    private var angleUnit: AngleUnit = .radians

    private enum Token: Equatable {
        case number(Double)
        case name(String)
        case op(Character)
        case lparen
        case rparen
        case comma
    }

    init?(_ source: String) {
        var out: [Token] = []
        let chars = Array(source.lowercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
                continue
            }
            if c.isNumber || c == "." {
                var s = String(c)
                i += 1
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    s.append(chars[i])
                    i += 1
                }
                guard let d = Double(s) else {
                    return nil
                }
                out.append(.number(d))
                continue
            }
            if c.isLetter || c == "_" || c == "π" {
                var s = String(c)
                i += 1
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                    s.append(chars[i])
                    i += 1
                }
                out.append(.name(s))
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^":
                out.append(.op(c))
            case "(":
                out.append(.lparen)
            case ")":
                out.append(.rparen)
            case ",":
                out.append(.comma)
            default:
                return nil
            }
            i += 1
        }
        if out.isEmpty {
            return nil
        }
        tokens = out
    }

    mutating func setAngleUnit(_ unit: AngleUnit) {
        angleUnit = unit
    }

    mutating func evaluate(x: Double = 0, variables: [String: Double] = [:]) -> Double? {
        index = 0
        var vars = variables
        vars["x"] = x
        return parseExpression(vars)
    }

    private mutating func peek() -> Token? {
        index < tokens.count ? tokens[index] : nil
    }
    private mutating func take() -> Token? {
        guard index < tokens.count else {
            return nil
        }
        defer {
            index += 1
        }
        return tokens[index]
    }
    private mutating func match(_ t: Token) -> Bool {
        if peek() == t {
            index += 1
            return true
        }
        return false
    }

    private mutating func parseExpression(_ vars: [String: Double]) -> Double? {
        var value = parseTerm(vars)
        while let tok = peek(), case .op(let op) = tok, op == "+" || op == "-" {
            _ = take()
            guard let rhs = parseTerm(vars), let lhs = value else {
                return nil
            }
            value = op == "+" ? lhs + rhs : lhs - rhs
        }
        return value
    }

    private mutating func parseTerm(_ vars: [String: Double]) -> Double? {
        var value = parseUnary(vars)
        while let tok = peek(), case .op(let op) = tok, op == "*" || op == "/" {
            _ = take()
            guard let rhs = parseUnary(vars), let lhs = value else {
                return nil
            }
            value = op == "*" ? lhs * rhs : (abs(rhs) < 1e-15 ? nil : lhs / rhs)
        }
        return value
    }

    private mutating func parseUnary(_ vars: [String: Double]) -> Double? {
        if let tok = peek(), case .op(let op) = tok, op == "-" {
            _ = take()
            return parseUnary(vars).map { -$0 }
        }
        if let tok = peek(), case .op(let op) = tok, op == "+" {
            _ = take()
            return parseUnary(vars)
        }
        return parsePower(vars)
    }

    private mutating func parsePower(_ vars: [String: Double]) -> Double? {
        guard let base = parseAtom(vars) else {
            return nil
        }
        if let tok = peek(), case .op(let op) = tok, op == "^" {
            _ = take()
            guard let exp = parseUnary(vars) else {
                return nil
            }
            return pow(base, exp)
        }
        return base
    }

    private mutating func parseAtom(_ vars: [String: Double]) -> Double? {
        guard let tok = take() else {
            return nil
        }
        switch tok {
        case .number(let d):
            return d
        case .lparen:
            let v = parseExpression(vars)
            guard match(.rparen) else {
                return nil
            }
            return v
        case .name(let name):
            if let v = vars[name] {
                return v
            }
            switch name {
            case "pi", "π":
                return .pi
            case "e":
                return M_E
            case "sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "abs", "ln",
                 "log", "exp", "floor", "ceil", "round":
                guard match(.lparen), let arg = parseExpression(vars), match(.rparen) else {
                    return nil
                }
                switch name {
                case "sin":
                    return sin(trigInput(arg))
                case "cos":
                    return cos(trigInput(arg))
                case "tan":
                    let t = tan(trigInput(arg))
                    return abs(t) > 1e12 ? nil : t
                case "asin":
                    return asin(arg)
                case "acos":
                    return acos(arg)
                case "atan":
                    return atan(arg)
                case "sqrt":
                    return arg < 0 ? nil : sqrt(arg)
                case "abs":
                    return abs(arg)
                case "ln", "log":
                    return arg <= 0 ? nil : log(arg)
                case "exp":
                    return exp(arg)
                case "floor":
                    return floor(arg)
                case "ceil":
                    return ceil(arg)
                case "round":
                    return arg.rounded()
                default:
                    return nil
                }
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func trigInput(_ x: Double) -> Double {
        angleUnit == .radians ? x : x * .pi / 180
    }
}
