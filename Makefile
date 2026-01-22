.PHONY: init

init:
	git submodule update --init --recursive
	ln -sf $(CURDIR)/tmux.conf $(HOME)/.tmux.conf
