SHELL := bash

ROOT := $(abspath .)
SWIFT_DIR := $(ROOT)/swift

UPDATE_CHECKOUT_SCHEME ?= release/6.3
UPDATE_CHECKOUT ?= python3 $(SWIFT_DIR)/utils/update-checkout --scheme $(UPDATE_CHECKOUT_SCHEME) --clone --skip-history --skip-tags --reset-to-remote --skip-repository swift
SHALLOW_SUBMODULE_JOBS ?= 16

BUILD_PRESET ?= ios_minimal_compiler_embedded
BUILD_SUBDIR ?= ios_minimal_compiler
BUILD_JOBS ?= $(shell sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)
LIT_JOBS ?= $(BUILD_JOBS)
USE_SCCACHE ?= 1
BUILD_SCRIPT_CACHE_FLAGS := $(if $(filter 1 YES yes true TRUE,$(USE_SCCACHE)),--sccache,)
ARTIFACTS_DIR ?= $(ROOT)/artifacts
INSTALL_DESTDIR ?= $(ARTIFACTS_DIR)/install
INSTALL_TOOLCHAIN_DIR ?= /Library/Developer/Toolchains/SwiftMinimalIOS.xctoolchain
INSTALLED_TOOLCHAIN_ROOT := $(INSTALL_DESTDIR)$(INSTALL_TOOLCHAIN_DIR)
CLANG_ARTIFACT_DIR ?= $(ARTIFACTS_DIR)/clang-ios-minimal
LLVM_XCFRAMEWORK_NAME ?= LLVM.xcframework
LLVM_XCFRAMEWORK_HEADERS_DIR ?= $(ARTIFACTS_DIR)/llvm-headers
LLVM_XCFRAMEWORK_LIB ?= $(ARTIFACTS_DIR)/libLLVM.a
LLVM_XCFRAMEWORK_PATH ?= $(ARTIFACTS_DIR)/$(LLVM_XCFRAMEWORK_NAME)
CLANG_XCFRAMEWORK_NAME ?= Clang.xcframework
CLANG_XCFRAMEWORK_HEADERS_DIR ?= $(ARTIFACTS_DIR)/clang-headers
CLANG_XCFRAMEWORK_LIB ?= $(ARTIFACTS_DIR)/libClang.a
CLANG_XCFRAMEWORK_PATH ?= $(ARTIFACTS_DIR)/$(CLANG_XCFRAMEWORK_NAME)
SWIFT_XCFRAMEWORK_NAME ?= Swift.xcframework
SWIFT_XCFRAMEWORK_HEADERS_DIR ?= $(ARTIFACTS_DIR)/swift-headers
SWIFT_XCFRAMEWORK_LIB ?= $(ARTIFACTS_DIR)/libSwift.a
SWIFT_XCFRAMEWORK_PATH ?= $(ARTIFACTS_DIR)/$(SWIFT_XCFRAMEWORK_NAME)
TOOLCHAIN_STAMP := $(ARTIFACTS_DIR)/.$(BUILD_SUBDIR)-installed

.PHONY: all swift-ios-minimal ensure-script-exec update-checkout shallowen-checkouts swift-toolchain collect-clang-artifacts package-llvm-xcframework package-clang-xcframework package-swift-xcframework package-xcframeworks clean

all: swift-ios-minimal

define log_info
	@echo "\033[32m\033[1m[*] \033[0m\033[32m$(1)\033[0m"
endef

swift-ios-minimal: package-xcframeworks

ensure-script-exec:
	$(call log_info,ensuring scripts in swift/utils are executable when they have a shebang)
	@python3 ./scripts/ensure_exec_bits.py --root "$(SWIFT_DIR)/utils"

update-checkout: ensure-script-exec
	$(call log_info,syncing Swift 6.3 checkout dependencies)
	$(UPDATE_CHECKOUT)

