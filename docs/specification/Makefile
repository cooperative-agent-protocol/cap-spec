# CAP Specification PDF Generation
# Requires: pandoc (brew install pandoc)
# Optional: mermaid-filter for diagram rendering (npm install -g mermaid-filter)

CHAPTERS = ch01-scope.md ch02-terms.md ch03-architecture.md ch04-communication-model.md \
           ch05-protocol-flows.md ch06-state-machines.md ch07-message-reference.md \
           ch08-error-handling.md ch09-security.md ch10-conformance.md ch11-implementation-guidelines.md

OUTPUT = cap-specification-v0.1.pdf
OUTPUT_HTML = cap-specification-v0.1.html

.PHONY: pdf html clean

pdf: $(OUTPUT)

html: $(OUTPUT_HTML)

$(OUTPUT): $(CHAPTERS)
	pandoc -o $@ --toc --toc-depth=3 \
		--metadata title="CAP Specification v0.1" \
		--metadata author="CAP Authors" \
		--metadata date="$$(date +%Y-%m-%d)" \
		--variable geometry:margin=2.5cm \
		--variable fontsize=11pt \
		--number-sections \
		$(CHAPTERS)

$(OUTPUT_HTML): $(CHAPTERS)
	pandoc -o $@ --toc --toc-depth=3 \
		--metadata title="CAP Specification v0.1" \
		--standalone \
		--number-sections \
		$(CHAPTERS)

clean:
	rm -f $(OUTPUT) $(OUTPUT_HTML)
