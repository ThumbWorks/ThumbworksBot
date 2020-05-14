//
//  EmojiTests.swift
//  AppTests
//
//  Created by Roderic Campbell on 5/14/20.
//

import XCTest
@testable import App
class EmojiTests: XCTestCase {


    func testAppleSymbol() {
        XCTAssertEqual(Emoji.apple.symbol, ":apple:")
    }

    func testUberSymbol() {
        XCTAssertEqual(Emoji.uber.symbol, ":uber:")
    }
    func testWalmartSymbol() {
        XCTAssertEqual(Emoji.lohi.symbol, ":walmart:")
    }

}
