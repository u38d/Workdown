
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
	private bool sectionContentsOpened;

	public this(R range) {
		this.range = range;

		ancestors = DList!string(new string[0]);
		buffer = DList!string(new string[0]);

		baseHeadingLevel = 0;
		sectionLevel = 0;
		sectionContentsOpened = false;

		popFront;
	}

	private void convertLine() {
		if (range.empty) {
			return;
		}
		auto line = range.front;
		range.popFront;
		line.chomp;
		if (line.empty) {
			return;
		}

		auto capture = matchFirst(line, headingRe);
		if (cast(bool)capture) {
			int headingLevel = cast(int)(capture[1].length);
			assert(headingLevel >= 1 && headingLevel <= 6);

			if (baseHeadingLevel == 0) {
				baseHeadingLevel = headingLevel;
				sectionLevel = headingLevel - 1;
			}

			if (headingLevel < baseHeadingLevel) {
				throw new Exception("最初の見出しよりも小さいレベルの見出しが出現しました。");
			}
			if (headingLevel > sectionLevel + 1) {
				throw new Exception("見出しのレベルが飛んでいます。");
			}

			// headingレベル - 1までsectionを閉じる
			foreach (i;0..sectionLevel - (headingLevel - 1)) {
				closeElement("section");
			}
			openElement("section");

			auto name = format("h%s", headingLevel);
			putStartTag(name);
			putString(capture[2].idup);
			putEndTag(name);
			putString("\n");
		} else {
			openContentBlock();
			putStartTag("p");
			putString(line.idup);
			putEndTag("p");
			putString("\n");
		}
	}

	public static string lf(string name) {
		if (name == "section" || name == "div") {
			return "\n";
		} else {
			return "";
		}
	}

	private void putStartTag(string name) {
		buffer.insertBack(format("<%s>%s", name, lf(name)));
		ancestors.insertBack(name);
	}

	private void putEndTag(string name) {
		assert(name == ancestors.back);

		buffer.insertBack(format("</%s>%s", name, lf(name)));
		ancestors.removeBack;
	}

	private void putString(string s) {
		buffer.insertBack(s);
	}

	private void openContentBlock() {
		if (sectionContentsOpened) {
			return;
		}
		putStartTag("div");
		sectionContentsOpened = true;
	}

	private void openElement(string name) {
		putStartTag(name);
		if (name == "section") {
			sectionContentsOpened = false;
			++sectionLevel;
		}
	}

	private void closeElement(string name) {
		while (!ancestors.empty) {
			auto current = ancestors.back;
			putEndTag(current);
			if (current == "section") {
				sectionContentsOpened = false;
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
			putEndTag(e);
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
