V_FILE_GEN   = build/ysyxSoCTop.sv
V_FILE_FINAL = build/ysyxSoCFull.v
SCALA_FILES = $(shell find src/ -name "*.scala")

# Firtool version
FIRTOOL_VERSION = 1.105.0
FIRTOOL_PATCH_DIR = $(shell pwd)/patch/firtool

$(V_FILE_FINAL): $(SCALA_FILES) 
# Replace firtool with a newer version
# TODO: This can be removed after chisel publishes a new version
	@./patch/update-firtool.sh $(FIRTOOL_VERSION) $(FIRTOOL_PATCH_DIR)
	CHISEL_FIRTOOL_PATH=$(FIRTOOL_PATCH_DIR)/firtool-$(FIRTOOL_VERSION)/bin \
	mill -i ysyxsoc.runMain ysyx.Elaborate --target-dir $(@D)
	mv $(V_FILE_GEN) $@
	sed -i -e 's/_\(aw\|ar\|w\|r\|b\)_\(\|bits_\)/_\1/g' $@
	sed -i '/firrtl_black_box_resource_files.f/, $$d' $@

verilog: change_sdramport

change_sdramport: $(V_FILE_FINAL)
	sed -E -i \
	    -e 's/^([[:space:]]+)sdram_dqm/output [3:0]	sdram_dqm/' \
	    -e 's/inout  \[15:0\] sdram_dq/inout  [31:0] sdram_dq/' \
	    -e 's/wire \[1:0\]  _asic_sdram_dqm/wire [3:0]  _asic_sdram_dqm/' \
	    -e 's/wire \[15:0\] _dq_wire/wire [31:0] _dq_wire/' \
	    -e 's/^([[:space:]]+)sdram_bundle_dqm/output [3:0]	sdram_bundle_dqm/' \
	    -e 's/inout  \[15:0\] sdram_bundle_dq/inout  [31:0] sdram_bundle_dq/' \
        $<
clean:
	-rm -rf build/

dev-init:
	git submodule update --init --recursive
	cd rocket-chip && git apply ../patch/rocket-chip.patch

.PHONY: verilog clean dev-init
