ROOT := $(PWD)
LLVM_VER ?= 21.1.6
OS_VER ?= 15.0
LLVM_ARCH ?= AArch64
APPLE_ARCH ?= arm64

LLVM_SRC_DIR := $(ROOT)/llvm-project-$(LLVM_VER).src
LLVM_BUILD_DIR := $(LLVM_SRC_DIR)/build
LLVM_INSTALL_DIR := $(ROOT)/LLVM-iphoneos

LLVM_CMAKE_FLAGS := -G "Ninja" \
					-DLLVM_ENABLE_PROJECTS="clang;lld" \
					-DLLVM_TARGETS_TO_BUILD="$(LLVM_ARCH)" \
					-DLLVM_TARGET_ARCH="$(LLVM_ARCH)" \
					-DLLVM_DEFAULT_TARGET_TRIPLE="$(APPLE_ARCH)-apple-ios" \
					-DLLVM_BUILD_TOOLS=OFF \
					-DCLANG_BUILD_TOOLS=OFF \
					-DBUILD_SHARED_LIBS=OFF \
					-DLLVM_ENABLE_ZLIB=OFF \
					-DLLVM_ENABLE_ZSTD=OFF \
					-DLLVM_ENABLE_THREADS=ON \
					-DLLVM_ENABLE_UNWIND_TABLES=OFF \
					-DLLVM_ENABLE_EH=OFF \
					-DLLVM_ENABLE_RTTI=ON \
					-DLLVM_ENABLE_TERMINFO=OFF \
					-DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_INSTALL_PREFIX="$(LLVM_INSTALL_DIR)" \
					-DLLVM_ENABLE_LIBXML2=OFF \
					-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
					-DCLANG_ENABLE_ARCMT=OFF \
					-DCLANG_TABLEGEN_TARGETS="$(LLVM_ARCH)" \
					-DCMAKE_C_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_CXX_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_OSX_ARCHITECTURES="$(APPLE_ARCH)" \
					-DCMAKE_OSX_DEPLOYMENT_TARGET="$(OS_VER)" \
					-DCMAKE_SYSTEM_NAME=iOS \
					-DCMAKE_OSX_SYSROOT=iphoneos \
					-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY

define log_info
	@echo "\033[32m\033[1m[*] \033[0m\033[32m$(1)\033[0m"
endef

.PHONY: all configure LLVM-iphoneos LLVM.xcframework Clang.xcframework clean clean-all

all: LLVM.xcframework Clang.xcframework clean

$(LLVM_BUILD_DIR)/build.ninja: $(LLVM_SRC_DIR)
	$(call log_info,configuring llvm ($(LLVM_VER)))
	mkdir -p "$(LLVM_BUILD_DIR)"
	cd "$(LLVM_BUILD_DIR)"; \
		cmake ../llvm $(LLVM_CMAKE_FLAGS)

configure: $(LLVM_BUILD_DIR)/build.ninja

LLVM-iphoneos: $(LLVM_BUILD_DIR)/build.ninja
	$(call log_info,building llvm ($(LLVM_VER)))
	cd "$(LLVM_BUILD_DIR)"; \
		cmake --build . --target install

$(LLVM_INSTALL_DIR)/llvm.a: LLVM-iphoneos
	$(call log_info,combining LLVM libraries into llvm.a)
	libtool -static -o "$(LLVM_INSTALL_DIR)/llvm.a" \
		$(LLVM_INSTALL_DIR)/lib/libLLVM*.a \
		$(LLVM_INSTALL_DIR)/lib/libclang*.a \
		$(LLVM_INSTALL_DIR)/lib/liblld*.a

LLVM.xcframework: $(LLVM_INSTALL_DIR)/llvm.a
	$(call log_info,creating LLVM framework out of llvm ($(LLVM_VER)))
	rm -rf llvm-headers
	mkdir -p llvm-headers
	cp -r "$(LLVM_INSTALL_DIR)/include/"* llvm-headers/
	rm -rf llvm-headers/clang-c
	xcodebuild -create-xcframework \
		-library "$(LLVM_INSTALL_DIR)/llvm.a" \
		-headers "llvm-headers" \
		-output LLVM.xcframework
	rm -rf llvm-headers

Clang.xcframework: LLVM-iphoneos
	$(call log_info,creating Clang framework out of llvm ($(LLVM_VER)))
	rm -rf clang-headers
	mkdir -p clang-headers
	cp -r "$(LLVM_INSTALL_DIR)/include/clang-c" clang-headers/
	xcodebuild -create-xcframework \
		-library "$(LLVM_INSTALL_DIR)/lib/libclang.dylib" \
		-headers "clang-headers" \
		-output Clang.xcframework
	rm -rf clang-headers

clean:
	$(call log_info,cleaning up)
	rm -rf llvm-headers
	rm -rf clang-headers
	rm -rf LLVM-iphoneos
	rm -rf Release-iphoneos
	rm -rf llvm-project-*.src/build

clean-all: clean
	rm -rf *.xcframework
