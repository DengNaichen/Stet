export type NavLink = {
  label: string;
  href: string;
};

export type WorkflowCard = {
  eyebrow: string;
  title: string;
  copy: string;
  accent: "orange" | "gold" | "ink";
};

const githubHref = "https://github.com/OpenWhispr/openwhispr";
const downloadHref = `${githubHref}/releases/latest`;

export const siteContent = {
  nav: {
    brand: "Stet",
    links: [
      { label: "Minimal edits", href: "#workflow" },
      { label: "Ownership", href: "#privacy" },
    ] satisfies NavLink[],
    ctaLabel: "Download",
    ctaHref: downloadHref,
  },
  hero: {
    eyebrow: "Mac-native transcription",
    title: "Speech to text for Mac, with minimal edits.",
    body: "Stet keeps your wording, lightly cleans up transcripts, and lets you export your personal dictionary.",
    primaryCtaLabel: "Download",
    primaryCtaHref: downloadHref,
    secondaryCtaLabel: "View on GitHub",
    secondaryCtaHref: githubHref,
    highlights: [
      "Keeps your wording",
      "Light cleanup only",
      "Export your dictionary",
    ],
    mockWindowTitle: "Minimal edits",
    mockLines: [
      "> transcript: close to source",
      "> cleanup: punctuation + caps",
      "> rewrite: only on request",
      "> dictionary: yours to export",
      "> workflow: menu bar -> paste",
    ],
  },
  workflow: {
    eyebrow: "Minimal edits",
    title: "Transcribe, don't rewrite",
    copy: "Most tools improve text by changing more. Stet improves it by changing less. It is built to preserve the words you meant, while making only the smallest useful corrections.",
    cards: [
      {
        eyebrow: "Keep your wording",
        title: "Stet stays close to what you said.",
        copy: "It stays close to your original phrasing instead of rewriting it into something generic.",
        accent: "orange",
      },
      {
        eyebrow: "Light cleanup only",
        title: "Fix the obvious parts, not the whole sentence.",
        copy: "It fixes punctuation, capitalization, and obvious recognition errors without over-editing the sentence.",
        accent: "gold",
      },
      {
        eyebrow: "Revise only when asked",
        title: "Polish stays optional.",
        copy: "Rewriting, polishing, and translation are available when you want them, not forced into the default flow.",
        accent: "ink",
      },
    ] satisfies WorkflowCard[],
  },
  privacy: {
    eyebrow: "Ownership",
    title: "Your dictionary stays yours",
    body: "Export your custom words and preferred terms. Open source and BYOK keep the rest of the stack understandable too.",
    panelLabel: "Keep control",
    points: ["Export your dictionary.", "Open source.", "Bring your own key."],
  },
  cta: {
    eyebrow: "Mac-native transcription",
    title: "Keep your words.",
    body: "Speech to text for Mac, with minimal edits.",
    primaryLabel: "Download",
    primaryHref: downloadHref,
    secondaryLabel: "View on GitHub",
    secondaryHref: githubHref,
  },
  footer: {
    copy: "Stet is Mac-native speech to text with minimal edits.",
  },
};
