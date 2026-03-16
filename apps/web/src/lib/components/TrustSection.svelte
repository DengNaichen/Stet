<script lang="ts">
	let {
		eyebrow,
		title,
		body,
		panelLabel,
		points
	}: {
		eyebrow: string;
		title: string;
		body: string;
		panelLabel: string;
		points: string[];
	} = $props();
</script>

<section
	class="mx-auto grid w-[min(1180px,calc(100vw-48px))] gap-6 py-18 md:grid-cols-[1.1fr_0.9fr] md:items-start"
	id="privacy"
>
	<div class="trust-copy">
		<p class="mb-3 text-[0.82rem] font-bold uppercase tracking-[0.12em] text-accent">{eyebrow}</p>
		<h2 class="mb-4 font-semibold">{title}</h2>
		<p class="text-[1.03rem] leading-7 text-muted md:leading-[1.75]">{body}</p>
	</div>

	<div class="frost-panel-dark rounded-[32px] border border-border p-7 text-white">
		<div class="mb-5 text-xs font-bold uppercase tracking-[0.16em] text-white/60">{panelLabel}</div>
		<ul class="grid gap-4">
			{#each points as point}
				<li class="dark-chip rounded-[22px] border border-white/10 px-4 py-4 text-[0.98rem] leading-7 text-white/86">
					{point}
				</li>
			{/each}
		</ul>
	</div>
</section>
