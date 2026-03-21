<script lang="ts">
	let { title, plans }: {
		title: string;
		plans: { name: string; price: string; description: string; features: string[] }[];
	} = $props();
</script>

<section class="relative mx-auto w-full max-w-[1100px] px-6 py-24 md:py-32" id="pricing">
	<h2 class="mb-16 text-center text-4xl font-semibold tracking-tight md:text-6xl">{title}</h2>
	
	<div class="grid w-full grid-cols-1 gap-8 md:grid-cols-2">
		{#each plans as plan}
			<div class="frost-panel flex flex-col rounded-[48px] border border-black/5 p-12 transition-all hover:-translate-y-1 hover:shadow-[0_40px_100px_rgba(0,0,0,0.06)]">
				<p class="mb-3 text-[0.8rem] font-bold uppercase tracking-[0.2em] text-accent/80">{plan.name}</p>
				<div class="mb-6 text-4xl font-bold tracking-tight text-ink">{plan.price}</div>
				
				<p class="mb-10 text-[1.1rem] leading-relaxed text-muted font-medium">
					{plan.description}
				</p>
				
				<ul class="mb-12 flex-grow space-y-5">
					{#each plan.features as feature}
						<li class="flex items-start gap-4 text-[1rem] text-muted/90">
							<span class="mt-1 flex-shrink-0 text-accent">
								<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
									<polyline points="20 6 9 17 4 12"/>
								</svg>
							</span>
							{feature}
						</li>
					{/each}
				</ul>
				
				<button class="w-full rounded-2xl bg-black py-5 text-[1.1rem] font-bold text-white transition-transform hover:scale-[1.01] active:scale-[0.99]">
					Get Started
				</button>
			</div>
		{/each}
	</div>
</section>
