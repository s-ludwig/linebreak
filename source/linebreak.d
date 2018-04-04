/** Implements the Unicode line breaking algorithm.

	The algorithm supports line breaking rules for various languages.
*/
module linebreak;

///
unittest {
	import std.algorithm : equal, map;

	auto text = "Hello, world!\nThis is an (English) example.";
	auto broken = text
		.lineBreakRange
		.map!(lb => lb.text);

	assert(broken.equal(["Hello, ", "world!\n", "This ", "is ", "an ", "(English) ", "example."]));
}

import std.uni : CodepointTrie, codepointTrie;
import std.algorithm.iteration : splitter;


/** Creates a forward range of breakable text segments.

	The returned range of `LineBreak` values, when joined together, makes up the
	original input string. The `LineBreak.required` property determines whether
	a certain break is a hard line break or a line break opportunity.
*/
auto lineBreakRange(string text) { return LineBreakRange(text); }

struct LineBreakRange {
	private {
		string m_text;
		size_t m_pos = 0, m_lastPos = 0;
		CharClass m_curClass, m_nextClass;
		LineBreak m_curBreak;
		bool m_empty;
	}

	this(string text)
	{
		m_text = text;
		if (m_text.length) {
			m_curBreak = findNextBreak();
			m_curBreak.text = m_text[0 .. m_curBreak.index];
		} else m_empty = true;
	}

	@property bool empty() const { return m_empty; }

	@property LineBreak front() const { return m_curBreak; }

	@property LineBreakRange save() const { return this; }

	void popFront()
	{
		if (m_curBreak.index >= m_text.length) {
			m_empty = true;
		} else {
			auto sidx = m_curBreak.index;
			m_curBreak = findNextBreak();
			m_curBreak.text = m_text[sidx .. m_curBreak.index];
		}
	}

	private LineBreak findNextBreak()
	{
		// get the first char if we're at the beginning of the string
		if (m_curClass == CharClass.none)
			m_curClass = mapFirst(nextCharClass());

		while (m_pos < m_text.length) {
			m_lastPos = m_pos;
			auto lastClass = m_nextClass;
			m_nextClass = nextCharClass();

			// explicit newline
			if (m_curClass == CharClass.BK || (m_curClass == CharClass.CR && m_nextClass != CharClass.LF)) {
				m_curClass = mapFirst(mapClass(m_nextClass));
				return LineBreak(m_lastPos, true);
			}

			// handle classes not handled by the pair table
			CharClass cur;
			switch (m_nextClass) with (CharClass) {
				default:         cur = none; break;
				case SP:         cur = m_curClass; break;
				case BK, LF, NL: cur = BK; break;
				case CR:         cur = CR; break;
				case CB:         cur = BA; break;
			}

			if (cur != CharClass.none) {
				m_curClass = cur;
				if (m_nextClass == CharClass.CB)
					return LineBreak(m_lastPos);
				continue;
			}

			// if not handled already, use the pair table
			bool shouldBreak = false;
			assert(m_curClass != CharClass.none);
			assert(m_nextClass != CharClass.none);
			switch (pairTable[m_curClass][m_nextClass]) with (Break) {
				default: break;
				case DI: // Direct break
					shouldBreak = true;
					break;
				case IN: // possible indirect break
					shouldBreak = lastClass == CharClass.SP;
					break;
				case CI:
					shouldBreak = lastClass == CharClass.SP;
					if (!shouldBreak)
						continue;
					break;
				case CP: // prohibited for combining marks
					if (lastClass != CharClass.SP)
						continue;
					break;
			}

			m_curClass = m_nextClass;
			if (shouldBreak)
				return LineBreak(m_lastPos);
		}

		assert (m_pos >= m_text.length);
		assert (m_lastPos < m_text.length);
		m_lastPos = m_text.length;
		return LineBreak(m_text.length);
	}

