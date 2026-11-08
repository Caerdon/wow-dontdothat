.PHONY: test check

# luajit tests/run.lua [pattern] runs a subset, e.g. luajit tests/run.lua trainer
test:
	@luajit tests/run.lua

# The same checks the release workflow runs.
check:
	@for toc in DontDoThat/DontDoThat_*.toc; do sh tools/check-toc.sh "$$toc" || exit 1; done
	@sh tools/check-tocs-match.sh
	@bash tools/check-embeds.sh
	@sh tools/check-version.sh
