# 快捷指令：make（編譯）、make run（在背景啟動，已經在跑的會換成新版）、make test（自我檢查）、make stop（關掉）

pikachu: Pikachu.swift
	swiftc -O Pikachu.swift -o pikachu

.PHONY: run test stop
run: pikachu stop                # 先編譯成功才關掉舊的，編譯失敗時舊的會繼續跑
	nohup ./pikachu >/dev/null 2>&1 &

test: pikachu
	./pikachu --selftest

stop:
	pkill -x pikachu || true