shallowen-checkouts: update-checkout
	$(call log_info,forcing checkout submodules to stay shallow and tagless)
	@find "$(ROOT)" -mindepth 1 -maxdepth 1 -type d | while read -r repo; do \
		if [[ ! -e "$$repo/.git" ]]; then continue; fi; \
		git -C "$$repo" config remote.origin.tagOpt --no-tags || true; \
		if [[ -f "$$repo/.gitmodules" ]]; then \
			while read -r key _; do \
				name="$${key#submodule.}"; \
				name="$${name%.path}"; \
				git -C "$$repo" config "submodule.$$name.shallow" true; \
			done < <(git -C "$$repo" config --file .gitmodules --get-regexp "^submodule\..*\.path$$" || true); \
			git -C "$$repo" submodule sync --recursive || true; \
			git -C "$$repo" submodule deinit -f --all || true; \
			rm -rf "$$repo/.git/modules"; \
			git -C "$$repo" submodule update --init --recursive --depth 1 --recommend-shallow --jobs "$(SHALLOW_SUBMODULE_JOBS)"; \
			git -C "$$repo" submodule foreach --recursive "git config remote.origin.tagOpt --no-tags || true"; \
		fi; \
	done

$(TOOLCHAIN_STAMP): shallowen-checkouts
	$(call log_info,building the minimal iOS Swift compiler toolchain with preset $(BUILD_PRESET))
	mkdir -p "$(ARTIFACTS_DIR)"
	rm -f "$(TOOLCHAIN_STAMP)"
	cd "$(SWIFT_DIR)" && CMAKE_BUILD_PARALLEL_LEVEL="$(BUILD_JOBS)" python3 ./utils/build-script \
		-j "$(BUILD_JOBS)" \
		$(BUILD_SCRIPT_CACHE_FLAGS) \
		--lit-jobs "$(LIT_JOBS)" \
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
	@cd "$(INSTALLED_TOOLCHAIN_ROOT)/usr" && { \
		find lib -type f \
			\( -name 'libclang*' -o -name 'libc++*' -o -name 'libc++abi*' -o -name 'libunwind*' \) -print0; \
	} | rsync --from0 --files-from=- -a . "$(CLANG_ARTIFACT_DIR)/"

