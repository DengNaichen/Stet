<script lang="ts">
	let {
		eyebrow,
		title,
		primaryCtaLabel,
		primaryCtaHref,
		secondaryCtaLabel,
		secondaryCtaHref,
		mockWindows
	}: {
		eyebrow: string;
		title: string;
		primaryCtaLabel: string;
		primaryCtaHref: string;
		secondaryCtaLabel: string;
		secondaryCtaHref: string;
		mockWindows: { title: string; lines: string[] }[];
	} = $props();
</script>

<section class="relative mx-auto w-full max-w-[1240px] px-6 py-24 md:py-32" id="top">
	<div class="z-10 mb-20 flex flex-col items-center text-center">
		{#if eyebrow}
			<p class="mb-4 text-[0.85rem] font-bold uppercase tracking-[0.2em] text-accent">
				{eyebrow}
			</p>
		{/if}
		
		<h1 class="mx-auto mb-6 max-w-[15ch] text-5xl font-semibold leading-[1.05] tracking-tight md:text-8xl">
			{title}
		</h1>
		
		<p class="mb-10 text-[1.15rem] font-medium text-muted/80 opacity-90">
			Swift-native speech to text. Built for professionals.
		</p>

		<div class="flex flex-wrap justify-center gap-4">
			<a
				class="inline-flex items-center justify-center rounded-full bg-black px-8 py-4 text-[1.05rem] font-bold text-white transition-transform hover:scale-105 active:scale-95 shadow-xl"
				href={primaryCtaHref}
			>
				{primaryCtaLabel}
			</a>
			<a
				class="inline-flex items-center justify-center rounded-full border border-black/10 px-8 py-4 text-[1.05rem] font-bold text-black transition-transform hover:scale-105 active:scale-95"
				href={secondaryCtaHref}
			>
				{secondaryCtaLabel}
			</a>
		</div>
	</div>

	<!-- 下方展示区：三栏并排窗口 -->
	<div class="grid w-full grid-cols-1 gap-8 md:grid-cols-3">
		{#each mockWindows as window}
			<div class="flex flex-col">
				<div class="mock-window !mx-0 !w-full !mt-0 !min-h-[300px] border border-black/5 shadow-2xl">
					<div class="mock-window-bar !bg-black/5">
						<div class="mock-dots">
							<span class="!bg-black/20"></span>
							<span class="!bg-black/20"></span>
							<span class="!bg-black/20"></span>
						</div>
						<span class="text-[0.7rem] font-bold uppercase tracking-widest text-black/40">{window.title}</span>
					</div>
					<div class="mock-window-body !text-black/80">
						{#each window.lines as line}
							<div class="whitespace-pre-wrap">{line}</div>
						{/each}
					</div>
				</div>
			</div>
		{/each}
	</div>
</section>

<style>
	:global(.hero-art) {
		display: none !important;
	}
</style>
