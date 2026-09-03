import XCTest
@testable import ToolBarCore

/// 覆盖技术方案第 5 节的全部单测用例。
/// 时区相关测试显式注入 TimeZone，不依赖测试机环境。
final class CommandsTests: XCTestCase {

    private func run(
        _ input: String,
        timeZone: String = "UTC",
        dbFormat: DBFormat = .auto
    ) -> Result<CommandOutput, CommandError> {
        let context = CommandContext(timeZone: TimeZone(identifier: timeZone)!, dbFormat: dbFormat)
        return CommandEngine.execute(input, context: context)!
    }

    // MARK: t

    func testTimeUTC() throws {
        XCTAssertEqual(try run("t 1756216800").get().display, "2025-08-26 14:00:00")
    }

    func testTimeShanghai() throws {
        XCTAssertEqual(try run("t 1756216800", timeZone: "Asia/Shanghai").get().display, "2025-08-26 22:00:00")
    }

    func testTimeInvalid() {
        XCTAssertEqual(run("t abc"), .failure(.invalidTimestamp))
        XCTAssertEqual(run("t 2025-13-99 99:99:99"), .failure(.invalidTimestamp))
    }

    func testTimeStringToTimestampUTC() throws {
        XCTAssertEqual(try run("t 2025-08-26 14:00:00").get().display, "1756216800")
    }

    func testTimeStringToTimestampShanghai() throws {
        XCTAssertEqual(try run("t 2025-08-26 22:00:00", timeZone: "Asia/Shanghai").get().display, "1756216800")
    }

    func testTimeStringCommonFormats() throws {
        // 各种常见时间字符串格式均可解析（UTC 下 → 1756216800）
        XCTAssertEqual(try run("t 2025-08-26 14:00").get().display, "1756216800")
        XCTAssertEqual(try run("t 2025-08-26T14:00:00").get().display, "1756216800")
        XCTAssertEqual(try run("t 2025/08/26 14:00:00").get().display, "1756216800")
        // 仅日期 → 当天零点：1756216800 - 14h = 1756166400
        XCTAssertEqual(try run("t 2025-08-26").get().display, "1756166400")
    }

    func testTimeEmptyReturnsCurrentTimestamp() throws {
        let before = Int64(Date().timeIntervalSince1970)
        let output = try run("t").get()
        let after = Int64(Date().timeIntervalSince1970)
        guard let value = Int64(output.display) else {
            return XCTFail("应输出秒级时间戳，实际: \(output.display)")
        }
        XCTAssertTrue((before...after).contains(value))
    }

    // MARK: l

    func testLengthAscii() throws {
        XCTAssertEqual(try run("l hello").get().display, "5")
    }

    func testLengthChinese() throws {
        // 中文每字按 1 个字符计
        XCTAssertEqual(try run("l 你好世界").get().display, "4")
        XCTAssertEqual(try run("l a中b").get().display, "3")
    }

    func testLengthEmpty() throws {
        XCTAssertEqual(try run("l").get().display, "0")
    }

    // MARK: db

    func testDbPowerOfTwoOutputsHex() throws {
        let output = try run("db 123456 128").get()
        XCTAssertEqual(output.copyable, "40")
        XCTAssertEqual(output.display, "table: 40")
    }

    func testDbHexDigitWidth() throws {
        // 分表 16 → 1 位（0–f）；64 / 128 / 256 → 2 位（00–ff）
        XCTAssertEqual(try run("db 11 16").get().copyable, "b")
        XCTAssertEqual(try run("db 5 16").get().copyable, "5")
        XCTAssertEqual(try run("db 10 64").get().copyable, "0a")
        XCTAssertEqual(try run("db 200 256").get().copyable, "c8")
    }

    func testDbDecimalCountOutputsDecimal() throws {
        XCTAssertEqual(try run("db 123456 100").get().copyable, "56")
    }

    func testDbOtherCountOutputsDecimal() throws {
        XCTAssertEqual(try run("db 123456 7").get().copyable, "4")
    }

    func testDbFormatOverride() throws {
        XCTAssertEqual(try run("db 123456 128", dbFormat: .decimal).get().copyable, "64")
        XCTAssertEqual(try run("db 123456 100", dbFormat: .hex).get().copyable, "38")
    }

    func testDbInvalid() {
        XCTAssertEqual(run("db abc 128"), .failure(.invalidDbArguments))
        XCTAssertEqual(run("db 123"), .failure(.invalidDbArguments))
        XCTAssertEqual(run("db 123 0"), .failure(.invalidDbArguments))
        XCTAssertEqual(run("db"), .failure(.invalidDbArguments))
    }

    // MARK: ip

    func testIpDottedToInt() throws {
        XCTAssertEqual(try run("ip 10.1.2.3").get().display, "167838211")
    }

    func testIpIntToDotted() throws {
        XCTAssertEqual(try run("ip 167838211").get().display, "10.1.2.3")
        XCTAssertEqual(try run("ip 12345678").get().display, "0.188.97.78")
    }

    func testIpInvalid() {
        XCTAssertEqual(run("ip 999.1.1.1"), .failure(.invalidIP))
        XCTAssertEqual(run("ip 10.1.2"), .failure(.invalidIP))
        XCTAssertEqual(run("ip 4294967296"), .failure(.invalidIP))
        XCTAssertEqual(run("ip abc"), .failure(.invalidIP))
    }

