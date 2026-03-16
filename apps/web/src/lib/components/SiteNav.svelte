<script lang="ts">
	import type { NavLink } from '$lib/content/site';

	let {
		brand,
		links,
		ctaLabel,
		ctaHref
	}: {
		brand: string;
		links: NavLink[];
		ctaLabel: string;
		ctaHref: string;
	} = $props();
</script>

<header class="mx-auto w-[min(1180px,calc(100vw-48px))]">
	<nav
		class="frost-panel frost-panel-nav mt-3.5 flex items-center justify-between gap-4 rounded-full border border-white/70 border-b-gold/50 px-4 py-3"
		aria-label="Primary"
	>
		<a class="inline-flex items-center gap-3 text-[0.98rem] font-bold" href="#top" aria-label={`${brand} home`}>
			<span
				class="h-4 w-4 rounded-full bg-linear-to-br from-accent to-gold shadow-[0_0_0_6px_rgba(240,81,56,0.1)]"
				aria-hidden="true"
			></span>
			<span>{brand}</span>
		</a>

		<div class="hidden items-center gap-4 text-[0.95rem] text-muted md:inline-flex">
			{#each links as link}
				<a class="hover:text-ink" href={link.href}>{link.label}</a>
			{/each}
		</div>

		<a
			class="frost-chip inline-flex items-center justify-center rounded-full border border-border px-4 py-3 text-[0.95rem] font-bold hover:-translate-y-px"
			href={ctaHref}
			>{ctaLabel}</a
		>
	</nav>
</header>