package-llvm-xcframework: $(TOOLCHAIN_STAMP)
	$(call log_info,packaging LLVM static libraries into $(LLVM_XCFRAMEWORK_NAME))
	@rm -rf "$(LLVM_XCFRAMEWORK_HEADERS_DIR)" "$(LLVM_XCFRAMEWORK_LIB)" "$(LLVM_XCFRAMEWORK_PATH)"
	@mkdir -p "$(LLVM_XCFRAMEWORK_HEADERS_DIR)"
	@if [ -d "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/llvm" ]; then \
		rsync -a "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/llvm" "$(LLVM_XCFRAMEWORK_HEADERS_DIR)/"; \
	fi
	@if [ -d "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/llvm-c" ]; then \
		rsync -a "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/llvm-c" "$(LLVM_XCFRAMEWORK_HEADERS_DIR)/"; \
	fi
	@llvm_libs=( $$(find "$(INSTALLED_TOOLCHAIN_ROOT)/usr/lib" -maxdepth 1 -name "libLLVM*.a" -print | sort) ); \
	if [[ $${#llvm_libs[@]} -eq 0 ]]; then \
		echo "error: no LLVM static libraries found under $(INSTALLED_TOOLCHAIN_ROOT)/usr/lib"; \
		exit 1; \
	fi; \
	libtool -static -o "$(LLVM_XCFRAMEWORK_LIB)" "$${llvm_libs[@]}"; \
	xcodebuild -create-xcframework \
		-library "$(LLVM_XCFRAMEWORK_LIB)" \
		-headers "$(LLVM_XCFRAMEWORK_HEADERS_DIR)" \
		-output "$(LLVM_XCFRAMEWORK_PATH)"

package-clang-xcframework: collect-clang-artifacts
	$(call log_info,packaging Clang and C++ static libraries into $(CLANG_XCFRAMEWORK_NAME))
	@rm -rf "$(CLANG_XCFRAMEWORK_HEADERS_DIR)" "$(CLANG_XCFRAMEWORK_LIB)" "$(CLANG_XCFRAMEWORK_PATH)"
	@mkdir -p "$(CLANG_XCFRAMEWORK_HEADERS_DIR)"
	@if [ -d "$(CLANG_ARTIFACT_DIR)/include/clang-c" ]; then \
		rsync -a "$(CLANG_ARTIFACT_DIR)/include/clang-c" "$(CLANG_XCFRAMEWORK_HEADERS_DIR)/"; \
	fi
	@if [ -d "$(CLANG_ARTIFACT_DIR)/include/c++" ]; then \
		rsync -a "$(CLANG_ARTIFACT_DIR)/include/c++" "$(CLANG_XCFRAMEWORK_HEADERS_DIR)/"; \
	fi
	@clang_libs=( $$(find "$(CLANG_ARTIFACT_DIR)/lib" -type f -name "*.a" -print | sort) ); \
	if [[ $${#clang_libs[@]} -eq 0 ]]; then \
		echo "error: no Clang/C++ static libraries found under $(CLANG_ARTIFACT_DIR)/lib"; \
		exit 1; \
	fi; \
	libtool -static -o "$(CLANG_XCFRAMEWORK_LIB)" "$${clang_libs[@]}"; \
	xcodebuild -create-xcframework \
		-library "$(CLANG_XCFRAMEWORK_LIB)" \
		-headers "$(CLANG_XCFRAMEWORK_HEADERS_DIR)" \
		-output "$(CLANG_XCFRAMEWORK_PATH)"

package-swift-xcframework: $(TOOLCHAIN_STAMP)
	$(call log_info,packaging Swift compiler static libraries into $(SWIFT_XCFRAMEWORK_NAME))
	@rm -rf "$(SWIFT_XCFRAMEWORK_HEADERS_DIR)" "$(SWIFT_XCFRAMEWORK_LIB)" "$(SWIFT_XCFRAMEWORK_PATH)"
	@mkdir -p "$(SWIFT_XCFRAMEWORK_HEADERS_DIR)"
	@if [ -d "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/swift" ]; then \
		rsync -a "$(INSTALLED_TOOLCHAIN_ROOT)/usr/include/swift" "$(SWIFT_XCFRAMEWORK_HEADERS_DIR)/"; \
	fi
	@swift_libs=( $$(find "$(INSTALLED_TOOLCHAIN_ROOT)/usr/lib" "$(INSTALLED_TOOLCHAIN_ROOT)/usr/lib/swift/host" -maxdepth 1 \
		\( -name "libSwift*.a" -o -name "libswift*.a" -o -name "lib_InternalSwift*.a" \) -print 2>/dev/null | sort -u) ); \
	if [[ $${#swift_libs[@]} -eq 0 ]]; then \
		echo "error: no Swift compiler static libraries found under $(INSTALLED_TOOLCHAIN_ROOT)/usr/lib or usr/lib/swift/host"; \
		exit 1; \
	fi; \
	libtool -static -o "$(SWIFT_XCFRAMEWORK_LIB)" "$${swift_libs[@]}"; \
	xcodebuild -create-xcframework \
		-library "$(SWIFT_XCFRAMEWORK_LIB)" \
		-headers "$(SWIFT_XCFRAMEWORK_HEADERS_DIR)" \
		-output "$(SWIFT_XCFRAMEWORK_PATH)"

package-xcframeworks: package-llvm-xcframework package-clang-xcframework package-swift-xcframework

clean:
	$(call log_info,cleaning generated artifacts)
	rm -rf "$(ARTIFACTS_DIR)"
