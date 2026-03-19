ROOT := $(abspath .)
SWIFT_DIR := $(ROOT)/swift

UPDATE_CHECKOUT_SCHEME ?= release/6.3
UPDATE_CHECKOUT ?= python3 $(SWIFT_DIR)/utils/update-checkout --scheme $(UPDATE_CHECKOUT_SCHEME) --clone --skip-history --reset-to-remote

BUILD_PRESET ?= ios_minimal_compiler_embedded
BUILD_SUBDIR ?= ios_minimal_compiler
ARTIFACTS_DIR ?= $(ROOT)/artifacts
INSTALL_DESTDIR ?= $(ARTIFACTS_DIR)/install
INSTALL_TOOLCHAIN_DIR ?= /Library/Developer/Toolchains/SwiftMinimalIOS.xctoolchain
INSTALLED_TOOLCHAIN_ROOT := $(INSTALL_DESTDIR)$(INSTALL_TOOLCHAIN_DIR)
CLANG_ARTIFACT_DIR ?= $(ARTIFACTS_DIR)/clang-ios-minimal
TOOLCHAIN_STAMP := $(ARTIFACTS_DIR)/.$(BUILD_SUBDIR)-installed

.PHONY: all swift-ios-minimal update-checkout swift-toolchain collect-clang-artifacts clean

all: swift-ios-minimal

define log_info
	@echo "\033[32m\033[1m[*] \033[0m\033[32m$(1)\033[0m"
endef

swift-ios-minimal: collect-clang-artifacts

update-checkout:
	$(call log_info,syncing Swift 6.3 checkout dependencies)
	$(UPDATE_CHECKOUT)

$(TOOLCHAIN_STAMP): update-checkout
	$(call log_info,building the minimal iOS Swift compiler toolchain with preset $(BUILD_PRESET))
	mkdir -p "$(ARTIFACTS_DIR)"
	rm -f "$(TOOLCHAIN_STAMP)"
	cd "$(SWIFT_DIR)" && python3 ./utils/build-script \
		--preset=$(BUILD_PRESET) \
		install_destdir="$(INSTALL_DESTDIR)" \
		install_toolchain_dir="$(INSTALL_TOOLCHAIN_DIR)"
	@test -d "$(INSTALLED_TOOLCHAIN_ROOT)"
	@touch "$(TOOLCHAIN_STAMP)"

swift-toolchain: $(TOOLCHAIN_STAMP)

collect-clang-artifacts: $(TOOLCHAIN_STAMP)
	$(call log_info,collecting clang and C++ artifacts from the installed toolchain)
	rm -rf "$(CLANG_ARTIFACT_DIR)"
	mkdir -p "$(CLANG_ARTIFACT_DIR)/include" "$(CLANG_ARTIFACT_DIR)/lib"
	@if [ -d "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/clang-c" ]; then \
		rsync -a "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/clang-c" "$(CLANG_ARTIFACT_DIR)/include/"; \
	fi
	@if [ -d "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/c++" ]; then \
		rsync -a "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/c++" "$(CLANG_ARTIFACT_DIR)/include/"; \
	fi
	@if [ -d "$(INSTALLED_TOOLCHAIN_ROOT)/usr/lib/clang" ]; then \
		rsync -a "$(INSTALLED_TOOLCHAIN_ROOT)/usr/lib/clang" "$(CLANG_ARTIFACT_DIR)/lib/"; \
	fi
	@find "$(INSTALLED_TOOLCHAIN_ROOT)/usr/lib" -maxdepth 1 \
		\( -name 'libclang*' -o -name 'libc++*' -o -name 'libc++abi*' -o -name 'libunwind*' \) \
		-exec cp -f {} "$(CLANG_ARTIFACT_DIR)/lib/" \\;

clean:
	$(call log_info,cleaning generated artifacts)
	rm -rf "$(ARTIFACTS_DIR)"
