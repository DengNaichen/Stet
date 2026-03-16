<script lang="ts">
	let {
		eyebrow,
		title,
		body,
		quote
	}: {
		eyebrow: string;
		title: string;
		body: string;
		quote: string;
	} = $props();
</script>

<section
	class="mx-auto grid w-[min(1180px,calc(100vw-48px))] gap-6 py-18 md:grid-cols-[1fr_0.8fr] md:items-stretch"
	id="voice"
>
	<div class="voice-card frost-panel rounded-[32px] border border-border p-8">
		<p class="mb-3 text-[0.82rem] font-bold uppercase tracking-[0.12em] text-accent">{eyebrow}</p>
		<h2 class="mb-4 font-semibold">{title}</h2>
		<p class="text-[1.03rem] leading-7 text-muted md:leading-[1.75]">{body}</p>
	</div>

	<blockquote class="quote-panel flex items-end rounded-[32px] border border-accent/15 p-8">
		<p class="max-w-[16ch] text-[2rem] leading-none font-semibold tracking-[-0.05em] text-ink md:text-[2.6rem]">
			{quote}
		</p>
	</blockquote>
</section>
