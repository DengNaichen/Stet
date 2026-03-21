<script lang="ts">
	let {
		eyebrow = "",
		title,
		copy
	}: {
		eyebrow?: string;
		title: string;
		copy: string;
	} = $props();
</script>

<section class="relative mx-auto w-full max-w-[1240px] px-6 py-24 md:py-48" id="workflow">
	<div class="mx-auto flex flex-col items-center text-center max-w-[960px]">
		{#if eyebrow}
			<p class="mb-5 text-[0.85rem] font-bold uppercase tracking-[0.2em] text-accent/80">
				{eyebrow}
			</p>
		{/if}
		
		<h2 class="mb-10 text-4xl md:text-6xl font-semibold tracking-tight leading-[1.05] text-ink">
			{title}
		</h2>
		
		<p class="text-xl md:text-2xl leading-[1.6] text-muted font-medium">
			{copy}
		</p>
	</div>
</section>
