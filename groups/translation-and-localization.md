# Translation And Localization

### §11.4.237 — Mandatory exhaustive context-and-spirit-aware translation review: every localized artifact independently reviewed for CONTEXT (source) + SPIRIT (target-language idiom/register) + technical/non-translatable fidelity — accuracy necessary, never sufficient (operator mandate, 2026-08-05)

**Forensic anchor (operator mandate, 2026-08-05):** a translated artifact that is merely ACCURATE — every source token faithfully rendered — can still read as stilted, foreign, machine-literal, register-wrong, or idiom-broken to a native speaker of the target language, and a localization pass that silently mangles a technical term or "translates" a non-translatable product/proper name ships a defect worse than untranslated text; the recurring failure mode is a translation that scores green on an accuracy check while a native reader immediately perceives it as non-native. Accuracy is NECESSARY; it is NOT SUFFICIENT for a slick, polished, professional localization.

The mandate (ALL hold):

**(A) EVERY LOCALIZED ARTIFACT IS INDEPENDENTLY REVIEWED — NEVER SELF-REVIEWED.** Every translation and every translated artifact — UI strings, pages, documents, PDFs, manuals, marketing copy, captions/subtitles, help text, any localized content — MUST undergo a HEAVY, EXHAUSTIVE, independent review by a reviewer (agent or human) STRUCTURALLY SEPARATE from the translator that produced it (§11.4.70/§11.4.20 independence). The translator's own pass (§11.4.92 multi-pass self-review) PRECEDES this review and NEVER satisfies it (§11.4.142's no-self-review-substitution discipline applied to localization; §11.4.92 precedes, never satisfies). A localized artifact accepted without an independent context-and-spirit review is a §11.4 PASS-bluff at the localization layer.

**(B) THE REVIEWER HOLDS AND APPLIES THREE DIMENSIONS.** (a) FULL CONTEXT OF THE SOURCE MATERIAL — the original ideas, the subject/domain, the purpose, and the intended audience; the reviewer reads the source MEANING, not merely the source STRING, so intent, nuance, and tone are carried across, never lost. (b) THE SPIRIT OF THE TARGET LANGUAGE — its tradition, idiom, register, tone, and cultural conventions — so the result reads as NATIVE, natural, fluent, and MAXIMALLY POLISHED, never literal / word-for-word / calqued; a construction correct in the source that reads foreign in the target is REWRITTEN into the natural target-language form. (c) CORRECT TECHNICAL VOCABULARY AND VERBATIM PRESERVATION OF NON-TRANSLATABLE TERMS — domain/technical terms rendered with their established target-language equivalents, and NON-TRANSLATABLE tokens (product names, brand names, proper nouns, technology/library/API names, code identifiers, trademarks) preserved VERBATIM — never "translated", never accidentally transliterated, never localized away.

**(C) THE GOAL IS MAXIMALLY POLISHED LOCALIZATION — ACCURACY NECESSARY, NEVER SUFFICIENT.** The bar is a slick, polished, professional, native-reading localization; fidelity to the source is the FLOOR, not the ceiling. A rendering that is accurate but stilted / foreign / register-wrong / idiom-broken is a FINDING, not a pass.

**(D) ANTI-BLUFF — CAPTURED MACHINE-READABLE POSITIVE EVIDENCE + FAIL-LOOPS-TO-CLEAN.** The review emits captured, machine-readable POSITIVE evidence per §11.4.5/§11.4.69 (`feature_class` = translation_review): a per-artifact verdict carrying a PER-DIMENSION rationale across the closed dimension set {fidelity, fluency/naturalness, spirit/register, terminology, completeness, non-translatable-preservation} — a PASS with no captured per-dimension rationale is a §11.4/§11.4.1 bluff. A FAIL on ANY dimension LOOPS BACK to re-translation/polish and re-review, iterating to a zero-finding clean verdict per §11.4.134 — a single pass that "looked fine" never closes the artifact.

**Honest boundary (§11.4.6).** This anchor REFINES the existing localization discipline from PASS/FAIL accuracy checking to CONTEXT-AND-SPIRIT native-polish review; it does NOT replace §11.4.140's canonical translation pipeline (the HelixTranslate-canonical-translation-pipeline sense of that anchor number) nor §11.4.141's independent per-language review (the independent-per-language-translation-review sense of that anchor number — a KNOWN operator-owned §11.4.54 anchor-number collision on `11.4.140`/`11.4.141`, re-mint still operator-owned; cited here strictly in those senses, introducing no new collision), it STRENGTHENS them (accuracy → native polish). It does not make a mistranslation impossible (a miscalibrated reviewer stays §11.4.107(10) golden-good/golden-bad fixture territory), and where a target language genuinely has no established term for a source concept, that gap is an honestly recorded finding (§11.4.3 SKIP-with-reason), never a silently invented word.

