x:
	Xephyr -br -ac -noreset -screen 1920x1080 :2 &

run:
	DISPLAY=:2 cargo run -- --config ./examples/config
