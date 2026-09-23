---
name: media-validator
description: Validates media files (MP4, PNG, TXT) by running OCR, metadata checks, and pattern matching against expected content, returning PASS/FAIL with captured evidence. Use when a task needs to verify a recording, screenshot, or text-evidence file actually contains an expected pattern before a PASS is claimed — the §11.4.107/§11.4.163 anti-bluff media-validation oracle.
version: 1.0.0
---

# Media Validator Skill

## Purpose
Validates media files (MP4, PNG, TXT) by running OCR, metadata checks, and pattern matching against expected content. Returns PASS/FAIL with evidence.

## Usage
```bash
bash skills/media-validator/media-validator.sh <file> [expected-pattern...]
```

## Inputs
- `file` — path to an MP4, PNG, or TXT file
- `expected-pattern` — one or more grep/extended regex patterns expected in the extracted text

## Outputs
- stdout: `PASS: <description> [evidence: <path>]` or `FAIL: <reason>`
- Evidence file at `qa-results/media-validator/<timestamp>-<basename>/`
- Exit 0 on PASS, 1 on FAIL, 2 on SKIP

## Dependencies
- `tesseract` (optional — for OCR on images/video frames)
- `ffmpeg` (optional — for frame extraction from MP4)
- `ffprobe` (optional — for video metadata)
- `file` (for MIME detection)

## Cross-references
- constitution/Constitution.md §11.4.107 (liveness evidence)
- constitution/Constitution.md §11.4.117 (CV/OCR pixel oracle)
- constitution/Constitution.md §11.4.137 (subtitle correctness)
- constitution/Constitution.md §11.4.69 (sink-side evidence taxonomy)