Classification: universal (§11.4.17) — no vendor/project/language literal; the consuming project supplies its language set, term glossary, non-translatable token list, and reviewer substrate as DATA per §11.4.35. Composes §11.4.140 (canonical translation pipeline) / §11.4.141 (independent per-language translation review — this REFINES it from PASS/FAIL accuracy to context+spirit polish) / §11.4.6 / §11.4.69 / §11.4.92 / §11.4.134 / §11.4.142 / §11.4.209 / §1.1. Propagation gate `CM-COVENANT-114-237-PROPAGATION` (literal `11.4.237`) + recommended gate `CM-TRANSLATION-CONTEXT-SPIRIT-REVIEW` (every localized artifact carries an independent per-dimension context-and-spirit review verdict with captured rationale across {fidelity, fluency/naturalness, spirit/register, terminology, completeness, non-translatable-preservation}, FAIL looping to re-review per §11.4.134) + paired §1.1 mutation (a translation accepted on an accuracy-only check, OR self-reviewed by its own translator, OR carrying a golden-bad-seeded mistranslated idiom / a "translated" non-translatable product name → the gate FAILs; strip the literal → the propagation gate FAILs; gate-code = separate work item, NOT claimed shipped §11.4.6/§11.4.227).

**Canonical authority:** constitution submodule [`Constitution.md`](Constitution.md) §11.4.237.

Non-compliance is a release blocker regardless of context. No escape hatch — no `--skip-spirit-review`, `--accuracy-only-OK`, `--self-review-translation-OK`, `--literal-translation-OK`, `--translate-non-translatable-OK`, `--skip-per-dimension-rationale` flag exists.

### §11.4.255 — Mandatory HelixTranslate canonical translation pipeline (User mandate, 2026-06-25)

**Forensic anchor — verbatim user mandate (2026-06-25):** "Every project that inherits this constitution MUST use HelixTranslate (git@github.com:HelixDevelopment/HelixTranslate.git) — via a universal, reusable pipeline — to generate ANY translations it needs. This is a hard rule/constraint."

ALL translations of ANY content — UI strings, documents, articles, CVs, READMEs, marketing copy, in-app messages, release notes, legal text, ANY human-language string rendered in a non-source language — MUST be produced by **HelixTranslate** (`git@github.com:HelixDevelopment/HelixTranslate.git`) driven through the **canonical universal translation pipeline** shipped in this submodule at `scripts/translation/` (`translate-pipeline.sh` + `render-articles.sh`). This is a hard, non-negotiable constraint.

The following are FORBIDDEN and constitute a §11.4.255 violation:

(a) **Hand-translation** — no human-authored, manually edited, or "good enough" hand-written translation of any content, ever. The engine is the single source of every translated string.

(b) **Other engines** — no Google Translate, DeepL, raw ChatGPT/Claude prompting, OS translation APIs, library i18n auto-translators, or any engine other than HelixTranslate's `unified-translator`. There is exactly one engine.

(c) **Silent fallback** — no quiet substitution of the source string, no empty/partial output passed off as a translation, no swallowed engine error, no "absence-of-error" PASS (§11.4 / §11.4.1). On exhaustion of all configured providers the pipeline MUST FAIL LOUD (non-zero exit, destination NOT written) so the caller detects it; a missing translation is a hard error, never a degraded-but-shipped string. Provider-to-provider failover WITHIN HelixTranslate (primary → fallback, with logged, evidenced retries) is NOT a silent fallback and is permitted; falling back to ANY non-HelixTranslate source is forbidden.

**Mandatory validation.** Every generated translation MUST be validated for accuracy with real (physical) captured evidence per §11.4.5 / §11.4.69 / §11.4.107 — no metadata-only / config-only / grep-without-runtime PASS (§11.4 / §11.4.1), no false results, no bluff of any kind (§11.4.6). The per-file run log (provider used, byte counts, retries, success/failure) is the evidence artifact; an unvalidated or unevidenced translation is treated as ABSENT.

**Explicit provider routing.** Provider + model routing MUST be explicit and recorded — never implicit/defaulted-in-the-dark. The canonical routing is provider `groq` / model `llama-3.3-70b-versatile` with documented failover to provider `mistral` / model `mistral-large-latest`; the provider that actually produced each output MUST be recorded in the per-file log. Any deviation from the canonical routing MUST be stated explicitly in configuration and logged.

**Canonical pipeline location.** `scripts/translation/translate-pipeline.sh` (universal Markdown / plain-text + article-frontmatter-preserving translator) and `scripts/translation/render-articles.sh` (article-source → HTML fragment renderer). Both are reusable verbatim across projects; the engine binary is supplied by the consuming project via `HELIX_TRANSLATE_BIN` and built from the HelixTranslate repository.