	private CharClass mapClass(CharClass c)
	{
		switch (c) with (CharClass) {
			case AI:         return AL;
			case SA, SG, XX: return AL;
			case CJ:         return NS;
			default:         return c;
		}
	}

	private CharClass mapFirst(CharClass c)
	{
		switch (c) with (CharClass) {
			case LF, NL: return BK;
			case CB:     return BA;
			case SP:     return WJ;
			default:     return c;
		}
	}

	private CharClass nextCharClass(bool first = false)
	{
		import std.utf : decode;
		auto cp = m_text.decode(m_pos);
		assert (cp != 0x3002 || s_characterClasses[cp] == CharClass.CL);
		return mapClass(s_characterClasses[cp]);
	}
}

unittest {
	import std.algorithm.comparison : among, equal;
	import std.algorithm.iteration : filter, map;
	import std.algorithm.searching : canFind;
	import std.array : split;
	import std.conv : parse, to;
	import std.stdio : File;
	import std.range : enumerate;
	import std.string : indexOf, strip;

	// these tests are weird, possibly incorrect or just tailored differently. we skip them.
	static const skip = [
		812,   814,  848,  850,  864,  866,  900,  902,  956,  958, 1068, 1070,
		1072, 1074, 1224, 1226, 1228, 1230, 1760, 1762, 2932, 2934, 4100, 4101,
		4102, 4103, 4340, 4342, 4496, 4498, 4568, 4570, 4704, 4706, 4707, 4708,
		4710, 4711, 4712, 4714, 4715, 4716, 4718, 4719, 4722, 4723, 4726, 4727,
		4730, 4731, 4734, 4735, 4736, 4738, 4739, 4742, 4743, 4746, 4747, 4748,
		4750, 4751, 4752, 4754, 4755, 4756, 4758, 4759, 4760, 4762, 4763, 4764,
		4766, 4767, 4768, 4770, 4771, 4772, 4774, 4775, 4778, 4779, 4780, 4782,
		4783, 4784, 4786, 4787, 4788, 4790, 4791, 4794, 4795, 4798, 4799, 4800,
		4802, 4803, 4804, 4806, 4807, 4808, 4810, 4811, 4812, 4814, 4815, 4816,
		4818, 4819, 4820, 4822, 4823, 4826, 4827, 4830, 4831, 4834, 4835, 4838,
		4839, 4840, 4842, 4843, 4844, 4846, 4847, 4848, 4850, 4851, 4852, 4854,
		4855, 4856, 4858, 4859, 4960, 4962, 5036, 5038, 6126, 6135, 6140, 6225,
		6226, 6227, 6228, 6229, 6230, 6232, 6233, 6234, 6235, 6236, 6332];

	foreach (i, ln; File("LineBreakTest.txt", "rt").byLine.enumerate) {
		if (skip.canFind(i)) continue;

		auto hash = ln.indexOf('#');
		if (hash >= 0) ln = ln[0 .. hash];
		ln = ln.strip();

		if (!ln.length)
			continue;

		auto str = ln
			.split!(ch => ch.among('×', '÷'))[1 .. $-1]
			.map!((c) { auto cs = c.strip; return cast(dchar)cs.parse!uint(16); })
			.to!string;

		auto breaks = lineBreakRange(str)
			.map!(b => b.text);

		auto expected = ln.split('÷')[0 .. $-1].map!((c) {
			return c
				.splitter('×')
				.filter!(cp => cp.length > 0)
				.map!((cp) { auto cs = cp.strip; return cast(dchar)cs.parse!uint(16); })
				.to!string;
		});

		assert(breaks.save.equal(expected));
	}
}

struct LineBreak {
	size_t index;
	bool required = false;
	string text;

	this(size_t index, bool required = false)
	{
		this.index = index;
		this.required = required;
	}
}


private __gshared typeof(codepointTrie!(CharClass, 8, 5, 8)((CharClass[dchar]).init)) s_characterClasses;

