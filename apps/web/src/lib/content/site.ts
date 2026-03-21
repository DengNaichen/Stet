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
    links: [] satisfies NavLink[],
    ctaLabel: "Download",
    ctaHref: downloadHref,
  },
  hero: {
    eyebrow: "",
    title: "Transcribe, don't transform.",
    primaryCtaLabel: "Download",
    primaryCtaHref: downloadHref,
    secondaryCtaLabel: "View on GitHub",
    secondaryCtaHref: githubHref,
    mockWindows: [
      {
        title: "Voice (Source)",
        lines: [
          "> stet is like... it's a Mac app",
          "> umm it transcribes u",
          "> but its not like... it doesn't",
          "> rewrite u know?",
          "> u keep ur own voice"
        ]
      },
      {
        title: "Stet (The Edit)",
        lines: [
          "> Stet is like... it's a Mac app.",
          "> It transcribes you,",
          "> but it's not like...",
          "> it doesn't rewrite, you know?",
          "> You keep your own voice."
        ]
      },
      {
        title: "Others (The Rewrite)",
        lines: [
          "> Stet is a macOS application",
          "> designed for transcription.",
          "> It maintains original intent",
          "> while improving readability",
          "> and ensuring professional tone."
        ]
      }
    ],
  },
  workflow: {
    title: "Of course it's fast. But",
    copy: "speed isn't the goal, Human's are. We don't let AI rewrite you, giving you the space to slow down and decide for every sentence: Stet, let it stand.",
  },
  pricing: {
    title: "Simple Pricing",
    plans: [
      {
        name: "Bring Your Own Key",
        price: "Free",
        description: "Stays local. You just pay your own LLM provider.",
        features: ["Fully open source", "Use your own API keys", "No intermediate servers"]
      },
      {
        name: "Cloud Managed",
        price: "Pay as you go",
        description: "No subscription required. Pay only for what you actually use.",
        features: ["1,000 free credits to start", "We process, but never store", "Transcripts live on your Mac"]
      }
    ]
  },
  privacy: {
    title: "Your dictionary stays yours",
    body: "Export your custom words and preferred terms. Open source and BYOK keep the rest of the stack understandable too.",
    panelLabel: "Keep control",
    points: ["Export your dictionary.", "Open source.", "Bring your own key."],
  },
  cta: {
    title: "Stet: Let it stand.",
    body: "The native transcription experience that preserves your authentic character.",
    primaryCtaLabel: "Download Stet for Mac",
    primaryCtaHref: downloadHref,
  },
  footer: {
    copy: "Stet is Mac-native speech to text with minimal edits.",
  },
};
