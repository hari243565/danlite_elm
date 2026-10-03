#!/usr/bin/env python3
"""Hindi for the basic tier: a deterministic, vocabulary-driven translation of a standard code title.

Why not one Hindi sentence per title: the standard's titles are built from a small vocabulary (about 740 distinct
words in the included titles). Translating the vocabulary once and composing every title from it means the same
English word is the same Hindi word in every title, and identical English is always identical Hindi.

Files (both in this folder, UTF-8, one entry per line, '#' starts a comment, columns separated by a TAB):
  basic_hi_vocab.tsv    english word or phrase (lower case)  ->  Hindi   (the translation memory; grows in rounds)
  basic_hi_titles.tsv   whole English title (exact)          ->  Hindi   (rare overrides; checked before the vocabulary)

How a title is translated:
  1. an exact entry in basic_hi_titles.tsv wins;
  2. otherwise the title is split into words and punctuation, the longest phrase in the vocabulary is matched at each
     position, single capital letters (sensor A, bus B), numbers and punctuation pass through unchanged, and the
     original spacing is kept;
  3. a few sentence frames reorder the words ("Lost Communication With X" -> "X से संचार टूट गया").
A word with no entry raises Missing(words); the builder lists them (build_basic.py --todo) and nothing is guessed.
"""
import os
import re
import unicodedata

import basic_common as B

TOKEN = re.compile(r"[A-Za-z0-9]+|[–—]|[^\sA-Za-z0-9]")
PASS_THROUGH = re.compile(r"^(?:[A-Za-z]|\d+|[^A-Za-z0-9\s])$")
MAX_PHRASE = 7

# sentence frames: leading words (lower case) -> Hindi template with {x} for the translated remainder
FRAMES = [
    (("lost", "communication", "with"), "{x} से संचार टूट गया"),
    (("invalid", "data", "received", "from"), "{x} से अमान्य डेटा मिला"),
    (("software", "incompatibility", "with"), "{x} के साथ सॉफ़्टवेयर असंगति"),
    (("unable", "to", "engage"), "{x} लगाने में असमर्थ"),
    (("stuck", "in"), "{x} में अटका"),
    (("incorrect", "shift", "from"), "{x} से गलत शिफ़्ट"),
    (("replace",), "{x} बदलें"),
    (("excessive", "time", "to", "enter", "closed", "loop"), "{x}: क्लोज़्ड लूप में प्रवेश में अत्यधिक समय"),
]
# rules for a phrase in the MIDDLE of a title: words before it ({a}) and after it ({b}) are translated separately.
# A trailing "(Bank 1 ...)" group (one that contains letters) stays at the end.
MIDDLE = [
    (("shorted", "to"), "{a} का {b} से शॉर्ट"),
]


class Missing(Exception):
    def __init__(self, words):
        super().__init__("no Hindi for: " + ", ".join(sorted(set(words))))
        self.words = list(words)


def nfc(s):
    return unicodedata.normalize("NFC", s)


def read_tsv(path):
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n").rstrip("\r")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if "\t" not in line:
                raise SystemExit(f"{os.path.basename(path)} line {n}: expected 'english<TAB>hindi'")
            en, hi = line.split("\t", 1)
            en, hi = " ".join(en.strip().split()), nfc(hi.split("\t#")[0].strip())
            key = en if path == B.TITLE_OVERRIDES_HI else en.lower()
            if key in out and out[key] != hi:
                raise SystemExit(f"{os.path.basename(path)} line {n}: {en!r} translated twice with different text")
            out[key] = hi
    return out


def tokens(title):
    """[(text, space_before)] for a title."""
    out = []
    for m in TOKEN.finditer(title):
        out.append((m.group(0), m.start() > 0 and title[m.start() - 1].isspace()))
    return out


class Translator:
    def __init__(self):
        self.vocab = read_tsv(B.VOCAB)
        self.titles = read_tsv(B.TITLE_OVERRIDES_HI)
        self.phrases = {}
        for k, v in self.vocab.items():
            self.phrases[tuple(TOKEN.findall(k))] = v

    def _units(self, toks, missing):
        """Translate a token list to [(hindi, space_before)]."""
        out, i = [], 0
        low = [t[0].lower() for t in toks]
        while i < len(toks):
            hit = None
            for n in range(min(MAX_PHRASE, len(toks) - i), 0, -1):
                key = tuple(low[i:i + n])
                if key in self.phrases:
                    hit = (n, self.phrases[key])
                    break
            if hit:
                out.append((hit[1], toks[i][1]))
                i += hit[0]
                continue
            text = toks[i][0]
            if PASS_THROUGH.match(text):
                out.append((text, toks[i][1]))
            else:
                missing.append(low[i])
                out.append((text, toks[i][1]))
            i += 1
        return out

    @staticmethod
    def _join(units):
        s = ""
        for k, (text, sp) in enumerate(units):
            s += (" " if (sp and k) else "") + text
        return s

    def translate(self, title):
        title = " ".join(title.split())
        if title in self.titles:
            return self.titles[title]
        toks = tokens(title)
        low = tuple(t[0].lower() for t in toks)
        missing = []
        for lead, tmpl in FRAMES:
            if low[:len(lead)] == lead and len(toks) > len(lead):
                rest = self._units(toks[len(lead):], missing)
                if missing:
                    raise Missing(missing)
                return nfc(tmpl.replace("{x}", self._join(rest)))
        for mid, tmpl in MIDDLE:
            hit = self._split_middle(toks, low, mid)
            if hit:
                a, b, tail = hit
                ua, ub = self._units(a, missing), self._units(b, missing)
                ut = self._units(tail, missing)
                if missing:
                    raise Missing(missing)
                text = tmpl.replace("{a}", self._join(ua)).replace("{b}", self._join(ub))
                return nfc(text + ((" " if tail[0][1] else "") + self._join(ut) if tail else ""))
        units = self._units(toks, missing)
        if missing:
            raise Missing(missing)
        return nfc(self._join(units))

    @staticmethod
    def _split_middle(toks, low, mid):
        n = len(mid)
        for i in range(1, len(toks) - n):
            if tuple(low[i:i + n]) == mid:
                rest = toks[i + n:]
                tail = []
                if rest and rest[-1][0] == ")":
                    j = max(k for k, t in enumerate(rest) if t[0] == "(") if any(t[0] == "(" for t in rest) else None
                    if j is not None and any(t[0].isalpha() for t in rest[j:]):
                        tail, rest = rest[j:], rest[:j]
                if rest:
                    return toks[:i], rest, tail
        return None