Classification: universal (§11.4.17) — a platform-neutral, language-neutral translation discipline reusable by ANY project; the consuming project supplies its concrete source files, target languages, and the HelixTranslate engine build per §11.4.35. Composes §11.4 / §11.4.1 / §11.4.5 / §11.4.6 / §11.4.7 / §11.4.69 / §11.4.107. Propagation gate `CM-COVENANT-114-255-PROPAGATION` (literal `11.4.255`) + recommended gate `CM-MANDATORY-HELIXTRANSLATE-PIPELINE` + paired §1.1 meta-test mutation (gate-code = separate work item).

**Rationale.** A single, evidenced, fail-loud translation engine guarantees that every translated string in the fleet has a known provenance, a reproducible pipeline, and a captured accuracy proof — eliminating the silent drift, inconsistent quality, and untraceable "where did this string come from" failures that hand-translation and ad-hoc engines produce. One engine, one pipeline, one evidence trail.

**Canonical authority:** this Constitution.md §11.4.255 in the HelixConstitution submodule. All consuming projects restate + cite via §11.4.35 inheritance.

Non-compliance is a release blocker regardless of context. No escape hatch — no `--allow-hand-translation`, `--other-engine-OK`, `--skip-translation-validation`, `--silent-fallback` flag exists.

---

### §11.4.256 — Mandatory independent per-language translation review (User mandate, 2026-06-25)

**Forensic anchor — verbatim user mandate (2026-06-25):** "Quality of translations for all languages MUST BE ALWAYS properly checked and reviewed! We MUST CREATE independent, specialized translations review agents for all languages we support which will be performing full testing, review, validation and verification for all translated content! This MUST BE mandatory part of our root constitution (Submodule) and followed as mandatory constraint / rule by this and all our projects implementing the constitution Submodule."

Every translated artifact produced under §11.4.255 MUST, before it is shipped / committed / deployed, be INDEPENDENTLY REVIEWED for quality by a per-language review agent. This is a hard, non-negotiable gate that composes with — and never replaces — the §11.4.255 generation mandate.

Requirements:

(a) **Independence.** The reviewer MUST be a different model/provider than the one that produced the translation (e.g. translator `mistral/mistral-large-latest` → reviewer `groq/llama-3.3-70b-versatile`, or any distinct verified model). A model reviewing its own output is NOT an independent review and is forbidden.

(b) **Per-language specialization.** The reviewer MUST act as a NATIVE speaker / linguistic reviewer of the SPECIFIC target language, evaluating that language's grammar, orthography, and correct script (Cyrillic for ru/be/kk, Arabic for ar/fa, Han/Kana/Hangul/Devanagari for zh/ja/ko/hi, Latin for sr/de/es/fr/tr, etc.).

(c) **Full criteria.** Each review MUST judge: accuracy/fidelity, fluency/naturalness, completeness (nothing omitted or invented), correct script & orthography, and absence of untranslated source leftovers (proper nouns / URLs / code excepted).

(d) **Strict machine-readable verdict + evidence.** Each review MUST emit a structured PASS/FAIL verdict with per-criterion scores and an issues list, persisted as a physical evidence artifact (§11.4.5 / §11.4.69 / §11.4.107). A FAIL — or an ERROR / unavailable-reviewer — BLOCKS the content; only a real PASS may ship. No metadata-only / absence-of-error PASS (§11.4 / §11.4.1); no bluff (§11.4.6).

(e) **Remediation loop.** A FAIL routes the artifact back through the §11.4.255 pipeline (re-translate / multipass-polish) and is re-reviewed, iterating until PASS — never hand-patched to pass (hand-translation remains forbidden under §11.4.255).

**Canonical tooling.** `scripts/translation/review-translations.sh` (per-language review driver) + `scripts/translation/review_translation.py` (independent reviewer engine emitting strict JSON verdicts). Reusable verbatim across projects; the consuming project supplies its source/translation file pairs and a reviewer provider DISTINCT from its translator.

Classification: universal (§11.4.17) — a platform-neutral, language-neutral translation-quality-assurance discipline reusable by ANY project that ships translated content; composes §11.4.255 (the translation it gates) / §11.4 / §11.4.1 / §11.4.5 / §11.4.6 / §11.4.69 / §11.4.107 / §11.4.134 (rock-solid evidence). Propagation gate `CM-COVENANT-114-256-PROPAGATION` (literal `11.4.256`) + recommended gate `CM-MANDATORY-TRANSLATION-REVIEW` + paired §1.1 meta-test mutation (gate-code = separate work item).

**Rationale.** §11.4.255 guarantees a translation's provenance and a fail-loud pipeline, but not its linguistic quality. An independent, native-level, per-language reviewer with a captured PASS/FAIL verdict is what turns "a string was produced" into "a string was verified correct" — making translation quality an auditable fact rather than an assumption.

**Canonical authority:** this Constitution.md §11.4.256 in the HelixConstitution submodule. All consuming projects restate + cite via §11.4.35 inheritance.

Non-compliance is a release blocker regardless of context. No escape hatch — no `--skip-translation-review`, `--self-review-OK`, `--accept-unreviewed-translation` flag exists.

---

