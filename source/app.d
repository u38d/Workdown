
import std.stdio;

import std.algorithm;
import std.string;
import std.regex;

auto headingRe = ctRegex!(`^(#{1,6})\s+(.*)`);

auto firstHeadingLevel = -1;
auto sectionLevel = 1;

void closeSection(int level) {
	assert(level >= firstHeadingLevel);

	while (sectionLevel > level) {
		writeln("</section>");
		--sectionLevel;
	}
}

void convertLine(C)(const(C)[] s) {
	s = s.chomp;

	auto capture = matchFirst(s, headingRe);
	if (cast(bool)capture) {
		auto headingLevel = cast(int)(capture[1].length);
		assert(headingLevel >= 1 && headingLevel <= 6);

		if (firstHeadingLevel <= 0) {
			firstHeadingLevel = sectionLevel = headingLevel;
			writefln("<h%s>%s</h%s>", headingLevel, capture[2], headingLevel);
		} else if (headingLevel <= firstHeadingLevel) {
			throw new Exception("ベースの見出しのレベル以下の見出しが出現しました。");
		} else if (headingLevel > sectionLevel + 1) {
			throw new Exception("見出しのレベルが飛んでいます。");
		} else {
			closeSection(headingLevel - 1);
			writeln("<section>");
			++sectionLevel;
			writefln("<h%s>%s</h%s>", headingLevel, capture[2], headingLevel);
		}
	} else {
		writefln("<p>%s</p>", s);
	}
}

void main() {
	foreach (line;stdin.byLine) {
		convertLine(line);
	}
	closeSection(1);
}
