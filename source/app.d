
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
enum DlRe = ctRegex!(`^\+ `);

enum ABlockStartRe = ctRegex!(`^\[\(([^\)]+)\)\{$`);
enum ABlockEndRe = ctRegex!(`^\}\]$`);

enum EmStartRe = ctRegex!(`^\*`);
enum EmEndRe = EmStartRe;
enum AInlineStartRe = ctRegex!(`^\[\(([^\)]+)\)`);
enum AInlineEndRe = ctRegex!(`^\]`);
enum ImgRe = ctRegex!(`^!\[\(([^\)]+)\)([^\)]+)\]`);

enum HtmlSourceRe = ctRegex!(`^<`);

enum Element {
	Nothing,
	em,
	a,
	ul,
	ol,
	dl,
	div,
	section,
}


class Parser {
	public static string escape(string s) {
		s = s.replace("&", "&amp;");
		s = s.replace("<", "&lt;");
		s = s.replace(">", "&gt;");
		s = s.replace("\"", "&quot;");
		s = s.replace("\'", "&#x27;");

		return s;
	}

	private Element[] opened;
	private Handler handler;

	private size_t baseHeadingLevel;

	public this(Handler handler) {
		this.handler = handler;
		baseHeadingLevel = 0;
	}

	bool inUl() const {
		return !opened.empty && opened.back == Element.ul;
	}
	bool inOl() const {
		return !opened.empty && opened.back == Element.ol;
	}
	bool inDl() const {
		return opened.length >= 2 && (opened[$ - 1] == Element.dl || opened[$ - 2] == Element.dl);
	}

	public void close() {
		while (!opened.empty) {
			closeElement(opened.back);
		}
	}

	private void closeElement(Element e) {
		while (!opened.empty) {
			auto c = opened.back;

			if (c == Element.div) {
				handler.divEnd();
			} else if (c == Element.section) {
				handler.sectionEnd();
			} else if (c == Element.a) {
				handler.aBlockEnd();
			} else if (c == Element.ul) {
				handler.ulEnd();
			} else if (c == Element.ol) {
//				handler.olEnd();
			} else if (c == Element.dl) {
				handler.dlEnd();
			} else {
				assert(false);
			}
			opened.popBack;

			if (c == e) {
				break;
			}
		}
	}

	public void parseLine(string line) {
		line = line.chomp;

		if (inUl) {
			if (auto captures = matchFirst(line, UlRe)) {
				handler.liInlineStart();
				parseInline(captures.post);
				handler.liInlineEnd();
				return;
			} else {
				closeElement(Element.ul);
			}
		} else if (auto captures = matchFirst(line, UlRe)) {
			opened ~= Element.ul;
			handler.ulStart();
			handler.liInlineStart();
			parseInline(captures.post);
			handler.liInlineEnd();
			return;
		}

		if (inDl) {// 複数dt, dd非対応
			if (line.empty) {
				closeElement(Element.dl);
			} else if (auto captures = matchFirst(line, DlRe)) {
				// 二つ目以降の要素
				opened ~= Element.div;
				handler.divStart();

				handler.dtStart();
				parseInline(captures.post);
				handler.dtEnd();
				return;
			} else {
				handler.ddStart();
				parseInline(line);
				handler.ddEnd();
				closeElement(Element.div);
				return;
			}
		} else if (auto captures = matchFirst(line, DlRe)) {
			opened ~= Element.dl;
			handler.dlStart();
			opened ~= Element.div;
			handler.divStart();

			handler.dtStart();
			parseInline(captures.post);
			handler.dtEnd();
			return;
		}

		if (line.empty) {
			return;
		}

		if (auto captures = matchFirst(line, HRe)) {
			auto level = captures[1].length;
			assert(level >= 1 && level <= 6);

			adjustSectionLevel(level);

			handler.hStart(cast(int)level);
			parseInline(captures.post);
			handler.hEnd(cast(int)level);
		} else if (auto captures = matchFirst(line, ABlockStartRe)) {
			opened ~= Element.a;
			handler.aBlockStart(escape(captures[1]));
		} else if (auto captures = matchFirst(line, ABlockEndRe)) {
			closeElement(Element.a);
		} else if (auto captures = matchFirst(line, HtmlSourceRe)) {
			handler.htmlSource(line);
		} else {
			handler.pStart();
			parseInline(line.strip);
			handler.pEnd();
		}
	}

