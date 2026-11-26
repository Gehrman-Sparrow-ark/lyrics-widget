package com.lyricswidget.app

fun main() {
    val cases = listOf(
        estimatePosition(25_000, 0, 100_000, true, 1.0) to 25.0,
        estimatePosition(25_000, 110_000, 100_000, true, 1.0) to 25.0,
        estimatePosition(25_000, 98_000, 100_000, true, 1.5) to 28.0,
        estimatePosition(25_000, 98_000, 100_000, false, 1.0) to 25.0,
        estimatePosition(0, 0, 100_000, true, 1.0) to 0.0
    )
    cases.forEach { (actual, expected) -> check(actual == expected) { "$actual != $expected" } }
    println("PASS: absent and future update times, speed, pause, real zero")
}
