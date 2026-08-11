R ?= Rscript
DATA_PATH := $(if $(FIFA2017_NL_PATH),$(FIFA2017_NL_PATH),data/FIFA2017_NL.RData)
REPORT_SHA256 := 4713a068de9d64c4948630422417618d335ca8a6b34fd220dd19ad62b603a23f
DATA_SHA256 := a56a3065dba053436d0302cbf08a854c94d9c4cdeccdf3a7bf68daa99fdac540

.PHONY: setup validate verify-data run pca pmd clean

setup:
	$(R) -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv", repos = "https://cloud.r-project.org"); renv::load(); renv::restore(prompt = FALSE)'

validate:
	$(R) -e 'files <- Sys.glob("src/*.R"); invisible(lapply(files, function(path) parse(file = path))); cat(sprintf("Parsed %d R programs successfully.\n", length(files)))'
	@if command -v sha256sum >/dev/null 2>&1; then actual=$$(sha256sum report/the-beautiful-game-reduced.pdf | awk '{print $$1}'); elif command -v shasum >/dev/null 2>&1; then actual=$$(shasum -a 256 report/the-beautiful-game-reduced.pdf | awk '{print $$1}'); else echo "Install sha256sum or shasum to validate artifacts."; exit 1; fi; test "$$actual" = "$(REPORT_SHA256)" || { echo "Report checksum mismatch: $$actual"; exit 1; }; echo "Canonical report checksum verified."
	@test ! -e data/FIFA2017_NL.RData || git check-ignore --quiet data/FIFA2017_NL.RData

verify-data:
	@test -f "$(DATA_PATH)" || { echo "Dataset not found: $(DATA_PATH)"; echo "See data/README.md or export FIFA2017_NL_PATH."; exit 1; }
	@if command -v sha256sum >/dev/null 2>&1; then actual=$$(sha256sum "$(DATA_PATH)" | awk '{print $$1}'); elif command -v shasum >/dev/null 2>&1; then actual=$$(shasum -a 256 "$(DATA_PATH)" | awk '{print $$1}'); else echo "Install sha256sum or shasum to validate artifacts."; exit 1; fi; test "$$actual" = "$(DATA_SHA256)" || { echo "Dataset checksum mismatch: $$actual"; exit 1; }
	@FIFA2017_NL_PATH="$(DATA_PATH)" $(R) -e 'e <- new.env(parent = emptyenv()); load(Sys.getenv("FIFA2017_NL_PATH"), envir = e); stopifnot(exists("fifa", envir = e, inherits = FALSE)); x <- e$$fifa; expected <- c("name", "club", "Position", "crossing", "finishing", "heading_accuracy", "short_passing", "volleys", "dribbling", "curve", "free_kick_accuracy", "long_passing", "ball_control", "acceleration", "sprint_speed", "agility", "reactions", "balance", "shot_power", "jumping", "stamina", "strength", "long_shots", "aggression", "interceptions", "positioning", "vision", "penalties", "composure", "marking", "standing_tackle", "sliding_tackle", "eur_value", "eur_wage", "eur_release_clause"); stopifnot(identical(dim(x), c(488L, 35L)), identical(names(x), expected), is.character(x$$name), is.factor(x$$club), is.factor(x$$Position), all(vapply(x[4:35], is.integer, logical(1))), sum(is.na(x$$eur_release_clause)) == 40L); cat("Dataset contract verified: fifa [488 x 35], ordered schema and storage types match.\n")'

run: verify-data pca pmd

pca:
	$(R) -e 'renv::load(); source("src/01_pca_spca.R", echo = FALSE)'

pmd:
	$(R) -e 'renv::load(); source("src/02_manual_pmd.R", echo = FALSE)'

clean:
	$(R) -e 'unlink("results", recursive = TRUE, force = TRUE)'
