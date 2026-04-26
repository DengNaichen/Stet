# Localization (L10n) Strategy

This document outlines the priority and technical strategy for adding new language localizations to Stet. Since Stet relies heavily on Whisper for speech-to-text and AI models (like Apple Intelligence and OpenAI) for transcript refinement, language prioritization is driven by a combination of **technical capability** and **market value**.

## Current State
- **English (`en`)**: Primary development language.
- **Simplified Chinese (`zh-Hans`)**: Fully implemented, serving as the benchmark for non-English closed-loop testing.

## Language Rollout Priorities

### 🥇 Priority 1 (Tier 1): High Market Value & Perfect Technical Synergy
These languages should be prioritized for the next phase of localization.

1. **Japanese (`ja`)**
   - **Why:** The Japanese market shows an exceptionally high willingness to pay for macOS productivity software. Whisper handles Japanese transcription with high accuracy, and major LLMs (including Apple Intelligence) offer top-tier support.
2. **Spanish (`es`)**
   - **Why:** One of the most spoken languages globally, covering massive markets in Europe and the Americas. Whisper and lightweight LLMs handle Spanish almost as efficiently and accurately as English.
3. **Traditional Chinese (`zh-Hant`)**
   - **Why:** High ROI. Since `zh-Hans` is already implemented, mapping the localization to Traditional Chinese is practically free and instantly unlocks high-value markets in Taiwan and Hong Kong.

### 🥈 Priority 2 (Tier 2): Core European Markets
1. **German (`de`) & French (`fr`)**
   - **Why:** These represent the largest software markets in Europe with a huge macOS user base. Apple Intelligence has explicitly announced priority support for French and German in upcoming macOS updates, creating perfect timing for synergy.

### 🥉 Priority 3 (Tier 3): Potential & Opportunistic Markets
1. **Korean (`ko`)**
   - **Why:** A strong tech consumption market, but Whisper's handling of Korean (especially loanwords and specific liaisons) sometimes requires heavier AI post-processing.
2. **Portuguese (`pt-BR`) & Italian (`it`)**
   - **Why:** Excellent for expanding into South America and broader Europe once the core markets are established and generating stable revenue.

---

## Technical Guidelines for Adding a New Language

Adding a new language to Stet goes beyond translating the UI. It requires ensuring the underlying AI pipeline remains robust.

### 1. Automated UI Translation
Do not manually translate UI strings line by line. Since the `Localizable.strings` files have been heavily cleaned up and standardized:
- Create a new `.lproj` folder (e.g., `ja.lproj`).
- Use an LLM (e.g., GPT-4o) via script to read the English or Simplified Chinese `Localizable.strings` and output the translated target file. This ensures perfect format retention.

### 2. AI Prompt Hardening
Stet's rewriting pipeline (e.g., `AppleIntelligenceRewriteService.swift`) relies on strict system prompts to prevent the LLM from trying to act like a chatbot. When extending into multi-language environments:
- **Enforce the "No Translation" rule:** Ensure the `[CRITICAL]` rule strongly specifies that the AI must *only correct typos in the original language* and is explicitly forbidden from translating the user's spoken words into English.
- Example prompt adjustment for global readiness: *"You are an ASR post-processor. You must output in the exact same language the user spoke. DO NOT translate to English under any circumstances."*

### 3. Testing the Pipeline
When a new language is added, verify the end-to-end pipeline:
1. **UI Check:** Open the app with `open ./Stet.app --args -AppleLanguages '({lang-code})'` to verify there are no truncated strings in SwiftUI layouts.
2. **Dictation Check:** Speak a highly colloquial sentence in the target language.
3. **Rewrite Check:** Check the `AppLogger` trace to ensure the Rewrite engine did not trigger an "unsafe" guardrail rejection, and confirm the text was not accidentally translated into English.
