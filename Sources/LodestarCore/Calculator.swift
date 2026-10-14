import Foundation

/// A small recursive-descent arithmetic evaluator.
///
/// Grammar:
///   expr    := term (('+' | '-') term)*
///   term    := power (('*' | '/' | '%' | 'x') power)*   // implicit multiplication too: 2(3), 2pi
///   power   := unary ('^' power)?                         // right associative
///   unary   := ('-' | '+') unary | postfix
///   postfix := primary '!'?
///   primary := number | constant | func '(' expr ')' | '(' expr ')'
public enum Calculator {
    public enum CalcError: Error, Equatable {
        case unexpectedEnd
        case unexpectedToken(String)
        case unknownIdentifier(String)
        case invalidNumber
    }

    /// Evaluates `input`; returns nil if the input is not a valid expression
    /// or doesn't look like a calculation worth showing (e.g. a bare number).
    public static func evaluateIfCalculation(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains(where: { $0.isNumber }) || trimmed.lowercased().contains("pi") else { return nil }
        // A bare number isn't a calculation.
        if Double(trimmed.replacingOccurrences(of: ",", with: "")) != nil { return nil }
        guard let value = try? evaluate(trimmed), value.isFinite else { return nil }
        return value
    }

    public static func evaluate(_ input: String) throws -> Double {
        var parser = Parser(tokens: try tokenize(input))
        let value = try parser.parseExpression()
        if let extra = parser.peek() { throw CalcError.unexpectedToken(extra.description) }
        return value
    }

    /// Formats a result without float noise: 0.1+0.2 -> "0.3", 1e21 stays scientific.
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 10
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if abs(value) >= 1e15 || abs(value) < 1e-9 {
            formatter.numberStyle = .scientific
            formatter.maximumFractionDigits = 8
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Tokenizer

    enum Token: Equatable, CustomStringConvertible {
        case number(Double)
        case ident(String)
        case op(Character)
        case lparen, rparen

        var description: String {
            switch self {
            case .number(let v): return String(v)
            case .ident(let s): return s
            case .op(let c): return String(c)
            case .lparen: return "("
            case .rparen: return ")"
            }
        }
    }

    static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace { i += 1; continue }
            if ch.isNumber || ch == "." {
                var s = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "," || chars[i] == "_" {
                    if chars[i] != "," && chars[i] != "_" { s.append(chars[i]) }
                    i += 1
                }
                // Scientific notation: 1e5, 2.5E-3
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var j = i + 1
                    if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
                    if j < chars.count, chars[j].isNumber {
                        s.append("e")
                        if chars[i + 1] == "-" { s.append("-") }
                        i = j
                        while i < chars.count, chars[i].isNumber { s.append(chars[i]); i += 1 }
                    }
                }
                guard let v = Double(s) else { throw CalcError.invalidNumber }
                tokens.append(.number(v))
                continue
            }
            if ch.isLetter {
                var s = ""
                while i < chars.count, chars[i].isLetter { s.append(chars[i]); i += 1 }
                // The only identifier containing a digit is log2.
                if s.lowercased() == "log", i < chars.count, chars[i] == "2" { s.append("2"); i += 1 }
                let lower = s.lowercased()
                // Treat a lone "x" between operands as multiplication.
                if lower == "x" { tokens.append(.op("*")) } else { tokens.append(.ident(lower)) }
                continue
            }
            switch ch {
            case "+", "-", "*", "/", "%", "^", "!": tokens.append(.op(ch))
            case "×", "·": tokens.append(.op("*"))
            case "÷": tokens.append(.op("/"))
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            default: throw CalcError.unexpectedToken(String(ch))
            }
            i += 1
        }
        return tokens
    }

    // MARK: - Parser

    struct Parser {
        let tokens: [Token]
        var pos = 0

        init(tokens: [Token]) { self.tokens = tokens }

        func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
        mutating func next() -> Token? { defer { pos += 1 }; return peek() }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while let t = peek(), case .op(let c) = t, c == "+" || c == "-" {
                pos += 1
                let rhs = try parseTerm()
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parsePower()
            while let t = peek() {
                if case .op(let c) = t, c == "*" || c == "/" || c == "%" {
                    pos += 1
                    let rhs = try parsePower()
                    switch c {
                    case "*": value *= rhs
                    case "/": value /= rhs
                    default: value = value.truncatingRemainder(dividingBy: rhs)
                    }
                } else if startsPrimary(t) {
                    // Implicit multiplication: 2(3+4), 2pi, (1)(2)
                    value *= try parsePower()
                } else {
                    break
                }
            }
            return value
        }

        func startsPrimary(_ t: Token) -> Bool {
            switch t {
            case .number, .ident, .lparen: return true
            default: return false
            }
        }

        mutating func parsePower() throws -> Double {
            let base = try parseUnary()
            if let t = peek(), case .op("^") = t {
                pos += 1
                let exponent = try parsePowerRHS()
                return pow(base, exponent)
            }
            return base
        }

        // Exponent may itself carry a unary sign: 2^-1
        mutating func parsePowerRHS() throws -> Double {
            if let t = peek(), case .op(let c) = t, c == "-" || c == "+" {
                pos += 1
                let v = try parsePowerRHS()
                return c == "-" ? -v : v
            }
            return try parsePower()
        }

        mutating func parseUnary() throws -> Double {
            if let t = peek(), case .op(let c) = t, c == "-" || c == "+" {
                pos += 1
                // -2^2 == -(2^2), matching conventional notation.
                let v = try parsePower()
                return c == "-" ? -v : v
            }
            return try parsePostfix()
        }

        mutating func parsePostfix() throws -> Double {
            var v = try parsePrimary()
            while let t = peek(), case .op("!") = t {
                pos += 1
                guard v >= 0, v == v.rounded(), v <= 170 else { throw CalcError.unexpectedToken("!") }
                v = (1...max(1, Int(v))).reduce(1.0) { $0 * Double($1) }
            }
            return v
        }

        mutating func parsePrimary() throws -> Double {
            guard let t = next() else { throw CalcError.unexpectedEnd }
            switch t {
            case .number(let v):
                return v
            case .lparen:
                let v = try parseExpression()
                guard case .rparen? = next() else { throw CalcError.unexpectedEnd }
                return v
            case .ident(let name):
                if let constant = Calculator.constants[name] { return constant }
                guard let fn = Calculator.functions[name] else { throw CalcError.unknownIdentifier(name) }
                guard case .lparen? = next() else { throw CalcError.unexpectedToken(name) }
                let arg = try parseExpression()
                guard case .rparen? = next() else { throw CalcError.unexpectedEnd }
                return fn(arg)
            default:
                throw CalcError.unexpectedToken(t.description)
            }
        }
    }

    static let constants: [String: Double] = ["pi": Double.pi, "e": M_E, "tau": 2 * Double.pi]

    static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() },
        "abs": { Swift.abs($0) },
        "sin": { Foundation.sin($0) },
        "cos": { Foundation.cos($0) },
        "tan": { Foundation.tan($0) },
        "asin": { Foundation.asin($0) },
        "acos": { Foundation.acos($0) },
        "atan": { Foundation.atan($0) },
        "ln": { Foundation.log($0) },
        "log": { Foundation.log10($0) },
        "log2": { Foundation.log2($0) },
        "exp": { Foundation.exp($0) },
        "round": { $0.rounded() },
        "floor": { Foundation.floor($0) },
        "ceil": { Foundation.ceil($0) },
    ]
}