	private void parseInline(string s) {
		auto elementLevel = opened.length;
		char[] token = new char[0];

		for (;;) {
			if (s.empty) {
				break;
			}

			if (!token.empty && InlineCommandHeadChars.indexOf(s[0]) >= 0) {
				handler.text(escape(token.idup));
				token.length = 0;
			}

			auto last = Element.Nothing;
			if (!opened.empty) {
				last = opened.back;
			}

			switch (last) {
			case Element.em:
				if (auto captures = matchFirst(s, EmEndRe)) {
					s = s[captures[0].length..$];
					opened.popBack;
					handler.emEnd;
					continue;
				}
				break;
			case Element.a:
				if (auto captures = matchFirst(s, AInlineEndRe)) {
					s = s[captures[0].length..$];
					opened.popBack;
					handler.aInlineEnd;
					continue;
				}
				break;
			default:
			}

			if (auto captures = matchFirst(s, EmStartRe)) {
				s = s[captures[0].length..$];
				opened ~= Element.em;
				handler.emStart();
				continue;
			} else if (auto captures = matchFirst(s, AInlineStartRe)) {
				s = s[captures[0].length..$];
				opened ~= Element.a;
				handler.aInlineStart(escape(captures[1]));
				continue;
			} else if (auto captures = matchFirst(s, ImgRe)) {
				s = s[captures[0].length..$];
				handler.img(escape(captures[1]), escape(captures[2]));
				continue;
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

		assert(elementLevel == opened.length);
		if (!token.empty) {
			handler.text(escape(token.idup));
		}
	}

	void adjustSectionLevel(size_t targetLevel) {
		assert(targetLevel >= 1 && targetLevel <= 6);

		if (baseHeadingLevel == 0) {
			opened ~= Element.section;
			handler.sectionStart();
			baseHeadingLevel = targetLevel;
			return;
		}

		if (targetLevel < baseHeadingLevel) {
			throw new Exception("最初の見出しのレベルより低いレベルの見出しが出現しました。");
		}

		auto sectionLevel = opened.count!((e) => e == Element.section);
		if (targetLevel >= sectionLevel + 2) {
			throw new Exception("見出しのレベルが飛んでいます。");
		}

		assert(sectionLevel + 1 >= targetLevel);
		foreach (i;0..(sectionLevel + 1 - targetLevel)) {
			closeElement(Element.section);
		}
		opened ~= Element.section;
		handler.sectionStart();
	}
}

interface Handler {
	// line head command
	void hStart(int);
	void hEnd(int);

	void ulStart();
	void ulEnd();
	void liInlineStart();
	void liInlineEnd();

	void dlStart();
	void dlEnd();
	void dtStart();
	void dtEnd();
	void ddStart();
	void ddEnd();

	void aBlockStart(string);
	void aBlockEnd();
	void pStart();
	void pEnd();

	// inline command
	void aInlineStart(string);
	void aInlineEnd();
	void img(string, string);
	void emStart();
	void emEnd();

	void text(string);
	void htmlSource(string);

	void sectionStart();
	void sectionEnd();
	void divStart();
	void divStart(string);
	void divEnd();
}

class DefaultHandler : Handler {
	private File outFile;

	public this(ref File outFile) {
		this.outFile = outFile;
	}

	// line head command
	void hStart(int level) {
		outFile.writef("<h%s>", level);
	}
	void hEnd(int level) {
		outFile.writefln("</h%s>", level);
	}

	void ulStart() {
		outFile.writeln("<ul>");
	}
	void ulEnd() {
		outFile.writeln("</ul>");
	}
	void liInlineStart() {
		outFile.write("<li>");
	}
	void liInlineEnd() {
		outFile.writeln("</li>");
	}

	void dlStart() {
		outFile.writeln("<dl>");
	}
	void dlEnd() {
		outFile.writeln("</dl>");
	}
	void dtStart() {
		outFile.write("<dt>");
	}
	void dtEnd() {
		outFile.writeln("</dt>");
	}
	void ddStart() {
		outFile.write("<dd>");
	}
	void ddEnd() {
		outFile.writeln("</dd>");
	}

	void aBlockStart(string url) {
		outFile.writefln(`<a href="%s">`, url);
	}
	void aBlockEnd() {
		outFile.writeln("</a>");
	}
	void pStart() {
		outFile.write("<p>");
	}
	void pEnd() {
		outFile.writeln("</p>");
	}

	// inline command
	void aInlineStart(string url) {
		outFile.writef(`<a href="%s">`, url);
	}
	void aInlineEnd() {
		outFile.write(`</a>`);
	}
	void img(string url, string altText) {
		outFile.writef(`<img src="%s" alt="%s" />`, url, altText);
	}
	void emStart() {
		outFile.write(`<em>`);
	}
	void emEnd() {
		outFile.write(`</em>`);
	}

	void text(string text) {
		outFile.writef("%s", text);
	}
	void htmlSource(string source) {
		outFile.writeln(source);
	}

	void sectionStart() {
		outFile.writeln("<section>");
	}
	void sectionEnd() {
		outFile.writeln("</section>");
	}
	void divStart() {
		outFile.writeln("<div>");
	}
	void divStart(string className) {
		outFile.writefln(`<div class="%s">`, className);
	}
	void divEnd() {
		outFile.writeln("</div>");
	}
}


void main(string[] args) {
	File inFile = stdin, outFile = stdout;

	if (args.length >= 3) {
		inFile = File(args[1], "r");
		outFile = File(args[2], "w");
	}

	auto parser = new Parser(new DefaultHandler(outFile));

	foreach (line;inFile.byLine) {
		parser.parseLine(line.idup);
	}
	parser.close();
}
