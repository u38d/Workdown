
import std.stdio;
import std.format;
import std.algorithm;
import std.string;
import std.regex;
import std.container;
import std.range;

/** 
 * # H1
 * ## H2
 * ### H3
 * #### H4
 * ##### H5
 * ###### H6
 */
const headingRe = ctRegex!(`^(#{1,6})\s+(.*)`);

class Converter(R) {
	private R range; // 行単位で取得できるレンジ
	private DList!(string) ancestors; // 祖先要素
	private DList!(string) buffer; // 出力バッファ

	private int baseHeadingLevel;
	private int sectionLevel;

	public this(R range) {
		this.range = range;

		ancestors = DList!string(new string[0]);
		buffer = DList!string(new string[0]);

		baseHeadingLevel = -1;
		sectionLevel = 1;

		popFront;
	}

	private void convertLine() {
		if (range.empty) {
			return;
		}
		auto line = range.front;
		range.popFront;
		line.chomp;

		auto capture = matchFirst(line, headingRe);
		if (cast(bool)capture) {
			int headingLevel = cast(int)(capture[1].length);
			assert(headingLevel >= 1 && headingLevel <= 6);

			if (baseHeadingLevel <= 0) {
				baseHeadingLevel = headingLevel;
			} else {
				if (headingLevel <= baseHeadingLevel) {
					throw new Exception("ベースの見出しのレベル以下の見出しが出現しました。");
				}
				if (headingLevel > sectionLevel + 1) {
					throw new Exception("見出しのレベルが飛んでいます。");
				}

				foreach (i;0..sectionLevel + 1 - headingLevel) {
					closeElement("section");
				}
				openElement("section");
			}
			buffer.insertBack(format("<h%s>%s</h%s>\n", headingLevel, capture[2], headingLevel));
		} else {
			buffer.insertBack(format("<p>%s</p>\n", line));
		}
	}

	private void openElement(string name) {
		buffer.insertBack(format("<%s>\n", name));
		ancestors.insertBack(name);
		if (name == "section") {
			++sectionLevel;
		}
	}

	private void closeElement() {
		assert(!ancestors.empty);
		closeElement(ancestors.back);
	}

	private void closeElement(string name) {
		while (!ancestors.empty) {
			auto current = ancestors.back;
			ancestors.removeBack;
			buffer.insertBack(format("</%s>\n", current));
			if (current == "section") {
				--sectionLevel;
			}
			if (current == name) {
				return;
			}
		}
		assert(false);
	}

	private void closeAllElement() {
		foreach_reverse (e;ancestors) {
			buffer.insertBack(format("</%s>\n", e));
		}
		ancestors.clear();
	}

	public void popFront() {
		if (!buffer.empty) {
			buffer.removeFront;
		}

		while (buffer.empty && !range.empty) {
			convertLine();
		}

		if (buffer.empty && range.empty) {
			closeAllElement();
		}
	}

	public string front() const {
		return buffer.front;
	}

	public bool empty() {
		return buffer.empty && range.empty;
	}
}

void main() {
	auto byLine = stdin.byLine;
	auto converter = new Converter!(typeof(byLine))(byLine);

	foreach (line;converter) {
		write(line);
	}
}
