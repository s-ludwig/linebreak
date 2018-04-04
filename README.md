Unicode line breaking algorithm
===============================

This implements the Unicode line breaking algorithm from
[annex 14](http://www.unicode.org/reports/tr14/). The currently implemented
version is based on the Unicode 7.0.0 standard and uses the table based
approximate algorithm.

Citing from the standard:

> Line breaking, also known as word wrapping, is the process of breaking a
> section of text into lines such that it will fit in the available width of a
> page, window or other display area. The Unicode Line Breaking Algorithm
> performs part of this process. Given an input text, it produces a set of
> positions called "break opportunities" that are appropriate points to begin a
> new line. The selection of actual line break positions from the set of break
> opportunities is not covered by the Unicode Line Breaking Algorithm, but is in
> the domain of higher level software with knowledge of the available width and
> the display size of the text.

This library has been ported from the CoffeScript implementation by
Devon Govett: [linebreak](https://github.com/devongovett/linebreak)

[![Build Status](https://travis-ci.org/s-ludwig/linebreak.svg?branch=master)](https://travis-ci.org/s-ludwig/linebreak)
