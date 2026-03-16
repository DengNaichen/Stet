<script lang="ts">
	let {
		eyebrow,
		title,
		body,
		primaryLabel,
		primaryHref,
		secondaryLabel,
		secondaryHref
	}: {
		eyebrow: string;
		title: string;
		body: string;
		primaryLabel: string;
		primaryHref: string;
		secondaryLabel: string;
		secondaryHref?: string;
	} = $props();
</script>

<section class="mx-auto w-[min(1180px,calc(100vw-48px))] py-18" id="cta">
	<div class="cta-card frost-panel rounded-[36px] border border-border p-8 md:p-10">
		<p class="mb-3 text-[0.82rem] font-bold uppercase tracking-[0.12em] text-accent">{eyebrow}</p>
		<h2 class="mb-4 font-semibold">{title}</h2>
		<p class="max-w-[60ch] text-[1.03rem] leading-7 text-muted md:leading-[1.75]">{body}</p>

		<div class="mt-8 flex flex-wrap items-center gap-4">
			<a
				class="inline-flex items-center justify-center rounded-full bg-linear-to-br from-accent to-[#f57a3e] px-5 py-4 text-[0.95rem] font-bold text-white shadow-[0_12px_24px_rgba(240,81,56,0.18)] hover:-translate-y-px"
				href={primaryHref}>{primaryLabel}</a
			>
			{#if secondaryHref}
				<a class="text-sm font-medium text-muted underline-offset-4 hover:text-ink hover:underline" href={secondaryHref}>
					{secondaryLabel}
				</a>
			{:else}
				<span class="text-sm font-medium text-muted">{secondaryLabel}</span>
			{/if}
		</div>
	</div>
</section>
