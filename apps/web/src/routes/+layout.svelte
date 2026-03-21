<script lang="ts">
	import '../app.css';

	let { children } = $props();
</script>

<svelte:head>
	<title>Stet</title>
	<meta
		name="description"
		content="Mac-native speech to text with minimal edits, portable language data, and full ownership of your personal dictionary."
	/>
	<link rel="icon" href="/favicon.png" />
</svelte:head>

{@render children()}
