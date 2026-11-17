#!/usr/bin/env python3
"""falseref14.py <gate> <table> - false-refusal measurement for R13-2 (round 14). A fixed list of real given names and
surnames (Latin, Cyrillic, Greek; built here, no personal data) is written in three spellings each (as listed, all
lower case, ALL CAPS). A pair of DIFFERENT names (different casefold) is a false refusal when the relation calls them
the same person. Reported for the round-13 relation (f) and the round-14 relation (f or e), with every pair the
round-14 relation adds. Deterministic (no randomness)."""
import os, sys, itertools, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gatefns14 as GF
ns = GF.load(sys.argv[1], sys.argv[2]); f, e = ns['f'], ns['e']   # the gate's own functions, loaded verbatim
G = """Aaron Abel Ada Adam Adrian Agnes Ahmed Aida Aiko Al Alan Alba Albert Alec Alex Alexa Ali Alice Alina Alla Allan Alma
Alva Amir Amy Ana Anil Anna Anne Anton Ari Ariel Arne Arno Arvid Asa Ava Axel Aya Ayla Bea Bela Ben Berit Bill Birgit Bo Boris
Brian Bruno Cara Carl Carla Carlo Cecil Chen Chloe Clara Clio Cole Dan Dana Daniel Dara Dave David Dean Dima Dina Dirk Dora
Ed Edda Eden Edith Ela Eli Elia Elin Elisa Ella Elle Ellen Elli Elly Elsa Emil Emily Ema Enzo Erik Erin Eva Evan Ewa Ezra Fil
Filip Finn Fiona Ida Igor Ike Ila Ilan Ilia Ilja Ilka Illa Ilona Ilse Ilya Imke Imre Ina Inge Ines Ingo Iola Ira Iris Irma
Isa Isak Ivan Ivo Iza Jan Jana Jill Joel Jon Kai Kaj Kim Kira Klaus Lale Lana Lars Lea Lean Lee Lena Leni Leo Leon Li Lia Lian
Lila Lili Lilli Lin Lina Linn Lisa Liv Liz Lola Lou Luca Lucy Luis Luka Lulu Mai Maia Mali Mara Marie Mark Max Mia Mila Milan
Milo Milos Mina Mira Nia Nik Nils Nina Noa Noel Ola Olaf Ole Olga Oli Olli Omar Ora Oscar Paul Pia Rafael Rani Ria Rik Rina
Rita Sam Sara Sela Silas Sila Sven Tia Tim Tina Toni Ulla Ulli Uri Vera Vic Vida Vil Vili Will Willi Yan Ylva Yuri Zeli Zia
Zoe Illi Lilia Ilina Lilo Iljana Niels Neil Nell Bill Bil Gil Gill Jil Phil Lill Ille Iles Iley Lile Iris Liris Lola Iola
Novak Vasic Ilic Lilic Ilies Lillie Kim Kirn Arne Ame Vern Vem Anna Arma Dima Dirna Erin Enn Ola""".split()
C = "Иван Илья Лиля Ольга Анна Алла Нина Мила Милош Васић Ира Ила".split()
E = "Ηλίας Ίλια Λίλα Άννα Ιάσων Ίρις".split()
names = sorted(set(G + C + E))
sp = sorted({v for n in names for v in (n, n.lower(), n.upper())})
pairs = [(x, y) for x, y in itertools.combinations(sp, 2) if x.casefold() != y.casefold()]
o = [p for p in pairs if f(p[0]) == f(p[1])]
n = [p for p in pairs if f(p[0]) == f(p[1]) or e(p[0]) == e(p[1])]
add = sorted(set(n) - set(o)); gone = sorted(set(o) - set(n))
print('names %d, spellings %d, pairs of different names %d' % (len(names), len(sp), len(pairs)))
print('refused as the same person: round-13 relation %d, round-14 relation %d (added %d, removed %d)' % (len(o), len(n), len(add), len(gone)))
d = lambda ps: len({frozenset((x.casefold(), y.casefold())) for x, y in ps})
tot = len({frozenset((x.casefold(), y.casefold())) for x, y in pairs})
print('distinct name pairs (by casefold): total %d; refused round-13 %d, round-14 %d (adds %d = %.4f%% of all name pairs)' % (
    tot, d(o), d(n), d(add), 100.0 * d(add) / tot))
for x, y in add: print('  added  %-10s %-10s' % (x, y))
for x, y in o: print('  round13 %-10s %-10s' % (x, y))
