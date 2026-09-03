.PHONY: test lint pack release-assets install clean help

ROCKSPEC=wjson-0.9-3.rockspec
VERSION=$(shell sed -n 's/^version = "\(.*\)"/\1/p' $(ROCKSPEC))
DIST_DIR=dist

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
	@echo "  release-assets - Build the single-file and source-rock release assets"
	@echo "  install - Install the rock locally from source"
	@echo "  clean   - Remove generated .rock files"

test:
	./run_tests.sh

lint:
	@$(call run_cmd,luarocks lint $(ROCKSPEC))

pack:
	@$(call run_cmd,luarocks pack $(ROCKSPEC))

release-assets: pack
	@rm -rf $(DIST_DIR)
	@mkdir -p $(DIST_DIR)
	@cp src/wjson.lua $(DIST_DIR)/wjson.lua
	@cp wjson-$(VERSION).src.rock $(DIST_DIR)/
	@(cd $(DIST_DIR) && sha256sum wjson.lua wjson-$(VERSION).src.rock > SHA256SUMS)
	@echo "Built release assets in $(DIST_DIR)/"

install:
	@$(call run_cmd,luarocks make $(ROCKSPEC))

clean:
	rm -f *.rock
	rm -rf $(DIST_DIR)
