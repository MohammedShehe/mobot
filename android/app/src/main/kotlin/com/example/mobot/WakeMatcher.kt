package com.example.mobot

/** Kotlin twin of lib/core/wake_word.dart. Keep both in sync. */
object WakeMatcher {
    private val greet = setOf("hey", "hay", "hi", "hello", "yo", "you", "yow", "your", "yeah", "okay", "ok", "oh", "hei", "eh")
    private val vowelish = Regex("ore|oar|oor|our|oo|ow|ou|oe|oh|au|aw|or")
    private val dup = Regex("(.)\\1+")
    private val ws = Regex("\\s+")

    private fun letters(s: String) = s.lowercase().replace(Regex("[^a-z]"), "")

    private fun key(s: String): String {
        val t = vowelish.replace(letters(s), "o")
        return dup.replace(t) { it.groupValues[1] }
    }

    private fun distance(a: String, b: String): Int {
        if (a == b) return 0
        var prev = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            val cur = IntArray(b.length + 1)
            cur[0] = i
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                cur[j] = minOf(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[b.length]
    }

    private fun clean(s: String) = s.replaceFirst(Regex("^[\\s,.!:;?-]+"), "").trim()

    /** Text after the wake word ("" if only the wake word was said) or null if no match. */
    fun match(heard: String, wake: String): String? {
        val h = heard.trim()
        val w = wake.trim()
        if (w.isEmpty()) return h
        val wk = key(w)
        val words = h.split(ws).filter { it.isNotEmpty() }
        if (words.isEmpty()) return null
        if (wk.isEmpty()) {
            return if (h.lowercase().startsWith(w.lowercase())) clean(h.substring(w.length)) else null
        }
        val wWords = w.split(ws).filter { it.isNotEmpty() }
        val n = wWords.size
        val tolerance = (wk.length * 0.25).toInt().coerceIn(1, 3)
        var bestK = -1
        var bestD = 999
        var k = 1
        while (k <= n + 1 && k <= words.size) {
            val d = distance(key(words.take(k).joinToString("")), wk)
            if (d < bestD || (d == bestD && k == n)) {
                bestD = d
                bestK = k
            }
            k++
        }
        if (bestK >= 0 && bestD <= tolerance) return clean(words.drop(bestK).joinToString(" "))

        // "<greeting> MO": accept any greeting (hey / yo / you / yow ...) before the name.
        if (wWords.size >= 2 && greet.contains(letters(wWords.first()))) {
            val core = key(wWords.drop(1).joinToString(""))
            if (core.isNotEmpty() && greet.contains(letters(words.first()))) {
                var m = 1
                while (m <= 3 && 1 + m <= words.size) {
                    if (key(words.drop(1).take(m).joinToString("")) == core) {
                        return clean(words.drop(1 + m).joinToString(" "))
                    }
                    m++
                }
            }
        }
        return null
    }
}
