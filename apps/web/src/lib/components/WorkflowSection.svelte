<script lang="ts">
	import type { WorkflowCard } from '$lib/content/site';

	let {
		eyebrow,
		title,
		copy,
		cards
	}: {
		eyebrow: string;
		title: string;
		copy: string;
		cards: WorkflowCard[];
	} = $props();
</script>

<section class="mx-auto w-[min(1180px,calc(100vw-48px))] py-8 md:py-18" id="workflow">
	<div class="section-heading mb-10 max-w-[720px]">
		<p class="mb-3 text-[0.82rem] font-bold uppercase tracking-[0.12em] text-accent">{eyebrow}</p>
		<h2 class="mb-4 font-semibold">{title}</h2>
		<p class="text-[1.03rem] leading-7 text-muted md:leading-[1.75]">{copy}</p>
	</div>

	<div class="grid gap-5 md:grid-cols-3">
		{#each cards as card}
			<article
				class={`frost-panel rounded-[32px] border p-7 ${
					card.accent === 'orange'
						? 'border-accent/20'
						: card.accent === 'gold'
							? 'border-gold/35'
							: 'border-border'
				}`}
			>
				<p class="mb-3 text-[0.82rem] font-bold uppercase tracking-[0.12em] text-accent">{card.eyebrow}</p>
				<h3 class="mb-3 text-[1.45rem] leading-tight font-semibold tracking-[-0.03em] text-ink">
					{card.title}
				</h3>
				<p class="text-base leading-7 text-muted">{card.copy}</p>
			</article>
		{/each}
	</div>
</section>