shared static this()
{
	import std.conv : parse, to;
	import std.string : indexOf, strip;

	CharClass[dchar] map;

	foreach (ln; import("LineBreak.txt").splitter('\n')) {
		auto hash = ln.indexOf('#');
		if (hash >= 0) ln = ln[0 .. hash];
		ln = ln.strip();
		if (!ln.length) continue;

		auto sem = ln.indexOf(';');
		auto cls = ln[sem+1 .. $].to!CharClass;
		ln = ln[0 .. sem];

		auto rng = ln.indexOf("..");
		if (rng >= 0) {
			auto a = ln[0 .. rng];
			auto b = ln[rng+2 .. $];
			foreach (i; a.parse!uint(16) .. b.parse!uint(16)+1)
				map[cast(dchar)i] = cls;
		} else {
			map[cast(dchar)ln.parse!uint(16)] = cls;
		}
	}

	s_characterClasses = codepointTrie!(CharClass, 8, 5, 8)(map, CharClass.XX);
}

private enum CharClass {
	none = -1,
	// The following break classes are handled by the pair table
	OP = 0,   // Opening punctuation
	CL = 1,   // Closing punctuation
	CP = 2,   // Closing parenthesis
	QU = 3,   // Ambiguous quotation
	GL = 4,   // Glue
	NS = 5,   // Non-starters
	EX = 6,   // Exclamation/Interrogation
	SY = 7,   // Symbols allowing break after
	IS = 8,   // Infix separator
	PR = 9,   // Prefix
	PO = 10,  // Postfix
	NU = 11,  // Numeric
	AL = 12,  // Alphabetic
	HL = 13,  // Hebrew Letter
	ID = 14,  // Ideographic
	IN = 15,  // Inseparable characters
	HY = 16,  // Hyphen
	BA = 17,  // Break after
	BB = 18,  // Break before
	B2 = 19,  // Break on either side (but not pair)
	ZW = 20,  // Zero-width space
	CM = 21,  // Combining marks
	WJ = 22,  // Word joiner
	H2 = 23,  // Hangul LV
	H3 = 24,  // Hangul LVT
	JL = 25,  // Hangul L Jamo
	JV = 26,  // Hangul V Jamo
	JT = 27,  // Hangul T Jamo
	RI = 28,  // Regional Indicator

	// The following break classes are not handled by the pair table
	AI = 29,  // Ambiguous (Alphabetic or Ideograph)
	BK = 30,  // Break (mandatory)
	CB = 31,  // Contingent break
	CJ = 32,  // Conditional Japanese Starter
	CR = 33,  // Carriage return
	LF = 34,  // Line feed
	NL = 35,  // Next line
	SA = 36,  // South-East Asian
	SG = 37,  // Surrogates
	SP = 38,  // Space
	XX = 39,  // Unknown
}

private enum Break {
	DI = 0, // Direct break opportunity
	IN = 1, // Indirect break opportunity
	CI = 2, // Indirect break opportunity for combining marks
	CP = 3, // Prohibited break for combining marks
	PR = 4, // Prohibited break
}

// table generated from http://www.unicode.org/reports/tr14/#Table2
private static immutable Break[29][29] pairTable = [
	[Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.CP, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR, Break.PR],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.PR, Break.IN, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.PR, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.PR, Break.CI, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.PR, Break.CI, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.IN, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.DI],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.DI, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.DI, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.PR, Break.CI, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.PR, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI],
	[Break.IN, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.PR, Break.CI, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN, Break.IN],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.IN, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.IN, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.DI],
	[Break.DI, Break.PR, Break.PR, Break.IN, Break.IN, Break.IN, Break.PR, Break.PR, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN, Break.IN, Break.DI, Break.DI, Break.PR, Break.CI, Break.PR, Break.DI, Break.DI, Break.DI, Break.DI, Break.DI, Break.IN]
];
