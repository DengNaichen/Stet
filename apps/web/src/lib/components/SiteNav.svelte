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

<header class="sticky top-0 z-50 w-full border-b border-white/10 bg-white/5 backdrop-blur-md">
	<nav
		class="mx-auto flex h-20 w-full max-w-[1240px] items-center justify-between gap-4 px-6 md:px-12"
		aria-label="Primary"
	>
		<a class="text-2xl tracking-tight" href="#top" aria-label={`${brand} home`}>
			<span>{brand}</span>
		</a>

		<div class="hidden items-center gap-8 text-[0.95rem] text-muted md:inline-flex">
			{#each links as link}
				<a class="transition-colors hover:text-ink" href={link.href}>{link.label}</a>
			{/each}
		</div>

		<div class="flex items-center gap-3">
			<a
				class="inline-flex h-11 w-11 items-center justify-center rounded-full bg-black text-white transition-transform hover:scale-[1.05] active:scale-95"
				href="https://github.com/DengNaichen/Stet"
				target="_blank"
				rel="noopener noreferrer"
				aria-label="View on GitHub"
			>
				<svg
					xmlns="http://www.w3.org/2000/svg"
					width="20"
					height="20"
					viewBox="0 0 24 24"
					fill="none"
					stroke="currentColor"
					stroke-width="2.2"
					stroke-linecap="round"
					stroke-linejoin="round"
				>
					<path
						d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4"
					/>
					<path d="M9 18c-4.51 2-5-2-7-2" />
				</svg>
			</a>

			<a
				class="inline-flex items-center justify-center rounded-full bg-black px-7 py-3 text-[0.92rem] font-bold text-white transition-transform hover:scale-[1.02] active:scale-95"
				href={ctaHref}
				>{ctaLabel}</a
			>
		</div>
	</nav>
</header>
