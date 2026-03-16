<script lang="ts">
	let {
		eyebrow,
		title,
		body,
		primaryCtaLabel,
		primaryCtaHref,
		secondaryCtaLabel,
		secondaryCtaHref,
		highlights,
		mockWindowTitle,
		mockLines
	}: {
		eyebrow: string;
		title: string;
		body: string;
		primaryCtaLabel: string;
		primaryCtaHref: string;
		secondaryCtaLabel: string;
		secondaryCtaHref: string;
		highlights: string[];
		mockWindowTitle: string;
		mockLines: string[];
	} = $props();
</script>

<section
	class="mx-auto grid w-[min(1180px,calc(100vw-48px))] gap-10 px-0 py-20 md:grid-cols-[1.08fr_0.92fr] md:items-center md:pt-24"
	id="top"
>
	<div>
		<p class="mb-3 text-[0.82rem] font-bold uppercase tracking-[0.12em] text-accent">{eyebrow}</p>
		<h1 class="hero-title mb-5 max-w-[13ch] font-semibold">{title}</h1>
		<p class="max-w-[65ch] text-[1.08rem] leading-[1.78] text-muted">{body}</p>

		<div class="mt-8 flex flex-wrap gap-3.5">
			<a
				class="inline-flex items-center justify-center rounded-full bg-linear-to-br from-accent to-[#f57a3e] px-5 py-4 text-[0.95rem] font-bold text-white shadow-[0_12px_24px_rgba(240,81,56,0.18)] hover:-translate-y-px"
				href={primaryCtaHref}>{primaryCtaLabel}</a
			>
			<a
				class="frost-chip inline-flex items-center justify-center rounded-full border border-border px-5 py-4 text-[0.95rem] font-bold text-ink hover:-translate-y-px"
				href={secondaryCtaHref}>{secondaryCtaLabel}</a
			>
		</div>

		<ul class="mt-8 flex flex-wrap gap-3" aria-label="Key highlights">
			{#each highlights as highlight}
				<li class="frost-chip rounded-full border border-border px-4 py-2 text-sm font-medium text-muted">
					{highlight}
				</li>
			{/each}
		</ul>
	</div>

	<div class="hero-art" aria-hidden="true">
		<div class="hero-glow hero-glow-orange"></div>
		<div class="hero-glow hero-glow-gold"></div>
		<div class="mock-window">
			<div class="mock-window-bar">
				<div class="mock-dots">
					<span></span>
					<span></span>
					<span></span>
				</div>
				<span>{mockWindowTitle}</span>
			</div>
			<div class="mock-window-body">
				{#each mockLines as line}
					<div>{line}</div>
				{/each}
			</div>
		</div>
		<div class="swift-swoop swift-swoop-top"></div>
		<div class="swift-swoop swift-swoop-bottom"></div>
	</div>
</section>
