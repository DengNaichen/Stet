<script lang="ts">
	let {
		title,
		body,
		primaryCtaLabel,
		primaryCtaHref
	}: {
		title: string;
		body: string;
		primaryCtaLabel: string;
		primaryCtaHref: string;
	} = $props();
</script>

<section class="relative mx-auto w-full max-w-[1240px] px-6 py-32 md:py-64 text-center" id="cta">
	<div class="mx-auto flex flex-col items-center max-w-[800px]">
		<h2 class="mb-10 text-5xl md:text-8xl font-semibold tracking-tighter leading-tight text-ink">
			{title}
		</h2>
		
		<p class="mb-16 text-xl md:text-2xl leading-[1.6] text-muted font-medium">
			{body}
		</p>
		
		<a
			class="inline-flex items-center justify-center rounded-full bg-black px-12 py-6 text-[1.15rem] font-bold text-white transition-all hover:scale-105 active:scale-95 shadow-2xl"
			href={primaryCtaHref}
		>
			{primaryCtaLabel}
		</a>
	</div>
</section>
