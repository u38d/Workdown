
import std.stdio;
import std.ascii;
import std.algorithm;
import std.string;
import std.regex;
import std.container;
import std.range;
import std.utf;

/+

"#",

"*", "[(", "![",

行頭コマンド(最初のスペースまで)
# Text
	<h1>Text</h1>

## Text
	<h2>Text</h2>

### Text
	<h3>Text</h3>

#### Text
	<h4>Text</h4>

##### Text
	<h5>Text</h5>

###### Text
	<h6>Text</h6>

Text
	<p>Text</p>

 Text
	<p>Text<\p>

[(http://example.com/){
セクションを入れるせいで見出しが入れられない
}]
	<a href="http://example.com/">
	<p>セクションを入れるせいで見出しが入れられない</p>
	</a>

+ term
- description
+ term1
+ term2
- description1
- description2
	<dl>
	<div>
	<dt>term</dt>
	<dd>description</dd>
	</div>
	<div>
	<dt>term1</dt>
	<dt>term2</dt>
	<dd>description1</dd>
	<dd>description2</dd>
	</div>
	</dl>

行中コマンド
Text *word*
	<p>Text <em>word<\em></p>
Text [(http://example.com/)Link]
	<p>Text <a href="http://example.com">Link</a></p>
![(http://example.com/image)Text]
	<p><img alt="Text" src="http://example.com/image" /></p>

\
`
*
_
{}
[]
()
#
+
-
.
!

+/

enum InlineCommandHeadChars = "!*[]{}";

enum HRe = ctRegex!(`^(#{1,6}) `);
enum UlRe = ctRegex!(`^\* `);
enum OlRe = ctRegex!(`^\. `);
enum DtRe = ctRegex!(`^\+ `);
enum DdRe = ctRegex!(`^- `);

enum ABlockStartRe = ctRegex!(`^\[\(([^\)]+)\)\{$`);
enum ABlockEndRe = ctRegex!(`^\}\]$`);

enum EmStartRe = ctRegex!(`^\*`);
enum EmEndRe = EmStartRe;
enum AInlineStartRe = ctRegex!(`^\[\(([^\)]+)\)`);
enum AInlineEndRe = ctRegex!(`^\]`);
enum ImgRe = ctRegex!(`^!\[\(([^\)]+)\)([^\]]*)\]`);

enum HtmlSourceRe = ctRegex!(`^<`);

static const string[] headings = ["h1", "h2", "h3", "h4", "h5", "h6"];

abstract class Node {
	public static string escape(string s) {
		s = s.replace("&", "&amp;");
		s = s.replace("<", "&lt;");
		s = s.replace(">", "&gt;");
		s = s.replace("\"", "&quot;");
		s = s.replace("\'", "&#x27;");

		return s;
	}

	protected Node parent_;
	protected Node[] childList_;

	public Node parent() @safe nothrow {
		return parent_;
	}

	public void parent(Node x) @safe nothrow {
		parent_ = x;
	}

	public void remove(Node n) {
		foreach (ref i;childList_) {
			if (i is null) {
				continue;
			}
			if (i is n) {
				i = null;
				n.parent_ = null;
				break;
			}
		}
	}

	public void add(Node n) {
		assert(n !is null);

		if (n.parent_) {
			n.parent_.remove(n);
		}

		childList_ ~= n;
		n.parent_ = this;
	}

	public Node lastChild() {
		foreach_reverse (c;childList_) {
			if (c !is null) {
				return c;
			}
		}

		return null;
	}

	public abstract void output(ref File);
}

class Text : Node {
	private string content;

	this(string content) {
		this.content = content;
	}

	public override void remove(Node) {
		assert(false, "Text ノードの子要素は削除できません");
	}

	public override void add(Node) {
		assert(false, "Text ノードには子ノードを追加できません");
	}

	public override void output(ref File outFile) {
		outFile.write(escape(content));
	}
}

class HtmlSource : Node {
	private string content;

	this(string content) {
		this.content = content;
	}

	public override void remove(Node) {
		assert(false, "HtmlSource ノードの子要素は削除できません");
	}

	public override void add(Node) {
		assert(false, "HtmlSource ノードには子ノードを追加できません");
	}

	public override void output(ref File outFile) {
		outFile.writeln(content);
	}
}

class Element : Node {
	private string name_;
	private string[string] attributes;
	private bool empty_; // 空要素(終了タグ禁止)
	private bool inline_; // 改行しない
	private bool multiline_; // 開始、終了どちらも改行
	private bool explicit_; // 明示的に閉じる必要がある

	invariant {
		if (multiline_) {
			assert(!inline_);
			assert(!empty_);
		}
		if (empty_) {
			assert(childList_.length == 0);
		}
	}

	public this(string name) {
		this.name_ = name;
		this.explicit_ = true;
	}

	public string name() const @safe nothrow {
		return name_;
	}

	public bool empty() const @safe nothrow {
		return empty_;
	}

	public void empty(bool x) @safe nothrow {
		empty_ = x;
	}

	public bool inline() const @safe nothrow {
		return inline_;
	}

	public void inline(bool x) @safe nothrow {
		inline_ = x;
	}

	public bool multiline() const @safe nothrow {
		return multiline_;
	}

	public void multiline(bool x) @safe nothrow {
		multiline_ = x;
	}

	public bool explicit() const @safe nothrow {
		return explicit_;
	}

	public void explicit(bool x) @safe nothrow {
		explicit_ = x;
	}

	public void setAttributes(ref string[string] x) @safe {
		attributes = x;
	}

	public string opIndex(string key) const @safe nothrow {
		return attributes[key];
	}

	public void opIndexAssign(string value, string key) {
		attributes[key] = value;
	}

	public override void output(ref File outFile) {
		outFile.writef(`<%s`, name_);
		foreach (kv;attributes.byPair) {
			outFile.writef(` %s="%s"`, kv.key, escape(kv.value));
		}

		if (empty_) {
			outFile.write(" />");
		} else {
			outFile.write(">");
		}

		if (multiline_) {
			outFile.writeln();
		}

		if (empty_) {
			return;
		}

		foreach (c;childList_) {
			if (c) {
				c.output(outFile);
			}
		}

		outFile.writef(`</%s>`, name_);
		if (multiline_ || !inline_) {
			outFile.writeln;
		}
	}
}

class RootElement : Element {
	public this() {
		super(null);
		explicit = false;
	}

	public override void output(ref File outFile) {
		foreach (c;childList_) {
			c.output(outFile);
		}
	}
}


interface Handler {
	Element currentElement();

	void elementStart(string, ref string[string], bool, bool, bool);
	void elementEnd(string);

	void attribute(string, string);

	void text(string);
	void htmlSource(string);

	void close();
}

class DefaultHandler : Handler {
	private File outFile;
	private Element root;
	private Element current;

	public this(ref File outFile, Element root = null) {
		this.outFile = outFile;
		if (root) {
			this.root = root;
		} else {
			this.root = new RootElement;
		}
		this.current = this.root;
	}

	public Element currentElement() {
		return current;
	}

	public void elementStart(string name, ref string[string] attributes, bool inline, bool multiline, bool empty) {
		auto e = new Element(name);
		e.setAttributes(attributes);
		e.empty = empty;
		e.inline = inline;
		e.multiline = multiline;

		current.add(e);

		if (!empty) {
			current = e;
		}
	}

	public void attribute(string key, string value) {
		current[key] = value;
	}

	public void elementEnd(string name) {
		if (current is null) {
			throw new Exception(name ~ "要素は開いていません");
		}
		if (current.name != name) {
			if (current.explicit) {
				throw new Exception(name ~ "要素の終了が来ましたが" ~ current.name ~ "要素が閉じられていません");
			} else {
				elementEnd(current.name);
			}
		}

		current = cast(Element)current.parent;
	}

	public void text(string s) {
		current.add(new Text(s));
	}

	public void htmlSource(string s) {
		current.add(new HtmlSource(s));
	}

	public void close() {
		root.output(outFile);
		while (current !is null) {
			if (current.explicit) {
				throw new Exception(current.name ~ "要素は明示的に閉じる必要があります");
			}
			current = cast(Element)current.parent;
		}
	}
}

class Sectioner : Handler {
	private Element root;
	private Handler nextHandler;
	private uint baseHeadingLevel, sectionLevel;

	public this(Element root, Handler nextHandler) {
		this.root = root;
		this.nextHandler = nextHandler;
		this.baseHeadingLevel = 0;
	}

	public Element currentElement() {
		return nextHandler.currentElement;
	}

	public void elementStart(string name, ref string[string] attributes, bool inline, bool multiline, bool empty) {
		auto targetLevel = cast(uint)(headings.countUntil(name) + 1);

		if (targetLevel == 0) {
			nextHandler.elementStart(name, attributes, inline, multiline, empty);
			return;
		}

		string[string] sectionAttr;

		if (baseHeadingLevel == 0) {
			baseHeadingLevel = targetLevel;
		} else if (targetLevel < baseHeadingLevel) {
			throw new Exception("最初の見出しのレベルより低いレベルの見出しが出現しました。");
		} else if (targetLevel > baseHeadingLevel + sectionLevel) {
			throw new Exception("見出しのレベルが飛んでいます。");
		} else {
			// セクションのレベルを合わせる
			while (sectionLevel > targetLevel - baseHeadingLevel) {
				nextHandler.elementEnd("div");
				nextHandler.elementEnd("section");
				--sectionLevel;
			}
		}

		nextHandler.elementStart("section", sectionAttr, false, true, false);
		nextHandler.currentElement.explicit = false;
		++sectionLevel;
		nextHandler.elementStart(name, attributes, inline, multiline, empty);
	}

	public void attribute(string key, string value) {
		nextHandler.attribute(key, value);
	}

	public void elementEnd(string name) {
		nextHandler.elementEnd(name);
		if (headings.countUntil(name) >= 0) {
			string[string] divAttr;
			divAttr["class"] = "section-contents";
			nextHandler.elementStart("div", divAttr, false, true, false);
			nextHandler.currentElement.explicit = false;
		}
	}

	public void text(string s) {
		nextHandler.text(s);
	}

	public void htmlSource(string s) {
		nextHandler.htmlSource(s);
	}

	public void close() {
		nextHandler.close();
	}
}


class Parser {
	private string[string] emptyAttr;
	private Handler handler;
	private string currentLine, nextLine;

	public this(Handler handler) {
		this.handler = handler;
	}

	public void close() {
		parseLine("");
		handler.close();
	}

	public void parseLine(string nline) {
		currentLine = nextLine;
		nextLine = nline.chomp;

		if (currentLine is null || currentLine.empty) {
			return;
		}

		auto line = currentLine;

		if (auto captures = matchFirst(line, UlRe)) {
			if (handler.currentElement.name != "ul") {
				handler.elementStart("ul", emptyAttr, false, true, false);
			}
			handler.elementStart("li", emptyAttr, false, false, false);
			parseInline(captures.post);
			handler.elementEnd("li");

			if (!matchFirst(nextLine, UlRe)) {
				handler.elementEnd("ul");
			}
		} else if (auto captures = matchFirst(line, OlRe)) {
			if (handler.currentElement.name != "ol") {
				handler.elementStart("ol", emptyAttr, false, true, false);
			}
			handler.elementStart("li", emptyAttr, false, false, false);
			parseInline(captures.post);
			handler.elementEnd("li");

			if (!matchFirst(nextLine, OlRe)) {
				handler.elementEnd("ol");
			}
		} else if (auto captures = matchFirst(line, DtRe)) {
			auto parent = cast(Element)handler.currentElement.parent;
			if (parent is null || parent.name != "dl") {
				handler.elementStart("dl", emptyAttr, false, true, false);
				handler.elementStart("div", emptyAttr, false, true, false);
				handler.currentElement.explicit = false;
			}
			handler.elementStart("dt", emptyAttr, false, false, false);
			parseInline(captures.post);
			handler.elementEnd("dt");
			if (!matchFirst(nextLine, DtRe) && !matchFirst(nextLine, DdRe)) {
				throw new Exception("dt要素の次に、dt要素かdd要素が来ません");
			}
		} else if (auto captures = matchFirst(line, DdRe)) {
			auto prev = handler.currentElement.lastChild;
			auto e = cast(Element)prev;
			if (e is null || (e.name != "dt" && e.name != "dd")) {
				throw new Exception("dd要素の前に、dt要素かdd要素がありません: " ~ handler.currentElement.name);
			}

			handler.elementStart("dd", emptyAttr, false, false, false);
			parseInline(captures.post);
			handler.elementEnd("dd");
			if (matchFirst(nextLine, DtRe)) {
				handler.elementEnd("div");
				handler.elementStart("div", emptyAttr, false, true, false);
			} else if (matchFirst(nextLine, DdRe)) {
				// do nothing
			} else {
				handler.elementEnd("div");
				handler.elementEnd("dl");
			}
		} else if (auto captures = matchFirst(line, HRe)) {
			auto level = captures[1].length;
			assert(level >= 1 && level <= 6);

			handler.elementStart(headings[level - 1], emptyAttr, false, false, false);
			parseInline(captures.post);
			handler.elementEnd(headings[level - 1]);
		} else if (auto captures = matchFirst(line, ABlockStartRe)) {
			string[string] attr;
			attr["href"] = captures[1];
			handler.elementStart("a", attr, false, true, false);
		} else if (auto captures = matchFirst(line, ABlockEndRe)) {
			handler.elementEnd("a");
		} else if (auto captures = matchFirst(line, HtmlSourceRe)) {
			handler.htmlSource(line);
		} else {
			handler.elementStart("p", emptyAttr, false, false, false);
			parseInline(line.strip);
			handler.elementEnd("p");
		}
	}

	private void parseInline(string s) {
		char[] token = new char[0];

		for (;;) {
			if (s.empty) {
				break;
			}

			if (!token.empty && InlineCommandHeadChars.indexOf(s[0]) >= 0) {
				handler.text(token.idup);
				token.length = 0;
			}
			if (handler.currentElement.name == "em") { // emは開始と終了が同じパターン
				if (auto captures = matchFirst(s, EmEndRe)) {
					s = captures.post;
					handler.elementEnd("em");
				}
			} else {
				if (auto captures = matchFirst(s, EmStartRe)) {
					s = captures.post;
					handler.elementStart("em", emptyAttr, true, false, false);
				}
			}

			if (auto captures = matchFirst(s, AInlineStartRe)) {
				s = captures.post;
				string[string] attr;
				attr["href"] = captures[1];
				handler.elementStart("a", attr, true, false, false);
			} else if (auto captures = matchFirst(s, AInlineEndRe)) {
				s = captures.post;
				handler.elementEnd("a");
			} else if (auto captures = matchFirst(s, ImgRe)) {
				s = captures.post;
				string[string] attr;
				attr["src"] = captures[1];
				attr["alt"] = captures[2];
				handler.elementStart("img", attr, true, false, true);
			}

			if (s.empty) {
				break;
			}
			// \でエスケープしつつtokenに追加
			if (s.length >= 2 && s[0] == '\\') {
				auto st = std.utf.stride(s, 1);
				token ~= s[1..st + 1];
				s = s[st + 1..$];
			} else {
				auto st = std.utf.stride(s);
				token ~= s[0..st];
				s = s[st..$];
			}
		}

		if (!token.empty) {
			handler.text(token.idup);
		}
	}
}

void main(string[] args) {
	File inFile = stdin, outFile = stdout;

	if (args.length >= 3) {
		inFile = File(args[1], "r");
		outFile = File(args[2], "w");
	}

	auto root = new RootElement;
	auto handler = new DefaultHandler(outFile, root);
	auto sectioner = new Sectioner(root, handler);
	auto parser = new Parser(sectioner);

	foreach (line;inFile.byLine) {
		parser.parseLine(line.idup);
	}
	parser.close();
}
