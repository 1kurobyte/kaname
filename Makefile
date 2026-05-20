# =========================
# Config
# =========================

ZIG_FLAGS :=
ZIG := zig

# =========================
# Targets
# =========================

.PHONY: all
all: build


.PHONY: build
build:
	$(ZIG) build $(ZIG_FLAGS)


.PHONY: bonus
bonus:
	$(ZIG) build -Dfull=true $(ZIG_FLAGS)


.PHONY: iso-grub
iso-grub:
	$(ZIG) build iso-grub


.PHONY: iso-limine
iso-limine:
	$(ZIG) build iso-limine


.PHONY: run-grub
run-grub:
	$(ZIG) build run-grub $(ZIG_FLAGS)


.PHONY: run-limine
run-limine:
	$(ZIG) build run-limine $(ZIG_FLAGS)


.PHONY: run-grub-bonus
run-grub-bonus:
	$(ZIG) build run-grub -Dfull=true $(ZIG_FLAGS)


.PHONY: run-limine-bonus
run-limine-bonus:
	$(ZIG) build run-limine -Dfull=true $(ZIG_FLAGS)

.PHONY: test
test:
	$(ZIG) build test $(ZIG_FLAGS)


.PHONY: fmt
fmt:
	$(ZIG) fmt kernel arch abi drivers


.PHONY: clean
clean:
	rm -rf zig-out .zig-cache iso-grub kaname-grub.iso iso-limine kaname-limine.iso
