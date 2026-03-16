<script lang="ts">
	let { copy }: { copy: string } = $props();
</script>

<footer class="mx-auto w-[min(1180px,calc(100vw-48px))] pb-10 text-sm text-muted">
	<p>{copy}</p>
</footer>
