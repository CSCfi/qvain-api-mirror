#
# -wvh- Makefile to build Go binaries for commands in cmd/*
#
#       The only thing this Makefile does as opposed to an ordinary `go build ./...` is to link in version info.
#

GO := go
CMDS := $(notdir $(wildcard cmd/*))
ROOTDIR := $(CURDIR)
PARENTDIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../)
BINDIR := $(ROOTDIR)/bin
DATADIRS := $(addprefix $(ROOTDIR)/,doc bench bin)
RELEASEDIR=$(ROOTDIR)/release
SOURCELINK := ${GOBIN}/sourcelink

export PATH := $(BINDIR):$(PATH):/usr/local/go/bin/

GO_VERSION := $(shell go version)

### VCS
TAG := $(shell git describe --tags --always --dirty="-dev" 2>/dev/null)
HASH := $(shell git rev-parse --short HEAD 2>/dev/null)
BRANCH := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
REPO := $(shell git ls-remote --get-url 2>/dev/null)
REPOLINK := $(shell test -x $(SOURCELINK) && ${GOBIN}/sourcelink $(REPO) $(HASH) $(BRANCH) 2>/dev/null || echo)
VERSION_PACKAGE := $(shell $(GO) list -f '{{.ImportPath}}' ./internal/version)

### collect VCS info for linker
LDFLAGS := "-s -w -X $(VERSION_PACKAGE).CommitHash=$(HASH) -X $(VERSION_PACKAGE).CommitTag=$(TAG) -X $(VERSION_PACKAGE).CommitBranch=$(BRANCH) -X $(VERSION_PACKAGE).CommitRepo=$(REPOLINK)"

### trim paths from binaries
# ... for go < 1.10
#TRIMFLAGS := -gcflags=-trimpath=$(PARENTDIR) -asmflags=-trimpath=$(PARENTDIR)
# ... for go >= 1.10
TRIMFLAGS := -gcflags=all=-trimpath=$(PARENTDIR) -asmflags=all=-trimpath=$(PARENTDIR)

#IMPORT_PATH := $(shell go list -f '{{.ImportPath}}' .)
#BINARY := $(notdir $(IMPORT_PATH))

.PHONY: all install run runall release clean cloc doc prebuild listall

all: listall $(CMDS) # badger
	@#@echo built all: $(CMDS)
	@echo build successful!

$(CMDS): prebuild $(wildcard cmd/$@/*.go)
	@echo building: $@
	@cd cmd/$@; \
	$(GO) build -o $(BINDIR)/$@ -ldflags $(LDFLAGS)

# badger:
#	@echo building: $@
# 	@env GOBIN=$(BINDIR) $(GO) install -v github.com/dgraph-io/badger/...

# this doesn't actually use make but relies on the build cache in Go 1.10 to build only those files that have changed
# TODO: what about data directories?
install: listall
	@env GOBIN=$(BINDIR) $(GO) install -v -ldflags $(LDFLAGS) $(TRIMFLAGS) ./cmd/...
	@if test -n "$(INSTALL)"; then \
		echo "installing to $(INSTALL):"; \
		cp -auvf $(BINDIR)/* $(INSTALL)/; \
	fi

# hack to run command from make command line goal arguments
# NOTE: any clean-up lines after the command is run won't execute if the program is interrupted with SIGINT
.SECONDEXPANSION:
runall: $$(filter-out $$@,$(MAKECMDGOALS))
	@- bash -c "trap 'true' SIGINT; $(BINDIR)/$<" || rm -f $(BINDIR)/$<
	rm -f $(addprefix $(BINDIR)/, $^)

# hack to run command from make command line goal arguments
# Supports simple arguments but won't work for complex arguments because Make splits on spaces.
# Remember to escape flags so Make doesn't interpret them:
#   $ make -- run some-command -d
# NOTE: any clean-up lines after the command is run won't execute if the program is interrupted with SIGINT
.SECONDEXPANSION:
run: $$(wordlist 2,2,$(MAKECMDGOALS))
	@- bash -c "trap 'true' SIGINT; $(BINDIR)/$< $(wordlist 3,100,$(MAKECMDGOALS))" || rm -f $(BINDIR)/$<
	rm -f $(addprefix $(BINDIR)/, $^)

clean:
	#rm -f $(foreach cmd,$(CMDS),cmd/$(cmd)/$(cmd))
	go clean ./...
	rm -f $(BINDIR)/*

# generate dependency list
doc: doc/go_dependencies.md
	scripts/make_go_dependencies_list.sh

$(SOURCELINK):
	-go get -v github.com/wvh/sourcelink

prebuild: $(SOURCELINK)
#	@$(eval REPOLINK=$(shell test -x ${GOBIN}/sourcelink && ${GOBIN}/sourcelink $(REPO) $(HASH) $(BRANCH) 2>/dev/null || echo ""))
	@echo ran prebuild requirements

release: listall minify doc
	@$(eval BUILDDIR=$(RELEASEDIR)/$(TAG))
	echo building release $(TAG) in $(BUILDDIR)
	mkdir -p $(BUILDDIR)/{bin,doc,schema}
	@env GOBIN=$(BUILDDIR)/bin $(GO) install -v -ldflags $(LDFLAGS) ./cmd/...
	cp -auvf doc/* $(BUILDDIR)/doc
	cp -auvf schema/* $(BUILDDIR)/schema
	ln -sfn $(BUILDDIR) $(RELEASEDIR)/stable
	ln -sfn $(BUILDDIR) $(RELEASEDIR)/testing
	ln -sfn $(BUILDDIR) $(RELEASEDIR)/test

cloc:
	cloc --exclude-dir=vendor .

listall:
	@echo
	@echo $(GO_VERSION)
	@echo qvain-api version: $(TAG)
	@echo building all: $(CMDS)
	@echo

check: lint staticcheck gosec
	@echo
	@echo "== Running tests =="
	-@go test ./...
	@echo "== Completed tests =="
	@echo

security: gosec

lint:
	@echo
	@echo "== Ensure golint is installed =="
	@go get -u golang.org/x/lint/golint 2> /dev/null
	@echo "== Completed golint installation =="
	@echo
	@echo "== Running golint =="
	@golint ./...
	@echo "== Completed golint =="
	@echo

staticcheck:
	@echo
	@echo "== Installing staticcheck =="
	@go get -u honnef.co/go/tools/cmd/staticcheck 2> /dev/null
	@echo "== Completed staticcheck installation =="
	@echo
	@echo "== Running staticcheck =="
	-@staticcheck -f stylish ./...
	@echo "== Completed staticcheck =="
	@echo

gosec:
	@echo
	@echo "== Installing gosec =="
	@go get github.com/securego/gosec/cmd/gosec
	@echo "== Completed gosec installation =="
	@echo
	@echo "== Running gosec =="
	-@gosec ./...
	@echo "== Completed gosec =="
