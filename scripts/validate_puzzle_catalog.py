#!/usr/bin/env python3
"""Read-only validation of literal puzzle data. Does NOT execute Swift logic."""
import ast
import re
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / 'Sources/SmartWakeCore/WakeGames.swift').read_text()
def collection(name):
    match = re.search(r'private static let ' + name + r':[^=]+?= (\[.*?\n    \])', source, re.S)
    assert match, f'Missing literal catalog: {name}'
    return ast.literal_eval(match.group(1))
def letters(value):
    return bool(re.fullmatch('[A-Z]+', value))
words = collection('words')
assert len({word for word, _ in words}) == len(words)
assert all(len(word) == 5 and letters(word) and clue for word, clue in words)
groups = collection('groupPairs')
for title1, first, title2, second in groups:
    assert title1 and title2 and title1 != title2
    assert len(first) == len(second) == 4
    assert len(set(first + second)) == 8
    assert all(letters(word) for word in first + second)
minis = collection('miniCrosswords')
for down, top, middle, bottom in minis:
    assert len(down[0]) == 5
    assert all(len(entry[0]) == 3 for entry in [top, middle, bottom])
    assert all(letters(answer) and clue for answer, clue in [down, top, middle, bottom])
    assert top[0][1] == down[0][0]
    assert middle[0][1] == down[0][2]
    assert bottom[0][1] == down[0][4]
print(f'PASS: literal catalog has {len(words)} unique five-letter words, {len(groups)} valid eight-tile boards, and {len(minis)} consistent intersecting mini crosswords.')
print('This checks source data only. Swift compilation, XCTest execution, UI and device behavior are NOT covered.')
