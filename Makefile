.PHONY: test lint pack install clean help

ROCKSPEC=wjson-0.1-1.rockspec

# Use nix-shell if nix is available, otherwise run directly
define run_cmd
	if command -v nix >/dev/null 2>&1; then \
		nix shell nixpkgs#luarocks --command $(1); \
	else \
		$(1); \
	fi
endef

help:
	@echo "Available targets:"
	@echo "  test    - Run busted tests"
	@echo "  lint    - Check rockspec for errors"
	@echo "  pack    - Create a source rock (requires valid URL in rockspec)"
	@echo "  install - Install the rock locally from source"
	@echo "  clean   - Remove generated .rock files"

test:
	./run_tests.sh

lint:
	@$(call run_cmd,luarocks lint $(ROCKSPEC))

pack:
	@$(call run_cmd,luarocks pack $(ROCKSPEC))

install:
	@$(call run_cmd,luarocks make $(ROCKSPEC))

clean:
	rm -f *.rock
