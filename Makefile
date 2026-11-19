PYTHON ?= python3
JAVA ?= java
JAR := .tools/tla2tools.jar
RELEASE := https://github.com/tlaplus/tlaplus/releases/download/v1.7.4
SHA256 := 936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
TRACE := examples/stale-report.trace
export JAVA

.PHONY: setup translate check safety witnesses unsafe test demo
setup: $(JAR)
	"$(JAVA)" -version

$(JAR):
	mkdir -p .tools
	curl -fLsS --retry 3 "$(RELEASE)/tla2tools.jar" -o "$@.part"
	$(PYTHON) -c 'import hashlib, pathlib, sys; sys.exit(hashlib.sha256(pathlib.Path("$@.part").read_bytes()).hexdigest() != "$(SHA256)")'
	mv "$@.part" "$@"

translate: $(JAR)
	"$(JAVA)" -cp "$(JAR)" pcal.trans -nocfg model/AegisUpdate.tla

check: $(JAR)
	$(PYTHON) tools/check.py verify $(SCENARIO)

safety: $(JAR)
	$(PYTHON) tools/check.py safety $(SCENARIO)

witnesses: $(JAR)
	$(PYTHON) tools/check.py witness

unsafe: $(JAR)
	$(PYTHON) tools/check.py unsafe

test:
	$(PYTHON) -m unittest discover -s tests -v

demo:
	@$(PYTHON) -m simulator.replay --unsafe $(TRACE); test $$? -eq 1
	@$(PYTHON) -m simulator.replay $(TRACE); test $$? -eq 2