    // MARK: en / de

    func testUrlEncode() throws {
        XCTAssertEqual(try run("en https://a.com/a b").get().display, "https%3A%2F%2Fa.com%2Fa%20b")
    }

    func testUrlDecode() throws {
        XCTAssertEqual(try run("de https%3A%2F%2Fa.com").get().display, "https://a.com")
    }

    func testUrlDecodeInvalid() {
        XCTAssertEqual(run("de 100%"), .failure(.invalidEncodedString))
    }

    // MARK: u

    func testUrlQuery() throws {
        let output = try run("u https://a.com/a?a=b&c=d").get()
        XCTAssertTrue(output.isMultiline)
        XCTAssertTrue(output.display.contains("\n"))
        let parsed = try JSONSerialization.jsonObject(with: Data(output.display.utf8)) as? [String: String]
        XCTAssertEqual(parsed, ["a": "b", "c": "d"])
    }

    func testUrlQueryRepeatedKeysMergeToArray() throws {
        let output = try run("u https://a.com/?a=1&a=2").get()
        XCTAssertTrue(output.isMultiline)
        let parsed = try JSONSerialization.jsonObject(with: Data(output.display.utf8)) as? [String: [String]]
        XCTAssertEqual(parsed, ["a": ["1", "2"]])
    }

    func testUrlInvalid() {
        XCTAssertEqual(run("u https://a.com/path"), .failure(.invalidURL))
    }

    // MARK: j

    func testJsonPrettyPrintKeepsUnicode() throws {
        let output = try run("j {\"name\":\"张三\"}").get()
        XCTAssertTrue(output.isMultiline)
        XCTAssertTrue(output.display.contains("张三"))
        XCTAssertTrue(output.display.contains("\n"))
        XCTAssertEqual(output.display, output.copyable)
    }

    func testJsonInvalid() {
        XCTAssertEqual(run("j {\"a\":"), .failure(.invalidJSON))
    }

    func testJsonEscapedQuotesAndHexBytes() throws {
        // 日志/Python 风格转义：\" 结构引号、\xHH UTF-8 字节、\” 弯引号结尾
        let input = #"j {\"role_id\":\"3269_1439_3169\",\"role_name\":\"\xe7\xaa\xa6\xe6\x98\x8e\",\"role_uid\":\"\",\"actor_uid\":\"1617423593\",\"chaohua_id\":\"1022:100808bd0661267467ef3ddeec18974b39263e\”}"#
        let output = try run(input).get()
        XCTAssertTrue(output.display.contains("窦明"))
        XCTAssertTrue(output.display.contains("\"role_id\" : \"3269_1439_3169\""))
        // 输出仍是合法 JSON
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(output.display.utf8)))
    }

    func testJsonStrictEscapedQuoteUnaffected() throws {
        // 合法 JSON 内含 \" 转义引号：严格解析优先，不被宽松预处理误伤
        let output = try run(#"j {"a":"x\"y"}"#).get()
        XCTAssertTrue(output.display.contains(#""a" : "x\"y""#))
    }

    // MARK: clipboardFits（命令 + 空格自动粘贴剪贴板）

    private func fits(_ command: String, _ clipboard: String) -> Bool {
        CommandEngine.clipboardFits(command: command, clipboard: clipboard)
    }

    func testClipboardFitsTimestamp() {
        XCTAssertTrue(fits("t", "1756216800"))
        XCTAssertTrue(fits("t", "2025-08-26 14:00:00"))
        XCTAssertFalse(fits("t", "abc"))
    }

    func testClipboardFitsDb() {
        XCTAssertTrue(fits("db", "123456 128"))
        XCTAssertFalse(fits("db", "123456"))
        XCTAssertFalse(fits("db", "abc 128"))
    }

    func testClipboardFitsIp() {
        XCTAssertTrue(fits("ip", "10.1.2.3"))
        XCTAssertTrue(fits("ip", "167838211"))
        XCTAssertFalse(fits("ip", "999.1.1.1"))
    }

    func testClipboardFitsEncodeDecode() {
        XCTAssertTrue(fits("en", "https://a.com/a b"))
        XCTAssertTrue(fits("de", "https%3A%2F%2Fa.com"))
        XCTAssertFalse(fits("de", "100%"))
    }

    func testClipboardFitsUrlRequiresQuery() {
        XCTAssertTrue(fits("u", "https://a.com/a?a=b"))
        XCTAssertFalse(fits("u", "https://a.com/path"))
    }

    func testClipboardFitsJson() {
        XCTAssertTrue(fits("j", "{\"a\":1}"))
        XCTAssertFalse(fits("j", "{\"a\":"))
    }

    func testClipboardFitsTrimsAndRejectsEmpty() {
        XCTAssertTrue(fits("t", "  1756216800\n"))
        XCTAssertFalse(fits("t", "   "))
        XCTAssertFalse(fits("t", ""))
    }

    func testClipboardFitsUnknownCommand() {
        XCTAssertFalse(fits("xxx", "1756216800"))
    }

    // MARK: 解析

    func testUnknownCommand() {
        XCTAssertEqual(run("xxx abc"), .failure(.unknownCommand))
    }

    func testEmptyInput() {
        XCTAssertNil(CommandEngine.execute("   "))
        XCTAssertNil(CommandEngine.execute(""))
    }
}
