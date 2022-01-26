
import std.stdio;
import std.ascii;
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

class ByLine {
	DList!(char) buffer;
	bool empty_;

	this() {
		empty_ = true;
	}

	void put(char c) {
		buffer.insertBack(c);

		if (empty_ && c == '\n') {
			empty_ = false;
		}
	}

	void put(string s) {
		foreach (c;s) {
			buffer.insertBack(c);
		}

		if (empty_ && s.indexOf('\n') >= 0) {
			empty_ = false;
		}
	}

	bool empty() const @safe nothrow {
		return empty_;
	}

	string front() {
		auto s = buffer[];
		return s.take(s.indexOf('\n') + 1).array.idup;
	}

	void popFront() {
		buffer.removeFront(cast(size_t)((buffer[]).indexOf('\n') + 1));
		empty_ = (buffer[]).indexOf('\n') == -1;
	}
}

class Node {
	protected Node[] children;

	public static string escape(string s) {
		s = s.replace("&", "&amp;");
		s = s.replace("<", "&lt;");
		s = s.replace(">", "&gt;");
		s = s.replace("\"", "&quot;");
		s = s.replace("\'", "&apos;");

		return s;
	}
}

class Element : Node {
	enum LineBreak {
		StartTag = 0x01,
		EndTag = 0x02,
		Both = StartTag | EndTag
	}

	protected string name;
	protected const string[string] attributes;
	protected LineBreak lineBreak;

	public this(string name, LineBreak lineBreak) {
		string[string] e;
		this(name, lineBreak, e);
	}

	public this(string name, LineBreak lineBreak, const ref string[string] attributes) {
		this.name = name.map!((c) => cast(char)(std.ascii.toLower(c))).array.idup;
		this.lineBreak = lineBreak;
		this.attributes = attributes;
	}

	public string startTagOpener() const @safe nothrow {
		return "<";
	}

	public string startTagCloser() const @safe nothrow {
		return ">";
	}

	public string endTagOpener() const @safe nothrow {
		return "</";
	}

	public string endTagCloser() const @safe nothrow {
		return ">";
	}

	public void putStartTag(R)(R dst) const {
		dst.put(startTagOpener);
		dst.put(name);

		foreach (key, value;attributes) {
			dst.put(' ');
			dst.put(key);
			dst.put(`="`);
			dst.put(escape(value));
			dst.put('\"');
		}

		dst.put(startTagCloser);

		if (lineBreak & LineBreak.StartTag) {
			dst.put('\n');
		}
	}

	public void putEndTag(R)(R dst) const {
		dst.put(endTagOpener);
		dst.put(name);
		dst.put(endTagCloser);
		if (lineBreak | LineBreak.EndTag) {
			dst.put('\n');
		}
	}
}

class EmptyElement : Element {
	public this(string name, LineBreak lineBreak) {
		super(name, lineBreak);
	}

	public this(string name, LineBreak lineBreak, const ref string[string] attributes) {
		super(name, lineBreak, attributes);
	}

	public override string startTagCloser() const @safe nothrow {
		return " />";
	}

	public override void putEndTag(R)(R) const {
	}
}

class ElementTree(R) {
	Element[] ancestors;
	R outputRange;
	size_t baseHeadingLevel;

	this(R outputRange) {
		this.outputRange = outputRange;
		ancestors = new Element[0];
		baseHeadingLevel = 0;
	}

	void openElement(string name, Element.LineBreak lineBreak, const ref string[string] attributes) {
		auto e = new Element(name, lineBreak, attributes);
		ancestors ~= e;
		e.putStartTag(outputRange);
	}

	void openElement(string name, Element.LineBreak lineBreak) {
		string[string] e;
		openElement(name, lineBreak, e);
	}

	void closeElement(string name) {
		while (!ancestors.empty) {
			auto e = ancestors.back;
			ancestors.popBack;

			e.putEndTag(outputRange);

			if (e.name == name) {
				break;
			}
		}
	}

	void closeAllElement() {
		foreach_reverse (e;ancestors) {
			e.putEndTag(outputRange);
		}

		ancestors.length = 0;
	}

	void insertText(string s) {
		outputRange.put(Element.escape(s));
	}

	void adjustSectionLevel(size_t targetLevel) {
		assert(targetLevel >= 1 && targetLevel <= 6);

		if (baseHeadingLevel == 0) {
			openElement("section", Element.LineBreak.Both);
			baseHeadingLevel = targetLevel;
			return;
		}

		if (targetLevel < baseHeadingLevel) {
			throw new Exception("最初の見出しのレベルより低いレベルの見出しが出現しました。");
		}

		auto sectionLevel = ancestors.count!((e) => e.name == "section");
		if (targetLevel >= sectionLevel + 2) {
			throw new Exception("見出しのレベルが飛んでいます。");
		}

		assert(sectionLevel + 1 >= targetLevel);
		foreach (i;0..(sectionLevel + 1 - targetLevel)) {
			closeElement("section");
		}
		openElement("section", Element.LineBreak.Both);
	}
}

class Converter(R) {
	private R range; // 行単位で取得できるレンジ
	private ByLine buffer; // 出力バッファ
	private ElementTree!ByLine tree;

	public this(R range) {
		this.range = range;
		this.buffer = new ByLine;
		this.tree = new ElementTree!ByLine(this.buffer);

		popFront;
	}

	public void popFront() {
		if (!buffer.empty) {
			buffer.popFront;
			if (!buffer.empty) {
				return;
			}
		}

		while (buffer.empty && !range.empty) {
			convertLine(range.front.idup);
			range.popFront;
		}

		if (buffer.empty && range.empty) {
			closeAll();
		}
	}

	public string front() {
		return buffer.front;
	}

	public bool empty() {
		return buffer.empty && range.empty;
	}

	private void convertLine(string line) {
		line = line.chomp;
		if (line.empty) {
			return;
		}

		bool result = false;

		result = heading(line);
		if (result) {
			return;
		}

		tree.openElement("p", Element.LineBreak.EndTag);
		tree.insertText(line);
		tree.closeElement("p");
	}

	private bool heading(string line) {
		if (line[0] != '#') {
			return false;
		}
		size_t level;
		string name;
		if (line.startsWith("# ")) {
			name = "h1";
			level = 1;
		} else if (line.startsWith("## ")) {
			name = "h2";
			level = 2;
		} else if (line.startsWith("### ")) {
			name = "h3";
			level = 3;
		} else if (line.startsWith("#### ")) {
			name = "h4";
			level = 4;
		} else if (line.startsWith("##### ")) {
			name = "h5";
			level = 5;
		} else if (line.startsWith("###### ")) {
			name = "h6";
			level = 6;
		} else {
			return false;
		}

		tree.adjustSectionLevel(level);
		tree.openElement(name, Element.LineBreak.EndTag);
		tree.insertText(line[level + 1..$]);
		tree.closeElement(name);

		return true;
	}

	private void closeAll() {
		tree.closeAllElement();
	}
}

void main() {
	auto byLine = stdin.byLine;
	auto converter = new Converter!(typeof(byLine))(byLine);

	foreach (line;converter) {
		write(line);
	}
}
