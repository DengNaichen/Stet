<script lang="ts">
	import CtaSection from '$lib/components/CtaSection.svelte';
	import HeroSection from '$lib/components/HeroSection.svelte';
	import PricingSection from '$lib/components/PricingSection.svelte';
	import SiteFooter from '$lib/components/SiteFooter.svelte';
	import SiteNav from '$lib/components/SiteNav.svelte';
	import TrustSection from '$lib/components/TrustSection.svelte';
	import WorkflowSection from '$lib/components/WorkflowSection.svelte';
	import { siteContent } from '$lib/content/site';
</script>

<svelte:head>
	<title>Stet | Speech to text for Mac</title>
	<meta
		name="description"
		content="Mac-native speech to text with minimal edits, portable language data, and full ownership of your personal dictionary."
	/>
</svelte:head>

<div class="page-shell">
	<SiteNav {...siteContent.nav} />

	<main>
		<HeroSection {...siteContent.hero} />
		<WorkflowSection {...siteContent.workflow} />
		<TrustSection {...siteContent.privacy} />
		<PricingSection {...siteContent.pricing} />
		<CtaSection {...siteContent.cta} />
	</main>

	<SiteFooter {...siteContent.footer} />
</div>
