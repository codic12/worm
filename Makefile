x:
	Xephyr -br -ac -noreset -screen 1920x1080 :2 &

run:
	DISPLAY=:2 cargo run -- --config ./examples/config

install:
	cargo build --release
	sudo mv target/release/{worm,wormc} /usr/local/bin
	sudo cp assets/worm.desktop /usr/share/xsessions
	mkdir -p ~/.config/worm
	touch ~/.config/worm/config
